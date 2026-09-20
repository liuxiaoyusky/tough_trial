import Foundation

/// Business receipts live with the facts they describe. Trace is diagnostic;
/// it is never used as the authority for retry or undo.
public struct V2StoredToolOperation: Codable, Equatable, Identifiable, Sendable {
    public var id: String { result.operationID }
    public var result: V2ToolExecutionResult
    public var arguments: Data
    public var requiredModules: [String]
    public var changes: [V2ToolFactChange]
    public var createdAt: Date
    public var schemaRevision: String
}

public struct V2ToolFactChange: Codable, Equatable, Sendable {
    public var collection: String
    public var recordID: String
    public var before: Data?
    public var after: Data?
}

public enum V2RegisteredToolError: Error, LocalizedError {
    case conflict, reference(String), missing(String)
    public var errorDescription: String? {
        switch self {
        case .conflict: "相关内容已改变，请重新整理，避免覆盖后来的修改。"
        case let .reference(value): "无法唯一找到「\(value)」，请提供更明确的名称。"
        case let .missing(value): "请补充\(value)。"
        }
    }
}

public extension V2Engine {
    func registeredToolCatalog() -> V2ToolCatalog {
        let fields = snapshot.extensionFields.definitions.filter(\.enabled).map { definition in
            let type: V2ToolFieldType
            switch definition.type {
            case .text: type = .text
            case .decimal: type = .decimal
            case .boolean: type = .boolean
            case .date: type = .date
            case .enumID: type = .enumID
            case .recordRef: type = .recordReference
            }
            return V2ToolDescriptor(
                id: definition.id + ".fill", moduleID: definition.domain,
                title: "填写\(definition.displayName)",
                purpose: "按现有字段定义填写；定义版本 \(definition.revision)。不修改核心字段。多值字段逐项追加。",
                inputSchema: .init(fields: [
                    .init(id: "recordReference", label: "记录名称", type: .recordReference, required: true, maxLength: 240),
                    .init(id: "value", label: definition.displayName, type: type, required: true, maxLength: definition.constraints["maxLength"].flatMap(Int.init) ?? 2_000, enumValues: definition.enums)
                ]), canUndo: true
            )
        }
        let builtins = V2ToolCatalogBuilder.builtinTools
        return V2ToolCatalogBuilder.make(runtime: moduleRuntime, additional: fields,
            registeredToolIDs: Set((builtins + fields).map(\.id)))
    }

    @discardableResult
    func executeRegisteredTool(
        _ call: V2AgentToolCall, context: V2ToolExecutionContext,
        requiresConfirmation: Bool = false, scheduleProposal: V2ScheduleProposal? = nil,
        at date: Date = Date(), calendar: Calendar = .current
    ) throws -> V2ToolExecutionResult {
        guard context.actor == .assistant, call.toolID == context.toolID else {
            throw V2ToolRegistryError.invalidResult("宿主调用身份不匹配")
        }
        let catalog = registeredToolCatalog()
        let (descriptor, arguments) = try catalog.validate(call)
        let canonical = try Self.toolJSON(JSONSerialization.jsonObject(with: call.argumentsJSON))
        if let existing = snapshot.toolOperations.first(where: { $0.id == context.operationID }) {
            guard existing.arguments == canonical else { throw V2RegisteredToolError.conflict }
            return existing.result
        }
        func result(_ state: V2ToolExecutionState, _ summary: String, references: [String] = [], undo: Bool = false) -> V2ToolExecutionResult {
            V2ToolExecutionResult(toolID: call.toolID, state: state, operationID: context.operationID,
                idempotencyKey: context.idempotencyKey, summary: summary, entityReferences: references,
                undoReference: undo ? context.operationID : nil, traceID: context.traceID).bound(to: call, context: context)
        }
        if let message = V2ToolSourcePolicy.missingInformation(for: descriptor, arguments: arguments, context: context, at: date, timeZone: calendar.timeZone) {
            return result(.needsInformation, message)
        }
        if descriptor.readOnly {
            return result(.applied, try registeredToolQuery(call.toolID, arguments: arguments, at: date, calendar: calendar,
                sourceTask: context.assistantContext?.referenceState == .available ? context.assistantContext?.sourceTask : nil))
        }
        let baseline = snapshot
        let staged = V2Engine(snapshot: baseline, moduleRuntime: moduleRuntime, reconcileExecutions: false)
        var summary = descriptor.title
        var refs: [String] = []
        var commandID = call.toolID
        if let definition = snapshot.extensionFields.definitions.first(where: { $0.id + ".fill" == call.toolID && $0.enabled }) {
            commandID = definition.domain + ".attributes.set"
            let reference = arguments.string("recordReference") ?? ""
            let matches = snapshot.fieldRecords(domainID: definition.domain).filter { $0.title == reference }
            guard matches.count == 1, let record = matches.first else { throw V2RegisteredToolError.reference(reference) }
            let raw: String
            switch arguments["value"] {
            case let .string(text): raw = text
            case let .number(number): raw = NSDecimalNumber(decimal: Decimal(number)).stringValue
            case let .boolean(value): raw = value ? "true" : "false"
            default: throw V2RegisteredToolError.missing("有效字段值")
            }
            let value: V2TypedFieldValue
            switch definition.type {
            case .text: value = .text(raw)
            case .decimal: value = .decimal(raw)
            case .boolean:
                guard ["true", "false"].contains(raw) else { throw V2RegisteredToolError.missing("true 或 false") }
                value = .boolean(raw == "true")
            case .date: value = .date(raw)
            case .enumID: value = .enumID(raw)
            case .recordRef:
                let domains = definition.constraints["allowedDomains"]?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? [definition.domain]
                let matches = domains.flatMap { domain in snapshot.fieldRecords(domainID: domain).filter { $0.title == raw }.map { (domain, $0.id) } }
                guard matches.count == 1, let target = matches.first else { throw V2RegisteredToolError.reference(raw) }
                value = .recordRef(domain: target.0, id: target.1)
            }
            let previous = snapshot.extensionFields.records.first { $0.domainID == definition.domain && $0.recordID == record.id }
            var values = previous?.values ?? []
            if !definition.multiple { values.removeAll { $0.fieldID == definition.id } }
            let attribute = V2TypedAttribute(fieldID: definition.id, value: value)
            if !values.contains(attribute) { values.append(attribute) }
            try staged.setRecordAttributes(domainID: definition.domain, recordID: record.id, values: values,
                expectedDefinitionsRevision: snapshot.extensionFields.revision, expectedRecordRevision: previous?.revision ?? 0)
            summary = "\(record.title)：\(definition.displayName) = \(raw)"
            refs = [record.id]
        } else {
            switch try V2TypedToolCommandDecoder.decode(toolID: call.toolID, arguments: arguments) {
            case let .tasksCreate(input):
                let contextID: String?
                if let reference = input.contextReference {
                    let matches = snapshot.taskContexts.filter { $0.archivedAt == nil && $0.title == reference }
                    guard matches.count == 1 else { throw V2RegisteredToolError.reference(reference) }
                    contextID = matches[0].id
                } else { contextID = nil }
                let task = try staged.createTask(title: input.title, contextID: contextID,
                    kind: input.kind.flatMap(V2Task.Kind.init(rawValue:)), note: input.note ?? "", at: date)
                refs = [task.id]; summary = "创建任务：\(task.title)" + (task.note.isEmpty ? "" : "\n\(task.note)")
                if V2AssistantScheduleContext.requestsToday(context.submittedText) {
                    let item = try staged.addTaskToToday(taskID: task.id, date: date, calendar: calendar)
                    refs.append(item.id); summary += "\n已安排到今天"
                }
            case .tasksSchedule:
                guard let scheduleProposal else { return result(.needsInformation, "请明确要安排的任务和时间。") }
                let receipt = try staged.applyScheduleProposal(scheduleProposal, requestID: context.operationID, at: date, calendar: calendar)
                refs = receipt.changes.map(\.entityID); summary = receipt.summary
            case let .ledgerCreatePending(input):
                let ledger = try staged.createManualLedgerEntry(amount: input.amount, currency: input.currency,
                    text: input.description, localDate: input.date, at: date)
                refs = [ledger.id]; summary = "记录账单：\(input.description) · \(input.amount) \(input.currency) · \(input.date)（Others，分类待确认）"
            case let .ledgerProposeCategory(input):
                let matches = snapshot.capture.ledger.filter { $0.text == input.ledgerReference }
                guard matches.count == 1 else { throw V2RegisteredToolError.reference(input.ledgerReference) }
                let ledger = matches[0]
                try staged.confirmLedgerCategory(ledgerID: ledger.id, categoryName: input.category,
                    expectedRevision: ledger.revision, confirmed: true)
                refs = [ledger.id]; summary = "账单「\(ledger.text)」· \(ledger.amount) \(ledger.currency) · \(ledger.localDate ?? "日期未填写")，分类为「\(input.category)」"
                commandID = "core.ledger.confirmCategory"
            case let .financeCreatePlan(input):
                guard let kind = V2FinancePlanKind(rawValue: input.kind) else { throw V2RegisteredToolError.missing("计划类型") }
                // A model can select a configured link by title, never invent a URL.
                let link: String
                if let alias = input.link {
                    let matches = (snapshot.capture.finance?.plans ?? []).filter { $0.title == alias && !$0.link.isEmpty }
                    guard matches.count == 1 else { throw V2RegisteredToolError.reference(alias) }
                    link = matches[0].link
                } else { link = "" }
                let plan = try staged.saveFinancePlan(.init(title: input.title, kind: kind, amount: input.amount,
                    currency: input.currency, dueDate: input.dueDate, timeZoneIdentifier: calendar.timeZone.identifier,
                    recurrence: input.recurrence.flatMap(V2FinanceRecurrence.init(rawValue:)) ?? .once, link: link))
                refs = [plan.id]; summary = "创建\(kind.label)：\(plan.title) · \(plan.amount) \(plan.currency) · \(plan.dueDate) · \(plan.recurrence == .monthly ? "每月" : plan.recurrence == .yearly ? "每年" : "单次")"
            case let .financeMarkPaid(input):
                let matches = (snapshot.capture.finance?.plans ?? []).filter { $0.title == input.planReference }
                guard matches.count == 1 else { throw V2RegisteredToolError.reference(input.planReference) }
                let plan = matches[0]
                let payment = try staged.payFinancePlan(id: plan.id, expectedRevision: plan.revision,
                    expectedDueDate: input.dueDate, at: date)
                refs = [payment.id, payment.ledgerID]; summary = "确认已支付：\(plan.title) · \(payment.amount) \(payment.currency) · \(input.dueDate)"
            case let .budgetSet(input):
                guard input.period == "monthly" else { throw V2RegisteredToolError.missing("月度预算") }
                let month = arguments.string("month") ?? String(V2CaptureContract.localDate(date, timeZone: calendar.timeZone).prefix(7))
                var categoryID: String?
                if let name = input.category {
                    let matches = snapshot.capture.categories.filter { $0.name == name && $0.mergedIntoID == nil }
                    guard matches.count == 1 else { throw V2RegisteredToolError.reference(name) }
                    categoryID = matches[0].id
                }
                var budget = snapshot.capture.finance?.budgets.first { $0.month == month && $0.currency == input.currency && $0.categoryID == categoryID }
                    ?? .init(currency: input.currency, amount: input.amount, month: month, categoryID: categoryID)
                let existing = snapshot.capture.finance?.budgets.contains { $0.id == budget.id } == true
                let revision = budget.revision
                budget.amount = input.amount
                let saved = try staged.saveBudget(budget, expectedRevision: existing ? revision : nil)
                refs = [saved.id]; summary = "设置 \(month) 预算：\(input.amount) \(input.currency)"
            case let .recallAppend(input):
                guard let day = V2CaptureContract.date(input.date, timeZone: calendar.timeZone) else { throw V2RegisteredToolError.missing("有效日期") }
                let existing = staged.recallEntry(on: day, calendar: calendar)
                let text = [existing?.text, input.text].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n\n")
                let saved = try staged.saveRecallEntry(date: day, text: text,
                    hasHandwriting: existing?.hasHandwriting ?? false,
                    references: .init(taskIDs: existing?.referencedTaskIDs ?? [], segmentIDs: existing?.referencedSegmentIDs ?? [], planItemIDs: existing?.referencedPlanItemIDs ?? []),
                    at: date, calendar: calendar)
                refs = [saved.id]; summary = "追加 \(input.date) 回响：\(input.text)"
            case let .captureCreate(input):
                let entry = try staged.saveCapture(text: input.text, at: date)
                refs = [entry.id]; summary = "保存随手记：\(input.text)"
            case let .notesCreate(input):
                let note = V2CaptureNote(id: UUID().uuidString,
                    kind: input.kind.flatMap(V2CaptureKind.init(rawValue:)) ?? .other,
                    title: nil, text: input.text, receiptID: context.operationID, recordedAt: date)
                try staged.commit(modules: ["core.notes"], commandID: "core.notes.create") { $0.capture.notes.append(note) }
                refs = [note.id]; summary = "保存笔记：\(input.text)"
            default: throw V2ToolExecutionError.unsupported(call.toolID)
            }
        }
        let changes = try Self.toolChanges(before: baseline, after: staged.snapshot)
        let needsConfirmation = descriptor.confirmationPolicy == .humanAlways || requiresConfirmation || context.requiresReview || context.intent != .explicitWrite
        let receipt = result(needsConfirmation ? .pendingConfirmation : .applied, summary,
            references: refs, undo: !needsConfirmation && !changes.isEmpty)
        let operation = V2StoredToolOperation(result: receipt, arguments: canonical,
            requiredModules: descriptor.requiredModules, changes: changes, createdAt: date, schemaRevision: catalog.revision)
        if needsConfirmation {
            let ticket = try moduleRuntime.ticket(for: descriptor.requiredModules)
            try commitHost { snapshot in
                try moduleRuntime.validate(ticket)
                snapshot.toolOperations.append(operation)
            }
        } else {
            try commit(modules: descriptor.requiredModules, commandID: commandID) { snapshot in
                try Self.applyToolChanges(changes, to: &snapshot, reversing: false)
                try Self.validateToolFactReferences(changes, snapshot: snapshot)
                snapshot.toolOperations.append(operation)
            }
        }
        return receipt
    }

    func confirmRegisteredTool(operationID: String, at date: Date = Date(), calendar: Calendar = .current) throws -> V2ToolExecutionResult {
        guard let operation = snapshot.toolOperations.first(where: { $0.id == operationID }) else { throw V2RegisteredToolError.conflict }
        if operation.result.state == .applied || operation.result.state == .undone { return operation.result }
        guard operation.result.state == .pendingConfirmation,
              registeredToolCatalog().revision == operation.schemaRevision else { throw V2RegisteredToolError.conflict }
        let result = Self.updatedToolResult(operation.result, state: .applied, undo: !operation.changes.isEmpty)
        try commit(modules: operation.requiredModules, commandID: Self.toolCommandID(operation.result.toolID)) { snapshot in
            try Self.applyToolChanges(operation.changes, to: &snapshot, reversing: false)
            try Self.validateToolFactReferences(operation.changes, snapshot: snapshot)
            guard let index = snapshot.toolOperations.firstIndex(where: { $0.id == operationID }) else { throw V2RegisteredToolError.conflict }
            snapshot.toolOperations[index].result = result
        }
        return result
    }

    func undoRegisteredTool(operationID: String, at date: Date = Date()) throws -> V2ToolExecutionResult {
        guard let operation = snapshot.toolOperations.first(where: { $0.id == operationID }) else { throw V2RegisteredToolError.conflict }
        if operation.result.state == .undone { return operation.result }
        guard operation.result.canUndo else { throw V2RegisteredToolError.conflict }
        let result = Self.updatedToolResult(operation.result, state: .undone, undo: false)
        let staged = V2Engine(snapshot: snapshot, moduleRuntime: moduleRuntime, reconcileExecutions: false)
        var domainUndo: [V2ToolFactChange]?
        if operation.result.toolID == "core.tasks.schedule",
           let receipt = snapshot.scheduleReceipts.first(where: { $0.requestID == operationID }) {
            try staged.undoScheduleReceipt(id: receipt.id, at: date)
            domainUndo = try Self.toolChanges(before: snapshot, after: staged.snapshot)
        } else if operation.result.toolID == "core.finance.markPaid",
                  let paymentID = operation.changes.first(where: { $0.collection == "capture.finance.payments" })?.recordID {
            try staged.undoFinancePayment(id: paymentID)
            domainUndo = try Self.toolChanges(before: snapshot, after: staged.snapshot)
        } else if operation.result.toolID == "core.ledger.proposeCategory",
                  let receiptID = operation.changes.first(where: { $0.collection == "capture.categoryReceipts" })?.recordID {
            try staged.undoCategoryReceipt(id: receiptID)
            domainUndo = try Self.toolChanges(before: snapshot, after: staged.snapshot)
        }
        try commit(modules: operation.requiredModules, commandID: Self.toolCommandID(operation.result.toolID)) { snapshot in
            if let domainUndo { try Self.applyToolChanges(domainUndo, to: &snapshot, reversing: false) }
            else {
                try Self.validateToolUndoReferences(operation, snapshot: snapshot)
                try Self.applyToolChanges(operation.changes, to: &snapshot, reversing: true)
            }
            let index = snapshot.toolOperations.firstIndex { $0.id == operationID }!
            snapshot.toolOperations[index].result = result
        }
        return result
    }
}

private extension V2Engine {
    static func toolCommandID(_ id: String) -> String {
        if id == "core.ledger.proposeCategory" { return "core.ledger.confirmCategory" }
        if id.hasSuffix(".fill") { return id.split(separator: ".").prefix(2).joined(separator: ".") + ".attributes.set" }
        return id
    }

    static func updatedToolResult(_ old: V2ToolExecutionResult, state: V2ToolExecutionState, undo: Bool) -> V2ToolExecutionResult {
        .init(toolID: old.toolID, state: state, operationID: old.operationID, idempotencyKey: old.idempotencyKey,
            summary: old.summary, entityReferences: old.entityReferences, undoReference: undo ? old.operationID : nil,
            traceID: old.traceID, assistantRequestID: old.assistantRequestID, callOrdinal: old.callOrdinal,
            argumentsJSON: old.argumentsJSON, modelCallID: old.modelCallID, submittedText: old.submittedText)
    }

    func registeredToolQuery(_ id: String, arguments: V2ToolArguments, at date: Date, calendar: Calendar, sourceTask: V2AgentSourceTask? = nil) throws -> String {
        let limit = max(1, min(30, arguments.integer("limit") ?? 20))
        let query = arguments.string("query") ?? ""
        func matches(_ text: String) -> Bool { query.isEmpty || text.localizedCaseInsensitiveContains(query) }
        let lines: [String]
        switch id {
        case "core.tasks.query":
            try moduleRuntime.require(["core.tasks"])
            let selected = sourceTask.flatMap { reference in snapshot.tasks.first { $0.id == reference.id } }
            let foundTasks = snapshot.tasks.filter { $0.status != .archived && $0.id != selected?.id && matches($0.title) }.suffix(max(0, limit - (selected == nil ? 0 : 1)))
            lines = (selected.map { ["当前引用：\($0.title) · \($0.status.rawValue)"] } ?? [])
                + foundTasks.map { "\($0.title) · \($0.status.rawValue)" }
        case "core.finance.queryPlans":
            try moduleRuntime.require(["core.finance"])
            lines = (snapshot.capture.finance?.plans ?? []).filter { matches($0.title) }.suffix(limit).map { "\($0.title) · \($0.amount) \($0.currency) · \($0.dueDate) · \($0.isActive ? "启用" : "停用")" }
        case "core.recall.query":
            try moduleRuntime.require(["core.recall"])
            lines = snapshot.recallEntries.filter { matches($0.text) }.suffix(limit).map { "\(V2CaptureContract.localDate($0.date, timeZone: calendar.timeZone))：\(String($0.text.prefix(240)))" }
        case "core.budget.queryProgress":
            try moduleRuntime.require(["core.budget"])
            let currency = arguments.string("currency")?.uppercased()
            let category = arguments.string("category")
            let categoryIDs = Set(snapshot.capture.categories.filter { $0.name == category }.map(\.id))
            lines = (snapshot.capture.finance?.budgets ?? []).filter {
                (currency == nil || $0.currency == currency) && (category == nil || $0.categoryID.map(categoryIDs.contains) == true)
            }.suffix(limit).map {
                let progress = budgetProgress(for: $0, timeZone: calendar.timeZone)
                return "\($0.month) · \($0.currency) · 预算 \($0.amount) · 已花费 \(progress.spent) · 剩余 \(progress.remaining)"
            }
        default: throw V2ToolExecutionError.unsupported(id)
        }
        return lines.isEmpty ? "没有匹配的记录。" : String(lines.joined(separator: "\n").prefix(8_000))
    }

    // Only host-created paths from this allowlist can become a receipt. Model
    // JSON never selects paths, IDs, versions, or before/after snapshots.
    static var toolCollections: [String] {
        ["tasks", "taskContexts", "planItems", "scheduleReceipts", "recallEntries",
         "capture.entries", "capture.notes", "capture.ledger", "capture.categories", "capture.categoryReceipts", "capture.receipts",
         "capture.finance.plans", "capture.finance.payments", "capture.finance.budgets", "extensionFields.records"]
    }
    static func toolJSON(_ object: Any) throws -> Data { try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .fragmentsAllowed]) }
    static func toolObject(_ snapshot: V2AppSnapshot) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as! [String: Any]
    }
    static func collection(_ path: String, from root: [String: Any]) -> [[String: Any]] {
        var value: Any = root
        for key in path.split(separator: ".") { value = (value as? [String: Any])?[String(key)] ?? [] }
        return value as? [[String: Any]] ?? []
    }
    static func recordIdentity(_ record: [String: Any], path: String) -> String {
        if path == "extensionFields.records" { return "\(record["domainID"] ?? ""):\(record["recordID"] ?? "")" }
        let id = record["id"] as? String ?? ""
        return path == "capture.entries" ? "\(id):\(record["revision"] ?? 0)" : id
    }
    static func toolChanges(before: V2AppSnapshot, after: V2AppSnapshot) throws -> [V2ToolFactChange] {
        let old = try toolObject(before), new = try toolObject(after)
        var changes: [V2ToolFactChange] = []
        for path in toolCollections {
            let a = Dictionary(uniqueKeysWithValues: collection(path, from: old).map { (recordIdentity($0, path: path), $0) })
            let b = Dictionary(uniqueKeysWithValues: collection(path, from: new).map { (recordIdentity($0, path: path), $0) })
            for id in Set(a.keys).union(b.keys).sorted() {
                let before = try a[id].map(toolJSON), after = try b[id].map(toolJSON)
                if before != after { changes.append(.init(collection: path, recordID: id, before: before, after: after)) }
            }
        }
        if before.capture.taxonomyRevision != after.capture.taxonomyRevision {
            changes.append(.init(collection: "capture.taxonomyRevision", recordID: "revision",
                before: try toolJSON(before.capture.taxonomyRevision), after: try toolJSON(after.capture.taxonomyRevision)))
        }
        guard changes.count <= 300 else { throw V2RegisteredToolError.conflict }
        var reconstructed = before
        try applyToolChanges(changes, to: &reconstructed, reversing: false)
        reconstructed.outbox = after.outbox
        guard reconstructed == after else { throw V2RegisteredToolError.conflict }
        return changes
    }
    static func applyToolChanges(_ changes: [V2ToolFactChange], to snapshot: inout V2AppSnapshot, reversing: Bool) throws {
        var root = try toolObject(snapshot)
        for change in changes {
            if change.collection == "capture.taxonomyRevision" {
                var capture = root["capture"] as! [String: Any]
                let current = try toolJSON(capture["taxonomyRevision"] ?? 1)
                guard current == (reversing ? change.after : change.before), let data = reversing ? change.before : change.after else { throw V2RegisteredToolError.conflict }
                capture["taxonomyRevision"] = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
                root["capture"] = capture
                continue
            }
            guard toolCollections.contains(change.collection) else { throw V2RegisteredToolError.conflict }
            var records = collection(change.collection, from: root)
            let index = records.firstIndex { recordIdentity($0, path: change.collection) == change.recordID }
            let current = try index.map { try toolJSON(records[$0]) }
            guard current == (reversing ? change.after : change.before) else { throw V2RegisteredToolError.conflict }
            if let index { records.remove(at: index) }
            if let data = reversing ? change.before : change.after {
                let record = try JSONSerialization.jsonObject(with: data) as! [String: Any]
                records.insert(record, at: min(index ?? records.count, records.count))
            }
            func set(_ keys: ArraySlice<Substring>, in object: inout [String: Any]) {
                let key = String(keys.first!)
                if keys.count == 1 { object[key] = records; return }
                var nested = object[key] as? [String: Any] ?? [:]
                if key == "finance" && nested.isEmpty { nested = ["schemaVersion": 1, "plans": [], "payments": [], "budgets": []] }
                set(keys.dropFirst(), in: &nested); object[key] = nested
            }
            set(change.collection.split(separator: ".")[...], in: &root)
        }
        snapshot = try JSONDecoder().decode(V2AppSnapshot.self, from: toolJSON(root))
    }
    static func validateToolFactReferences(_ changes: [V2ToolFactChange], snapshot: V2AppSnapshot) throws {
        for change in changes where change.after != nil {
            switch change.collection {
            case "tasks":
                guard let task = snapshot.tasks.first(where: { $0.id == change.recordID }) else { throw V2RegisteredToolError.conflict }
                if let context = task.contextID, !snapshot.taskContexts.contains(where: { $0.id == context && $0.archivedAt == nil }) { throw V2RegisteredToolError.conflict }
                if let parent = task.parentID, !snapshot.tasks.contains(where: { $0.id == parent && $0.status != .archived }) { throw V2RegisteredToolError.conflict }
            case "capture.finance.budgets":
                if let category = snapshot.capture.finance?.budgets.first(where: { $0.id == change.recordID })?.categoryID,
                   !snapshot.capture.categories.contains(where: { $0.id == category && $0.mergedIntoID == nil }) { throw V2RegisteredToolError.conflict }
            case "extensionFields.records":
                guard let record = snapshot.extensionFields.records.first(where: { $0.id == change.recordID }),
                      snapshot.containsFieldRecord(domainID: record.domainID, recordID: record.recordID) else { throw V2RegisteredToolError.conflict }
                let definitions = Dictionary(uniqueKeysWithValues: snapshot.extensionFields.definitions.filter { $0.domain == record.domainID }.map { ($0.id, $0) })
                try V2TypedAttribute.validate(record.values, using: definitions)
                for attribute in record.values {
                    if case let .recordRef(domain, id) = attribute.value,
                       !snapshot.containsFieldRecord(domainID: domain, recordID: id) { throw V2RegisteredToolError.conflict }
                }
            default: break
            }
        }
    }

    static func validateToolUndoReferences(_ operation: V2StoredToolOperation, snapshot: V2AppSnapshot) throws {
        for change in operation.changes where change.before == nil {
            let id = change.recordID
            if snapshot.extensionFields.records.contains(where: { $0.recordID == id }) { throw V2RegisteredToolError.conflict }
            switch change.collection {
            case "tasks":
                if snapshot.tasks.contains(where: { $0.parentID == id }) || snapshot.planItems.contains(where: { item in item.taskID == id && !operation.changes.contains(where: { $0.recordID == item.id && $0.collection == "planItems" }) }) || snapshot.executionSegments.contains(where: { $0.taskID == id }) || snapshot.recallEntries.contains(where: { $0.referencedTaskIDs.contains(id) }) { throw V2RegisteredToolError.conflict }
            case "capture.finance.plans":
                if snapshot.capture.finance?.payments.contains(where: { $0.planID == id }) == true { throw V2RegisteredToolError.conflict }
            case "capture.entries":
                let sourceID = id.split(separator: ":").first.map(String.init) ?? id
                if snapshot.capture.batches.contains(where: { $0.proposal.captureID == sourceID }) || snapshot.capture.entries.filter({ $0.id == sourceID }).count > 1 { throw V2RegisteredToolError.conflict }
            case "capture.ledger":
                if snapshot.capture.finance?.payments.contains(where: { payment in payment.ledgerID == id && !operation.changes.contains(where: { $0.recordID == payment.id && $0.collection == "capture.finance.payments" }) }) == true { throw V2RegisteredToolError.conflict }
            case "capture.categories":
                if snapshot.capture.ledger.contains(where: { ledger in ledger.categoryID == id && !operation.changes.contains(where: { $0.recordID == ledger.id && $0.collection == "capture.ledger" }) }) || snapshot.capture.finance?.budgets.contains(where: { $0.categoryID == id }) == true { throw V2RegisteredToolError.conflict }
            default: break
            }
        }
    }
}

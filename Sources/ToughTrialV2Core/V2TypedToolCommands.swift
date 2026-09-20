import Foundation

/// Typed inputs passed from the bounded tool schema to a native host handler.
/// The model-facing representation remains JSON, but a domain adapter never
/// needs to decode arbitrary JSON or accept persistent IDs from the model.
public struct V2ToolTaskCreateInput: Equatable, Sendable {
    public let title: String
    public let note: String?
    public let contextReference: String?
    public let kind: String?

    public init(title: String, note: String? = nil, contextReference: String? = nil, kind: String? = nil) {
        self.title = title
        self.note = note
        self.contextReference = contextReference
        self.kind = kind
    }
}

public struct V2ToolTaskScheduleInput: Equatable, Sendable {
    public let request: String
    public init(request: String) { self.request = request }
}

public struct V2ToolLedgerCreatePendingInput: Equatable, Sendable {
    public let description: String
    public let amount: String
    public let currency: String
    public let date: String

    public init(description: String, amount: String, currency: String, date: String) {
        self.description = description
        self.amount = amount
        self.currency = currency
        self.date = date
    }
}

public struct V2ToolLedgerProposeCategoryInput: Equatable, Sendable {
    public let ledgerReference: String
    public let category: String

    public init(ledgerReference: String, category: String) {
        self.ledgerReference = ledgerReference
        self.category = category
    }
}

public struct V2ToolFinanceCreatePlanInput: Equatable, Sendable {
    public let title: String
    public let amount: String
    public let currency: String
    public let dueDate: String
    public let kind: String
    public let recurrence: String?
    public let link: String?

    public init(
        title: String,
        amount: String,
        currency: String,
        dueDate: String,
        kind: String,
        recurrence: String? = nil,
        link: String? = nil
    ) {
        self.title = title
        self.amount = amount
        self.currency = currency
        self.dueDate = dueDate
        self.kind = kind
        self.recurrence = recurrence
        self.link = link
    }
}

public struct V2ToolFinanceMarkPaidInput: Equatable, Sendable {
    public let planReference: String
    public let dueDate: String

    public init(planReference: String, dueDate: String) {
        self.planReference = planReference
        self.dueDate = dueDate
    }
}

public struct V2ToolBudgetSetInput: Equatable, Sendable {
    public let amount: String
    public let currency: String
    public let period: String
    public let category: String?

    public init(amount: String, currency: String, period: String, category: String? = nil) {
        self.amount = amount
        self.currency = currency
        self.period = period
        self.category = category
    }
}

public struct V2ToolBudgetQueryInput: Equatable, Sendable {
    public let currency: String?
    public let category: String?

    public init(currency: String? = nil, category: String? = nil) {
        self.currency = currency
        self.category = category
    }
}

public struct V2ToolRecallAppendInput: Equatable, Sendable {
    public let text: String
    public let date: String

    public init(text: String, date: String) {
        self.text = text
        self.date = date
    }
}

public struct V2ToolCaptureCreateInput: Equatable, Sendable {
    public let text: String
    public init(text: String) { self.text = text }
}

public struct V2ToolNotesCreateInput: Equatable, Sendable {
    public let text: String
    public let kind: String?

    public init(text: String, kind: String? = nil) {
        self.text = text
        self.kind = kind
    }
}

public struct V2ToolTextQueryInput: Equatable, Sendable {
    public let query: String?
    public let limit: Int

    public init(query: String? = nil, limit: Int = 20) {
        self.query = query
        self.limit = max(1, min(100, limit))
    }
}

public enum V2TypedToolCommand: Equatable, Sendable {
    case tasksCreate(V2ToolTaskCreateInput)
    case tasksSchedule(V2ToolTaskScheduleInput)
    case tasksQuery(V2ToolTextQueryInput)
    case ledgerCreatePending(V2ToolLedgerCreatePendingInput)
    case ledgerProposeCategory(V2ToolLedgerProposeCategoryInput)
    case financeCreatePlan(V2ToolFinanceCreatePlanInput)
    case financeMarkPaid(V2ToolFinanceMarkPaidInput)
    case financeQueryPlans(V2ToolTextQueryInput)
    case budgetSet(V2ToolBudgetSetInput)
    case budgetQueryProgress(V2ToolBudgetQueryInput)
    case recallAppend(V2ToolRecallAppendInput)
    case recallQuery(V2ToolTextQueryInput)
    case captureCreate(V2ToolCaptureCreateInput)
    case notesCreate(V2ToolNotesCreateInput)
}

public enum V2TypedToolCommandError: Error, LocalizedError, Equatable, Sendable {
    case unsupported(String)
    case missing(String)
    case invalid(String)

    public var errorDescription: String? {
        switch self {
        case let .unsupported(tool): return "工具没有对应的受信任命令：\(tool)"
        case let .missing(field): return "工具命令缺少字段：\(field)"
        case let .invalid(field): return "工具命令字段无效：\(field)"
        }
    }
}

/// Converts validated schema arguments into domain-specific value types. It
/// never exposes an object ID, operation ID, confirmation flag, or path.
public enum V2TypedToolCommandDecoder {
    public static func decode(toolID: String, arguments: V2ToolArguments) throws -> V2TypedToolCommand {
        switch toolID {
        case "core.tasks.create":
            return .tasksCreate(.init(
                title: try requiredText(arguments, "title"),
                note: optionalText(arguments, "note"),
                contextReference: optionalText(arguments, "contextReference"),
                kind: optionalText(arguments, "kind")
            ))
        case "core.tasks.schedule":
            return .tasksSchedule(.init(request: try requiredText(arguments, "request")))
        case "core.tasks.query":
            return .tasksQuery(query(arguments))
        case "core.ledger.createPending":
            return .ledgerCreatePending(.init(
                description: try requiredText(arguments, "description"),
                amount: try requiredDecimal(arguments, "amount"),
                currency: try requiredText(arguments, "currency").uppercased(),
                date: try requiredText(arguments, "date")
            ))
        case "core.ledger.proposeCategory":
            return .ledgerProposeCategory(.init(
                ledgerReference: try requiredText(arguments, "ledgerReference"),
                category: try requiredText(arguments, "category")
            ))
        case "core.finance.createPlan":
            return .financeCreatePlan(.init(
                title: try requiredText(arguments, "title"),
                amount: try requiredDecimal(arguments, "amount"),
                currency: try requiredText(arguments, "currency").uppercased(),
                dueDate: try requiredText(arguments, "dueDate"),
                kind: try requiredText(arguments, "kind"),
                recurrence: optionalText(arguments, "recurrence"),
                link: optionalText(arguments, "link")
            ))
        case "core.finance.markPaid":
            return .financeMarkPaid(.init(
                planReference: try requiredText(arguments, "planReference"),
                dueDate: try requiredText(arguments, "dueDate")
            ))
        case "core.finance.queryPlans":
            return .financeQueryPlans(query(arguments))
        case "core.budget.set":
            return .budgetSet(.init(
                amount: try requiredDecimal(arguments, "amount"),
                currency: try requiredText(arguments, "currency").uppercased(),
                period: try requiredText(arguments, "period"),
                category: optionalText(arguments, "category")
            ))
        case "core.budget.queryProgress":
            return .budgetQueryProgress(.init(
                currency: optionalText(arguments, "currency"),
                category: optionalText(arguments, "category")
            ))
        case "core.recall.append":
            return .recallAppend(.init(
                text: try requiredText(arguments, "text"),
                date: try requiredText(arguments, "date")
            ))
        case "core.recall.query":
            return .recallQuery(query(arguments))
        case "core.capture.create":
            return .captureCreate(.init(text: try requiredText(arguments, "text")))
        case "core.notes.create":
            return .notesCreate(.init(
                text: try requiredText(arguments, "text"),
                kind: optionalText(arguments, "kind")
            ))
        default:
            throw V2TypedToolCommandError.unsupported(toolID)
        }
    }

    private static func requiredText(_ arguments: V2ToolArguments, _ field: String) throws -> String {
        guard let value = arguments.string(field)?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            throw V2TypedToolCommandError.missing(field)
        }
        return value
    }

    private static func optionalText(_ arguments: V2ToolArguments, _ field: String) -> String? {
        guard let value = arguments.string(field)?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func requiredDecimal(_ arguments: V2ToolArguments, _ field: String) throws -> String {
        guard let value = arguments[field] else { throw V2TypedToolCommandError.missing(field) }
        switch value {
        case let .string(text):
            let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard V2CaptureContract.validAmount(normalized) else { throw V2TypedToolCommandError.invalid(field) }
            return normalized
        case let .number(number):
            guard number.isFinite, number > 0 else { throw V2TypedToolCommandError.invalid(field) }
            let decimal = Decimal(number)
            let value = NSDecimalNumber(decimal: decimal).stringValue
            guard V2CaptureContract.validAmount(value) else { throw V2TypedToolCommandError.invalid(field) }
            return value
        default:
            throw V2TypedToolCommandError.invalid(field)
        }
    }

    private static func query(_ arguments: V2ToolArguments) -> V2ToolTextQueryInput {
        .init(query: optionalText(arguments, "query"), limit: arguments.integer("limit") ?? 20)
    }
}

/// A conservative host-side intent classifier. Hosts may supply a stronger
/// classifier, but a request phrased as discussion must never become a write
/// solely because the model selected a write tool.
public enum V2ToolIntentClassifier {
    public static func classify(_ rawText: String) -> V2ToolIntent {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .unknown }
        if ["不要创建", "不要记录", "不要添加", "不要保存", "不要执行", "不要修改", "不想", "暂不", "先不", "只是讨论", "举例", "假如", "如果", "别创建", "别记录"].contains(where: text.contains) { return .discussion }
        let discussionMarkers = ["讨论", "考虑", "建议", "是否", "要不要", "怎么选", "对比", "评估", "聊聊", "方案"]
        let explicitMarkers = ["创建", "新增", "添加", "记录", "保存", "设置", "安排", "记账", "标记", "确认已", "付款了"]
        let isDiscussion = discussionMarkers.contains { text.localizedCaseInsensitiveContains($0) }
        let isExplicit = explicitMarkers.contains { text.localizedCaseInsensitiveContains($0) }
        if isDiscussion && !isExplicit { return .discussion }
        return isExplicit ? .explicitWrite : .unknown
    }
}

import Foundation

public enum V2EngineError: Error, Equatable, Sendable {
    case blankTitle
    case contextNotFound(String)
    case taskNotFound(String)
    case parentContextMismatch
    case taskHierarchyCycle
    case taskArchived(String)
    case taskCompleted(String)
    case taskAlreadyRunning(String)
    case taskNotPaused(String)
    case segmentNotFound(String)
    case segmentAlreadyClosed(String)
    case invalidSegmentEnd
    case planDraftNotFound(String)
    case planDraftNotEditable(String)
    case unsupportedPlanMode(V2PlanDraftRecord.Mode)
    case invalidPlanDraft(String)
    case duplicateProposalID(String)
    case invalidPlanTimeRange(String)
    case planItemNotFound(String)
    case planExecutionMismatch(String)
    case recallEntryNotFound(String)
    case blankRecallText
    case invalidScheduleRequestID
    case invalidScheduleOperation(String)
    case duplicateScheduleLocalID(String)
    case scheduleTooManyOperations(Int)
    case scheduleReceiptNotFound(String)
    case scheduleReceiptAlreadyUndone(String)
    case scheduleReceiptConflict(String)
    case scheduleReceiptDanglingReference(String)
    case staleScheduleProposal(String)
}

public final class V2Engine {
    public private(set) var snapshot: V2AppSnapshot

    private let store: V2JSONSnapshotStore?
    private let commitLock = NSRecursiveLock()
    public var moduleRuntime: V2ModuleRuntime
    /// Host integration hook for trace projection. It is called only after a
    /// successful business snapshot save, so staged engines and failed writes
    /// never emit a committed operation event.
    public var onCommandCommitted: ((V2NativeCommandDescriptor) -> Void)?

    public init(
        snapshot: V2AppSnapshot = .empty,
        store: V2JSONSnapshotStore? = nil,
        moduleRuntime: V2ModuleRuntime = .init(),
        onCommandCommitted: ((V2NativeCommandDescriptor) -> Void)? = nil,
        reconcileExecutions: Bool = true
    ) {
        self.moduleRuntime = moduleRuntime
        self.snapshot = reconcileExecutions ? Self.reconcilingOpenExecutions(in: snapshot) : snapshot
        self.store = store
        self.onCommandCommitted = onCommandCommitted
    }

    public static func load(from store: V2JSONSnapshotStore) throws -> V2Engine {
        let snapshot = try store.loadOrCreateEmpty()
        return V2Engine(snapshot: snapshot, store: store)
    }

    @discardableResult
    public func createTaskContext(
        title: String,
        note: String = "",
        colorName: String,
        at date: Date = Date()
    ) throws -> V2TaskContext {
        let title = try normalizedTitle(title)
        let context = V2TaskContext(
            id: UUID().uuidString,
            title: title,
            note: note,
            colorName: colorName,
            createdAt: date,
            updatedAt: date
        )

        return try commit(modules: ["core.tasks"], commandID: "core.tasks.createContext") { snapshot in
            snapshot.taskContexts.append(context)
            return context
        }
    }

    @discardableResult
    public func createTask(
        title: String,
        parentID: String? = nil,
        contextID: String? = nil,
        kind: V2Task.Kind? = nil,
        note: String = "",
        sourceReference: V2TaskSourceReference? = nil,
        at date: Date = Date()
    ) throws -> V2Task {
        let title = try normalizedTitle(title)

        return try commit(modules: ["core.tasks"], commandID: "core.tasks.create") { snapshot in
            let effectiveContextID = try Self.validatePlacement(
                parentID: parentID,
                contextID: contextID,
                tasks: snapshot.tasks,
                contexts: snapshot.taskContexts
            )
            let task = V2Task(
                id: UUID().uuidString,
                contextID: effectiveContextID,
                parentID: parentID,
                title: title,
                note: note,
                kind: kind,
                createdAt: date,
                updatedAt: date,
                sourceReference: sourceReference
            )
            snapshot.tasks.append(task)
            return task
        }
    }

    @discardableResult
    public func updateTask(
        id: String,
        title: String,
        note: String,
        parentID: String?,
        contextID: String?,
        kind: V2Task.Kind?,
        at date: Date = Date()
    ) throws -> V2Task {
        let title = try normalizedTitle(title)

        return try commit(modules: ["core.tasks"], commandID: "core.tasks.update") { snapshot in
            guard let index = snapshot.tasks.firstIndex(where: { $0.id == id }) else {
                throw V2EngineError.taskNotFound(id)
            }
            guard snapshot.tasks[index].status != .archived else {
                throw V2EngineError.taskArchived(id)
            }

            let descendantIDs = Self.descendantIDs(of: id, in: snapshot.tasks)
            if parentID == id || parentID.map(descendantIDs.contains) == true {
                throw V2EngineError.taskHierarchyCycle
            }

            let effectiveContextID = try Self.validatePlacement(
                parentID: parentID,
                contextID: contextID,
                tasks: snapshot.tasks,
                contexts: snapshot.taskContexts
            )

            snapshot.tasks[index].title = title
            snapshot.tasks[index].note = note
            snapshot.tasks[index].parentID = parentID
            snapshot.tasks[index].contextID = effectiveContextID
            snapshot.tasks[index].kind = kind
            snapshot.tasks[index].updatedAt = date

            for descendantID in descendantIDs {
                guard let descendantIndex = snapshot.tasks.firstIndex(where: { $0.id == descendantID }) else {
                    continue
                }
                snapshot.tasks[descendantIndex].contextID = effectiveContextID
                snapshot.tasks[descendantIndex].updatedAt = date
            }

            return snapshot.tasks[index]
        }
    }

    @discardableResult
    public func completeTask(id: String, at date: Date = Date()) throws -> V2Task {
        try updateTaskStatus(id: id, status: .done, completedAt: date, archivedAt: nil, at: date)
    }

    @discardableResult
    public func restoreTask(id: String, at date: Date = Date()) throws -> V2Task {
        let hasOpenExecution = snapshot.executionSegments.contains { $0.taskID == id && $0.endAt == nil }
        return try updateTaskStatus(
            id: id,
            status: hasOpenExecution ? .active : .notStarted,
            completedAt: nil,
            archivedAt: nil,
            at: date
        )
    }

    public func archiveTask(id: String, at date: Date = Date()) throws {
        try commit(modules: ["core.tasks"], commandID: "core.tasks.archive") { snapshot in
            guard let task = snapshot.tasks.first(where: { $0.id == id }) else {
                throw V2EngineError.taskNotFound(id)
            }
            guard task.status != .archived else {
                return
            }

            let affectedIDs = Self.descendantIDs(of: id, in: snapshot.tasks).union([id])
            for index in snapshot.tasks.indices where affectedIDs.contains(snapshot.tasks[index].id) {
                snapshot.tasks[index].status = .archived
                snapshot.tasks[index].archivedAt = date
                snapshot.tasks[index].updatedAt = date
            }
        }
    }

    public func taskTree(contextID: String?) -> [V2TaskTreeNode] {
        let tasks = snapshot.tasks.filter {
            $0.status != .archived && $0.contextID == contextID
        }
        let includedIDs = Set(tasks.map(\.id))
        let roots = tasks.filter { task in
            guard let parentID = task.parentID else { return true }
            return !includedIDs.contains(parentID)
        }

        return Self.sorted(roots).map { Self.makeTreeNode(task: $0, tasks: tasks, visited: []) }
    }

    public func completionSignal(taskID: String) throws -> Double {
        guard let task = snapshot.tasks.first(where: { $0.id == taskID && $0.status != .archived }) else {
            throw V2EngineError.taskNotFound(taskID)
        }
        return Self.completionSignal(for: task, tasks: snapshot.tasks, visited: [])
    }

    @discardableResult
    public func addTaskToToday(
        taskID: String,
        date: Date,
        calendar: Calendar = .current
    ) throws -> V2PlanItem {
        try commit(modules: ["core.tasks"], commandID: "core.tasks.schedule") { snapshot in
            guard let task = snapshot.tasks.first(where: { $0.id == taskID }) else {
                throw V2EngineError.taskNotFound(taskID)
            }
            guard task.status != .archived else {
                throw V2EngineError.taskArchived(taskID)
            }
            let day = calendar.startOfDay(for: date)
            if let existing = snapshot.planItems.first(where: {
                $0.taskID == taskID && calendar.isDate($0.date, inSameDayAs: day) && $0.status != .canceled
            }) {
                return existing
            }

            let item = V2PlanItem(
                id: UUID().uuidString,
                date: day,
                taskID: taskID,
                title: task.title
            )
            snapshot.planItems.append(item)
            return item
        }
    }

    @discardableResult
    public func completePlanItem(id: String) throws -> V2PlanItem {
        try commit(modules: ["core.tasks"], commandID: "core.tasks.complete") { snapshot in
            guard let index = snapshot.planItems.firstIndex(where: { $0.id == id }) else {
                throw V2EngineError.planItemNotFound(id)
            }
            guard snapshot.planItems[index].status != .canceled else {
                throw V2EngineError.planItemNotFound(id)
            }
            snapshot.planItems[index].status = .completed
            return snapshot.planItems[index]
        }
    }

    @discardableResult
    public func restorePlanItem(id: String) throws -> V2PlanItem {
        try commit(modules: ["core.tasks"], commandID: "core.tasks.restore") { snapshot in
            guard let index = snapshot.planItems.firstIndex(where: { $0.id == id }) else {
                throw V2EngineError.planItemNotFound(id)
            }
            guard snapshot.planItems[index].status != .canceled else {
                throw V2EngineError.planItemNotFound(id)
            }
            snapshot.planItems[index].status = .planned
            return snapshot.planItems[index]
        }
    }

    public func completeTodayItem(
        planItemID: String?,
        taskID: String?,
        at date: Date = Date(),
        finishExecution: Bool = false
    ) throws {
        try commit(modules: ["core.tasks"], commandID: "core.tasks.complete") { snapshot in
            if let planItemID {
                guard let index = snapshot.planItems.firstIndex(where: {
                    $0.id == planItemID && $0.status != .canceled
                }) else {
                    throw V2EngineError.planItemNotFound(planItemID)
                }
                guard snapshot.planItems[index].taskID == taskID else {
                    throw V2EngineError.planExecutionMismatch(planItemID)
                }
                snapshot.planItems[index].status = .completed
            }

            if finishExecution {
                for index in snapshot.executionSegments.indices {
                    let segment = snapshot.executionSegments[index]
                    let matches = taskID.map { segment.taskID == $0 }
                        ?? (planItemID != nil && segment.createdFromPlanItemID == planItemID)
                    guard matches, segment.endAt == nil || segment.endReason == .paused else { continue }
                    if segment.endAt == nil {
                        guard date >= segment.startAt else { throw V2EngineError.invalidSegmentEnd }
                        snapshot.executionSegments[index].endAt = date
                    }
                    snapshot.executionSegments[index].endReason = .stopped
                }
            }

            if let taskID {
                guard let index = snapshot.tasks.firstIndex(where: { $0.id == taskID }) else {
                    throw V2EngineError.taskNotFound(taskID)
                }
                snapshot.tasks[index].status = .done
                snapshot.tasks[index].completedAt = date
                snapshot.tasks[index].updatedAt = date
            }
        }
    }

    public func restoreTodayItem(
        planItemID: String?,
        taskID: String?,
        at date: Date = Date()
    ) throws {
        try commit(modules: ["core.tasks"], commandID: "core.tasks.restore") { snapshot in
            if let planItemID {
                guard let index = snapshot.planItems.firstIndex(where: {
                    $0.id == planItemID && $0.status != .canceled
                }) else {
                    throw V2EngineError.planItemNotFound(planItemID)
                }
                guard snapshot.planItems[index].taskID == taskID else {
                    throw V2EngineError.planExecutionMismatch(planItemID)
                }
                snapshot.planItems[index].status = .planned
            }

            if let taskID {
                guard let index = snapshot.tasks.firstIndex(where: { $0.id == taskID }) else {
                    throw V2EngineError.taskNotFound(taskID)
                }
                let hasOpenExecution = snapshot.executionSegments.contains {
                    $0.taskID == taskID && $0.endAt == nil
                }
                snapshot.tasks[index].status = hasOpenExecution ? .active : .notStarted
                snapshot.tasks[index].completedAt = nil
                snapshot.tasks[index].updatedAt = date
            }
        }
    }

    @discardableResult
    public func quickInsertTodayTask(
        title: String,
        note: String = "",
        at date: Date = Date(),
        calendar: Calendar = .current
    ) throws -> (task: V2Task, planItem: V2PlanItem) {
        let title = try normalizedTitle(title)
        let startAt = Self.explicitTodayStartAt(in: title, on: date, calendar: calendar)
        return try commit(modules: ["core.tasks"], commandID: "core.tasks.create") { snapshot in
            let task = V2Task(
                id: UUID().uuidString,
                title: title,
                note: note,
                createdAt: date,
                updatedAt: date
            )
            let item = V2PlanItem(
                id: UUID().uuidString,
                date: calendar.startOfDay(for: date),
                startAt: startAt,
                taskID: task.id,
                title: title
            )
            snapshot.tasks.append(task)
            snapshot.planItems.append(item)
            return (task, item)
        }
    }

    @discardableResult
    public func quickInsertScheduledTask(
        title: String,
        note: String = "",
        on date: Date,
        calendar: Calendar = .current
    ) throws -> (task: V2Task, planItem: V2PlanItem) {
        let title = try normalizedTitle(title)
        return try commit(modules: ["core.tasks"], commandID: "core.tasks.schedule") { snapshot in
            let createdAt = Date()
            let task = V2Task(
                id: UUID().uuidString,
                title: title,
                note: note,
                createdAt: createdAt,
                updatedAt: createdAt
            )
            let item = V2PlanItem(
                id: UUID().uuidString,
                date: calendar.startOfDay(for: date),
                taskID: task.id,
                title: title
            )
            snapshot.tasks.append(task)
            snapshot.planItems.append(item)
            return (task, item)
        }
    }

    @discardableResult
    public func startExecution(
        taskID: String?,
        title: String,
        source: V2ExecutionSegment.Source,
        at date: Date = Date(),
        createdFromPlanItemID: String? = nil,
        note: String = ""
    ) throws -> V2ExecutionSegment {
        try commit(modules: ["core.tasks"], commandID: "core.tasks.startExecution") { snapshot in
            if let createdFromPlanItemID {
                guard let planItem = snapshot.planItems.first(where: {
                    $0.id == createdFromPlanItemID && $0.status != .canceled
                }) else {
                    throw V2EngineError.planItemNotFound(createdFromPlanItemID)
                }
                guard planItem.taskID == taskID else {
                    throw V2EngineError.planExecutionMismatch(createdFromPlanItemID)
                }
            }
            let linkedTaskIndex = try Self.executableTaskIndex(taskID: taskID, snapshot: snapshot)
            if let taskID,
               snapshot.executionSegments.contains(where: { $0.taskID == taskID && $0.endAt == nil }) {
                throw V2EngineError.taskAlreadyRunning(taskID)
            }

            let fallbackTitle = linkedTaskIndex.map { snapshot.tasks[$0].title } ?? ""
            let titleSnapshot = try normalizedTitle(title.isEmpty ? fallbackTitle : title)
            let segmentID = UUID().uuidString
            let segment = V2ExecutionSegment(
                id: segmentID,
                sessionID: segmentID,
                taskID: taskID,
                titleSnapshot: titleSnapshot,
                startAt: date,
                source: source,
                createdFromPlanItemID: createdFromPlanItemID,
                note: note
            )
            snapshot.executionSegments.append(segment)

            if let linkedTaskIndex {
                snapshot.tasks[linkedTaskIndex].status = .active
                snapshot.tasks[linkedTaskIndex].updatedAt = date
            }
            return segment
        }
    }

    @discardableResult
    public func pauseExecution(segmentID: String, at date: Date = Date()) throws -> V2ExecutionSegment {
        try closeExecution(
            segmentID: segmentID,
            at: date,
            endReason: .paused,
            taskStatus: .paused
        )
    }

    @discardableResult
    public func endExecution(segmentID: String, at date: Date = Date()) throws -> V2ExecutionSegment {
        try closeExecution(
            segmentID: segmentID,
            at: date,
            endReason: .stopped,
            taskStatus: .notStarted
        )
    }

    @discardableResult
    public func pauseExecutionSession(
        sessionID: String,
        at date: Date = Date()
    ) throws -> V2ExecutionSegment {
        guard let segment = snapshot.executionSegments.first(where: {
            $0.logicalSessionID == sessionID && $0.endAt == nil
        }) else {
            throw V2EngineError.segmentNotFound(sessionID)
        }
        return try pauseExecution(segmentID: segment.id, at: date)
    }

    @discardableResult
    public func resumeExecution(
        after segmentID: String,
        at date: Date = Date()
    ) throws -> V2ExecutionSegment {
        try commit(modules: ["core.tasks"], commandID: "core.tasks.resumeExecution") { snapshot in
            guard let previous = snapshot.executionSegments.first(where: { $0.id == segmentID }) else {
                throw V2EngineError.segmentNotFound(segmentID)
            }
            guard previous.endAt != nil, previous.endReason == .paused else {
                throw V2EngineError.taskNotPaused(previous.taskID ?? previous.logicalSessionID)
            }
            guard !snapshot.executionSegments.contains(where: {
                $0.logicalSessionID == previous.logicalSessionID && $0.endAt == nil
            }) else {
                throw V2EngineError.taskAlreadyRunning(previous.taskID ?? previous.logicalSessionID)
            }

            let taskIndex = try Self.executableTaskIndex(taskID: previous.taskID, snapshot: snapshot)
            let segment = V2ExecutionSegment(
                id: UUID().uuidString,
                sessionID: previous.logicalSessionID,
                taskID: previous.taskID,
                titleSnapshot: taskIndex.map { snapshot.tasks[$0].title } ?? previous.titleSnapshot,
                startAt: date,
                source: previous.source,
                createdFromPlanItemID: previous.createdFromPlanItemID,
                note: previous.note
            )
            snapshot.executionSegments.append(segment)
            if let taskIndex {
                snapshot.tasks[taskIndex].status = .active
                snapshot.tasks[taskIndex].updatedAt = date
            }
            return segment
        }
    }

    @discardableResult
    public func resumeExecutionSession(
        sessionID: String,
        at date: Date = Date()
    ) throws -> V2ExecutionSegment {
        guard let latest = snapshot.executionSegments
            .filter({ $0.logicalSessionID == sessionID })
            .max(by: { $0.startAt < $1.startAt }) else {
            throw V2EngineError.segmentNotFound(sessionID)
        }
        return try resumeExecution(after: latest.id, at: date)
    }

    public func stopExecutionSession(sessionID: String, at date: Date = Date()) throws {
        try commit(modules: ["core.tasks"], commandID: "core.tasks.stopExecution") { snapshot in
            guard let index = snapshot.executionSegments.indices
                .filter({ snapshot.executionSegments[$0].logicalSessionID == sessionID })
                .max(by: {
                    snapshot.executionSegments[$0].startAt < snapshot.executionSegments[$1].startAt
                }) else {
                throw V2EngineError.segmentNotFound(sessionID)
            }

            if snapshot.executionSegments[index].endAt == nil {
                guard date >= snapshot.executionSegments[index].startAt else {
                    throw V2EngineError.invalidSegmentEnd
                }
                snapshot.executionSegments[index].endAt = date
            } else if snapshot.executionSegments[index].endReason != .paused {
                throw V2EngineError.segmentAlreadyClosed(snapshot.executionSegments[index].id)
            }
            snapshot.executionSegments[index].endReason = .stopped

            if let taskID = snapshot.executionSegments[index].taskID,
               let taskIndex = snapshot.tasks.firstIndex(where: { $0.id == taskID }),
               snapshot.tasks[taskIndex].status != .done,
               snapshot.tasks[taskIndex].status != .archived {
                snapshot.tasks[taskIndex].status = .notStarted
                snapshot.tasks[taskIndex].updatedAt = date
            }
        }
    }

    @discardableResult
    public func resumeTaskExecution(taskID: String, at date: Date = Date()) throws -> V2ExecutionSegment {
        guard let task = snapshot.tasks.first(where: { $0.id == taskID }) else {
            throw V2EngineError.taskNotFound(taskID)
        }
        guard task.status == .paused else {
            throw V2EngineError.taskNotPaused(taskID)
        }
        guard let latest = snapshot.executionSegments
            .filter({ $0.taskID == taskID })
            .max(by: { $0.startAt < $1.startAt }) else {
            throw V2EngineError.taskNotPaused(taskID)
        }
        return try resumeExecution(after: latest.id, at: date)
    }

    public func openExecutionSegments() -> [V2ExecutionSegment] {
        snapshot.executionSegments
            .filter { $0.endAt == nil }
            .sorted { $0.startAt < $1.startAt }
    }

    public func executionSegments(on date: Date, calendar: Calendar = .current) -> [V2ExecutionSegment] {
        let dayStart = calendar.startOfDay(for: date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return []
        }

        return snapshot.executionSegments.filter { segment in
            segment.startAt < dayEnd && (segment.endAt ?? .distantFuture) >= dayStart
        }
    }

    public func spentDuration(taskID: String, through date: Date = Date()) -> TimeInterval {
        snapshot.executionSegments
            .filter { $0.taskID == taskID }
            .reduce(0) { $0 + $1.duration(through: date) }
    }

    public func persist() throws {
        try store?.save(snapshot)
    }

    /// Execute a registered, bounded read projection for host and assistant
    /// adapters.  The returned JSON is the encoding of one of the typed
    /// `V2Native*Read` values; callers select the type from the query
    /// descriptor's stable ID rather than inspecting arbitrary snapshot keys.
    public func nativeQueryData(
        _ request: V2NativeQueryRequest,
        traceEvents: [V2UsageEvent] = [],
        fieldDefinitions: [V2NativeFieldDefinition] = [],
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws -> Data {
        let descriptor = try moduleRuntime.requireQuery(request, now: now)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        func encode<Projection: Encodable>(_ projection: Projection) throws -> Data {
            try encoder.encode(projection)
        }

        let anchor = request.to ?? now
        if let from = request.from {
            guard from <= anchor else { throw V2NativeQueryError.invalidDateRange }
            if let days = descriptor.maxDays, anchor.timeIntervalSince(from) > Double(days) * 86_400 { throw V2NativeQueryError.invalidDateRange }
        }
        let lowerBound: Date? = {
            if let from = request.from { return from }
            guard let maxDays = descriptor.maxDays else { return nil }
            return anchor.addingTimeInterval(-Double(maxDays) * 86_400)
        }()
        let upperBound = request.to ?? now
        let matchesDate: (Date) -> Bool = { date in
            if let lowerBound, date < lowerBound { return false }
            if date > upperBound { return false }
            return true
        }
        let limit = request.limit

        switch request.id {
        case "core.tasks.today":
            let dayStart = calendar.startOfDay(for: request.from ?? anchor)
            guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
                throw V2NativeQueryError.invalidDateRange
            }
            let items = snapshot.planItems
                .filter { $0.date >= dayStart && $0.date < dayEnd && $0.status != .canceled }
                .sorted { ($0.startAt ?? $0.date, $0.id) < ($1.startAt ?? $1.date, $1.id) }
            let boundedItems = Array(items.prefix(limit))
            let taskIDs = Set(boundedItems.compactMap(\.taskID))
            let tasks = snapshot.tasks.filter { taskIDs.contains($0.id) }
            return try encode(V2NativeTasksTodayRead(date: dayStart, planItems: boundedItems, tasks: tasks))

        case "core.tasks.workspace":
            let contexts = Array(snapshot.taskContexts
                .filter { $0.archivedAt == nil }
                .sorted { ($0.updatedAt, $0.id) > ($1.updatedAt, $1.id) }
                .prefix(limit))
            let tasks = Array(snapshot.tasks
                .filter { $0.status != .archived }
                .sorted { ($0.updatedAt, $0.id) > ($1.updatedAt, $1.id) }
                .prefix(limit))
            let drafts = Array(snapshot.planDrafts
                .sorted { ($0.updatedAt, $0.id) > ($1.updatedAt, $1.id) }
                .prefix(limit))
            let items = Array(snapshot.planItems
                .sorted { ($0.date, $0.id) > ($1.date, $1.id) }
                .prefix(limit))
            return try encode(V2NativeTasksWorkspaceRead(contexts: contexts, tasks: tasks, planDrafts: drafts, planItems: items))

        case "core.tasks.execution":
            let segments = Array(snapshot.executionSegments
                .filter { segment in
                    if let lowerBound, segment.startAt < lowerBound,
                       let endAt = segment.endAt, endAt < lowerBound { return false }
                    if segment.startAt > upperBound { return false }
                    return true
                }
                .sorted { ($0.startAt, $0.id) > ($1.startAt, $1.id) }
                .prefix(limit))
            return try encode(V2NativeExecutionRead(segments: segments))

        case "core.capture.recent":
            let entries = Array(snapshot.capture.latestEntries
                .filter { matchesDate($0.recordedAt) }
                .sorted { ($0.recordedAt, $0.id) > ($1.recordedAt, $1.id) }
                .prefix(limit))
            let entryIDs = Set(entries.map(\.id))
            let batches = Array(snapshot.capture.batches
                .filter { matchesDate($0.createdAt) }
                .sorted { ($0.createdAt, $0.id) > ($1.createdAt, $1.id) }
                .prefix(limit))
            let batchIDs = Set(batches.map(\.id))
            let receipts = Array(snapshot.capture.receipts
                .filter { receipt in
                    batchIDs.contains(receipt.batchID) || entryIDs.contains(receipt.targetID ?? "")
                }
                .prefix(limit))
            return try encode(V2NativeCaptureRead(entries: entries, batches: batches, receipts: receipts))

        case "core.ledger.recent":
            let entries = Array(snapshot.capture.ledger
                .filter { matchesDate($0.recordedAt) }
                .sorted { ($0.recordedAt, $0.id) > ($1.recordedAt, $1.id) }
                .prefix(limit))
            let categories = Array(snapshot.capture.categories
                .sorted { ($0.name, $0.id) < ($1.name, $1.id) }
                .prefix(limit))
            return try encode(V2NativeLedgerRead(entries: entries, categories: categories))

        case "core.finance.plans":
            let finance = snapshot.capture.finance ?? V2FinanceState()
            let plans = Array(finance.plans
                .sorted { ($0.dueDate, $0.id) < ($1.dueDate, $1.id) }
                .prefix(limit))
            let payments = Array(finance.payments
                .filter { matchesDate($0.paidAt) }
                .sorted { ($0.paidAt, $0.id) > ($1.paidAt, $1.id) }
                .prefix(limit))
            return try encode(V2NativeFinanceRead(plans: plans, payments: payments))

        case "core.budget.queryProgress":
            let budgets = Array((snapshot.capture.finance?.budgets ?? []).prefix(limit))
            let progress = budgets.map { budgetProgress(for: $0) }
            return try encode(V2NativeBudgetProgressRead(budgets: budgets, progress: Array(progress.prefix(limit))))

        case "core.recall.recent":
            let entries = Array(snapshot.recallEntries
                .filter { matchesDate($0.date) }
                .sorted { ($0.date, $0.id) > ($1.date, $1.id) }
                .prefix(limit))
            return try encode(V2NativeRecallRead(entries: entries))

        case "core.notes.recent":
            let entries = Array(snapshot.capture.notes
                .filter { matchesDate($0.recordedAt) }
                .sorted { ($0.recordedAt, $0.id) > ($1.recordedAt, $1.id) }
                .prefix(limit))
            return try encode(V2NativeNotesRead(entries: entries))

        case "core.imports.recent":
            let receipts = Array((snapshot.capture.imports ?? [])
                .filter { matchesDate($0.importedAt) }
                .sorted { ($0.importedAt, $0.id) > ($1.importedAt, $1.id) }
                .prefix(limit))
            return try encode(V2NativeImportRead(receipts: receipts))

        case "core.attachments.recent":
            let assets = Array(snapshot.capture.assets.prefix(limit))
            return try encode(V2NativeAssetRead(assets: assets))

        case "core.trace.recent":
            let events = Array(traceEvents
                .filter { matchesDate($0.at) }
                .sorted { ($0.at, $0.id) > ($1.at, $1.id) }
                .prefix(limit))
            return try encode(V2NativeTraceRead(events: events))

        case let id where id.hasSuffix(".fields"):
            let moduleID = String(id.dropLast(".fields".count))
            let definitions = Array(fieldDefinitions
                .filter { $0.domainID == moduleID }
                .sorted { ($0.id, $0.revision) < ($1.id, $1.revision) }
                .prefix(limit))
            return try encode(V2NativeFieldRead(definitions: definitions))

        default:
            throw V2NativeQueryError.unsupportedProjection(request.id)
        }
    }

    public func nativeQueryData(
        id: String,
        limit: Int = 100,
        from: Date? = nil,
        to: Date? = nil,
        fields: Set<String> = [],
        traceEvents: [V2UsageEvent] = [],
        fieldDefinitions: [V2NativeFieldDefinition] = [],
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws -> Data {
        try nativeQueryData(
            V2NativeQueryRequest(id: id, limit: limit, from: from, to: to, fields: fields),
            traceEvents: traceEvents,
            fieldDefinitions: fieldDefinitions,
            now: now,
            calendar: calendar
        )
    }

    public func nativeQuery<Projection: Decodable>(
        _ type: Projection.Type,
        request: V2NativeQueryRequest,
        traceEvents: [V2UsageEvent] = [],
        fieldDefinitions: [V2NativeFieldDefinition] = [],
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws -> Projection {
        try JSONDecoder().decode(
            Projection.self,
            from: nativeQueryData(
                request,
                traceEvents: traceEvents,
                fieldDefinitions: fieldDefinitions,
                now: now,
                calendar: calendar
            )
        )
    }

    @discardableResult
    private func closeExecution(
        segmentID: String,
        at date: Date,
        endReason: V2ExecutionSegment.EndReason,
        taskStatus: V2Task.Status
    ) throws -> V2ExecutionSegment {
        try commit(modules: ["core.tasks"], commandID: endReason == .paused ? "core.tasks.pauseExecution" : "core.tasks.endExecution") { snapshot in
            guard let segmentIndex = snapshot.executionSegments.firstIndex(where: { $0.id == segmentID }) else {
                throw V2EngineError.segmentNotFound(segmentID)
            }
            guard snapshot.executionSegments[segmentIndex].endAt == nil else {
                throw V2EngineError.segmentAlreadyClosed(segmentID)
            }
            guard date >= snapshot.executionSegments[segmentIndex].startAt else {
                throw V2EngineError.invalidSegmentEnd
            }

            snapshot.executionSegments[segmentIndex].endAt = date
            snapshot.executionSegments[segmentIndex].endReason = endReason
            let taskID = snapshot.executionSegments[segmentIndex].taskID
            if let taskID,
               let taskIndex = snapshot.tasks.firstIndex(where: { $0.id == taskID }),
               snapshot.tasks[taskIndex].status != .done,
               snapshot.tasks[taskIndex].status != .archived {
                snapshot.tasks[taskIndex].status = taskStatus
                snapshot.tasks[taskIndex].updatedAt = date
            }
            return snapshot.executionSegments[segmentIndex]
        }
    }

    @discardableResult
    private func updateTaskStatus(
        id: String,
        status: V2Task.Status,
        completedAt: Date?,
        archivedAt: Date?,
        at date: Date
    ) throws -> V2Task {
        try commit(modules: ["core.tasks"], commandID: status == .done ? "core.tasks.complete" : "core.tasks.restore") { snapshot in
            guard let index = snapshot.tasks.firstIndex(where: { $0.id == id }) else {
                throw V2EngineError.taskNotFound(id)
            }
            guard snapshot.tasks[index].status != .archived else {
                throw V2EngineError.taskArchived(id)
            }
            snapshot.tasks[index].status = status
            snapshot.tasks[index].completedAt = completedAt
            snapshot.tasks[index].archivedAt = archivedAt
            snapshot.tasks[index].updatedAt = date
            return snapshot.tasks[index]
        }
    }

    @discardableResult
    func commit<Result>(
        modules: [String],
        commandID: String,
        _ mutation: (inout V2AppSnapshot) throws -> Result
    ) throws -> Result {
        commitLock.lock(); defer { commitLock.unlock() }
        try moduleRuntime.requireCommand(commandID, modules: modules)
        guard let descriptor = moduleRuntime.commandDescriptor(commandID) else {
            throw V2ModuleRuntimeError.commandNotRegistered(commandID)
        }
        var next = snapshot
        let result = try mutation(&next)
        try moduleRuntime.requireCommand(commandID, modules: modules)
        V2OutboxPolicy.enqueueChanges(from: snapshot, into: &next, at: Date())
        try store?.save(next)
        snapshot = next
        onCommandCommitted?(descriptor)
        return result
    }

    /// Host-only maintenance commits are allowed to finish durable cleanup
    /// after a module has been stopped. They never enter a plugin/module
    /// context and are intentionally unavailable to the public module client.
    @discardableResult
    func commitHost<Result>(
        _ mutation: (inout V2AppSnapshot) throws -> Result
    ) throws -> Result {
        commitLock.lock(); defer { commitLock.unlock() }
        var next = snapshot
        let result = try mutation(&next)
        try store?.save(next)
        snapshot = next
        return result
    }

    private func normalizedTitle(_ title: String) throws -> String {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw V2EngineError.blankTitle
        }
        return normalized
    }

    private static func explicitTodayStartAt(
        in title: String,
        on date: Date,
        calendar: Calendar
    ) -> Date? {
        let futureMarkers = [
            "明天", "后天", "大后天", "下周", "下星期", "下礼拜",
            "下个月", "下月", "明年", "未来",
        ]
        guard !futureMarkers.contains(where: { title.contains($0) }) else {
            return nil
        }

        if let time = explicit24HourTime(in: title) {
            return calendar.date(
                bySettingHour: time.hour,
                minute: time.minute,
                second: 0,
                of: date
            )
        }
        if title.contains("下午三点半") {
            return calendar.date(bySettingHour: 15, minute: 30, second: 0, of: date)
        }
        if title.contains("下午三点") {
            return calendar.date(bySettingHour: 15, minute: 0, second: 0, of: date)
        }
        return nil
    }

    private static func explicit24HourTime(in title: String) -> (hour: Int, minute: Int)? {
        let candidates = title.split { character in
            !character.isNumber && character != ":"
        }
        for candidate in candidates {
            let components = candidate.split(separator: ":", omittingEmptySubsequences: false)
            guard components.count == 2,
                  (1...2).contains(components[0].count),
                  components[1].count == 2,
                  let hour = Int(components[0]),
                  let minute = Int(components[1]),
                  (0...23).contains(hour),
                  (0...59).contains(minute) else {
                continue
            }
            return (hour, minute)
        }
        return nil
    }

    private static func executableTaskIndex(
        taskID: String?,
        snapshot: V2AppSnapshot
    ) throws -> Int? {
        guard let taskID else { return nil }
        guard let index = snapshot.tasks.firstIndex(where: { $0.id == taskID }) else {
            throw V2EngineError.taskNotFound(taskID)
        }
        switch snapshot.tasks[index].status {
        case .archived:
            throw V2EngineError.taskArchived(taskID)
        case .done:
            throw V2EngineError.taskCompleted(taskID)
        case .notStarted, .active, .paused:
            return index
        }
    }

    static func validatePlacement(
        parentID: String?,
        contextID: String?,
        tasks: [V2Task],
        contexts: [V2TaskContext]
    ) throws -> String? {
        let parent: V2Task?
        if let parentID {
            guard let found = tasks.first(where: { $0.id == parentID && $0.status != .archived }) else {
                throw V2EngineError.taskNotFound(parentID)
            }
            parent = found
        } else {
            parent = nil
        }

        let effectiveContextID = contextID ?? parent?.contextID
        if let effectiveContextID,
           !contexts.contains(where: { $0.id == effectiveContextID && $0.archivedAt == nil }) {
            throw V2EngineError.contextNotFound(effectiveContextID)
        }
        if let parent, parent.contextID != effectiveContextID {
            throw V2EngineError.parentContextMismatch
        }
        return effectiveContextID
    }

    private static func descendantIDs(of taskID: String, in tasks: [V2Task]) -> Set<String> {
        var result = Set<String>()
        var pending = tasks.filter { $0.parentID == taskID }.map(\.id)
        while let next = pending.popLast() {
            guard result.insert(next).inserted else { continue }
            pending.append(contentsOf: tasks.filter { $0.parentID == next }.map(\.id))
        }
        return result
    }

    private static func sorted(_ tasks: [V2Task]) -> [V2Task] {
        tasks.sorted {
            if $0.createdAt == $1.createdAt {
                return $0.id < $1.id
            }
            return $0.createdAt < $1.createdAt
        }
    }

    private static func makeTreeNode(
        task: V2Task,
        tasks: [V2Task],
        visited: Set<String>
    ) -> V2TaskTreeNode {
        guard !visited.contains(task.id) else {
            return V2TaskTreeNode(task: task)
        }
        let nextVisited = visited.union([task.id])
        let children = sorted(tasks.filter { $0.parentID == task.id }).map {
            makeTreeNode(task: $0, tasks: tasks, visited: nextVisited)
        }
        return V2TaskTreeNode(task: task, children: children)
    }

    private static func completionSignal(
        for task: V2Task,
        tasks: [V2Task],
        visited: Set<String>
    ) -> Double {
        guard !visited.contains(task.id) else { return 0 }
        let children = tasks.filter { $0.parentID == task.id && $0.status != .archived }
        guard !children.isEmpty else {
            return task.status == .done ? 1 : 0
        }
        let nextVisited = visited.union([task.id])
        return children.reduce(0) {
            $0 + completionSignal(for: $1, tasks: tasks, visited: nextVisited)
        } / Double(children.count)
    }

    private static func reconcilingOpenExecutions(in snapshot: V2AppSnapshot) -> V2AppSnapshot {
        var reconciled = snapshot
        let activeTaskIDs = Set(
            reconciled.executionSegments.compactMap { segment in
                segment.endAt == nil ? segment.taskID : nil
            }
        )
        for index in reconciled.tasks.indices where activeTaskIDs.contains(reconciled.tasks[index].id) {
            guard reconciled.tasks[index].status != .archived,
                  reconciled.tasks[index].status != .done else {
                continue
            }
            reconciled.tasks[index].status = .active
            reconciled.tasks[index].completedAt = nil
        }
        return reconciled
    }
}

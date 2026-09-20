import Foundation

public extension V2Engine {
    /// Direct checkbox action uses the same task/plan mutations as Today.
    /// Retain a receipt so immediately restoring completion also restores exact prior values.
    func toggleAssistantTaskCompletion(taskID: String, planItemID: String?, at date: Date = Date()) throws {
        try commit(modules: ["core.tasks"], commandID: "core.tasks.schedule") { snapshot in
            guard let task = snapshot.tasks.first(where: { $0.id == taskID }) else { throw V2EngineError.taskNotFound(taskID) }
            guard task.status != .archived else { throw V2EngineError.taskArchived(taskID) }
            let prefix = "assistant-checkbox:" + taskID + ":"
            if task.status == .done,
               let index = snapshot.scheduleReceipts.lastIndex(where: {
                   $0.requestID.hasPrefix(prefix) && $0.undoneAt == nil
                       && (planItemID == nil || $0.changes.contains { $0.entityID == planItemID })
               }), (try? Self.validateUndoPreconditions(snapshot.scheduleReceipts[index], in: snapshot)) != nil {
                try Self.restore(snapshot.scheduleReceipts[index], in: &snapshot)
                snapshot.scheduleReceipts[index].undoneAt = date
                return
            }
            let staged = V2Engine(snapshot: snapshot, reconcileExecutions: false)
            if task.status == .done { try staged.restoreTodayItem(planItemID: planItemID, taskID: taskID, at: date) }
            else { try staged.completeTodayItem(planItemID: planItemID, taskID: taskID, at: date) }
            var changes = [V2ScheduleChange(taskID: taskID, before: task, after: staged.snapshot.tasks.first { $0.id == taskID })]
            if let planItemID {
                changes.append(.init(planItemID: planItemID, before: snapshot.planItems.first { $0.id == planItemID },
                    after: staged.snapshot.planItems.first { $0.id == planItemID }))
            }
            snapshot.tasks = staged.snapshot.tasks
            snapshot.planItems = staged.snapshot.planItems
            let id = UUID().uuidString
            snapshot.scheduleReceipts.append(.init(id: id, requestID: prefix + id,
                summary: task.status == .done ? "恢复待办" : "完成任务", changes: changes, createdAt: date))
        }
    }

    @discardableResult
    func applyScheduleProposal(
        _ proposal: V2ScheduleProposal,
        requestID: String,
        at date: Date = Date(),
        calendar: Calendar = .current,
        expectedSnapshot: V2AppSnapshot? = nil
    ) throws -> V2ScheduleReceipt {
        let normalizedRequestID = requestID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedRequestID.isEmpty, normalizedRequestID == requestID else {
            throw V2EngineError.invalidScheduleRequestID
        }

        if let existing = snapshot.scheduleReceipts.first(where: { $0.requestID == normalizedRequestID }) {
            return existing
        }

        guard proposal.operations.count <= Self.maximumScheduleOperations else {
            throw V2EngineError.scheduleTooManyOperations(proposal.operations.count)
        }
        guard !proposal.operations.isEmpty else {
            throw V2EngineError.invalidScheduleOperation("proposal has no operations")
        }

        let summary = proposal.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else {
            throw V2EngineError.invalidScheduleOperation("proposal summary is blank")
        }

        return try commit(modules: ["core.tasks"], commandID: "core.tasks.schedule") { snapshot in
            if let expectedSnapshot {
                try Self.validateExpectedSnapshot(
                    expectedSnapshot,
                    current: snapshot,
                    proposal: proposal
                )
            }
            let before = snapshot
            var aliases: [String: String] = [:]
            var touched = TouchedEntities()

            for operation in proposal.operations {
                try Self.apply(
                    operation,
                    to: &snapshot,
                    aliases: &aliases,
                    touched: &touched,
                    at: date,
                    calendar: calendar
                )
            }

            let receipt = V2ScheduleReceipt(
                id: UUID().uuidString,
                requestID: normalizedRequestID,
                summary: summary,
                changes: Self.changes(
                    from: before,
                    to: snapshot,
                    touched: touched
                ),
                createdAt: date
            )
            snapshot.scheduleReceipts.append(receipt)
            return receipt
        }
    }

    @discardableResult
    func undoScheduleReceipt(
        id: String,
        at date: Date = Date()
    ) throws -> V2ScheduleReceipt {
        guard snapshot.scheduleReceipts.contains(where: { $0.id == id }) else {
            throw V2EngineError.scheduleReceiptNotFound(id)
        }

        return try commit(modules: ["core.tasks"], commandID: "core.tasks.undoSchedule") { snapshot in
            guard let receiptIndex = snapshot.scheduleReceipts.firstIndex(where: { $0.id == id }) else {
                throw V2EngineError.scheduleReceiptNotFound(id)
            }
            guard snapshot.scheduleReceipts[receiptIndex].undoneAt == nil else {
                throw V2EngineError.scheduleReceiptAlreadyUndone(id)
            }

            let receipt = snapshot.scheduleReceipts[receiptIndex]
            try Self.validateUndoPreconditions(receipt, in: snapshot)
            try Self.restore(receipt, in: &snapshot)
            snapshot.scheduleReceipts[receiptIndex].undoneAt = date
            return snapshot.scheduleReceipts[receiptIndex]
        }
    }
}

private extension V2Engine {
    static let maximumScheduleOperations = 100

    struct TouchedEntities {
        var taskIDs: [String] = []
        var planItemIDs: [String] = []

        mutating func task(_ id: String) {
            if !taskIDs.contains(id) {
                taskIDs.append(id)
            }
        }

        mutating func planItem(_ id: String) {
            if !planItemIDs.contains(id) {
                planItemIDs.append(id)
            }
        }
    }

    static func apply(
        _ operation: V2ScheduleOperation,
        to snapshot: inout V2AppSnapshot,
        aliases: inout [String: String],
        touched: inout TouchedEntities,
        at date: Date,
        calendar: Calendar
    ) throws {
        switch operation.kind {
        case .createTask:
            try createTask(
                operation,
                in: &snapshot,
                aliases: &aliases,
                touched: &touched,
                at: date
            )
        case .updateTask:
            try updateTask(
                operation,
                in: &snapshot,
                aliases: aliases,
                touched: &touched,
                at: date
            )
        case .scheduleTask:
            try scheduleTask(
                operation,
                in: &snapshot,
                aliases: aliases,
                touched: &touched,
                calendar: calendar
            )
        case .reschedulePlanItem:
            try reschedulePlanItem(
                operation,
                in: &snapshot,
                touched: &touched,
                calendar: calendar
            )
        case .cancelPlanItem:
            try cancelPlanItem(operation, in: &snapshot, touched: &touched)
        case .completeTask:
            try updateTaskStatus(
                operation,
                in: &snapshot,
                aliases: aliases,
                touched: &touched,
                status: .done,
                completedAt: date,
                archivedAt: nil,
                at: date
            )
        case .restoreTask:
            try validateStatusOperation(operation, name: "restoreTask")
            let taskID = try resolvedTaskID(for: operation, aliases: aliases)
            guard let taskIndex = snapshot.tasks.firstIndex(where: { $0.id == taskID }) else {
                throw V2EngineError.taskNotFound(taskID)
            }
            if let parentID = snapshot.tasks[taskIndex].parentID,
               let parent = snapshot.tasks.first(where: { $0.id == parentID }),
               parent.status == .archived {
                throw V2EngineError.taskArchived(parentID)
            }
            let status: V2Task.Status = snapshot.executionSegments.contains {
                $0.taskID == taskID && $0.endAt == nil
            } ? .active : .notStarted
            snapshot.tasks[taskIndex].status = status
            snapshot.tasks[taskIndex].completedAt = nil
            snapshot.tasks[taskIndex].archivedAt = nil
            snapshot.tasks[taskIndex].updatedAt = date
            touched.task(taskID)
        case .archiveTask:
            try archiveTask(
                operation,
                in: &snapshot,
                aliases: aliases,
                touched: &touched,
                at: date
            )
        }
    }

    static func createTask(
        _ operation: V2ScheduleOperation,
        in snapshot: inout V2AppSnapshot,
        aliases: inout [String: String],
        touched: inout TouchedEntities,
        at date: Date
    ) throws {
        guard operation.targetID == nil,
              operation.day == nil,
              operation.startMinute == nil,
              operation.durationMinutes == nil,
              !operation.clearParent,
              !operation.clearContext,
              !operation.clearTime,
              operation.title != nil else {
            throw V2EngineError.invalidScheduleOperation("createTask contains unsupported or missing fields")
        }
        let title = try normalizedScheduleTitle(operation.title!)
        let parentID = try resolvedOptionalTaskReference(operation.parentID, aliases: aliases)
        let contextID = try normalizedOptionalID(operation.contextID)
        let effectiveContextID = try V2Engine.validatePlacement(
            parentID: parentID,
            contextID: contextID,
            tasks: snapshot.tasks,
            contexts: snapshot.taskContexts
        )

        if let localID = operation.localID {
            guard isCleanID(localID) else {
                throw V2EngineError.invalidScheduleOperation("createTask localID is invalid")
            }
            let existingIDs = Set(
                snapshot.tasks.map(\.id)
                    + snapshot.planItems.map(\.id)
                    + snapshot.taskContexts.map(\.id)
            )
            guard aliases[localID] == nil,
                  !existingIDs.contains(localID) else {
                throw V2EngineError.duplicateScheduleLocalID(localID)
            }
        }

        let task = V2Task(
            id: UUID().uuidString,
            contextID: effectiveContextID,
            parentID: parentID,
            title: title,
            note: operation.note ?? "",
            createdAt: date,
            updatedAt: date
        )
        snapshot.tasks.append(task)
        if let localID = operation.localID {
            aliases[localID] = task.id
        }
        touched.task(task.id)
    }

    static func updateTask(
        _ operation: V2ScheduleOperation,
        in snapshot: inout V2AppSnapshot,
        aliases: [String: String],
        touched: inout TouchedEntities,
        at date: Date
    ) throws {
        guard operation.day == nil,
              operation.startMinute == nil,
              operation.durationMinutes == nil,
              !operation.clearTime,
              !(operation.clearParent && operation.parentID != nil),
              !(operation.clearContext && operation.contextID != nil),
              operation.title != nil || operation.note != nil || operation.parentID != nil
                || operation.contextID != nil || operation.clearParent || operation.clearContext else {
            throw V2EngineError.invalidScheduleOperation("updateTask has no supported changes")
        }
        let taskID = try resolvedTaskID(for: operation, aliases: aliases)
        guard let index = snapshot.tasks.firstIndex(where: { $0.id == taskID }) else {
            throw V2EngineError.taskNotFound(taskID)
        }
        guard snapshot.tasks[index].status != .archived else {
            throw V2EngineError.taskArchived(taskID)
        }

        let descendants = descendantIDs(of: taskID, in: snapshot.tasks)
        let parentID: String?
        if operation.clearParent {
            parentID = nil
        } else if let requestedParentID = operation.parentID {
            parentID = try resolvedTaskReference(requestedParentID, aliases: aliases)
        } else {
            parentID = snapshot.tasks[index].parentID
        }
        if parentID == taskID || parentID.map(descendants.contains) == true {
            throw V2EngineError.taskHierarchyCycle
        }

        let requestedContextID: String?
        if operation.clearContext {
            requestedContextID = nil
        } else if let contextID = operation.contextID {
            requestedContextID = try normalizedOptionalID(contextID)
        } else {
            requestedContextID = snapshot.tasks[index].contextID
        }
        let effectiveContextID = try V2Engine.validatePlacement(
            parentID: parentID,
            contextID: requestedContextID,
            tasks: snapshot.tasks,
            contexts: snapshot.taskContexts
        )

        if let title = operation.title {
            snapshot.tasks[index].title = try normalizedScheduleTitle(title)
        }
        if let note = operation.note {
            snapshot.tasks[index].note = note
        }
        snapshot.tasks[index].parentID = parentID
        snapshot.tasks[index].contextID = effectiveContextID
        snapshot.tasks[index].updatedAt = date
        touched.task(taskID)

        for descendantID in descendants {
            guard let descendantIndex = snapshot.tasks.firstIndex(where: { $0.id == descendantID }) else {
                continue
            }
            snapshot.tasks[descendantIndex].contextID = effectiveContextID
            snapshot.tasks[descendantIndex].updatedAt = date
            touched.task(descendantID)
        }
    }

    static func scheduleTask(
        _ operation: V2ScheduleOperation,
        in snapshot: inout V2AppSnapshot,
        aliases: [String: String],
        touched: inout TouchedEntities,
        calendar: Calendar
    ) throws {
        guard operation.day != nil,
              operation.note == nil,
              operation.parentID == nil,
              operation.contextID == nil,
              !operation.clearParent,
              !operation.clearContext,
              !operation.clearTime else {
            throw V2EngineError.invalidScheduleOperation("scheduleTask contains unsupported or missing fields")
        }
        let taskID = try resolvedTaskID(for: operation, aliases: aliases)
        guard let task = snapshot.tasks.first(where: { $0.id == taskID }) else {
            throw V2EngineError.taskNotFound(taskID)
        }
        guard task.status != .archived else {
            throw V2EngineError.taskArchived(taskID)
        }
        let day = try dayStart(operation.day!, calendar: calendar)
        let times = try planTimes(
            day: day,
            startMinute: operation.startMinute,
            durationMinutes: operation.durationMinutes,
            calendar: calendar
        )
        let title = try normalizedScheduleTitle(operation.title ?? task.title)
        let item = V2PlanItem(
            id: UUID().uuidString,
            date: day,
            startAt: times.startAt,
            endAt: times.endAt,
            taskID: taskID,
            title: title
        )
        snapshot.planItems.append(item)
        touched.planItem(item.id)
    }

    static func reschedulePlanItem(
        _ operation: V2ScheduleOperation,
        in snapshot: inout V2AppSnapshot,
        touched: inout TouchedEntities,
        calendar: Calendar
    ) throws {
        guard operation.localID == nil,
              operation.note == nil,
              operation.parentID == nil,
              operation.contextID == nil,
              !operation.clearParent,
              !operation.clearContext,
              operation.clearTime || operation.day != nil || operation.startMinute != nil
                || operation.durationMinutes != nil || operation.title != nil else {
            throw V2EngineError.invalidScheduleOperation("reschedulePlanItem has no supported changes")
        }
        let planItemID = try requiredTargetID(operation)
        guard let index = snapshot.planItems.firstIndex(where: { $0.id == planItemID }) else {
            throw V2EngineError.planItemNotFound(planItemID)
        }
        guard snapshot.planItems[index].status == .planned else {
                throw V2EngineError.invalidScheduleOperation("plan item is not planned: \(planItemID)")
        }

        let oldItem = snapshot.planItems[index]
        let oldDay = calendar.startOfDay(for: oldItem.date)
        let day = try operation.day.map { try dayStart($0, calendar: calendar) } ?? oldDay
        let times: (startAt: Date?, endAt: Date?)
        if operation.clearTime {
            guard operation.startMinute == nil, operation.durationMinutes == nil else {
                throw V2EngineError.invalidScheduleOperation("clearTime cannot include time fields")
            }
            times = (nil, nil)
        } else {
            times = try shiftedPlanTimes(
                item: oldItem,
                oldDay: oldDay,
                newDay: day,
                startMinute: operation.startMinute,
                durationMinutes: operation.durationMinutes,
                calendar: calendar
            )
        }

        snapshot.planItems[index].date = day
        snapshot.planItems[index].startAt = times.startAt
        snapshot.planItems[index].endAt = times.endAt
        if let title = operation.title {
            snapshot.planItems[index].title = try normalizedScheduleTitle(title)
        }
        touched.planItem(planItemID)
    }

    static func cancelPlanItem(
        _ operation: V2ScheduleOperation,
        in snapshot: inout V2AppSnapshot,
        touched: inout TouchedEntities
    ) throws {
        guard operation.localID == nil,
              operation.title == nil,
              operation.note == nil,
              operation.parentID == nil,
              operation.contextID == nil,
              operation.day == nil,
              operation.startMinute == nil,
              operation.durationMinutes == nil,
              !operation.clearParent,
              !operation.clearContext,
              !operation.clearTime else {
            throw V2EngineError.invalidScheduleOperation("cancelPlanItem contains unsupported fields")
        }
        let planItemID = try requiredTargetID(operation)
        guard let index = snapshot.planItems.firstIndex(where: { $0.id == planItemID }) else {
            throw V2EngineError.planItemNotFound(planItemID)
        }
        guard snapshot.planItems[index].status == .planned else {
            throw V2EngineError.invalidScheduleOperation("plan item is not planned: \(planItemID)")
        }
        snapshot.planItems[index].status = .canceled
        touched.planItem(planItemID)
    }

    static func updateTaskStatus(
        _ operation: V2ScheduleOperation,
        in snapshot: inout V2AppSnapshot,
        aliases: [String: String],
        touched: inout TouchedEntities,
        status: V2Task.Status,
        completedAt: Date?,
        archivedAt: Date?,
        at date: Date
    ) throws {
        try validateStatusOperation(operation, name: "task status")
        let taskID = try resolvedTaskID(for: operation, aliases: aliases)
        guard let index = snapshot.tasks.firstIndex(where: { $0.id == taskID }) else {
            throw V2EngineError.taskNotFound(taskID)
        }
        guard snapshot.tasks[index].status != .archived else {
            throw V2EngineError.taskArchived(taskID)
        }
        snapshot.tasks[index].status = status
        snapshot.tasks[index].completedAt = completedAt
        snapshot.tasks[index].archivedAt = archivedAt
        snapshot.tasks[index].updatedAt = date
        touched.task(taskID)
    }

    static func archiveTask(
        _ operation: V2ScheduleOperation,
        in snapshot: inout V2AppSnapshot,
        aliases: [String: String],
        touched: inout TouchedEntities,
        at date: Date
    ) throws {
        try validateStatusOperation(operation, name: "archiveTask")
        let taskID = try resolvedTaskID(for: operation, aliases: aliases)
        guard snapshot.tasks.contains(where: { $0.id == taskID }) else {
            throw V2EngineError.taskNotFound(taskID)
        }
        let affectedIDs = descendantIDs(of: taskID, in: snapshot.tasks).union([taskID])
        for index in snapshot.tasks.indices where affectedIDs.contains(snapshot.tasks[index].id) {
            guard snapshot.tasks[index].status != .archived else { continue }
            snapshot.tasks[index].status = .archived
            snapshot.tasks[index].archivedAt = date
            snapshot.tasks[index].updatedAt = date
            touched.task(snapshot.tasks[index].id)
        }
    }

    static func validateStatusOperation(
        _ operation: V2ScheduleOperation,
        name: String
    ) throws {
        guard operation.title == nil,
              operation.note == nil,
              operation.parentID == nil,
              operation.contextID == nil,
              operation.day == nil,
              operation.startMinute == nil,
              operation.durationMinutes == nil,
              !operation.clearParent,
              !operation.clearContext,
              !operation.clearTime else {
            throw V2EngineError.invalidScheduleOperation("\(name) contains unsupported fields")
        }
    }

    static func changes(
        from before: V2AppSnapshot,
        to after: V2AppSnapshot,
        touched: TouchedEntities
    ) -> [V2ScheduleChange] {
        var result: [V2ScheduleChange] = []
        for taskID in touched.taskIDs {
            let old = before.tasks.first { $0.id == taskID }
            let new = after.tasks.first { $0.id == taskID }
            guard old != new else { continue }
            result.append(V2ScheduleChange(taskID: taskID, before: old, after: new))
        }
        for planItemID in touched.planItemIDs {
            let old = before.planItems.first { $0.id == planItemID }
            let new = after.planItems.first { $0.id == planItemID }
            guard old != new else { continue }
            result.append(V2ScheduleChange(planItemID: planItemID, before: old, after: new))
        }
        return result
    }

    static func validateUndoPreconditions(
        _ receipt: V2ScheduleReceipt,
        in snapshot: V2AppSnapshot
    ) throws {
        for change in receipt.changes {
            switch change.entityKind {
            case .task:
                guard change.beforePlanItem == nil, change.afterPlanItem == nil else {
                    throw V2EngineError.scheduleReceiptConflict(change.entityID)
                }
                let current = snapshot.tasks.first { $0.id == change.entityID }
                guard current == change.afterTask else {
                    throw V2EngineError.scheduleReceiptConflict(change.entityID)
                }
            case .planItem:
                guard change.beforeTask == nil, change.afterTask == nil else {
                    throw V2EngineError.scheduleReceiptConflict(change.entityID)
                }
                let current = snapshot.planItems.first { $0.id == change.entityID }
                guard current == change.afterPlanItem else {
                    throw V2EngineError.scheduleReceiptConflict(change.entityID)
                }
            }
        }

        let removedTaskIDs = Set(
            receipt.changes.compactMap { change in
                change.entityKind == .task && change.beforeTask == nil && change.afterTask != nil
                    ? change.entityID : nil
            }
        )
        let removedPlanItemIDs = Set(
            receipt.changes.compactMap { change in
                change.entityKind == .planItem && change.beforePlanItem == nil && change.afterPlanItem != nil
                    ? change.entityID : nil
            }
        )

        for task in snapshot.tasks where !removedTaskIDs.contains(task.id) {
            if let parentID = task.parentID, removedTaskIDs.contains(parentID) {
                throw V2EngineError.scheduleReceiptDanglingReference(task.id)
            }
        }
        for item in snapshot.planItems where !removedPlanItemIDs.contains(item.id) {
            if let taskID = item.taskID, removedTaskIDs.contains(taskID) {
                throw V2EngineError.scheduleReceiptDanglingReference(item.id)
            }
        }
        for segment in snapshot.executionSegments {
            if let taskID = segment.taskID, removedTaskIDs.contains(taskID) {
                throw V2EngineError.scheduleReceiptDanglingReference(segment.id)
            }
            if let planItemID = segment.createdFromPlanItemID,
               removedPlanItemIDs.contains(planItemID) {
                throw V2EngineError.scheduleReceiptDanglingReference(segment.id)
            }
        }

        var candidate = snapshot
        try restore(receipt, in: &candidate)
        try validateRestoredSnapshot(candidate)
    }

    static func validateRestoredSnapshot(_ snapshot: V2AppSnapshot) throws {
        for task in snapshot.tasks {
            if let contextID = task.contextID {
                guard snapshot.taskContexts.contains(where: {
                    $0.id == contextID && $0.archivedAt == nil
                }) else {
                    throw V2EngineError.scheduleReceiptDanglingReference(task.id)
                }
            }
            if let parentID = task.parentID {
                guard let parent = snapshot.tasks.first(where: { $0.id == parentID }) else {
                    throw V2EngineError.scheduleReceiptDanglingReference(task.id)
                }
                guard parent.contextID == task.contextID else {
                    throw V2EngineError.scheduleReceiptDanglingReference(task.id)
                }
            }
        }
        for item in snapshot.planItems {
            if let taskID = item.taskID,
               !snapshot.tasks.contains(where: { $0.id == taskID }) {
                throw V2EngineError.scheduleReceiptDanglingReference(item.id)
            }
        }
        for segment in snapshot.executionSegments {
            if let taskID = segment.taskID,
               !snapshot.tasks.contains(where: { $0.id == taskID }) {
                throw V2EngineError.scheduleReceiptDanglingReference(segment.id)
            }
            if let planItemID = segment.createdFromPlanItemID,
               !snapshot.planItems.contains(where: { $0.id == planItemID }) {
                throw V2EngineError.scheduleReceiptDanglingReference(segment.id)
            }
        }
    }

    static func validateExpectedSnapshot(
        _ expected: V2AppSnapshot,
        current: V2AppSnapshot,
        proposal: V2ScheduleProposal
    ) throws {
        var aliases: Set<String> = []
        for operation in proposal.operations where operation.kind == .createTask {
            if let localID = operation.localID {
                aliases.insert(localID)
            }
        }

        var taskIDs: Set<String> = []
        var planItemIDs: Set<String> = []
        var contextIDs: Set<String> = []
        var taskIDsWhoseDescendantsMatter: Set<String> = []
        var taskIDsWhoseExecutionMatters: Set<String> = []

        for operation in proposal.operations {
            switch operation.kind {
            case .createTask:
                if let parentID = operation.parentID, !aliases.contains(parentID) {
                    taskIDs.insert(parentID)
                }
                if let contextID = operation.contextID {
                    contextIDs.insert(contextID)
                }
            case .updateTask:
                if let taskID = existingReference(
                    operation,
                    aliases: aliases
                ) {
                    taskIDs.insert(taskID)
                    taskIDsWhoseDescendantsMatter.insert(taskID)
                }
                if let parentID = operation.parentID, !aliases.contains(parentID) {
                    taskIDs.insert(parentID)
                }
                if let contextID = operation.contextID {
                    contextIDs.insert(contextID)
                }
            case .scheduleTask:
                if let taskID = existingReference(
                    operation,
                    aliases: aliases
                ) {
                    taskIDs.insert(taskID)
                }
            case .reschedulePlanItem, .cancelPlanItem:
                if let targetID = operation.targetID, !aliases.contains(targetID) {
                    planItemIDs.insert(targetID)
                }
            case .completeTask:
                if let taskID = existingReference(
                    operation,
                    aliases: aliases
                ) {
                    taskIDs.insert(taskID)
                }
            case .restoreTask:
                if let taskID = existingReference(
                    operation,
                    aliases: aliases
                ) {
                    taskIDs.insert(taskID)
                    taskIDsWhoseExecutionMatters.insert(taskID)
                }
            case .archiveTask:
                if let taskID = existingReference(
                    operation,
                    aliases: aliases
                ) {
                    taskIDs.insert(taskID)
                    taskIDsWhoseDescendantsMatter.insert(taskID)
                }
            }
        }

        for taskID in taskIDsWhoseDescendantsMatter {
            taskIDs.formUnion(descendantIDs(of: taskID, in: expected.tasks))
            taskIDs.formUnion(descendantIDs(of: taskID, in: current.tasks))
        }
        for contextID in contextIDs {
            guard expected.taskContexts.first(where: { $0.id == contextID }) ==
                    current.taskContexts.first(where: { $0.id == contextID }) else {
                throw V2EngineError.staleScheduleProposal(contextID)
            }
        }
        for taskID in taskIDs {
            guard expected.tasks.first(where: { $0.id == taskID }) ==
                    current.tasks.first(where: { $0.id == taskID }) else {
                throw V2EngineError.staleScheduleProposal(taskID)
            }
        }
        for planItemID in planItemIDs {
            guard expected.planItems.first(where: { $0.id == planItemID }) ==
                    current.planItems.first(where: { $0.id == planItemID }) else {
                throw V2EngineError.staleScheduleProposal(planItemID)
            }
        }
        for taskID in taskIDsWhoseExecutionMatters {
            let expectedSegments = expected.executionSegments.filter {
                $0.taskID == taskID && $0.endAt == nil
            }
            let currentSegments = current.executionSegments.filter {
                $0.taskID == taskID && $0.endAt == nil
            }
            guard expectedSegments == currentSegments else {
                throw V2EngineError.staleScheduleProposal(taskID)
            }
        }

    }

    static func existingReference(
        _ operation: V2ScheduleOperation,
        aliases: Set<String>
    ) -> String? {
        let rawID = operation.targetID ?? operation.localID
        guard let rawID, !aliases.contains(rawID) else {
            return nil
        }
        return rawID
    }

    static func restore(
        _ receipt: V2ScheduleReceipt,
        in snapshot: inout V2AppSnapshot
    ) throws {
        for change in receipt.changes {
            switch change.entityKind {
            case .task:
                if let before = change.beforeTask {
                    if let index = snapshot.tasks.firstIndex(where: { $0.id == change.entityID }) {
                        snapshot.tasks[index] = before
                    } else {
                        snapshot.tasks.append(before)
                    }
                } else {
                    snapshot.tasks.removeAll { $0.id == change.entityID }
                }
            case .planItem:
                if let before = change.beforePlanItem {
                    if let index = snapshot.planItems.firstIndex(where: { $0.id == change.entityID }) {
                        snapshot.planItems[index] = before
                    } else {
                        snapshot.planItems.append(before)
                    }
                } else {
                    snapshot.planItems.removeAll { $0.id == change.entityID }
                }
            }
        }
    }

    static func resolvedTaskID(
        for operation: V2ScheduleOperation,
        aliases: [String: String]
    ) throws -> String {
        guard operation.targetID == nil || operation.localID == nil else {
            throw V2EngineError.invalidScheduleOperation("operation has both targetID and localID")
        }
        if let targetID = operation.targetID {
            guard isCleanID(targetID) else {
                throw V2EngineError.invalidScheduleOperation("targetID is invalid")
            }
            return aliases[targetID] ?? targetID
        }
        if let localID = operation.localID {
            guard isCleanID(localID), let resolved = aliases[localID] else {
                throw V2EngineError.taskNotFound(localID)
            }
            return resolved
        }
        throw V2EngineError.invalidScheduleOperation("operation requires targetID or localID")
    }

    static func requiredTargetID(_ operation: V2ScheduleOperation) throws -> String {
        guard let targetID = operation.targetID,
              isCleanID(targetID),
              operation.localID == nil else {
            throw V2EngineError.invalidScheduleOperation("plan item operation requires targetID")
        }
        return targetID
    }

    static func resolvedTaskReference(
        _ rawID: String,
        aliases: [String: String]
    ) throws -> String {
        guard isCleanID(rawID) else {
            throw V2EngineError.invalidScheduleOperation("task reference is invalid")
        }
        return aliases[rawID] ?? rawID
    }

    static func resolvedOptionalTaskReference(
        _ rawID: String?,
        aliases: [String: String]
    ) throws -> String? {
        guard let rawID else { return nil }
        return try resolvedTaskReference(rawID, aliases: aliases)
    }

    static func normalizedOptionalID(_ rawID: String?) throws -> String? {
        guard let rawID else { return nil }
        guard isCleanID(rawID) else {
            throw V2EngineError.invalidScheduleOperation("ID is invalid")
        }
        return rawID
    }

    static func isCleanID(_ value: String) -> Bool {
        !value.isEmpty && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalizedScheduleTitle(_ title: String) throws -> String {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw V2EngineError.blankTitle
        }
        return normalized
    }

    static func dayStart(_ rawDay: String, calendar: Calendar) throws -> Date {
        guard rawDay.count == 10,
              rawDay.index(rawDay.startIndex, offsetBy: 4) < rawDay.endIndex,
              rawDay[rawDay.index(rawDay.startIndex, offsetBy: 4)] == "-",
              rawDay[rawDay.index(rawDay.startIndex, offsetBy: 7)] == "-" else {
            throw V2EngineError.invalidScheduleOperation("invalid day: \(rawDay)")
        }
        let parts = rawDay.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4,
              parts[1].count == 2,
              parts[2].count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            throw V2EngineError.invalidScheduleOperation("invalid day: \(rawDay)")
        }
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        guard let parsed = calendar.date(from: components),
              calendar.dateComponents([.year, .month, .day], from: parsed).year == year,
              calendar.dateComponents([.year, .month, .day], from: parsed).month == month,
              calendar.dateComponents([.year, .month, .day], from: parsed).day == day else {
            throw V2EngineError.invalidScheduleOperation("invalid day: \(rawDay)")
        }
        return calendar.startOfDay(for: parsed)
    }

    static func planTimes(
        day: Date,
        startMinute: Int?,
        durationMinutes: Int?,
        calendar: Calendar
    ) throws -> (startAt: Date?, endAt: Date?) {
        guard let startMinute else {
            guard durationMinutes == nil else {
                throw V2EngineError.invalidScheduleOperation("duration requires startMinute")
            }
            return (nil, nil)
        }
        guard (0..<24 * 60).contains(startMinute) else {
            throw V2EngineError.invalidScheduleOperation("startMinute is out of range")
        }
        let duration = try validatedDuration(durationMinutes)
        let startAt = try wallClockTime(
            day: day,
            startMinute: startMinute,
            calendar: calendar
        )
        guard let duration else { return (startAt, nil) }
        guard startMinute + duration <= 24 * 60,
              let endAt = calendar.date(byAdding: .minute, value: duration, to: startAt),
              endAt > startAt else {
            throw V2EngineError.invalidPlanTimeRange("schedule")
        }
        return (startAt, endAt)
    }

    static func wallClockTime(
        day: Date,
        startMinute: Int,
        calendar: Calendar
    ) throws -> Date {
        let hour = startMinute / 60
        let minute = startMinute % 60
        guard let candidate = calendar.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: day
        ) else {
            throw V2EngineError.invalidScheduleOperation("startMinute cannot be represented")
        }
        let expectedDay = calendar.dateComponents([.year, .month, .day], from: day)
        let actual = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: candidate
        )
        guard actual.year == expectedDay.year,
              actual.month == expectedDay.month,
              actual.day == expectedDay.day,
              actual.hour == hour,
              actual.minute == minute else {
            throw V2EngineError.invalidScheduleOperation("startMinute is not a valid wall-clock time")
        }
        return candidate
    }

    static func shiftedPlanTimes(
        item: V2PlanItem,
        oldDay: Date,
        newDay: Date,
        startMinute: Int?,
        durationMinutes: Int?,
        calendar: Calendar
    ) throws -> (startAt: Date?, endAt: Date?) {
        let dateShiftedStart: Date? = item.startAt.map {
            shiftTime($0, from: oldDay, to: newDay, calendar: calendar)
        }
        let dateShiftedEnd: Date? = item.endAt.map {
            shiftTime($0, from: oldDay, to: newDay, calendar: calendar)
        }
        if let startMinute {
            guard (0..<24 * 60).contains(startMinute) else {
                throw V2EngineError.invalidScheduleOperation("startMinute is out of range")
            }
            let startAt = try wallClockTime(
                day: newDay,
                startMinute: startMinute,
                calendar: calendar
            )
            let duration: Int?
            if let durationMinutes {
                duration = try validatedDuration(durationMinutes)
            } else if let oldStart = item.startAt, let oldEnd = item.endAt {
                duration = Int(oldEnd.timeIntervalSince(oldStart) / 60)
            } else {
                duration = nil
            }
            guard let duration else { return (startAt, nil) }
            guard startMinute + duration <= 24 * 60,
                  let endAt = calendar.date(byAdding: .minute, value: duration, to: startAt),
                  endAt > startAt else {
                throw V2EngineError.invalidPlanTimeRange(item.id)
            }
            return (startAt, endAt)
        }

        if let durationMinutes {
            guard let startAt = dateShiftedStart else {
                throw V2EngineError.invalidScheduleOperation("duration requires an existing startAt")
            }
            let duration = try validatedDuration(durationMinutes)!
            let startComponents = calendar.dateComponents([.hour, .minute], from: startAt)
            let startMinute = (startComponents.hour ?? 0) * 60 + (startComponents.minute ?? 0)
            guard startMinute + duration <= 24 * 60,
                  let endAt = calendar.date(byAdding: .minute, value: duration, to: startAt),
                  endAt > startAt else {
                throw V2EngineError.invalidPlanTimeRange(item.id)
            }
            return (startAt, endAt)
        }
        if let startAt = dateShiftedStart,
           let endAt = dateShiftedEnd,
           endAt <= startAt {
            throw V2EngineError.invalidPlanTimeRange(item.id)
        }
        return (dateShiftedStart, dateShiftedEnd)
    }

    static func validatedDuration(_ durationMinutes: Int?) throws -> Int? {
        guard let durationMinutes else { return nil }
        guard (1...24 * 60).contains(durationMinutes) else {
            throw V2EngineError.invalidScheduleOperation("durationMinutes is out of range")
        }
        return durationMinutes
    }

    static func shiftTime(
        _ date: Date,
        from oldDay: Date,
        to newDay: Date,
        calendar: Calendar
    ) -> Date {
        let sourceDay = calendar.startOfDay(for: date)
        let dayOffset = calendar.dateComponents(
            [.day],
            from: oldDay,
            to: sourceDay
        ).day ?? 0
        let targetDay = calendar.date(
            byAdding: .day,
            value: dayOffset,
            to: newDay
        ) ?? newDay
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        return calendar.date(
            bySettingHour: components.hour ?? 0,
            minute: components.minute ?? 0,
            second: components.second ?? 0,
            of: targetDay
        ) ?? date
    }

    static func descendantIDs(of taskID: String, in tasks: [V2Task]) -> Set<String> {
        var result = Set<String>()
        var pending = tasks.filter { $0.parentID == taskID }.map(\.id)
        while let next = pending.popLast() {
            guard result.insert(next).inserted else { continue }
            pending.append(contentsOf: tasks.filter { $0.parentID == next }.map(\.id))
        }
        return result
    }
}

import Foundation

public extension V2Engine {
    /// Completes or restores one task and every non-canceled plan item for
    /// that task on the requested day in one durable schedule transaction.
    ///
    /// The staged Today mutations are deliberately used for each plan item so
    /// task status and open-execution behavior stay aligned with Today. The
    /// outer commit is the only operation that saves the resulting snapshot,
    /// which also gives the caller one receipt to undo atomically.
    @discardableResult
    func setTaskCompletion(
        taskID: String,
        completed: Bool,
        at date: Date = Date(),
        calendar: Calendar = .current
    ) throws -> V2ScheduleReceipt {
        try commit(modules: ["core.tasks"], commandID: "core.tasks.schedule") { snapshot in
            guard let taskIndex = snapshot.tasks.firstIndex(where: { $0.id == taskID }) else {
                throw V2EngineError.taskNotFound(taskID)
            }
            let task = snapshot.tasks[taskIndex]
            guard task.status != .archived else {
                throw V2EngineError.taskArchived(taskID)
            }

            let day = calendar.startOfDay(for: date)
            let planItemIDs = snapshot.planItems.compactMap { item -> String? in
                guard item.taskID == taskID,
                      item.status != .canceled,
                      calendar.isDate(item.date, inSameDayAs: day) else {
                    return nil
                }
                return item.id
            }
            let desiredPlanStatus: V2PlanItem.Status = completed ? .completed : .planned
            let hasOpenExecution = snapshot.executionSegments.contains {
                $0.taskID == taskID && $0.endAt == nil
            }
            let desiredTaskStatus: V2Task.Status = completed
                ? .done
                : (hasOpenExecution ? .active : .notStarted)
            let taskAlreadyMatches = task.status == desiredTaskStatus
                && (completed ? task.completedAt != nil : task.completedAt == nil)
            let planItemsAlreadyMatch = planItemIDs.allSatisfy { id in
                snapshot.planItems.first(where: { $0.id == id })?.status == desiredPlanStatus
            }
            let requestPrefix = "task-completion:\(taskID):\(completed ? "complete" : "restore"):"

            // Reusing an outstanding empty receipt keeps repeated taps
            // idempotent while still giving the host a durable receipt ID.
            if taskAlreadyMatches && planItemsAlreadyMatch {
                if let existing = snapshot.scheduleReceipts.last(where: {
                    $0.requestID.hasPrefix(requestPrefix)
                        && $0.undoneAt == nil
                        && $0.changes.isEmpty
                }) {
                    return existing
                }
                let id = UUID().uuidString
                let receipt = V2ScheduleReceipt(
                    id: id,
                    requestID: requestPrefix + id,
                    summary: completed ? "完成任务" : "恢复待办",
                    changes: [],
                    createdAt: date
                )
                snapshot.scheduleReceipts.append(receipt)
                return receipt
            }

            let beforeTask = task
            let beforePlanItems = planItemIDs.compactMap { id in
                snapshot.planItems.first(where: { $0.id == id }).map { (id, $0) }
            }
            let staged = V2Engine(snapshot: snapshot, reconcileExecutions: false)
            for planItemID in planItemIDs {
                if completed {
                    try staged.completeTodayItem(planItemID: planItemID, taskID: taskID, at: date)
                } else {
                    try staged.restoreTodayItem(planItemID: planItemID, taskID: taskID, at: date)
                }
            }
            if planItemIDs.isEmpty {
                if completed {
                    try staged.completeTodayItem(planItemID: nil, taskID: taskID, at: date)
                } else {
                    try staged.restoreTodayItem(planItemID: nil, taskID: taskID, at: date)
                }
            }

            snapshot.tasks = staged.snapshot.tasks
            snapshot.planItems = staged.snapshot.planItems
            var changes: [V2ScheduleChange] = []
            let afterTask = staged.snapshot.tasks.first { $0.id == taskID }
            if beforeTask != afterTask {
                changes.append(V2ScheduleChange(taskID: taskID, before: beforeTask, after: afterTask))
            }
            for (id, beforePlanItem) in beforePlanItems {
                let afterPlanItem = staged.snapshot.planItems.first { $0.id == id }
                if beforePlanItem != afterPlanItem {
                    changes.append(V2ScheduleChange(planItemID: id, before: beforePlanItem, after: afterPlanItem))
                }
            }

            let id = UUID().uuidString
            let receipt = V2ScheduleReceipt(
                id: id,
                requestID: requestPrefix + id,
                summary: completed ? "完成任务" : "恢复待办",
                changes: changes,
                createdAt: date
            )
            snapshot.scheduleReceipts.append(receipt)
            return receipt
        }
    }
}

import Foundation
import ToughTrialV2Core

extension V2AppStore {
    func planReminderItems(at date: Date = Date()) -> [V2PlanItem] {
        let snapshot = engine.snapshot
        let today = calendar.startOfDay(for: date)
        let runningPlans = Set(snapshot.executionSegments.filter { $0.endAt == nil }.compactMap(\.createdFromPlanItemID))
        return snapshot.planItems.filter { item in
            let task = snapshot.tasks.first { $0.id == item.taskID }
            return item.status == .planned && item.date >= today && !runningPlans.contains(item.id)
                && task?.status != .done && task?.status != .archived
        }.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            return ($0.startAt ?? .distantFuture) < ($1.startAt ?? .distantFuture)
        }
    }

    @discardableResult
    func setPlanReminder(_ original: V2PlanItem, startAt: Date?, at date: Date = Date()) -> V2ScheduleReceipt? {
        taskChange(at: date) {
            guard planReminderItems(at: date).contains(where: { $0.id == original.id }),
                  let current = engine.snapshot.planItems.first(where: { $0.id == original.id }) else {
                throw V2TaskEditingError.planUnavailable
            }
            guard current == original else { throw V2TaskEditingError.changed }
            let normalized = startAt.map { calendar.dateInterval(of: .minute, for: $0)!.start }
            if let normalized, normalized <= date { throw V2TaskEditingError.pastReminder }
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "yyyy-MM-dd"
            let components = normalized.map { calendar.dateComponents([.hour, .minute], from: $0) }
            let operation = V2ScheduleOperation(kind: .reschedulePlanItem, targetID: original.id,
                day: normalized.map(formatter.string(from:)),
                startMinute: components.map { ($0.hour ?? 0) * 60 + ($0.minute ?? 0) },
                clearTime: normalized == nil)
            return try engine.applyScheduleProposal(.init(summary: normalized == nil ? "清除计划提醒时间" : "设置计划提醒时间",
                operations: [operation]), requestID: "plan-reminder:" + UUID().uuidString,
                at: date, calendar: calendar, expectedSnapshot: engine.snapshot)
        }
    }

    @discardableResult
    func editTask(_ original: V2Task, title: String, note: String, at date: Date = Date()) -> V2ScheduleReceipt? {
        taskChange(at: date) {
            guard let current = engine.snapshot.tasks.first(where: { $0.id == original.id }), current.status != .archived else {
                throw V2TaskEditingError.unavailable
            }
            guard current == original else { throw V2TaskEditingError.changed }
            let proposal = V2ScheduleProposal(summary: "修改任务", operations: [
                .init(kind: .updateTask, targetID: original.id, title: title, note: note)
            ])
            return try engine.applyScheduleProposal(proposal, requestID: "task-editor:" + UUID().uuidString,
                at: date, calendar: calendar, expectedSnapshot: engine.snapshot)
        }
    }

    @discardableResult
    func editTask(
        _ original: V2Task,
        title: String,
        note: String,
        classification: V2TaskClassification,
        at date: Date = Date()
    ) -> V2ScheduleReceipt? {
        taskChange(at: date) {
            guard let current = engine.snapshot.tasks.first(where: { $0.id == original.id }),
                  current.status != .archived else {
                throw V2TaskEditingError.unavailable
            }
            guard current == original else { throw V2TaskEditingError.changed }

            return try engine.updateTaskClassification(
                id: original.id,
                title: title,
                note: note,
                classification: classification,
                expectedTask: original,
                at: date
            )
        }
    }

    @discardableResult
    func setTaskCompletion(taskID: String, completed: Bool, at date: Date = Date()) -> V2ScheduleReceipt? {
        taskChange(at: date) {
            try engine.setTaskCompletion(taskID: taskID, completed: completed, at: date, calendar: calendar)
        }
    }

    @discardableResult
    func undoTaskChange(receiptID: String, at date: Date = Date()) -> Bool {
        taskChange(at: date) { try engine.undoScheduleReceipt(id: receiptID, at: date) } != nil
    }

    private func taskChange(at date: Date, _ action: () throws -> V2ScheduleReceipt) -> V2ScheduleReceipt? {
        guard canWrite else { errorMessage = "本地数据当前不可写，请恢复后重试。"; return nil }
        do {
            let receipt = try action()
            errorMessage = nil
            highlightedScheduleIDs = Set(receipt.changes.map(\.entityID))
            V2UsageTrace.shared.record(.init(kind: .manualEdit, source: .manual, at: date))
            refreshProjection(at: date)
            refreshScheduleReminders(receipt, at: date)
            return receipt
        } catch {
            errorMessage = (error as? V2TaskEditingError)?.errorDescription
                ?? V2ScheduleUIError(underlying: error).localizedDescription
            return nil
        }
    }
}

private enum V2TaskEditingError: LocalizedError {
    case unavailable, changed, planUnavailable, pastReminder
    var errorDescription: String? {
        switch self {
        case .unavailable: "此任务已删除或归档，请关闭后重新查看。"
        case .changed: "此任务已在其他地方修改。请保留需要的文字，取消后重新打开再编辑。"
        case .planUnavailable: "此规划已完成、正在执行或不在今日及未来，请重新查看。"
        case .pastReminder: "提醒时间已过去，请选择稍后的时间。"
        }
    }
}

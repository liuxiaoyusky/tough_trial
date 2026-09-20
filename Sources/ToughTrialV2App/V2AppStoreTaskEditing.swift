import Foundation
import ToughTrialV2Core

extension V2AppStore {
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
    case unavailable, changed
    var errorDescription: String? {
        switch self {
        case .unavailable: "此任务已删除或归档，请关闭后重新查看。"
        case .changed: "此任务已在其他地方修改。请保留需要的文字，取消后重新打开再编辑。"
        }
    }
}

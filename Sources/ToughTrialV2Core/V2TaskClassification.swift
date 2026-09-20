import Foundation

/// The optional classification fields edited from an existing task.
///
/// This is deliberately a payload over the existing task fields. It does not
/// introduce a second task taxonomy or share ledger categories.
public struct V2TaskClassification: Codable, Equatable, Sendable {
    public var kind: V2Task.Kind?

    public init(kind: V2Task.Kind? = nil) {
        self.kind = kind
    }
}

public extension V2Engine {
    /// Atomically updates title/body and the optional task classification.
    ///
    /// The existing task ID is retained. This command updates only the current
    /// task's document and type; parent/context placement and descendants
    /// remain untouched because context is a structural grouping, not this
    /// type label.
    /// A schedule receipt is recorded so the same undo and stale-write checks
    /// used by task editing remain available to the app layer.
    @discardableResult
    func updateTaskClassification(
        id: String,
        title: String,
        note: String,
        classification: V2TaskClassification,
        expectedTask: V2Task? = nil,
        at date: Date = Date()
    ) throws -> V2ScheduleReceipt {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else {
            throw V2EngineError.blankTitle
        }

        return try commit(modules: ["core.tasks"], commandID: "core.tasks.update") { snapshot in
            guard let index = snapshot.tasks.firstIndex(where: { $0.id == id }) else {
                throw V2EngineError.taskNotFound(id)
            }
            let current = snapshot.tasks[index]
            guard current.status != .archived else {
                throw V2EngineError.taskArchived(id)
            }
            if let expectedTask, current != expectedTask {
                throw V2EngineError.staleScheduleProposal(id)
            }
            let beforeTarget = current
            var afterTarget = current
            afterTarget.title = normalizedTitle
            afterTarget.note = note
            afterTarget.kind = classification.kind
            afterTarget.updatedAt = date
            snapshot.tasks[index] = afterTarget

            var changes: [V2ScheduleChange] = []
            if beforeTarget != afterTarget {
                changes.append(.init(taskID: id, before: beforeTarget, after: afterTarget))
            }

            let receipt = V2ScheduleReceipt(
                id: UUID().uuidString,
                requestID: "task-classification:" + UUID().uuidString,
                summary: "修改任务分类",
                changes: changes,
                createdAt: date
            )
            snapshot.scheduleReceipts.append(receipt)
            return receipt
        }
    }

    /// Convenience overload for callers that already have the individual
    /// classification fields.
    @discardableResult
    func updateTaskClassification(
        id: String,
        title: String,
        note: String,
        kind: V2Task.Kind?,
        expectedTask: V2Task? = nil,
        at date: Date = Date()
    ) throws -> V2ScheduleReceipt {
        try updateTaskClassification(
            id: id,
            title: title,
            note: note,
            classification: V2TaskClassification(kind: kind),
            expectedTask: expectedTask,
            at: date
        )
    }
}

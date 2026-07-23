import Foundation

public extension V2PlanDraft {
    func durableRecord(at date: Date) -> V2PlanDraftRecord {
        let mode: V2PlanDraftRecord.Mode
        if !taskChanges.isEmpty && !scheduleItems.isEmpty {
            mode = .mixed
        } else if !taskChanges.isEmpty {
            mode = .breakdownOnly
        } else {
            mode = .scheduleOnly
        }

        return V2PlanDraftRecord(
            id: id,
            mode: mode,
            userPrompt: userPrompt,
            summary: "\(title)：\(summary)",
            proposedTaskChanges: taskChanges.map { change in
                V2ProposedTaskChange(
                    id: change.id,
                    title: change.title,
                    parentID: change.parentID,
                    contextID: change.contextID,
                    kind: change.kind
                )
            },
            proposedPlanItems: scheduleItems.map { item in
                V2ProposedPlanItem(
                    id: item.id,
                    date: item.date,
                    startAt: item.startAt,
                    endAt: item.endAt,
                    proposedTaskID: item.proposedTaskID,
                    title: item.title
                )
            },
            createdAt: date,
            updatedAt: date
        )
    }
}

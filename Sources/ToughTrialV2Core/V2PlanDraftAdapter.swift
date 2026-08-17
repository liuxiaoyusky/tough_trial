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
                    taskID: item.taskID,
                    proposedTaskID: item.proposedTaskID,
                    title: item.title
                )
            },
            createdAt: date,
            updatedAt: date
        )
    }
}

public extension V2PlanDraftRecord {
    func editableDraft() -> V2PlanDraft {
        let summaryParts = summary.split(separator: "：", maxSplits: 1).map(String.init)
        let restoredTitle = summaryParts.first?.trimmingCharacters(in: .whitespacesAndNewlines)
        let restoredSummary = summaryParts.count > 1
            ? summaryParts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            : summary

        return V2PlanDraft(
            id: id,
            userPrompt: userPrompt,
            title: restoredTitle?.isEmpty == false ? restoredTitle! : "未完成的计划",
            summary: restoredSummary,
            decisions: [],
            taskChanges: proposedTaskChanges.map { change in
                V2PlanDraftTaskChange(
                    id: change.id,
                    title: change.title,
                    parentID: change.parentID,
                    contextID: change.contextID,
                    kind: change.kind
                )
            },
            scheduleItems: proposedPlanItems.map { item in
                V2PlanDraftScheduleItem(
                    id: item.id,
                    date: item.date,
                    startAt: item.startAt,
                    endAt: item.endAt,
                    taskID: item.taskID,
                    proposedTaskID: item.proposedTaskID,
                    title: item.title
                )
            }
        )
    }
}

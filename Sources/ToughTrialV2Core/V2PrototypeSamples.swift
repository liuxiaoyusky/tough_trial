public extension V2PrototypeState {
    static func sample() -> V2PrototypeState {
        V2PrototypeState(
            tasks: [
                V2TaskNode(
                    id: writingTaskID,
                    title: "写作",
                    subtitle: "整理 Tough Trial V2 交互说明",
                    goal: "把计划页和执行页边界写清楚",
                    colorName: "mint",
                    status: .active,
                    spentMinutes: 42
                ),
                V2TaskNode(
                    id: runningTaskID,
                    title: "跑步",
                    subtitle: "傍晚轻量恢复",
                    goal: "保持身体状态",
                    colorName: "orange",
                    status: .planned,
                    spentMinutes: 0
                ),
                V2TaskNode(
                    id: readingTaskID,
                    title: "阅读",
                    subtitle: "读产品笔记并摘录",
                    goal: "补充任务认知素材",
                    colorName: "indigo",
                    status: .paused,
                    spentMinutes: 18
                )
            ],
            timelineItems: [
                V2TimelineItem(
                    id: "timeline-writing-start",
                    timeLabel: "09:00",
                    title: "写作进行中",
                    detail: "已投入 42 分钟，继续收束 V2 说明。",
                    taskID: writingTaskID,
                    isDone: false
                ),
                V2TimelineItem(
                    id: "timeline-running-plan",
                    timeLabel: "18:30",
                    title: "跑步",
                    detail: "晚饭前 30 分钟轻量恢复。",
                    taskID: runningTaskID,
                    isDone: false
                ),
                V2TimelineItem(
                    id: "timeline-reading-done",
                    timeLabel: "21:00",
                    title: "阅读摘录",
                    detail: "完成一轮材料阅读，留下回想证据。",
                    taskID: readingTaskID,
                    isDone: true
                )
            ],
            selectedTaskID: writingTaskID,
            activeSessions: [],
            planMessages: [
                V2PlanMessage(id: "plan-agent-welcome", role: .agent, text: "说出你想安排的时间段，我先给草稿。")
            ],
            currentPlanDraft: nil,
            savedPlanDrafts: [],
            recallReferences: [
                V2RecallReference(
                    id: recallEventID,
                    kind: .event,
                    title: "上午写作推进",
                    detail: "写作连续推进 42 分钟。"
                ),
                V2RecallReference(
                    id: recallDeviationID,
                    kind: .deviation,
                    title: "下午偏离",
                    detail: "偏离原计划，临时处理维护事项。"
                ),
                V2RecallReference(
                    id: recallPastID,
                    kind: .past,
                    title: "昨晚阅读",
                    detail: "阅读记录可作为今天计划调整的背景。"
                )
            ],
            selectedRecallReferenceIDs: [],
            recallDraft: "",
            appliedRecallText: "",
            isRecallFullscreen: false
        )
    }
}

public extension V2PrototypeState {
    static func sample() -> V2PrototypeState {
        V2PrototypeState(
            tasks: [
                V2TaskNode(
                    id: writingTaskID,
                    title: "论文段落重写",
                    subtitle: "收束今天最重要的表达",
                    goal: "写作系统",
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
                    title: "阅读 20 页",
                    subtitle: "午后暂停，可继续",
                    goal: "认知积累",
                    colorName: "indigo",
                    status: .paused,
                    spentMinutes: 18
                )
            ],
            timelineItems: [
                V2TimelineItem(
                    id: "timeline-admin-done",
                    timeLabel: "09:20",
                    title: "查报销到账",
                    detail: "已完成，可在回想引用。",
                    taskID: nil,
                    isDone: true
                ),
                V2TimelineItem(
                    id: "timeline-reading-paused",
                    timeLabel: "14:00",
                    title: "阅读 20 页",
                    detail: "暂停过一次，累计 18 分钟。",
                    taskID: readingTaskID,
                    isDone: false
                ),
                V2TimelineItem(
                    id: "timeline-writing-current",
                    timeLabel: "16:10",
                    title: "论文段落重写",
                    detail: "当前进行中，只记录今天真实耗时。",
                    taskID: writingTaskID,
                    isDone: false
                ),
                V2TimelineItem(
                    id: "timeline-urgent-form",
                    timeLabel: "刚刚",
                    title: "补交登记表",
                    detail: "临时插入，不要求分类或冲突处理。",
                    taskID: nil,
                    isDone: false
                ),
                V2TimelineItem(
                    id: "timeline-running-plan",
                    timeLabel: "晚上",
                    title: "跑步",
                    detail: "晚饭前 30 分钟轻量恢复。",
                    taskID: runningTaskID,
                    isDone: false
                )
            ],
            selectedTaskID: writingTaskID,
            activeSessions: [
                V2ActiveSession(
                    id: "session-sample-writing",
                    taskID: writingTaskID,
                    title: "论文段落重写",
                    startedAtLabel: "16:10",
                    currentElapsed: 12,
                    totalElapsed: 42,
                    status: .running
                ),
                V2ActiveSession(
                    id: "session-sample-reading",
                    taskID: readingTaskID,
                    title: "阅读 20 页",
                    startedAtLabel: "14:00",
                    currentElapsed: 0,
                    totalElapsed: 18,
                    status: .paused
                )
            ],
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

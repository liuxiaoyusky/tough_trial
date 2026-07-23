import Foundation

public extension V2PrototypeState {
    static func sample() -> V2PrototypeState {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        func day(_ offset: Int) -> Date {
            calendar.date(byAdding: .day, value: offset, to: today) ?? today
        }

        return V2PrototypeState(
            tasks: [
                V2TaskNode(
                    id: "goal-creator-growth",
                    title: "自媒体成长",
                    subtitle: "把被称赞的内容沉淀成稳定系统",
                    goal: "自媒体成长",
                    colorName: "blue",
                    status: .active,
                    spentMinutes: 42,
                    children: [
                        V2TaskNode(
                            id: "branch-positioning",
                            title: "定位",
                            subtitle: "找到可重复的内容位置",
                            goal: "自媒体成长",
                            colorName: "orange",
                            status: .planned,
                            spentMinutes: 0,
                            children: [
                                V2TaskNode(
                                    id: "task-position-boundary",
                                    title: "内容边界",
                                    subtitle: "明确什么不做",
                                    goal: "自媒体成长",
                                    colorName: "orange",
                                    status: .done,
                                    spentMinutes: 35
                                ),
                                V2TaskNode(
                                    id: "task-position-audience",
                                    title: "目标读者",
                                    subtitle: "补一轮真实反馈",
                                    goal: "自媒体成长",
                                    colorName: "orange",
                                    status: .planned,
                                    spentMinutes: 0
                                )
                            ]
                        ),
                        V2TaskNode(
                            id: "branch-topic-bank",
                            title: "选题库",
                            subtitle: "把灵感变成可复用材料",
                            goal: "自媒体成长",
                            colorName: "blue",
                            status: .active,
                            spentMinutes: 18,
                            children: [
                                V2TaskNode(
                                    id: "task-benchmark-accounts",
                                    title: "对标账号",
                                    subtitle: "建立 3 个观察对象",
                                    goal: "自媒体成长",
                                    colorName: "blue",
                                    status: .done,
                                    spentMinutes: 40,
                                    children: [
                                        V2TaskNode(
                                            id: "leaf-benchmark-redbook",
                                            title: "小红书对标",
                                            subtitle: "已建立观察对象",
                                            goal: "自媒体成长",
                                            colorName: "blue",
                                            status: .done,
                                            spentMinutes: 12
                                        ),
                                        V2TaskNode(
                                            id: "leaf-benchmark-video",
                                            title: "视频号对标",
                                            subtitle: "已建立观察对象",
                                            goal: "自媒体成长",
                                            colorName: "blue",
                                            status: .done,
                                            spentMinutes: 14
                                        ),
                                        V2TaskNode(
                                            id: "leaf-benchmark-podcast",
                                            title: "播客对标",
                                            subtitle: "已建立观察对象",
                                            goal: "自媒体成长",
                                            colorName: "blue",
                                            status: .done,
                                            spentMinutes: 14
                                        )
                                    ]
                                ),
                                V2TaskNode(
                                    id: "task-hit-breakdown",
                                    title: "爆款拆解",
                                    subtitle: "先拆 10 个样本",
                                    goal: "自媒体成长",
                                    colorName: "blue",
                                    status: .planned,
                                    spentMinutes: 0,
                                    children: [
                                        V2TaskNode(
                                            id: "leaf-hit-title",
                                            title: "标题结构",
                                            subtitle: "完成第一轮归纳",
                                            goal: "自媒体成长",
                                            colorName: "blue",
                                            status: .done,
                                            spentMinutes: 18
                                        ),
                                        V2TaskNode(
                                            id: "leaf-hit-comment",
                                            title: "评论动机",
                                            subtitle: "继续补真实评论",
                                            goal: "自媒体成长",
                                            colorName: "blue",
                                            status: .planned,
                                            spentMinutes: 0
                                        ),
                                        V2TaskNode(
                                            id: "leaf-hit-retention",
                                            title: "停留钩子",
                                            subtitle: "找开头保留原因",
                                            goal: "自媒体成长",
                                            colorName: "blue",
                                            status: .planned,
                                            spentMinutes: 0
                                        )
                                    ]
                                ),
                                V2TaskNode(
                                    id: "task-daily-topic",
                                    title: "每日选题",
                                    subtitle: "形成低摩擦记录",
                                    goal: "自媒体成长",
                                    colorName: "blue",
                                    status: .planned,
                                    spentMinutes: 0
                                )
                            ]
                        ),
                        V2TaskNode(
                            id: "branch-expression",
                            title: "表达",
                            subtitle: "把材料写成稳定输出",
                            goal: "自媒体成长",
                            colorName: "mint",
                            status: .active,
                            spentMinutes: 42,
                            children: [
                                V2TaskNode(
                                    id: writingTaskID,
                                    title: "论文段落重写",
                                    subtitle: "收束今天最重要的表达",
                                    goal: "自媒体成长",
                                    colorName: "mint",
                                    status: .active,
                                    spentMinutes: 42
                                )
                            ]
                        ),
                        V2TaskNode(
                            id: "branch-review",
                            title: "复盘",
                            subtitle: "把反馈沉淀成下一步",
                            goal: "自媒体成长",
                            colorName: "violet",
                            status: .planned,
                            spentMinutes: 0,
                            children: [
                                V2TaskNode(
                                    id: "task-comment-review",
                                    title: "评论复盘",
                                    subtitle: "保留真实反馈",
                                    goal: "自媒体成长",
                                    colorName: "violet",
                                    status: .planned,
                                    spentMinutes: 0
                                )
                            ]
                        )
                    ]
                ),
                V2TaskNode(
                    id: "goal-health",
                    title: "健康生活",
                    subtitle: "现实维护和长期状态放在一起观察",
                    goal: "保持身体状态",
                    colorName: "orange",
                    status: .planned,
                    spentMinutes: 0,
                    children: [
                        V2TaskNode(
                            id: runningTaskID,
                            title: "跑步",
                            subtitle: "傍晚轻量恢复",
                            goal: "保持身体状态",
                            colorName: "orange",
                            status: .planned,
                            spentMinutes: 0
                        )
                    ]
                ),
                V2TaskNode(
                    id: "goal-reading",
                    title: "认知积累",
                    subtitle: "长期输入不要求每天完成",
                    goal: "认知积累",
                    colorName: "indigo",
                    status: .paused,
                    spentMinutes: 18,
                    children: [
                        V2TaskNode(
                            id: readingTaskID,
                            title: "阅读 20 页",
                            subtitle: "午后暂停，可继续",
                            goal: "认知积累",
                            colorName: "indigo",
                            status: .paused,
                            spentMinutes: 18
                        )
                    ]
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
            scheduledTasks: [
                V2ScheduledTask(
                    id: "schedule-admin-done",
                    title: "查报销到账",
                    detail: "上午确认到账结果。",
                    taskID: nil,
                    date: today,
                    placement: .timed(startMinute: 9 * 60, durationMinutes: 45),
                    isDone: true
                ),
                V2ScheduledTask(
                    id: "schedule-writing",
                    title: "论文段落重写",
                    detail: "继续今天正在推进的表达任务。",
                    taskID: writingTaskID,
                    date: today,
                    placement: .timed(startMinute: 16 * 60 + 10, durationMinutes: 90),
                    isDone: false
                ),
                V2ScheduledTask(
                    id: "schedule-payment",
                    title: "交费截止",
                    detail: "今天内处理。",
                    taskID: nil,
                    date: today,
                    placement: .allDay,
                    isDone: false
                ),
                V2ScheduledTask(
                    id: "schedule-interview",
                    title: "整理访谈记录",
                    detail: "先整理事实，不做扩写。",
                    taskID: nil,
                    date: day(1),
                    placement: .timed(startMinute: 10 * 60, durationMinutes: 60),
                    isDone: false
                ),
                V2ScheduledTask(
                    id: "schedule-reading",
                    title: "阅读 20 页",
                    detail: "可暂停，保留低摩擦。",
                    taskID: readingTaskID,
                    date: day(1),
                    placement: .timed(startMinute: 14 * 60, durationMinutes: 65),
                    isDone: false
                ),
                V2ScheduledTask(
                    id: "schedule-running",
                    title: "跑步 3 km",
                    detail: "傍晚轻量恢复。",
                    taskID: runningTaskID,
                    date: day(2),
                    placement: .timed(startMinute: 18 * 60 + 30, durationMinutes: 60),
                    isDone: false
                ),
                V2ScheduledTask(
                    id: "schedule-material",
                    title: "回材料",
                    detail: "可与电话并行。",
                    taskID: nil,
                    date: day(3),
                    placement: .timed(startMinute: 15 * 60, durationMinutes: 60),
                    isDone: false
                ),
                V2ScheduledTask(
                    id: "schedule-call",
                    title: "电话",
                    detail: "临时维护事项。",
                    taskID: nil,
                    date: day(3),
                    placement: .timed(startMinute: 15 * 60, durationMinutes: 40),
                    isDone: false
                ),
                V2ScheduledTask(
                    id: "schedule-form",
                    title: "补交登记表",
                    detail: "已安排的现实维护。",
                    taskID: nil,
                    date: day(4),
                    placement: .timed(startMinute: 10 * 60, durationMinutes: 85),
                    isDone: false
                ),
                V2ScheduledTask(
                    id: "schedule-family",
                    title: "家庭聚餐",
                    detail: "全天提醒。",
                    taskID: nil,
                    date: day(5),
                    placement: .allDay,
                    isDone: false
                ),
                V2ScheduledTask(
                    id: "schedule-next-week",
                    title: "下周资料整理",
                    detail: "给下周留一个明确落点。",
                    taskID: nil,
                    date: day(6),
                    placement: .timed(startMinute: 16 * 60, durationMinutes: 70),
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
            planMessages: [],
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

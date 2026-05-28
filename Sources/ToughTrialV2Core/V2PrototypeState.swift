public struct V2TaskNode: Equatable, Sendable {
    public enum Status: String, Equatable, Sendable {
        case planned
        case active
        case paused
        case done
    }

    public var id: String
    public var title: String
    public var subtitle: String
    public var goal: String
    public var colorName: String
    public var status: Status
    public var spentMinutes: Int
    public var children: [V2TaskNode]

    public init(
        id: String,
        title: String,
        subtitle: String,
        goal: String,
        colorName: String,
        status: Status,
        spentMinutes: Int,
        children: [V2TaskNode] = []
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.goal = goal
        self.colorName = colorName
        self.status = status
        self.spentMinutes = spentMinutes
        self.children = children
    }
}

public struct V2TimelineItem: Equatable, Sendable {
    public var id: String
    public var timeLabel: String
    public var title: String
    public var detail: String
    public var taskID: String?
    public var isDone: Bool

    public init(
        id: String,
        timeLabel: String,
        title: String,
        detail: String,
        taskID: String?,
        isDone: Bool
    ) {
        self.id = id
        self.timeLabel = timeLabel
        self.title = title
        self.detail = detail
        self.taskID = taskID
        self.isDone = isDone
    }
}

public struct V2ActiveSession: Equatable, Sendable {
    public enum Status: String, Equatable, Sendable {
        case running
        case paused
    }

    public var id: String
    public var taskID: String
    public var title: String
    public var startedAtLabel: String
    public var currentElapsed: Int
    public var totalElapsed: Int
    public var status: Status

    public init(
        id: String,
        taskID: String,
        title: String,
        startedAtLabel: String,
        currentElapsed: Int,
        totalElapsed: Int,
        status: Status
    ) {
        self.id = id
        self.taskID = taskID
        self.title = title
        self.startedAtLabel = startedAtLabel
        self.currentElapsed = currentElapsed
        self.totalElapsed = totalElapsed
        self.status = status
    }
}

public struct V2PlanMessage: Equatable, Sendable {
    public enum Role: String, Equatable, Sendable {
        case user
        case agent
    }

    public var id: String
    public var role: Role
    public var text: String

    public init(id: String, role: Role, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }
}

public struct V2PlanDraft: Equatable, Sendable {
    public var title: String
    public var summary: String
    public var decisions: [String]
    public var scheduleItems: [String]

    public init(title: String, summary: String, decisions: [String], scheduleItems: [String]) {
        self.title = title
        self.summary = summary
        self.decisions = decisions
        self.scheduleItems = scheduleItems
    }
}

public struct V2RecallReference: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case event
        case deviation
        case past
    }

    public var id: String
    public var kind: Kind
    public var title: String
    public var detail: String

    public init(id: String, kind: Kind, title: String, detail: String) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
    }
}

public struct V2PrototypeState: Equatable, Sendable {
    public static let writingTaskID = "task-writing"
    public static let runningTaskID = "task-running"
    public static let readingTaskID = "task-reading"
    public static let recallEventID = "recall-event-writing"
    public static let recallDeviationID = "recall-deviation-afternoon"
    public static let recallPastID = "recall-past-reading"

    public var tasks: [V2TaskNode]
    public var timelineItems: [V2TimelineItem]
    public var selectedTaskID: String?
    public var activeSession: V2ActiveSession?
    public var planMessages: [V2PlanMessage]
    public var currentPlanDraft: V2PlanDraft?
    public var savedPlanDrafts: [V2PlanDraft]
    public var recallReferences: [V2RecallReference]
    public var selectedRecallReferenceIDs: [String]
    public var recallDraft: String
    public var appliedRecallText: String
    public var isRecallFullscreen: Bool

    public init(
        tasks: [V2TaskNode],
        timelineItems: [V2TimelineItem],
        selectedTaskID: String?,
        activeSession: V2ActiveSession?,
        planMessages: [V2PlanMessage],
        currentPlanDraft: V2PlanDraft?,
        savedPlanDrafts: [V2PlanDraft],
        recallReferences: [V2RecallReference],
        selectedRecallReferenceIDs: [String],
        recallDraft: String,
        appliedRecallText: String,
        isRecallFullscreen: Bool
    ) {
        self.tasks = tasks
        self.timelineItems = timelineItems
        self.selectedTaskID = selectedTaskID
        self.activeSession = activeSession
        self.planMessages = planMessages
        self.currentPlanDraft = currentPlanDraft
        self.savedPlanDrafts = savedPlanDrafts
        self.recallReferences = recallReferences
        self.selectedRecallReferenceIDs = selectedRecallReferenceIDs
        self.recallDraft = recallDraft
        self.appliedRecallText = appliedRecallText
        self.isRecallFullscreen = isRecallFullscreen
    }

    public static func sample() -> V2PrototypeState {
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
            activeSession: nil,
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

    public func flattenTasks() -> [V2TaskNode] {
        tasks.flatMap { task in
            [task] + flatten(task.children)
        }
    }

    public func taskTitle(for id: String) -> String? {
        flattenTasks().first { $0.id == id }?.title
    }

    public mutating func startSession(taskID: String, title: String, startedAtLabel: String) {
        activeSession = V2ActiveSession(
            id: "session-\(taskID)-\(timelineItems.count + 1)",
            taskID: taskID,
            title: title,
            startedAtLabel: startedAtLabel,
            currentElapsed: 0,
            totalElapsed: 0,
            status: .running
        )
        selectedTaskID = taskID
        updateTask(taskID) { task in
            task.status = .active
        }
    }

    public mutating func toggleSession(_ id: String) {
        guard var session = activeSession, session.id == id else { return }
        session.status = session.status == .running ? .paused : .running
        activeSession = session
        updateTask(session.taskID) { task in
            task.status = session.status == .paused ? .paused : .active
        }
    }

    public mutating func endSession(_ id: String, totalElapsed: Int, endLabel: String) {
        guard let session = activeSession, session.id == id else { return }
        updateTask(session.taskID) { task in
            task.spentMinutes += totalElapsed
            task.status = .done
        }
        timelineItems.append(
            V2TimelineItem(
                id: "timeline-session-\(timelineItems.count + 1)",
                timeLabel: endLabel,
                title: session.title,
                detail: "完成一次 \(totalElapsed) 分钟执行。",
                taskID: session.taskID,
                isDone: true
            )
        )
        activeSession = nil
    }

    public mutating func quickAddTodayTask(title: String) {
        let taskID = "task-quick-\(flattenTasks().count + 1)"
        tasks.append(
            V2TaskNode(
                id: taskID,
                title: title,
                subtitle: "快速加入今天",
                goal: "先记录，再决定是否展开",
                colorName: "teal",
                status: .planned,
                spentMinutes: 0
            )
        )
        timelineItems.append(
            V2TimelineItem(
                id: "timeline-quick-\(timelineItems.count + 1)",
                timeLabel: "今天",
                title: title,
                detail: "快速加入今天，可并行处理，不打断当前执行。",
                taskID: taskID,
                isDone: false
            )
        )
        selectedTaskID = taskID
    }

    public mutating func sendPlanPrompt(_ prompt: String) {
        planMessages.append(V2PlanMessage(id: "plan-user-\(planMessages.count + 1)", role: .user, text: prompt))
        let draft = V2PlanDraft(
            title: "计划草稿",
            summary: "根据“\(prompt)”生成的低摩擦安排。",
            decisions: [
                "先保留用户输入的意图",
                "只生成草稿，等待确认后写入今天"
            ],
            scheduleItems: [
                "写作：继续推进当前主线",
                "阅读：安排在低能量时段"
            ]
        )
        currentPlanDraft = draft
        planMessages.append(
            V2PlanMessage(
                id: "plan-agent-\(planMessages.count + 1)",
                role: .agent,
                text: "我先整理成一个草稿，确认后再写入时间线。"
            )
        )
    }

    public mutating func saveCurrentPlanDraft() {
        guard let draft = currentPlanDraft else { return }
        savedPlanDrafts.append(draft)
    }

    public mutating func acceptCurrentPlanDraft() {
        guard let draft = currentPlanDraft else { return }
        saveCurrentPlanDraft()
        timelineItems.append(
            V2TimelineItem(
                id: "timeline-plan-\(timelineItems.count + 1)",
                timeLabel: "计划",
                title: draft.title,
                detail: draft.summary,
                taskID: nil,
                isDone: false
            )
        )
        currentPlanDraft = nil
    }

    public mutating func insertRecallReference(_ id: String) {
        guard let reference = recallReferences.first(where: { $0.id == id }) else { return }
        if !selectedRecallReferenceIDs.contains(id) {
            selectedRecallReferenceIDs.append(id)
            appendRecallEvidence(reference)
        }
    }

    public mutating func applyRecallDraft() {
        appliedRecallText = recallDraft
    }

    public mutating func toggleRecallFullscreen() {
        isRecallFullscreen.toggle()
    }

    private func flatten(_ nodes: [V2TaskNode]) -> [V2TaskNode] {
        nodes.flatMap { node in
            [node] + flatten(node.children)
        }
    }

    private mutating func updateTask(_ id: String, mutate: (inout V2TaskNode) -> Void) {
        updateTask(id, in: &tasks, mutate: mutate)
    }

    private func updateTask(_ id: String, in nodes: inout [V2TaskNode], mutate: (inout V2TaskNode) -> Void) {
        for index in nodes.indices {
            if nodes[index].id == id {
                mutate(&nodes[index])
                return
            }
            updateTask(id, in: &nodes[index].children, mutate: mutate)
        }
    }

    private mutating func appendRecallEvidence(_ reference: V2RecallReference) {
        let evidence = "[\(reference.kind.rawValue)] \(reference.title)：\(reference.detail)"
        if recallDraft.isEmpty {
            recallDraft = evidence
        } else {
            recallDraft += "\n\(evidence)"
        }
    }
}

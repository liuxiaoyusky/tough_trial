public struct V2PrototypeState: Equatable, Sendable {
    public static let writingTaskID = "task-writing"
    public static let runningTaskID = "task-running"
    public static let readingTaskID = "task-reading"
    public static let recallEventID = "recall-event-writing"
    public static let recallDeviationID = "recall-deviation-afternoon"
    public static let recallPastID = "recall-past-reading"

    public var tasks: [V2TaskNode]
    public var timelineItems: [V2TimelineItem]
    public var scheduledTasks: [V2ScheduledTask]
    public var selectedTaskID: String?
    public var activeSessions: [V2ActiveSession]
    public var planMessages: [V2PlanMessage]
    public var currentPlanDraft: V2PlanDraft?
    public var savedPlanDrafts: [V2PlanDraft]
    public var recallReferences: [V2RecallReference]
    public var selectedRecallReferenceIDs: [String]
    public var recallDraft: String
    public var appliedRecallText: String
    public var recallDraftsByDate: [String: String]
    public var selectedRecallReferenceIDsByDate: [String: [String]]
    public var appliedRecallTextsByDate: [String: String]
    public var isRecallFullscreen: Bool

    public init(
        tasks: [V2TaskNode],
        timelineItems: [V2TimelineItem],
        scheduledTasks: [V2ScheduledTask] = [],
        selectedTaskID: String?,
        activeSessions: [V2ActiveSession],
        planMessages: [V2PlanMessage],
        currentPlanDraft: V2PlanDraft?,
        savedPlanDrafts: [V2PlanDraft],
        recallReferences: [V2RecallReference],
        selectedRecallReferenceIDs: [String],
        recallDraft: String,
        appliedRecallText: String,
        recallDraftsByDate: [String: String] = [:],
        selectedRecallReferenceIDsByDate: [String: [String]] = [:],
        appliedRecallTextsByDate: [String: String] = [:],
        isRecallFullscreen: Bool
    ) {
        self.tasks = tasks
        self.timelineItems = timelineItems
        self.scheduledTasks = scheduledTasks
        self.selectedTaskID = selectedTaskID
        self.activeSessions = activeSessions
        self.planMessages = planMessages
        self.currentPlanDraft = currentPlanDraft
        self.savedPlanDrafts = savedPlanDrafts
        self.recallReferences = recallReferences
        self.selectedRecallReferenceIDs = selectedRecallReferenceIDs
        self.recallDraft = recallDraft
        self.appliedRecallText = appliedRecallText
        self.recallDraftsByDate = recallDraftsByDate
        self.selectedRecallReferenceIDsByDate = selectedRecallReferenceIDsByDate
        self.appliedRecallTextsByDate = appliedRecallTextsByDate
        self.isRecallFullscreen = isRecallFullscreen
    }

    public func flattenTasks() -> [V2TaskNode] {
        func flatten(_ nodes: [V2TaskNode]) -> [V2TaskNode] {
            nodes.flatMap { node in
                [node] + flatten(node.children)
            }
        }

        return flatten(tasks)
    }

    public func taskTitle(for id: String) -> String? {
        flattenTasks().first { $0.id == id }?.title
    }
}

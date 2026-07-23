import Foundation

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

public extension V2TaskNode {
    var completionSignal: Double {
        guard !children.isEmpty else {
            return status == .done ? 1 : 0
        }

        let childTotal = children.reduce(0) { $0 + $1.completionSignal }
        return childTotal / Double(children.count)
    }

    func containsTask(id: String) -> Bool {
        self.id == id || children.contains { $0.containsTask(id: id) }
    }
}

public struct V2TimelineItem: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case task
        case executionRecord
    }

    public var id: String
    public var kind: Kind
    public var timeLabel: String
    public var title: String
    public var detail: String
    public var taskID: String?
    public var isDone: Bool

    public init(
        id: String,
        kind: Kind = .task,
        timeLabel: String,
        title: String,
        detail: String,
        taskID: String?,
        isDone: Bool
    ) {
        self.id = id
        self.kind = kind
        self.timeLabel = timeLabel
        self.title = title
        self.detail = detail
        self.taskID = taskID
        self.isDone = isDone
    }
}

public enum V2SchedulePlacement: Equatable, Sendable {
    case allDay
    case timed(startMinute: Int, durationMinutes: Int)
}

public struct V2ScheduledTask: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var detail: String
    public var taskID: String?
    public var date: Date
    public var placement: V2SchedulePlacement
    public var isDone: Bool

    public init(
        id: String,
        title: String,
        detail: String,
        taskID: String?,
        date: Date,
        placement: V2SchedulePlacement,
        isDone: Bool
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.taskID = taskID
        self.date = date
        self.placement = placement
        self.isDone = isDone
    }
}

public struct V2ActiveSession: Equatable, Sendable {
    public enum Status: String, Equatable, Sendable {
        case running
        case paused
    }

    public var id: String
    public var taskID: String?
    public var title: String
    public var startedAtLabel: String
    public var currentElapsed: Int
    public var totalElapsed: Int
    public var currentElapsedSeconds: Int
    public var totalElapsedSeconds: Int
    public var status: Status

    public init(
        id: String,
        taskID: String?,
        title: String,
        startedAtLabel: String,
        currentElapsed: Int,
        totalElapsed: Int,
        currentElapsedSeconds: Int? = nil,
        totalElapsedSeconds: Int? = nil,
        status: Status
    ) {
        self.id = id
        self.taskID = taskID
        self.title = title
        self.startedAtLabel = startedAtLabel
        self.currentElapsed = currentElapsed
        self.totalElapsed = totalElapsed
        self.currentElapsedSeconds = currentElapsedSeconds ?? currentElapsed * 60
        self.totalElapsedSeconds = totalElapsedSeconds ?? totalElapsed * 60
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

public enum V2PlanConversationPhase: String, Equatable, Sendable {
    case empty
    case clarifying
    case reviewingDraft
    case complete
}

public struct V2PlanDraftScheduleItem: Identifiable, Equatable, Sendable {
    public var id: String
    public var date: Date
    public var startAt: Date?
    public var endAt: Date?
    public var title: String

    public init(
        id: String,
        date: Date,
        startAt: Date? = nil,
        endAt: Date? = nil,
        title: String
    ) {
        self.id = id
        self.date = date
        self.startAt = startAt
        self.endAt = endAt
        self.title = title
    }
}

public struct V2PlanDraft: Equatable, Sendable {
    public var id: String
    public var userPrompt: String
    public var title: String
    public var summary: String
    public var decisions: [String]
    public var scheduleItems: [V2PlanDraftScheduleItem]

    public init(
        id: String = UUID().uuidString,
        userPrompt: String,
        title: String,
        summary: String,
        decisions: [String],
        scheduleItems: [V2PlanDraftScheduleItem]
    ) {
        self.id = id
        self.userPrompt = userPrompt
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

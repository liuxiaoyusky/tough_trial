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
    public var taskID: String?
    public var title: String
    public var startedAtLabel: String
    public var currentElapsed: Int
    public var totalElapsed: Int
    public var status: Status

    public init(
        id: String,
        taskID: String?,
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

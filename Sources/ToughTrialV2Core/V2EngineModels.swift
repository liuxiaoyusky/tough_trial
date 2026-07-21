import Foundation

public struct V2TaskContext: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var note: String
    public var colorName: String
    public var createdAt: Date
    public var updatedAt: Date
    public var archivedAt: Date?

    public init(
        id: String,
        title: String,
        note: String = "",
        colorName: String,
        createdAt: Date,
        updatedAt: Date,
        archivedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.note = note
        self.colorName = colorName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.archivedAt = archivedAt
    }
}

public struct V2Task: Identifiable, Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Equatable, Sendable {
        case goal
        case commitment
        case maintenance
    }

    public enum Status: String, Codable, Equatable, Sendable {
        case notStarted
        case active
        case paused
        case done
        case archived
    }

    public var id: String
    public var contextID: String?
    public var parentID: String?
    public var title: String
    public var note: String
    public var kind: Kind?
    public var status: Status
    public var createdAt: Date
    public var updatedAt: Date
    public var completedAt: Date?
    public var archivedAt: Date?

    public init(
        id: String,
        contextID: String? = nil,
        parentID: String? = nil,
        title: String,
        note: String = "",
        kind: Kind? = nil,
        status: Status = .notStarted,
        createdAt: Date,
        updatedAt: Date,
        completedAt: Date? = nil,
        archivedAt: Date? = nil
    ) {
        self.id = id
        self.contextID = contextID
        self.parentID = parentID
        self.title = title
        self.note = note
        self.kind = kind
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
        self.archivedAt = archivedAt
    }
}

public struct V2TaskTreeNode: Equatable, Sendable {
    public var task: V2Task
    public var children: [V2TaskTreeNode]

    public init(task: V2Task, children: [V2TaskTreeNode] = []) {
        self.task = task
        self.children = children
    }

    public var completionSignal: Double {
        guard !children.isEmpty else {
            return task.status == .done ? 1 : 0
        }

        return children.reduce(0) { $0 + $1.completionSignal } / Double(children.count)
    }
}

public struct V2ExecutionSegment: Identifiable, Codable, Equatable, Sendable {
    public enum Source: String, Codable, Equatable, Sendable {
        case normal
        case zen
        case urgentInsert
    }

    public enum EndReason: String, Codable, Equatable, Sendable {
        case paused
        case stopped
    }

    public var id: String
    public var sessionID: String?
    public var taskID: String?
    public var titleSnapshot: String
    public var startAt: Date
    public var endAt: Date?
    public var endReason: EndReason?
    public var source: Source
    public var createdFromPlanItemID: String?
    public var note: String

    public init(
        id: String,
        sessionID: String? = nil,
        taskID: String? = nil,
        titleSnapshot: String,
        startAt: Date,
        endAt: Date? = nil,
        endReason: EndReason? = nil,
        source: Source,
        createdFromPlanItemID: String? = nil,
        note: String = ""
    ) {
        self.id = id
        self.sessionID = sessionID
        self.taskID = taskID
        self.titleSnapshot = titleSnapshot
        self.startAt = startAt
        self.endAt = endAt
        self.endReason = endReason
        self.source = source
        self.createdFromPlanItemID = createdFromPlanItemID
        self.note = note
    }

    public func duration(through date: Date) -> TimeInterval {
        max(0, (endAt ?? date).timeIntervalSince(startAt))
    }

    public var logicalSessionID: String {
        sessionID ?? id
    }
}

public struct V2ProposedTaskChange: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var parentID: String?
    public var contextID: String?
    public var kind: V2Task.Kind?

    public init(
        id: String,
        title: String,
        parentID: String? = nil,
        contextID: String? = nil,
        kind: V2Task.Kind? = nil
    ) {
        self.id = id
        self.title = title
        self.parentID = parentID
        self.contextID = contextID
        self.kind = kind
    }
}

public struct V2ProposedPlanItem: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var date: Date
    public var startAt: Date?
    public var endAt: Date?
    public var taskID: String?
    public var title: String

    public init(
        id: String,
        date: Date,
        startAt: Date? = nil,
        endAt: Date? = nil,
        taskID: String? = nil,
        title: String
    ) {
        self.id = id
        self.date = date
        self.startAt = startAt
        self.endAt = endAt
        self.taskID = taskID
        self.title = title
    }
}

public struct V2PlanDraftRecord: Identifiable, Codable, Equatable, Sendable {
    public enum Status: String, Codable, Equatable, Sendable {
        case draft
        case accepted
        case discarded
    }

    public enum Mode: String, Codable, Equatable, Sendable {
        case scheduleOnly
        case breakdownOnly
        case mixed
    }

    public var id: String
    public var status: Status
    public var mode: Mode
    public var userPrompt: String
    public var summary: String
    public var proposedTaskChanges: [V2ProposedTaskChange]
    public var proposedPlanItems: [V2ProposedPlanItem]
    public var createdAt: Date
    public var updatedAt: Date
    public var acceptedAt: Date?

    public init(
        id: String,
        status: Status = .draft,
        mode: Mode,
        userPrompt: String,
        summary: String,
        proposedTaskChanges: [V2ProposedTaskChange] = [],
        proposedPlanItems: [V2ProposedPlanItem] = [],
        createdAt: Date,
        updatedAt: Date,
        acceptedAt: Date? = nil
    ) {
        self.id = id
        self.status = status
        self.mode = mode
        self.userPrompt = userPrompt
        self.summary = summary
        self.proposedTaskChanges = proposedTaskChanges
        self.proposedPlanItems = proposedPlanItems
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.acceptedAt = acceptedAt
    }
}

public struct V2PlanItem: Identifiable, Codable, Equatable, Sendable {
    public enum Status: String, Codable, Equatable, Sendable {
        case planned
        case canceled
        case convertedToExecution
    }

    public var id: String
    public var date: Date
    public var startAt: Date?
    public var endAt: Date?
    public var taskID: String?
    public var title: String
    public var sourceDraftID: String?
    public var status: Status

    public init(
        id: String,
        date: Date,
        startAt: Date? = nil,
        endAt: Date? = nil,
        taskID: String? = nil,
        title: String,
        sourceDraftID: String? = nil,
        status: Status = .planned
    ) {
        self.id = id
        self.date = date
        self.startAt = startAt
        self.endAt = endAt
        self.taskID = taskID
        self.title = title
        self.sourceDraftID = sourceDraftID
        self.status = status
    }
}

public struct V2RecallEntry: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var date: Date
    public var text: String
    public var referencedTaskIDs: [String]
    public var referencedSegmentIDs: [String]
    public var referencedPlanItemIDs: [String]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        date: Date,
        text: String,
        referencedTaskIDs: [String] = [],
        referencedSegmentIDs: [String] = [],
        referencedPlanItemIDs: [String] = [],
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.date = date
        self.text = text
        self.referencedTaskIDs = referencedTaskIDs
        self.referencedSegmentIDs = referencedSegmentIDs
        self.referencedPlanItemIDs = referencedPlanItemIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct V2DreamingSuggestion: Identifiable, Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Equatable, Sendable {
        case scheduleSuggestion
        case breakdownSuggestion
    }

    public enum Status: String, Codable, Equatable, Sendable {
        case pending
        case accepted
        case discarded
    }

    public var id: String
    public var kind: Kind
    public var status: Status
    public var summary: String
    public var proposedTaskChanges: [V2ProposedTaskChange]
    public var proposedPlanItems: [V2ProposedPlanItem]
    public var createdAt: Date
    public var acceptedAt: Date?

    public init(
        id: String,
        kind: Kind,
        status: Status = .pending,
        summary: String,
        proposedTaskChanges: [V2ProposedTaskChange] = [],
        proposedPlanItems: [V2ProposedPlanItem] = [],
        createdAt: Date,
        acceptedAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.status = status
        self.summary = summary
        self.proposedTaskChanges = proposedTaskChanges
        self.proposedPlanItems = proposedPlanItems
        self.createdAt = createdAt
        self.acceptedAt = acceptedAt
    }
}

public struct V2AppSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var taskContexts: [V2TaskContext]
    public var tasks: [V2Task]
    public var planDrafts: [V2PlanDraftRecord]
    public var planItems: [V2PlanItem]
    public var executionSegments: [V2ExecutionSegment]
    public var recallEntries: [V2RecallEntry]
    public var dreamingSuggestions: [V2DreamingSuggestion]

    public init(
        schemaVersion: Int = V2AppSnapshot.currentSchemaVersion,
        taskContexts: [V2TaskContext] = [],
        tasks: [V2Task] = [],
        planDrafts: [V2PlanDraftRecord] = [],
        planItems: [V2PlanItem] = [],
        executionSegments: [V2ExecutionSegment] = [],
        recallEntries: [V2RecallEntry] = [],
        dreamingSuggestions: [V2DreamingSuggestion] = []
    ) {
        self.schemaVersion = schemaVersion
        self.taskContexts = taskContexts
        self.tasks = tasks
        self.planDrafts = planDrafts
        self.planItems = planItems
        self.executionSegments = executionSegments
        self.recallEntries = recallEntries
        self.dreamingSuggestions = dreamingSuggestions
    }

    public static var empty: V2AppSnapshot {
        V2AppSnapshot()
    }
}

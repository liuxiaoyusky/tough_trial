import Foundation

public struct V2TaskSourceReference: Codable, Equatable, Hashable, Sendable {
    public enum Kind: String, Codable, Equatable, Hashable, Sendable {
        case feishuBase
        case obsidianMarkdown
        case localCatalog
        case fixture
        case calendar
        case github
    }

    public var kind: Kind
    public var key: String
    public var location: String?
    public var updatedAt: Date?

    public init(
        kind: Kind,
        key: String,
        location: String? = nil,
        updatedAt: Date? = nil
    ) {
        self.kind = kind
        self.key = key
        self.location = location
        self.updatedAt = updatedAt
    }
}

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
    public var sourceReference: V2TaskSourceReference?

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
        archivedAt: Date? = nil,
        sourceReference: V2TaskSourceReference? = nil
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
        self.sourceReference = sourceReference
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
    public var proposedTaskID: String?
    public var title: String

    public init(
        id: String,
        date: Date,
        startAt: Date? = nil,
        endAt: Date? = nil,
        taskID: String? = nil,
        proposedTaskID: String? = nil,
        title: String
    ) {
        self.id = id
        self.date = date
        self.startAt = startAt
        self.endAt = endAt
        self.taskID = taskID
        self.proposedTaskID = proposedTaskID
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
        case completed
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

public struct V2ScheduleProposal: Codable, Equatable, Sendable {
    public var summary: String
    public var operations: [V2ScheduleOperation]

    public init(summary: String, operations: [V2ScheduleOperation]) {
        self.summary = summary
        self.operations = operations
    }
}

public struct V2ScheduleOperation: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Equatable, Sendable {
        case createTask
        case updateTask
        case scheduleTask
        case reschedulePlanItem
        case cancelPlanItem
        case completeTask
        case restoreTask
        case archiveTask
    }

    public var kind: Kind
    public var targetID: String?
    public var localID: String?
    public var title: String?
    public var note: String?
    public var parentID: String?
    public var contextID: String?
    public var day: String?
    public var startMinute: Int?
    public var durationMinutes: Int?
    public var clearParent: Bool
    public var clearContext: Bool
    public var clearTime: Bool

    public init(
        kind: Kind,
        targetID: String? = nil,
        localID: String? = nil,
        title: String? = nil,
        note: String? = nil,
        parentID: String? = nil,
        contextID: String? = nil,
        day: String? = nil,
        startMinute: Int? = nil,
        durationMinutes: Int? = nil,
        clearParent: Bool = false,
        clearContext: Bool = false,
        clearTime: Bool = false
    ) {
        self.kind = kind
        self.targetID = targetID
        self.localID = localID
        self.title = title
        self.note = note
        self.parentID = parentID
        self.contextID = contextID
        self.day = day
        self.startMinute = startMinute
        self.durationMinutes = durationMinutes
        self.clearParent = clearParent
        self.clearContext = clearContext
        self.clearTime = clearTime
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case targetID
        case localID
        case title
        case note
        case parentID
        case contextID
        case day
        case startMinute
        case durationMinutes
        case clearParent
        case clearContext
        case clearTime
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(Kind.self, forKey: .kind)
        targetID = try container.decodeIfPresent(String.self, forKey: .targetID)
        localID = try container.decodeIfPresent(String.self, forKey: .localID)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        parentID = try container.decodeIfPresent(String.self, forKey: .parentID)
        contextID = try container.decodeIfPresent(String.self, forKey: .contextID)
        day = try container.decodeIfPresent(String.self, forKey: .day)
        startMinute = try container.decodeIfPresent(Int.self, forKey: .startMinute)
        durationMinutes = try container.decodeIfPresent(Int.self, forKey: .durationMinutes)
        clearParent = try container.decodeIfPresent(Bool.self, forKey: .clearParent) ?? false
        clearContext = try container.decodeIfPresent(Bool.self, forKey: .clearContext) ?? false
        clearTime = try container.decodeIfPresent(Bool.self, forKey: .clearTime) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(targetID, forKey: .targetID)
        try container.encodeIfPresent(localID, forKey: .localID)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(note, forKey: .note)
        try container.encodeIfPresent(parentID, forKey: .parentID)
        try container.encodeIfPresent(contextID, forKey: .contextID)
        try container.encodeIfPresent(day, forKey: .day)
        try container.encodeIfPresent(startMinute, forKey: .startMinute)
        try container.encodeIfPresent(durationMinutes, forKey: .durationMinutes)
        if clearParent { try container.encode(true, forKey: .clearParent) }
        if clearContext { try container.encode(true, forKey: .clearContext) }
        if clearTime { try container.encode(true, forKey: .clearTime) }
    }
}

public struct V2ScheduleChange: Codable, Equatable, Sendable {
    public enum EntityKind: String, Codable, Equatable, Sendable {
        case task
        case planItem
    }

    public var entityKind: EntityKind
    public var entityID: String
    public var beforeTask: V2Task?
    public var afterTask: V2Task?
    public var beforePlanItem: V2PlanItem?
    public var afterPlanItem: V2PlanItem?

    public init(
        taskID: String,
        before: V2Task?,
        after: V2Task?
    ) {
        entityKind = .task
        entityID = taskID
        beforeTask = before
        afterTask = after
        beforePlanItem = nil
        afterPlanItem = nil
    }

    public init(
        planItemID: String,
        before: V2PlanItem?,
        after: V2PlanItem?
    ) {
        entityKind = .planItem
        entityID = planItemID
        beforeTask = nil
        afterTask = nil
        beforePlanItem = before
        afterPlanItem = after
    }
}

public struct V2ScheduleReceipt: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var requestID: String
    public var summary: String
    public var changes: [V2ScheduleChange]
    public var createdAt: Date
    public var undoneAt: Date?

    public init(
        id: String,
        requestID: String,
        summary: String,
        changes: [V2ScheduleChange],
        createdAt: Date,
        undoneAt: Date? = nil
    ) {
        self.id = id
        self.requestID = requestID
        self.summary = summary
        self.changes = changes
        self.createdAt = createdAt
        self.undoneAt = undoneAt
    }
}

public struct V2RecallEntry: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var date: Date
    public var text: String
    public var hasHandwriting: Bool
    public var referencedTaskIDs: [String]
    public var referencedSegmentIDs: [String]
    public var referencedPlanItemIDs: [String]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        date: Date,
        text: String,
        hasHandwriting: Bool = false,
        referencedTaskIDs: [String] = [],
        referencedSegmentIDs: [String] = [],
        referencedPlanItemIDs: [String] = [],
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.date = date
        self.text = text
        self.hasHandwriting = hasHandwriting
        self.referencedTaskIDs = referencedTaskIDs
        self.referencedSegmentIDs = referencedSegmentIDs
        self.referencedPlanItemIDs = referencedPlanItemIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case date
        case text
        case hasHandwriting
        case referencedTaskIDs
        case referencedSegmentIDs
        case referencedPlanItemIDs
        case createdAt
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        date = try container.decode(Date.self, forKey: .date)
        text = try container.decode(String.self, forKey: .text)
        hasHandwriting = try container.decodeIfPresent(Bool.self, forKey: .hasHandwriting) ?? false
        referencedTaskIDs = try container.decode([String].self, forKey: .referencedTaskIDs)
        referencedSegmentIDs = try container.decode([String].self, forKey: .referencedSegmentIDs)
        referencedPlanItemIDs = try container.decode([String].self, forKey: .referencedPlanItemIDs)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(date, forKey: .date)
        try container.encode(text, forKey: .text)
        try container.encode(hasHandwriting, forKey: .hasHandwriting)
        try container.encode(referencedTaskIDs, forKey: .referencedTaskIDs)
        try container.encode(referencedSegmentIDs, forKey: .referencedSegmentIDs)
        try container.encode(referencedPlanItemIDs, forKey: .referencedPlanItemIDs)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
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
    public static let currentSchemaVersion = 2

    public var schemaVersion: Int
    public var taskContexts: [V2TaskContext]
    public var tasks: [V2Task]
    public var planDrafts: [V2PlanDraftRecord]
    public var planItems: [V2PlanItem]
    public var executionSegments: [V2ExecutionSegment]
    public var recallEntries: [V2RecallEntry]
    public var dreamingSuggestions: [V2DreamingSuggestion]
    public var scheduleReceipts: [V2ScheduleReceipt]
    public var scheduleDocumentState: V2ScheduleDocumentState?
    public var capture: V2CaptureState
    public var outbox: [V2OutboxJob]
    public var toolOperations: [V2StoredToolOperation]
    public var extensionFields: V2ExtensionFieldState

    public init(
        schemaVersion: Int = V2AppSnapshot.currentSchemaVersion,
        taskContexts: [V2TaskContext] = [],
        tasks: [V2Task] = [],
        planDrafts: [V2PlanDraftRecord] = [],
        planItems: [V2PlanItem] = [],
        executionSegments: [V2ExecutionSegment] = [],
        recallEntries: [V2RecallEntry] = [],
        dreamingSuggestions: [V2DreamingSuggestion] = [],
        scheduleReceipts: [V2ScheduleReceipt] = [],
        scheduleDocumentState: V2ScheduleDocumentState? = nil,
        capture: V2CaptureState = V2CaptureState(),
        outbox: [V2OutboxJob] = [],
        extensionFields: V2ExtensionFieldState = .init(),
        toolOperations: [V2StoredToolOperation] = []
    ) {
        self.schemaVersion = schemaVersion
        self.taskContexts = taskContexts
        self.tasks = tasks
        self.planDrafts = planDrafts
        self.planItems = planItems
        self.executionSegments = executionSegments
        self.recallEntries = recallEntries
        self.dreamingSuggestions = dreamingSuggestions
        self.scheduleReceipts = scheduleReceipts
        self.scheduleDocumentState = scheduleDocumentState
        self.capture = capture
        self.outbox = outbox
        self.extensionFields = extensionFields
        self.toolOperations = toolOperations
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case taskContexts
        case tasks
        case planDrafts
        case planItems
        case executionSegments
        case recallEntries
        case dreamingSuggestions
        case scheduleReceipts
        case scheduleDocumentState
        case capture
        case outbox
        case extensionFields
        case toolOperations
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard (1...Self.currentSchemaVersion).contains(schemaVersion) else {
            throw V2SnapshotStoreError.unsupportedSchema(schemaVersion)
        }
        taskContexts = try container.decode([V2TaskContext].self, forKey: .taskContexts)
        tasks = try container.decode([V2Task].self, forKey: .tasks)
        planDrafts = try container.decode([V2PlanDraftRecord].self, forKey: .planDrafts)
        planItems = try container.decode([V2PlanItem].self, forKey: .planItems)
        executionSegments = try container.decode([V2ExecutionSegment].self, forKey: .executionSegments)
        recallEntries = try container.decode([V2RecallEntry].self, forKey: .recallEntries)
        dreamingSuggestions = try container.decode([V2DreamingSuggestion].self, forKey: .dreamingSuggestions)
        capture = try container.decodeIfPresent(V2CaptureState.self, forKey: .capture) ?? V2CaptureState()
        outbox = try container.decodeIfPresent([V2OutboxJob].self, forKey: .outbox) ?? []
        toolOperations = try container.decodeIfPresent([V2StoredToolOperation].self, forKey: .toolOperations) ?? []
        extensionFields = try container.decodeIfPresent(V2ExtensionFieldState.self, forKey: .extensionFields) ?? .init()
        guard capture.schemaVersion == 1, capture.finance?.schemaVersion == nil || capture.finance?.schemaVersion == 1 else { throw V2CaptureError.invalidSchema }
        scheduleDocumentState = try container.decodeIfPresent(V2ScheduleDocumentState.self, forKey: .scheduleDocumentState)
        scheduleReceipts = try container.decodeIfPresent(
            [V2ScheduleReceipt].self,
            forKey: .scheduleReceipts
        ) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(taskContexts, forKey: .taskContexts)
        try container.encode(tasks, forKey: .tasks)
        try container.encode(planDrafts, forKey: .planDrafts)
        try container.encode(planItems, forKey: .planItems)
        try container.encode(executionSegments, forKey: .executionSegments)
        try container.encode(recallEntries, forKey: .recallEntries)
        try container.encode(dreamingSuggestions, forKey: .dreamingSuggestions)
        try container.encode(scheduleReceipts, forKey: .scheduleReceipts)
        try container.encode(capture, forKey: .capture)
        try container.encode(outbox, forKey: .outbox)
        try container.encode(extensionFields, forKey: .extensionFields)
        try container.encode(toolOperations, forKey: .toolOperations)
        try container.encodeIfPresent(scheduleDocumentState, forKey: .scheduleDocumentState)
    }

    public static var empty: V2AppSnapshot {
        V2AppSnapshot()
    }
}

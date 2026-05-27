import Foundation

public enum ConfirmationState: String, Codable, Sendable, Equatable {
    case pending
    case confirmed
    case dismissed
}

public struct AITaskDraft: Codable, Sendable, Equatable {
    public let title: String
    public let priority: TaskPriorityTier
    public let estimatedDurationMinutes: Int?
    public let confirmationState: ConfirmationState

    public init(
        title: String,
        priority: TaskPriorityTier,
        estimatedDurationMinutes: Int?,
        confirmationState: ConfirmationState
    ) {
        self.title = title
        self.priority = priority
        self.estimatedDurationMinutes = estimatedDurationMinutes
        self.confirmationState = confirmationState
    }

    public func confirmed() -> AITaskDraft {
        AITaskDraft(
            title: title,
            priority: priority,
            estimatedDurationMinutes: estimatedDurationMinutes,
            confirmationState: .confirmed
        )
    }

    public func confirmedTask(id: UUID) -> TaskItem? {
        guard confirmationState == .confirmed else {
            return nil
        }

        return TaskItem.oneTime(
            id: id,
            title: title,
            priority: priority
        )
    }
}

public struct MemorySuggestion: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let title: String
    public let evidenceSummary: String
    public let confirmationState: ConfirmationState

    public init(
        id: UUID,
        title: String,
        evidenceSummary: String,
        confirmationState: ConfirmationState
    ) {
        self.id = id
        self.title = title
        self.evidenceSummary = evidenceSummary
        self.confirmationState = confirmationState
    }

    public var canSave: Bool {
        confirmationState == .confirmed
    }

    public func confirmed() -> MemorySuggestion {
        MemorySuggestion(
            id: id,
            title: title,
            evidenceSummary: evidenceSummary,
            confirmationState: .confirmed
        )
    }
}

public enum InboxMessageKind: String, Codable, Sendable, Equatable {
    case aiSuggestion
    case dreamingSuggestion
    case planningNotice
}

public struct InboxMessage: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let kind: InboxMessageKind
    public let title: String
    public let body: String
    public let confirmationState: ConfirmationState

    public init(
        id: UUID,
        kind: InboxMessageKind,
        title: String,
        body: String,
        confirmationState: ConfirmationState
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.body = body
        self.confirmationState = confirmationState
    }

    public var isActionable: Bool {
        confirmationState == .confirmed
    }

    public func confirmed() -> InboxMessage {
        InboxMessage(
            id: id,
            kind: kind,
            title: title,
            body: body,
            confirmationState: .confirmed
        )
    }
}

import Foundation

public enum AppleExternalObjectKind: String, Codable, Sendable, Equatable {
    case reminder
    case calendarEvent
    case alarm
    case localNotification
}

public struct ReminderPayload: Codable, Sendable, Equatable {
    public let title: String
    public let sourceTaskID: UUID

    public init(title: String, sourceTaskID: UUID) {
        self.title = title
        self.sourceTaskID = sourceTaskID
    }
}

public struct CalendarPayload: Codable, Sendable, Equatable {
    public let title: String
    public let sourceEventID: UUID
    public let durationMinutes: Int

    public init(title: String, sourceEventID: UUID, durationMinutes: Int) {
        self.title = title
        self.sourceEventID = sourceEventID
        self.durationMinutes = durationMinutes
    }
}

public struct AppleReminderPlan: Sendable, Equatable {
    public let policy: ReminderPolicy
    public let externalObjectKind: AppleExternalObjectKind

    public init(policy: ReminderPolicy, externalObjectKind: AppleExternalObjectKind) {
        self.policy = policy
        self.externalObjectKind = externalObjectKind
    }
}

public enum AppleIntegrationMapper {
    public static func reminderPayload(for task: TaskItem) -> ReminderPayload {
        ReminderPayload(title: task.title, sourceTaskID: task.id)
    }

    public static func calendarPayload(
        for event: TimelineEvent,
        durationMinutes: Int
    ) -> CalendarPayload {
        CalendarPayload(
            title: event.title,
            sourceEventID: event.id,
            durationMinutes: durationMinutes
        )
    }

    public static func reminderPlan(
        for task: TaskItem,
        alarmKitAvailable: Bool
    ) -> AppleReminderPlan {
        let policy = ReminderPolicy.policy(
            for: task.priority,
            alarmKitAvailable: alarmKitAvailable
        )

        return AppleReminderPlan(
            policy: policy,
            externalObjectKind: externalObjectKind(for: policy.primaryChannel)
        )
    }

    private static func externalObjectKind(for channel: ReminderChannel) -> AppleExternalObjectKind {
        switch channel {
        case .alarmKit:
            return .alarm
        case .localNotificationWithSound, .soundNotificationAndVibration, .notificationOnly:
            return .localNotification
        case .none:
            return .reminder
        }
    }
}

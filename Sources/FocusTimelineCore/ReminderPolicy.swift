import Foundation

public enum ReminderChannel: String, Codable, Sendable, Equatable {
    case alarmKit
    case localNotificationWithSound
    case soundNotificationAndVibration
    case notificationOnly
    case none
}

public struct ReminderPolicy: Equatable, Sendable {
    public let primaryChannel: ReminderChannel
    public let fallbackChannel: ReminderChannel?
    public let requiresScheduledStart: Bool

    public static func policy(
        for priority: TaskPriorityTier,
        alarmKitAvailable: Bool
    ) -> ReminderPolicy {
        switch priority {
        case .critical:
            if alarmKitAvailable {
                return ReminderPolicy(
                    primaryChannel: .alarmKit,
                    fallbackChannel: .localNotificationWithSound,
                    requiresScheduledStart: true
                )
            }

            return ReminderPolicy(
                primaryChannel: .localNotificationWithSound,
                fallbackChannel: nil,
                requiresScheduledStart: true
            )
        case .medium:
            return ReminderPolicy(
                primaryChannel: .soundNotificationAndVibration,
                fallbackChannel: nil,
                requiresScheduledStart: false
            )
        case .notifyOnly:
            return ReminderPolicy(
                primaryChannel: .notificationOnly,
                fallbackChannel: nil,
                requiresScheduledStart: false
            )
        case .none:
            return ReminderPolicy(
                primaryChannel: .none,
                fallbackChannel: nil,
                requiresScheduledStart: false
            )
        }
    }
}

import FocusTimelineCore
import Foundation

func expect(
    _ condition: @autoclosure () -> Bool,
    _ message: String,
    file: StaticString = #file,
    line: UInt = #line
) {
    if !condition() {
        FileHandle.standardError.write(Data("Check failed: \(message) at \(file):\(line)\n".utf8))
        Foundation.exit(1)
    }
}

func checkCriticalTaskUsesAlarmKitWithLocalNotificationFallback() {
    let policy = ReminderPolicy.policy(for: .critical, alarmKitAvailable: true)

    expect(policy.primaryChannel == .alarmKit, "critical task should use AlarmKit when available")
    expect(policy.fallbackChannel == .localNotificationWithSound, "critical task should fall back to local notification with sound")
    expect(policy.requiresScheduledStart, "critical task alarm should require a scheduled start")
}

func checkCriticalTaskFallsBackWhenAlarmKitUnavailable() {
    let policy = ReminderPolicy.policy(for: .critical, alarmKitAvailable: false)

    expect(policy.primaryChannel == .localNotificationWithSound, "critical task should fall back without AlarmKit")
    expect(policy.fallbackChannel == nil, "fallback policy should not have a second fallback")
    expect(policy.requiresScheduledStart, "critical fallback still requires a scheduled start")
}

func checkMediumTaskUsesSoundNotificationAndVibration() {
    let policy = ReminderPolicy.policy(for: .medium, alarmKitAvailable: true)

    expect(policy.primaryChannel == .soundNotificationAndVibration, "medium task should use sound notification and vibration")
    expect(policy.fallbackChannel == nil, "medium task should not need fallback")
    expect(!policy.requiresScheduledStart, "medium task does not require scheduled start")
}

func checkNotifyOnlyTaskUsesNotificationOnly() {
    let policy = ReminderPolicy.policy(for: .notifyOnly, alarmKitAvailable: true)

    expect(policy.primaryChannel == .notificationOnly, "notify-only task should use notification only")
    expect(policy.fallbackChannel == nil, "notify-only task should not need fallback")
    expect(!policy.requiresScheduledStart, "notify-only task does not require scheduled start")
}

func checkNoPriorityTaskDoesNotNotify() {
    let policy = ReminderPolicy.policy(for: .none, alarmKitAvailable: true)

    expect(policy.primaryChannel == .none, "no-priority task should not notify")
    expect(policy.fallbackChannel == nil, "no-priority task should not need fallback")
    expect(!policy.requiresScheduledStart, "no-priority task does not require scheduled start")
}

checkCriticalTaskUsesAlarmKitWithLocalNotificationFallback()
checkCriticalTaskFallsBackWhenAlarmKitUnavailable()
checkMediumTaskUsesSoundNotificationAndVibration()
checkNotifyOnlyTaskUsesNotificationOnly()
checkNoPriorityTaskDoesNotNotify()

print("FocusTimelineCoreChecks passed")

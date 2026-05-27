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

func checkOneTimeTaskCompletesOnce() {
    var task = TaskItem.oneTime(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        title: "买耳塞",
        priority: .notifyOnly
    )

    task.recordCompletion(amount: nil, at: Date(timeIntervalSince1970: 100))

    expect(task.status == .completed, "one-time task should complete after one completion")
    expect(task.progress.completedAmount == 1, "one-time task should record one completed amount")
    expect(task.progress.targetAmount == 1, "one-time task target should be one")
}

func checkCumulativeTaskAddsProgressTowardTotal() {
    var task = TaskItem.cumulative(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        title: "读完一本书",
        unit: "页",
        targetAmount: 1000,
        priority: .none
    )

    task.recordCompletion(amount: 30, at: Date(timeIntervalSince1970: 100))
    task.recordCompletion(amount: 20, at: Date(timeIntervalSince1970: 200))

    expect(task.progress.completedAmount == 50, "cumulative task should add progress amounts")
    expect(task.status == .active, "cumulative task should remain active before reaching target")
}

func checkFrequencyTaskCountsCompletionsInPeriod() {
    var task = TaskItem.frequencyGoal(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
        title: "本周跑 5 次 3 公里",
        targetCount: 5,
        period: .week,
        priority: .medium
    )

    task.recordCompletion(amount: nil, at: Date(timeIntervalSince1970: 100))
    task.recordCompletion(amount: nil, at: Date(timeIntervalSince1970: 200))

    expect(task.progress.completedAmount == 2, "frequency task should count completions")
    expect(task.progress.targetAmount == 5, "frequency task target should match requested count")
    expect(task.status == .active, "frequency task should remain active before target count")
}

checkCriticalTaskUsesAlarmKitWithLocalNotificationFallback()
checkCriticalTaskFallsBackWhenAlarmKitUnavailable()
checkMediumTaskUsesSoundNotificationAndVibration()
checkNotifyOnlyTaskUsesNotificationOnly()
checkNoPriorityTaskDoesNotNotify()
checkOneTimeTaskCompletesOnce()
checkCumulativeTaskAddsProgressTowardTotal()
checkFrequencyTaskCountsCompletionsInPeriod()

print("FocusTimelineCoreChecks passed")

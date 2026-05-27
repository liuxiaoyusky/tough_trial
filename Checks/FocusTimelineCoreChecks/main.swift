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

func checkPlanningDraftKeepsUnknownTimesAndUnplacedTasks() {
    let targetDate = Date(timeIntervalSince1970: 1_780_000_000)
    let fixedEvent = TimelineEvent(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
        date: targetDate,
        time: .fixed(hour: 12, minute: 0),
        title: "午餐",
        linkedTaskID: nil,
        source: .calendar,
        parallelGroupID: nil
    )
    let uncertainEvent = TimelineEvent(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!,
        date: targetDate,
        time: .unknown,
        title: "读书 40 页",
        linkedTaskID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        source: .aiPlanning,
        parallelGroupID: nil
    )
    let unplaced = TaskItem.oneTime(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000103")!,
        title: "整理相册",
        priority: .none
    )

    let draft = PlanningDraft(
        targetDate: targetDate,
        fixedEvents: [fixedEvent],
        plannedEvents: [uncertainEvent],
        unplacedTasks: [unplaced]
    )

    expect(draft.fixedEvents.count == 1, "planning draft should keep fixed events")
    expect(draft.plannedEvents.first?.time == .unknown, "planning draft should allow unknown times")
    expect(draft.unplacedTasks.first?.title == "整理相册", "planning draft should keep tasks that do not fit")
}

func checkTimelineSupportsParallelEvents() {
    let targetDate = Date(timeIntervalSince1970: 1_780_000_000)
    let groupID = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!
    let email = TimelineEvent(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000202")!,
        date: targetDate,
        time: .fixed(hour: 15, minute: 0),
        title: "回邮件",
        linkedTaskID: nil,
        source: .manual,
        parallelGroupID: groupID
    )
    let organize = TimelineEvent(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000203")!,
        date: targetDate,
        time: .fixed(hour: 15, minute: 0),
        title: "整理资料",
        linkedTaskID: nil,
        source: .manual,
        parallelGroupID: groupID
    )

    let draft = PlanningDraft(
        targetDate: targetDate,
        fixedEvents: [],
        plannedEvents: [email, organize],
        unplacedTasks: []
    )

    let parallelEvents = draft.parallelEvents(in: groupID)
    expect(parallelEvents.map(\.title) == ["回邮件", "整理资料"], "planning draft should return parallel events in timeline order")
}

checkCriticalTaskUsesAlarmKitWithLocalNotificationFallback()
checkCriticalTaskFallsBackWhenAlarmKitUnavailable()
checkMediumTaskUsesSoundNotificationAndVibration()
checkNotifyOnlyTaskUsesNotificationOnly()
checkNoPriorityTaskDoesNotNotify()
checkOneTimeTaskCompletesOnce()
checkCumulativeTaskAddsProgressTowardTotal()
checkFrequencyTaskCountsCompletionsInPeriod()
checkPlanningDraftKeepsUnknownTimesAndUnplacedTasks()
checkTimelineSupportsParallelEvents()

print("FocusTimelineCoreChecks passed")

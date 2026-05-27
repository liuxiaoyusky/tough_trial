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

func checkDailyMarkdownRendersTimelineAndRecall() {
    let date = Date(timeIntervalSince1970: 1_780_000_000)
    let event = TimelineEvent(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000301")!,
        date: date,
        time: .fixed(hour: 14, minute: 0),
        title: "写作提纲",
        linkedTaskID: nil,
        source: .focus,
        parallelGroupID: nil
    )
    let record = DailyMarkdownRecord(
        dateLabel: "2026-05-27",
        timelineEvents: [event],
        recallText: "今天下午的写作提纲比预期顺。"
    )

    let markdown = record.render()

    expect(markdown.contains("# 2026-05-27"), "daily markdown should render date title")
    expect(markdown.contains("- 14:00 写作提纲"), "daily markdown should render fixed timeline event")
    expect(markdown.contains("## 回想"), "daily markdown should include recall heading")
    expect(markdown.contains("今天下午的写作提纲比预期顺。"), "daily markdown should include recall text")
}

func checkTaskCSVUsesStableColumnOrder() {
    let task = TaskItem.cumulative(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000302")!,
        title: "读完一本书",
        unit: "页",
        targetAmount: 1000,
        priority: .none
    )

    let row = TaskCSVRow(task: task)

    expect(TaskCSVRow.header == "id,title,kind,priority,status,completed_amount,target_amount,unit", "task CSV header should be stable")
    expect(row.csvLine == "00000000-0000-0000-0000-000000000302,读完一本书,cumulative,none,active,0.0,1000.0,页", "task CSV row should be deterministic")
}

func checkTimelineCSVUsesStableColumnOrder() {
    let date = Date(timeIntervalSince1970: 1_780_000_000)
    let event = TimelineEvent(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000303")!,
        date: date,
        time: .unknown,
        title: "读书 40 页",
        linkedTaskID: UUID(uuidString: "00000000-0000-0000-0000-000000000302")!,
        source: .aiPlanning,
        parallelGroupID: nil
    )

    let row = TimelineEventCSVRow(event: event)

    expect(TimelineEventCSVRow.header == "id,date,time,title,linked_task_id,source,parallel_group_id", "timeline CSV header should be stable")
    expect(row.csvLine == "00000000-0000-0000-0000-000000000303,2026-05-28T20:26:40Z,unknown,读书 40 页,00000000-0000-0000-0000-000000000302,aiPlanning,", "timeline CSV row should be deterministic")
}

func checkTaskMapsToReminderAndScheduledBlockMapsToCalendar() {
    let task = TaskItem.oneTime(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000401")!,
        title: "写作提纲",
        priority: .notifyOnly
    )
    let reminder = AppleIntegrationMapper.reminderPayload(for: task)

    expect(reminder.title == "写作提纲", "task should map to reminder title")
    expect(reminder.sourceTaskID == task.id, "reminder payload should keep source task ID")

    let event = TimelineEvent(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000402")!,
        date: Date(timeIntervalSince1970: 1_780_000_000),
        time: .fixed(hour: 14, minute: 0),
        title: "专注：写作提纲",
        linkedTaskID: task.id,
        source: .aiPlanning,
        parallelGroupID: nil
    )
    let calendar = AppleIntegrationMapper.calendarPayload(for: event, durationMinutes: 25)

    expect(calendar.title == "专注：写作提纲", "scheduled timeline block should map to calendar title")
    expect(calendar.durationMinutes == 25, "calendar payload should preserve duration")
    expect(calendar.sourceEventID == event.id, "calendar payload should keep source event ID")
}

func checkCriticalTaskStartMapsToAlarmPolicy() {
    let task = TaskItem.oneTime(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000403")!,
        title: "重要会议准备",
        priority: .critical
    )

    let plan = AppleIntegrationMapper.reminderPlan(for: task, alarmKitAvailable: true)

    expect(plan.policy.primaryChannel == .alarmKit, "critical task plan should use AlarmKit")
    expect(plan.externalObjectKind == .alarm, "critical task plan should target alarm external object")
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
checkDailyMarkdownRendersTimelineAndRecall()
checkTaskCSVUsesStableColumnOrder()
checkTimelineCSVUsesStableColumnOrder()
checkTaskMapsToReminderAndScheduledBlockMapsToCalendar()
checkCriticalTaskStartMapsToAlarmPolicy()

print("FocusTimelineCoreChecks passed")

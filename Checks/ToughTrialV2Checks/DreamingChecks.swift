import Foundation
import ToughTrialV2Core

func checkDreamingEligibilityAndDraftOnlySuggestions() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    let now = calendar.date(from: DateComponents(
        year: 2026,
        month: 7,
        day: 23,
        hour: 12
    ))!

    func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!
    }

    let goal = V2Task(
        id: "goal-writing",
        title: "持续写作",
        kind: .goal,
        createdAt: day(-30),
        updatedAt: day(-30)
    )
    let leaf = V2Task(
        id: "task-reading",
        title: "整理阅读笔记",
        kind: .maintenance,
        createdAt: day(-20),
        updatedAt: day(-20)
    )
    let executions = [-6, -4, -2].map { offset in
        V2ExecutionSegment(
            id: "segment-\(offset)",
            taskID: leaf.id,
            titleSnapshot: leaf.title,
            startAt: day(offset).addingTimeInterval(9 * 3_600),
            endAt: day(offset).addingTimeInterval(9 * 3_600 + 1_800),
            endReason: .stopped,
            source: .normal
        )
    }
    let plans = [-5, -3, -1, 0].map { offset in
        V2PlanItem(
            id: "plan-\(offset)",
            date: day(offset),
            title: "历史计划 \(offset)"
        )
    }
    let snapshot = V2AppSnapshot(
        tasks: [goal, leaf],
        planItems: plans,
        executionSegments: executions
    )

    let report = V2DreamingEngine.eligibility(
        snapshot: snapshot,
        now: now,
        calendar: calendar
    )
    require(report.isEligible, "Seven observed days across a six-day span should unlock Dreaming")
    require(report.executionDayCount == 3, "Dreaming should require three real execution days")
    require(report.planningDayCount == 4, "Dreaming should count distinct historical planning days")

    let nextDay = day(1)
    let availability = V2UserMemoryRecord(
        kind: .availability,
        statement: "每周这个工作日晚上有一小时空闲",
        origin: .explicitUser,
        createdAt: day(-10),
        updatedAt: day(-10),
        availability: V2WeeklyAvailability(
            weekday: calendar.component(.weekday, from: nextDay),
            startMinute: 18 * 60,
            durationMinutes: 60
        )
    )
    let before = snapshot
    let candidates = V2DreamingEngine.candidates(
        snapshot: snapshot,
        memoryRecords: [availability],
        now: now,
        calendar: calendar
    )
    require(candidates.count == 2, "Eligible evidence should allow one schedule and one breakdown suggestion")
    require(
        candidates.contains(where: { $0.kind == .schedule }),
        "Explicit availability should permit an empty-time schedule suggestion"
    )
    require(
        candidates.contains(where: { $0.kind == .breakdown }),
        "A childless long-term goal should permit a breakdown suggestion"
    )
    let schedule = candidates.first { $0.kind == .schedule }
    require(
        schedule?.draft.scheduleItems.first?.taskID == leaf.id,
        "Schedule suggestion should link an existing leaf task without creating durable data"
    )
    require(snapshot == before, "Generating Dreaming candidates must not mutate the durable snapshot")

    let withoutAvailability = V2DreamingEngine.candidates(
        snapshot: snapshot,
        memoryRecords: [],
        now: now,
        calendar: calendar
    )
    require(
        withoutAvailability.allSatisfy { $0.kind != .schedule },
        "Calendar blank space alone must never be treated as confirmed free time"
    )

    var onlySixDays = snapshot
    onlySixDays.planItems.removeLast()
    require(
        !V2DreamingEngine.eligibility(
            snapshot: onlySixDays,
            now: now,
            calendar: calendar
        ).isEligible,
        "Six observed days must not unlock Dreaming"
    )
}

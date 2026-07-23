import Foundation

public struct V2DreamingEligibilityReport: Equatable, Sendable {
    public var isEligible: Bool
    public var observedDayCount: Int
    public var executionDayCount: Int
    public var planningDayCount: Int
    public var observedSpanDays: Int

    public init(
        isEligible: Bool,
        observedDayCount: Int,
        executionDayCount: Int,
        planningDayCount: Int,
        observedSpanDays: Int
    ) {
        self.isEligible = isEligible
        self.observedDayCount = observedDayCount
        self.executionDayCount = executionDayCount
        self.planningDayCount = planningDayCount
        self.observedSpanDays = observedSpanDays
    }
}

public struct V2DreamingCandidate: Identifiable, Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case schedule
        case breakdown
    }

    public var id: String
    public var kind: Kind
    public var title: String
    public var summary: String
    public var draft: V2PlanDraft

    public init(
        id: String,
        kind: Kind,
        title: String,
        summary: String,
        draft: V2PlanDraft
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.summary = summary
        self.draft = draft
    }
}

public enum V2DreamingEngine {
    public static func eligibility(
        snapshot: V2AppSnapshot,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> V2DreamingEligibilityReport {
        let today = calendar.startOfDay(for: now)
        let windowStart = calendar.date(byAdding: .day, value: -27, to: today) ?? today
        let windowEnd = calendar.date(byAdding: .day, value: 1, to: today) ?? now

        var executionDays = Set<Date>()
        for segment in snapshot.executionSegments {
            let segmentEnd = min(segment.endAt ?? now, windowEnd)
            var day = max(calendar.startOfDay(for: segment.startAt), windowStart)
            guard segmentEnd > day else { continue }
            while day < segmentEnd, day < windowEnd {
                executionDays.insert(day)
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }

        let planningDays = Set(
            snapshot.planItems.compactMap { item -> Date? in
                guard item.status != .canceled else { return nil }
                let day = calendar.startOfDay(for: item.date)
                guard day >= windowStart, day <= today else { return nil }
                return day
            }
        )
        let observedDays = executionDays.union(planningDays)
        let sortedDays = observedDays.sorted()
        let spanDays: Int
        if let first = sortedDays.first, let last = sortedDays.last {
            spanDays = calendar.dateComponents([.day], from: first, to: last).day ?? 0
        } else {
            spanDays = 0
        }

        let eligible = observedDays.count >= 7
            && executionDays.count >= 3
            && planningDays.count >= 3
            && spanDays >= 6
        return V2DreamingEligibilityReport(
            isEligible: eligible,
            observedDayCount: observedDays.count,
            executionDayCount: executionDays.count,
            planningDayCount: planningDays.count,
            observedSpanDays: spanDays
        )
    }

    public static func candidates(
        snapshot: V2AppSnapshot,
        memoryRecords: [V2UserMemoryRecord],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [V2DreamingCandidate] {
        guard eligibility(snapshot: snapshot, now: now, calendar: calendar).isEligible else {
            return []
        }

        var result: [V2DreamingCandidate] = []
        if let schedule = scheduleCandidate(
            snapshot: snapshot,
            memoryRecords: memoryRecords,
            now: now,
            calendar: calendar
        ) {
            result.append(schedule)
        }
        if let breakdown = breakdownCandidate(snapshot: snapshot, now: now) {
            result.append(breakdown)
        }
        return result
    }
}

private extension V2DreamingEngine {
    static func scheduleCandidate(
        snapshot: V2AppSnapshot,
        memoryRecords: [V2UserMemoryRecord],
        now: Date,
        calendar: Calendar
    ) -> V2DreamingCandidate? {
        guard let memory = memoryRecords.first(where: {
            $0.kind == .availability && $0.availability != nil
        }), let availability = memory.availability else {
            return nil
        }

        let parentIDs = Set(snapshot.tasks.compactMap(\.parentID))
        let futureTaskIDs = Set(
            snapshot.planItems.compactMap { item -> String? in
                guard item.status != .canceled,
                      item.date >= calendar.startOfDay(for: now)
                else {
                    return nil
                }
                return item.taskID
            }
        )
        guard let task = snapshot.tasks.first(where: {
            $0.status != .done
                && $0.status != .archived
                && $0.kind != .goal
                && !parentIDs.contains($0.id)
                && !futureTaskIDs.contains($0.id)
        }) else {
            return nil
        }
        guard let window = nextWindow(
            availability,
            after: now,
            calendar: calendar
        ) else {
            return nil
        }

        let itemID = "dream-schedule-item-\(task.id)-\(Int(window.start.timeIntervalSince1970))"
        let draft = V2PlanDraft(
            id: "dream-schedule-\(task.id)-\(Int(window.start.timeIntervalSince1970))",
            userPrompt: "把已有任务安排到我确认的空闲时间",
            title: "空闲时间建议",
            summary: "根据「\(memory.statement)」为「\(task.title)」留出一段时间。",
            decisions: ["这只是草稿，不占用或替换其他任务。"],
            scheduleItems: [
                V2PlanDraftScheduleItem(
                    id: itemID,
                    date: calendar.startOfDay(for: window.start),
                    startAt: window.start,
                    endAt: window.end,
                    taskID: task.id,
                    title: task.title
                ),
            ]
        )
        return V2DreamingCandidate(
            id: draft.id,
            kind: .schedule,
            title: "把「\(task.title)」放进空闲时间",
            summary: memory.statement,
            draft: draft
        )
    }

    static func breakdownCandidate(
        snapshot: V2AppSnapshot,
        now: Date
    ) -> V2DreamingCandidate? {
        let parentIDs = Set(snapshot.tasks.compactMap(\.parentID))
        guard let goal = snapshot.tasks.first(where: {
            $0.kind == .goal
                && $0.status != .done
                && $0.status != .archived
                && !parentIDs.contains($0.id)
        }) else {
            return nil
        }

        let prefix = "dream-breakdown-\(goal.id)"
        let taskChanges = [
            V2PlanDraftTaskChange(
                id: "\(prefix)-next",
                title: "明确「\(goal.title)」的下一步",
                parentID: goal.id,
                contextID: goal.contextID,
                kind: .goal
            ),
            V2PlanDraftTaskChange(
                id: "\(prefix)-test",
                title: "完成一次小验证",
                parentID: goal.id,
                contextID: goal.contextID,
                kind: .goal
            ),
            V2PlanDraftTaskChange(
                id: "\(prefix)-review",
                title: "记录结果并调整",
                parentID: goal.id,
                contextID: goal.contextID,
                kind: .goal
            ),
        ]
        let draft = V2PlanDraft(
            id: "\(prefix)-\(Int(now.timeIntervalSince1970))",
            userPrompt: "继续拆解长期目标",
            title: "继续拆解「\(goal.title)」",
            summary: "先补三个可继续修改的子节点，不替你决定实际执行。",
            decisions: ["仅拆解目标，暂不安排日期。"],
            taskChanges: taskChanges,
            scheduleItems: []
        )
        return V2DreamingCandidate(
            id: draft.id,
            kind: .breakdown,
            title: "继续拆解「\(goal.title)」",
            summary: "它目前还没有可执行子节点。",
            draft: draft
        )
    }

    static func nextWindow(
        _ availability: V2WeeklyAvailability,
        after now: Date,
        calendar: Calendar
    ) -> (start: Date, end: Date)? {
        let today = calendar.startOfDay(for: now)
        for offset in 0...13 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else {
                continue
            }
            guard calendar.component(.weekday, from: day) == availability.weekday,
                  let start = calendar.date(
                    byAdding: .minute,
                    value: availability.startMinute,
                    to: day
                  ),
                  start > now,
                  let end = calendar.date(
                    byAdding: .minute,
                    value: availability.durationMinutes,
                    to: start
                  )
            else {
                continue
            }
            return (start, end)
        }
        return nil
    }
}

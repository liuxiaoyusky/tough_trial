import Foundation

public struct V2RecallReferences: Equatable, Sendable {
    public var taskIDs: [String]
    public var segmentIDs: [String]
    public var planItemIDs: [String]

    public init(
        taskIDs: [String] = [],
        segmentIDs: [String] = [],
        planItemIDs: [String] = []
    ) {
        self.taskIDs = taskIDs
        self.segmentIDs = segmentIDs
        self.planItemIDs = planItemIDs
    }
}

public struct V2RecallReferenceCandidate: Identifiable, Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case event
        case deviation
        case past
    }

    public var id: String
    public var kind: Kind
    public var title: String
    public var detail: String
    public var references: V2RecallReferences

    public init(
        id: String,
        kind: Kind,
        title: String,
        detail: String,
        references: V2RecallReferences
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.references = references
    }
}

public struct V2RecallExecutionEvidence: Identifiable, Equatable, Sendable {
    public var id: String
    public var sessionID: String
    public var segmentIDs: [String]
    public var taskID: String?
    public var title: String
    public var startedAt: Date
    public var endedAt: Date?
    public var duration: TimeInterval
    public var source: V2ExecutionSegment.Source
    public var createdFromPlanItemIDs: [String]

    public init(
        id: String,
        sessionID: String,
        segmentIDs: [String],
        taskID: String?,
        title: String,
        startedAt: Date,
        endedAt: Date?,
        duration: TimeInterval,
        source: V2ExecutionSegment.Source,
        createdFromPlanItemIDs: [String]
    ) {
        self.id = id
        self.sessionID = sessionID
        self.segmentIDs = segmentIDs
        self.taskID = taskID
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.duration = duration
        self.source = source
        self.createdFromPlanItemIDs = createdFromPlanItemIDs
    }
}

public struct V2PlanDeviation: Equatable, Sendable {
    public var date: Date
    public var plannedButNotExecuted: [V2PlanItem]
    public var executedWithoutPlan: [V2RecallExecutionEvidence]

    public init(
        date: Date,
        plannedButNotExecuted: [V2PlanItem],
        executedWithoutPlan: [V2RecallExecutionEvidence]
    ) {
        self.date = date
        self.plannedButNotExecuted = plannedButNotExecuted
        self.executedWithoutPlan = executedWithoutPlan
    }
}

public struct V2RecallEvidenceSnapshot: Equatable, Sendable {
    public var date: Date
    public var executionEvents: [V2RecallExecutionEvidence]
    public var planItems: [V2PlanItem]
    public var deviation: V2PlanDeviation
    public var savedEntry: V2RecallEntry?

    public init(
        date: Date,
        executionEvents: [V2RecallExecutionEvidence],
        planItems: [V2PlanItem],
        deviation: V2PlanDeviation,
        savedEntry: V2RecallEntry?
    ) {
        self.date = date
        self.executionEvents = executionEvents
        self.planItems = planItems
        self.deviation = deviation
        self.savedEntry = savedEntry
    }
}

public extension V2Engine {
    @discardableResult
    func saveRecallEntry(
        date: Date,
        text: String,
        hasHandwriting: Bool = false,
        references: V2RecallReferences = V2RecallReferences(),
        at timestamp: Date = Date(),
        calendar: Calendar = .current
    ) throws -> V2RecallEntry {
        try commit { snapshot in
            let validatedText = try Self.validatedRecallText(
                text,
                hasHandwriting: hasHandwriting
            )
            let validatedReferences = try Self.validatedRecallReferences(references, snapshot: snapshot)
            let day = calendar.startOfDay(for: date)

            if let index = Self.latestRecallEntryIndex(on: day, snapshot: snapshot, calendar: calendar) {
                snapshot.recallEntries[index].text = validatedText
                snapshot.recallEntries[index].hasHandwriting = hasHandwriting
                snapshot.recallEntries[index].referencedTaskIDs = validatedReferences.taskIDs
                snapshot.recallEntries[index].referencedSegmentIDs = validatedReferences.segmentIDs
                snapshot.recallEntries[index].referencedPlanItemIDs = validatedReferences.planItemIDs
                snapshot.recallEntries[index].updatedAt = timestamp
                return snapshot.recallEntries[index]
            }

            let entry = V2RecallEntry(
                id: UUID().uuidString,
                date: day,
                text: validatedText,
                hasHandwriting: hasHandwriting,
                referencedTaskIDs: validatedReferences.taskIDs,
                referencedSegmentIDs: validatedReferences.segmentIDs,
                referencedPlanItemIDs: validatedReferences.planItemIDs,
                createdAt: timestamp,
                updatedAt: timestamp
            )
            snapshot.recallEntries.append(entry)
            return entry
        }
    }

    @discardableResult
    func updateRecallEntry(
        id: String,
        text: String,
        references: V2RecallReferences,
        hasHandwriting: Bool? = nil,
        at timestamp: Date = Date()
    ) throws -> V2RecallEntry {
        try commit { snapshot in
            guard let index = snapshot.recallEntries.firstIndex(where: { $0.id == id }) else {
                throw V2EngineError.recallEntryNotFound(id)
            }
            let resolvedHasHandwriting =
                hasHandwriting ?? snapshot.recallEntries[index].hasHandwriting
            let validatedText = try Self.validatedRecallText(
                text,
                hasHandwriting: resolvedHasHandwriting
            )
            let validatedReferences = try Self.validatedRecallReferences(references, snapshot: snapshot)
            snapshot.recallEntries[index].text = validatedText
            snapshot.recallEntries[index].hasHandwriting = resolvedHasHandwriting
            snapshot.recallEntries[index].referencedTaskIDs = validatedReferences.taskIDs
            snapshot.recallEntries[index].referencedSegmentIDs = validatedReferences.segmentIDs
            snapshot.recallEntries[index].referencedPlanItemIDs = validatedReferences.planItemIDs
            snapshot.recallEntries[index].updatedAt = timestamp
            return snapshot.recallEntries[index]
        }
    }

    func recallEntry(on date: Date, calendar: Calendar = .current) -> V2RecallEntry? {
        guard let index = Self.latestRecallEntryIndex(on: date, snapshot: snapshot, calendar: calendar) else {
            return nil
        }
        return snapshot.recallEntries[index]
    }

    func recallEvidence(
        date: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> V2RecallEvidenceSnapshot {
        let dayStart = calendar.startOfDay(for: date)
        let events = Self.recallExecutionEvents(
            date: dayStart,
            now: now,
            calendar: calendar,
            snapshot: snapshot
        )
        let planItems = snapshot.planItems
            .filter {
                $0.status != .canceled && calendar.isDate($0.date, inSameDayAs: dayStart)
            }
            .sorted {
                let lhs = $0.startAt ?? $0.date
                let rhs = $1.startAt ?? $1.date
                if lhs == rhs { return $0.id < $1.id }
                return lhs < rhs
            }
        let deviation = Self.makePlanDeviation(
            date: dayStart,
            dayEnd: calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart,
            now: now,
            planItems: planItems,
            events: events
        )
        return V2RecallEvidenceSnapshot(
            date: dayStart,
            executionEvents: events,
            planItems: planItems,
            deviation: deviation,
            savedEntry: recallEntry(on: dayStart, calendar: calendar)
        )
    }

    func planDeviation(
        date: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> V2PlanDeviation {
        recallEvidence(date: date, now: now, calendar: calendar).deviation
    }

    func recallReferenceCandidates(
        date: Date,
        now: Date = Date(),
        lookbackDays: Int = 7,
        calendar: Calendar = .current
    ) -> [V2RecallReferenceCandidate] {
        let evidence = recallEvidence(date: date, now: now, calendar: calendar)
        var candidates = evidence.executionEvents.map {
            Self.referenceCandidate(from: $0, kind: .event, dateLabel: nil)
        }

        candidates.append(contentsOf: evidence.deviation.plannedButNotExecuted.map { item in
            V2RecallReferenceCandidate(
                id: "deviation-plan-\(item.id)",
                kind: .deviation,
                title: item.title,
                detail: "计划时间已过，但没有找到对应执行记录。",
                references: V2RecallReferences(
                    taskIDs: item.taskID.map { [$0] } ?? [],
                    planItemIDs: [item.id]
                )
            )
        })
        candidates.append(contentsOf: evidence.deviation.executedWithoutPlan.map {
            Self.referenceCandidate(
                from: $0,
                kind: .deviation,
                dateLabel: "计划外执行"
            )
        })

        guard lookbackDays > 0 else { return candidates }
        for offset in 1...lookbackDays {
            guard let pastDate = calendar.date(byAdding: .day, value: -offset, to: date) else {
                continue
            }
            let label = Self.recallDayLabel(pastDate, calendar: calendar)
            let pastEvidence = recallEvidence(date: pastDate, now: now, calendar: calendar)
            candidates.append(contentsOf: pastEvidence.executionEvents.map {
                Self.referenceCandidate(from: $0, kind: .past, dateLabel: label)
            })
        }
        return candidates
    }
}

private extension V2Engine {
    static func referenceCandidate(
        from event: V2RecallExecutionEvidence,
        kind: V2RecallReferenceCandidate.Kind,
        dateLabel: String?
    ) -> V2RecallReferenceCandidate {
        let duration = max(0, Int(event.duration.rounded(.down)))
        let minutes = max(1, duration / 60)
        let prefix = dateLabel.map { "\($0) · " } ?? ""
        return V2RecallReferenceCandidate(
            id: "\(kind.rawValue)-\(event.id)",
            kind: kind,
            title: event.title,
            detail: "\(prefix)\(minutes) 分钟",
            references: V2RecallReferences(
                taskIDs: event.taskID.map { [$0] } ?? [],
                segmentIDs: event.segmentIDs,
                planItemIDs: event.createdFromPlanItemIDs
            )
        )
    }

    static func recallDayLabel(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.month, .day], from: date)
        return "\(components.month ?? 1)月\(components.day ?? 1)日"
    }

    static func validatedRecallText(
        _ text: String,
        hasHandwriting: Bool = false
    ) throws -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if hasHandwriting {
                return ""
            }
            throw V2EngineError.blankRecallText
        }
        return text
    }

    static func validatedRecallReferences(
        _ references: V2RecallReferences,
        snapshot: V2AppSnapshot
    ) throws -> V2RecallReferences {
        let taskIDs = uniquePreservingOrder(references.taskIDs)
        let segmentIDs = uniquePreservingOrder(references.segmentIDs)
        let planItemIDs = uniquePreservingOrder(references.planItemIDs)

        for taskID in taskIDs where !snapshot.tasks.contains(where: { $0.id == taskID }) {
            throw V2EngineError.taskNotFound(taskID)
        }
        for segmentID in segmentIDs where !snapshot.executionSegments.contains(where: { $0.id == segmentID }) {
            throw V2EngineError.segmentNotFound(segmentID)
        }
        for planItemID in planItemIDs where !snapshot.planItems.contains(where: { $0.id == planItemID }) {
            throw V2EngineError.planItemNotFound(planItemID)
        }
        return V2RecallReferences(
            taskIDs: taskIDs,
            segmentIDs: segmentIDs,
            planItemIDs: planItemIDs
        )
    }

    static func uniquePreservingOrder(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }

    static func latestRecallEntryIndex(
        on date: Date,
        snapshot: V2AppSnapshot,
        calendar: Calendar
    ) -> Int? {
        snapshot.recallEntries.indices
            .filter { calendar.isDate(snapshot.recallEntries[$0].date, inSameDayAs: date) }
            .max {
                snapshot.recallEntries[$0].updatedAt < snapshot.recallEntries[$1].updatedAt
            }
    }

    static func recallExecutionEvents(
        date: Date,
        now: Date,
        calendar: Calendar,
        snapshot: V2AppSnapshot
    ) -> [V2RecallExecutionEvidence] {
        let dayStart = calendar.startOfDay(for: date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        let segments = snapshot.executionSegments.filter {
            overlapsRecallDay($0, dayStart: dayStart, dayEnd: dayEnd, now: now)
        }
        let groups = Dictionary(grouping: segments, by: \V2ExecutionSegment.logicalSessionID)

        return groups.compactMap { sessionID, groupedSegments -> V2RecallExecutionEvidence? in
            let ordered = groupedSegments.sorted {
                if $0.startAt == $1.startAt { return $0.id < $1.id }
                return $0.startAt < $1.startAt
            }
            guard let first = ordered.first, let latest = ordered.last else { return nil }
            let isOpen = ordered.contains { $0.endAt == nil }
            let boundedEnd = ordered.compactMap(\.endAt).max().map { min($0, dayEnd, now) }
            return V2RecallExecutionEvidence(
                id: "recall-event-\(sessionID)-\(Int(dayStart.timeIntervalSince1970))",
                sessionID: sessionID,
                segmentIDs: ordered.map(\.id),
                taskID: latest.taskID,
                title: latest.titleSnapshot,
                startedAt: max(first.startAt, dayStart),
                endedAt: isOpen ? nil : boundedEnd,
                duration: recallDuration(
                    of: ordered,
                    dayStart: dayStart,
                    dayEnd: dayEnd,
                    now: now
                ),
                source: latest.source,
                createdFromPlanItemIDs: uniquePreservingOrder(
                    ordered.compactMap(\.createdFromPlanItemID)
                )
            )
        }
        .sorted {
            if $0.startedAt == $1.startedAt { return $0.id < $1.id }
            return $0.startedAt < $1.startedAt
        }
    }

    static func makePlanDeviation(
        date: Date,
        dayEnd: Date,
        now: Date,
        planItems: [V2PlanItem],
        events: [V2RecallExecutionEvidence]
    ) -> V2PlanDeviation {
        let plannedButNotExecuted = planItems.filter { planItem in
            planCanBeJudgedMissing(
                planItem,
                dayStart: date,
                dayEnd: dayEnd,
                now: now
            ) && !events.contains { eventMatchesPlan($0, planItem: planItem) }
        }
        let executedWithoutPlan = events.filter { event in
            !planItems.contains { eventMatchesPlan(event, planItem: $0) }
        }
        return V2PlanDeviation(
            date: date,
            plannedButNotExecuted: plannedButNotExecuted,
            executedWithoutPlan: executedWithoutPlan
        )
    }

    static func planCanBeJudgedMissing(
        _ planItem: V2PlanItem,
        dayStart: Date,
        dayEnd: Date,
        now: Date
    ) -> Bool {
        guard now >= dayStart else { return false }
        if now >= dayEnd { return true }
        guard let endAt = planItem.endAt else { return false }
        return endAt <= now
    }

    static func eventMatchesPlan(
        _ event: V2RecallExecutionEvidence,
        planItem: V2PlanItem
    ) -> Bool {
        if event.createdFromPlanItemIDs.contains(planItem.id) {
            return true
        }
        guard let eventTaskID = event.taskID, let planTaskID = planItem.taskID else {
            return false
        }
        return eventTaskID == planTaskID
    }

    static func overlapsRecallDay(
        _ segment: V2ExecutionSegment,
        dayStart: Date,
        dayEnd: Date,
        now: Date
    ) -> Bool {
        segment.startAt < dayEnd && min(segment.endAt ?? now, now) > dayStart
    }

    static func recallDuration(
        of segments: [V2ExecutionSegment],
        dayStart: Date,
        dayEnd: Date,
        now: Date
    ) -> TimeInterval {
        segments.reduce(0) { total, segment in
            let start = max(segment.startAt, dayStart)
            let end = min(segment.endAt ?? now, dayEnd, now)
            return total + max(0, end.timeIntervalSince(start))
        }
    }
}

import Foundation

public struct V2TodayExecutionSnapshot: Equatable, Sendable {
    public var date: Date
    public var items: [V2TodayItemSnapshot]
    public var sessions: [V2ExecutionSessionSnapshot]

    public init(
        date: Date,
        items: [V2TodayItemSnapshot],
        sessions: [V2ExecutionSessionSnapshot]
    ) {
        self.date = date
        self.items = items
        self.sessions = sessions
    }
}

public struct V2TodayItemSnapshot: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case task
        case executionRecord
    }

    public var id: String
    public var kind: Kind
    public var taskID: String?
    public var title: String
    public var plannedAt: Date?
    public var isDone: Bool
    public var spentDuration: TimeInterval

    public init(
        id: String,
        kind: Kind,
        taskID: String?,
        title: String,
        plannedAt: Date?,
        isDone: Bool,
        spentDuration: TimeInterval
    ) {
        self.id = id
        self.kind = kind
        self.taskID = taskID
        self.title = title
        self.plannedAt = plannedAt
        self.isDone = isDone
        self.spentDuration = spentDuration
    }
}

public struct V2ExecutionSessionSnapshot: Identifiable, Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        case running
        case paused
    }

    public var id: String
    public var latestSegmentID: String
    public var taskID: String?
    public var title: String
    public var startedAt: Date
    public var currentDuration: TimeInterval
    public var totalDuration: TimeInterval
    public var status: Status
    public var source: V2ExecutionSegment.Source

    public init(
        id: String,
        latestSegmentID: String,
        taskID: String?,
        title: String,
        startedAt: Date,
        currentDuration: TimeInterval,
        totalDuration: TimeInterval,
        status: Status,
        source: V2ExecutionSegment.Source
    ) {
        self.id = id
        self.latestSegmentID = latestSegmentID
        self.taskID = taskID
        self.title = title
        self.startedAt = startedAt
        self.currentDuration = currentDuration
        self.totalDuration = totalDuration
        self.status = status
        self.source = source
    }
}

public extension V2Engine {
    func todaySnapshot(
        date: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> V2TodayExecutionSnapshot {
        let dayStart = calendar.startOfDay(for: date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return V2TodayExecutionSnapshot(date: dayStart, items: [], sessions: [])
        }

        let taskByID = Dictionary(uniqueKeysWithValues: snapshot.tasks.map { ($0.id, $0) })
        let segmentsToday = snapshot.executionSegments.filter {
            Self.overlaps($0, dayStart: dayStart, dayEnd: dayEnd, now: now)
        }
        var items = snapshot.planItems.compactMap { item -> V2TodayItemSnapshot? in
            guard item.status != .canceled,
                  calendar.isDate(item.date, inSameDayAs: dayStart) else {
                return nil
            }
            let task = item.taskID.flatMap { taskByID[$0] }
            let itemSegments = item.taskID.map { taskID in
                segmentsToday.filter { $0.taskID == taskID }
            } ?? []
            return V2TodayItemSnapshot(
                id: item.id,
                kind: .task,
                taskID: item.taskID,
                title: task?.title ?? item.title,
                plannedAt: item.startAt,
                isDone: task?.status == .done,
                spentDuration: Self.duration(
                    of: itemSegments,
                    dayStart: dayStart,
                    dayEnd: dayEnd,
                    now: now
                )
            )
        }

        let plannedTaskIDs = Set(items.compactMap(\.taskID))
        let executedTaskGroups = Dictionary(
            grouping: segmentsToday.compactMap { segment in
                segment.taskID.map { ($0, segment) }
            },
            by: { $0.0 }
        )
        for (taskID, pairs) in executedTaskGroups where !plannedTaskIDs.contains(taskID) {
            guard let task = taskByID[taskID], task.status != .archived else { continue }
            let segments = pairs.map(\.1)
            items.append(
                V2TodayItemSnapshot(
                    id: "execution-task-\(taskID)-\(Int(dayStart.timeIntervalSince1970))",
                    kind: .task,
                    taskID: taskID,
                    title: task.title,
                    plannedAt: segments.map(\.startAt).min(),
                    isDone: task.status == .done,
                    spentDuration: Self.duration(
                        of: segments,
                        dayStart: dayStart,
                        dayEnd: dayEnd,
                        now: now
                    )
                )
            )
        }

        let unlinkedGroups = Dictionary(
            grouping: segmentsToday.filter { $0.taskID == nil },
            by: \V2ExecutionSegment.logicalSessionID
        )
        for (sessionID, segments) in unlinkedGroups {
            guard let latest = segments.max(by: { $0.startAt < $1.startAt }) else { continue }
            items.append(
                V2TodayItemSnapshot(
                    id: "execution-session-\(sessionID)-\(Int(dayStart.timeIntervalSince1970))",
                    kind: .executionRecord,
                    taskID: nil,
                    title: latest.titleSnapshot,
                    plannedAt: segments.map(\.startAt).min(),
                    isDone: latest.endReason == .stopped,
                    spentDuration: Self.duration(
                        of: segments,
                        dayStart: dayStart,
                        dayEnd: dayEnd,
                        now: now
                    )
                )
            )
        }

        let sessionGroups = Dictionary(
            grouping: snapshot.executionSegments,
            by: \V2ExecutionSegment.logicalSessionID
        )
        let sessions = sessionGroups.compactMap { sessionID, segments -> V2ExecutionSessionSnapshot? in
            guard let latest = segments.max(by: { $0.startAt < $1.startAt }) else { return nil }
            let status: V2ExecutionSessionSnapshot.Status
            if latest.endAt == nil {
                status = .running
            } else if latest.endReason == .paused {
                status = .paused
            } else {
                return nil
            }

            let totalSegments: [V2ExecutionSegment]
            if let taskID = latest.taskID {
                totalSegments = segmentsToday.filter { $0.taskID == taskID }
            } else {
                totalSegments = segmentsToday.filter { $0.logicalSessionID == sessionID }
            }
            return V2ExecutionSessionSnapshot(
                id: sessionID,
                latestSegmentID: latest.id,
                taskID: latest.taskID,
                title: latest.titleSnapshot,
                startedAt: latest.startAt,
                currentDuration: latest.duration(through: now),
                totalDuration: Self.duration(
                    of: totalSegments,
                    dayStart: dayStart,
                    dayEnd: dayEnd,
                    now: now
                ),
                status: status,
                source: latest.source
            )
        }
        .sorted { $0.startedAt > $1.startedAt }

        items.sort {
            let lhs = $0.plannedAt ?? dayStart
            let rhs = $1.plannedAt ?? dayStart
            if lhs == rhs { return $0.id < $1.id }
            return lhs < rhs
        }
        return V2TodayExecutionSnapshot(date: dayStart, items: items, sessions: sessions)
    }

    private static func overlaps(
        _ segment: V2ExecutionSegment,
        dayStart: Date,
        dayEnd: Date,
        now: Date
    ) -> Bool {
        segment.startAt < dayEnd && min(segment.endAt ?? now, now) > dayStart
    }

    private static func duration(
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

import Foundation

public struct DailyMarkdownRecord: Sendable, Equatable {
    public let dateLabel: String
    public let timelineEvents: [TimelineEvent]
    public let recallText: String

    public init(dateLabel: String, timelineEvents: [TimelineEvent], recallText: String) {
        self.dateLabel = dateLabel
        self.timelineEvents = timelineEvents
        self.recallText = recallText
    }

    public func render() -> String {
        var lines: [String] = [
            "# \(dateLabel)",
            "",
            "## 时间线"
        ]

        lines.append(contentsOf: timelineEvents.map { "- \($0.time.markdownLabel) \($0.title)" })
        lines.append("")
        lines.append("## 回想")
        lines.append(recallText)

        return lines.joined(separator: "\n")
    }
}

public struct TaskCSVRow: Sendable, Equatable {
    public static let header = "id,title,kind,priority,status,completed_amount,target_amount,unit"

    public let task: TaskItem

    public init(task: TaskItem) {
        self.task = task
    }

    public var csvLine: String {
        [
            task.id.uuidString,
            task.title,
            task.kind.csvValue,
            task.priority.rawValue,
            task.status.rawValue,
            String(task.progress.completedAmount),
            String(task.progress.targetAmount),
            task.progress.unit ?? ""
        ].map(\.csvEscaped).joined(separator: ",")
    }
}

public struct TimelineEventCSVRow: Sendable, Equatable {
    public static let header = "id,date,time,title,linked_task_id,source,parallel_group_id"

    public let event: TimelineEvent

    public init(event: TimelineEvent) {
        self.event = event
    }

    public var csvLine: String {
        [
            event.id.uuidString,
            Self.isoString(from: event.date),
            event.time.csvValue,
            event.title,
            event.linkedTaskID?.uuidString ?? "",
            event.source.rawValue,
            event.parallelGroupID?.uuidString ?? ""
        ].map(\.csvEscaped).joined(separator: ",")
    }

    private static func isoString(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

private extension TaskKind {
    var csvValue: String {
        switch self {
        case .oneTime:
            return "oneTime"
        case .cumulative:
            return "cumulative"
        case .frequencyGoal:
            return "frequencyGoal"
        }
    }
}

private extension TimelineTime {
    var markdownLabel: String {
        switch self {
        case .fixed(let hour, let minute):
            return String(format: "%02d:%02d", hour, minute)
        case .unknown:
            return "?"
        case .fuzzy(let label):
            return label
        }
    }

    var csvValue: String {
        switch self {
        case .fixed(let hour, let minute):
            return String(format: "%02d:%02d", hour, minute)
        case .unknown:
            return "unknown"
        case .fuzzy(let label):
            return label
        }
    }
}

private extension String {
    var csvEscaped: String {
        if contains(",") || contains("\"") || contains("\n") {
            return "\"\(replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return self
    }
}

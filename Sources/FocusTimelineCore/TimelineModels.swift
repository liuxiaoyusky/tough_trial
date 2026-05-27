import Foundation

public enum TimelineTime: Codable, Sendable, Equatable {
    case fixed(hour: Int, minute: Int)
    case unknown
    case fuzzy(label: String)
}

public enum TimelineEventSource: String, Codable, Sendable, Equatable {
    case manual
    case task
    case focus
    case calendar
    case aiPlanning
    case recall
}

public struct TimelineEvent: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var date: Date
    public var time: TimelineTime
    public var title: String
    public var linkedTaskID: UUID?
    public var source: TimelineEventSource
    public var parallelGroupID: UUID?

    public init(
        id: UUID,
        date: Date,
        time: TimelineTime,
        title: String,
        linkedTaskID: UUID?,
        source: TimelineEventSource,
        parallelGroupID: UUID?
    ) {
        self.id = id
        self.date = date
        self.time = time
        self.title = title
        self.linkedTaskID = linkedTaskID
        self.source = source
        self.parallelGroupID = parallelGroupID
    }
}

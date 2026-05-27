import Foundation

public struct PlanningDraft: Codable, Sendable, Equatable {
    public var targetDate: Date
    public var fixedEvents: [TimelineEvent]
    public var plannedEvents: [TimelineEvent]
    public var unplacedTasks: [TaskItem]

    public init(
        targetDate: Date,
        fixedEvents: [TimelineEvent],
        plannedEvents: [TimelineEvent],
        unplacedTasks: [TaskItem]
    ) {
        self.targetDate = targetDate
        self.fixedEvents = fixedEvents
        self.plannedEvents = plannedEvents
        self.unplacedTasks = unplacedTasks
    }

    public func parallelEvents(in groupID: UUID) -> [TimelineEvent] {
        plannedEvents.filter { $0.parallelGroupID == groupID }
    }
}

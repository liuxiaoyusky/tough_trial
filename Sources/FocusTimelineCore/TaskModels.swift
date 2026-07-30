import Foundation

public enum TaskPriorityTier: String, Codable, Sendable, CaseIterable {
    case critical
    case medium
    case notifyOnly
    case none
}

public enum TaskStatus: String, Codable, Sendable, Equatable {
    case active
    case completed
    case notStarted
}

public enum GoalPeriod: String, Codable, Sendable, Equatable {
    case day
    case week
    case month
}

public enum TaskKind: Codable, Sendable, Equatable {
    case oneTime
    case cumulative(unit: String)
    case frequencyGoal(period: GoalPeriod)
}

public struct TaskProgress: Codable, Sendable, Equatable {
    public var completedAmount: Double
    public let targetAmount: Double
    public let unit: String?

    public init(completedAmount: Double, targetAmount: Double, unit: String?) {
        self.completedAmount = completedAmount
        self.targetAmount = targetAmount
        self.unit = unit
    }
}

public struct TaskCompletionRecord: Codable, Sendable, Equatable {
    public let amount: Double
    public let completedAt: Date

    public init(amount: Double, completedAt: Date) {
        self.amount = amount
        self.completedAt = completedAt
    }
}

public struct TaskItem: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var title: String
    public var kind: TaskKind
    public var priority: TaskPriorityTier
    public var status: TaskStatus
    public var progress: TaskProgress
    public var completions: [TaskCompletionRecord]

    public init(
        id: UUID,
        title: String,
        kind: TaskKind,
        priority: TaskPriorityTier,
        status: TaskStatus,
        progress: TaskProgress,
        completions: [TaskCompletionRecord] = []
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.priority = priority
        self.status = status
        self.progress = progress
        self.completions = completions
    }

    public static func oneTime(
        id: UUID,
        title: String,
        priority: TaskPriorityTier
    ) -> TaskItem {
        TaskItem(
            id: id,
            title: title,
            kind: .oneTime,
            priority: priority,
            status: .active,
            progress: TaskProgress(completedAmount: 0, targetAmount: 1, unit: nil)
        )
    }

    public static func cumulative(
        id: UUID,
        title: String,
        unit: String,
        targetAmount: Double,
        priority: TaskPriorityTier
    ) -> TaskItem {
        TaskItem(
            id: id,
            title: title,
            kind: .cumulative(unit: unit),
            priority: priority,
            status: .active,
            progress: TaskProgress(completedAmount: 0, targetAmount: targetAmount, unit: unit)
        )
    }

    public static func frequencyGoal(
        id: UUID,
        title: String,
        targetCount: Int,
        period: GoalPeriod,
        priority: TaskPriorityTier
    ) -> TaskItem {
        TaskItem(
            id: id,
            title: title,
            kind: .frequencyGoal(period: period),
            priority: priority,
            status: .active,
            progress: TaskProgress(completedAmount: 0, targetAmount: Double(targetCount), unit: "次")
        )
    }

    public mutating func recordCompletion(amount: Double?, at completedAt: Date) {
        let completedAmount: Double

        switch kind {
        case .oneTime, .frequencyGoal:
            completedAmount = 1
        case .cumulative:
            completedAmount = amount ?? 0
        }

        progress.completedAmount += completedAmount
        completions.append(TaskCompletionRecord(amount: completedAmount, completedAt: completedAt))

        if progress.completedAmount >= progress.targetAmount {
            status = .completed
        }
    }
}

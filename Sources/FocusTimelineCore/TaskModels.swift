import Foundation

public enum TaskPriorityTier: String, Codable, Sendable, CaseIterable {
    case critical
    case medium
    case notifyOnly
    case none
}

import Foundation

public struct V2ScheduleRemoteRequest: Codable, Equatable, Identifiable, Sendable {
    public enum Status: String, Codable, Sendable {
        case pending, processed, needsClarification
    }

    public var id: String
    public var prompt: String
    public var status: Status
    public var createdAt: Date
    public var processedAt: Date?
    public var result: String?

    public init(id: String = UUID().uuidString, prompt: String, status: Status = .pending,
                createdAt: Date, processedAt: Date? = nil, result: String? = nil) {
        self.id = id
        self.prompt = prompt
        self.status = status
        self.createdAt = createdAt
        self.processedAt = processedAt
        self.result = result
    }
}

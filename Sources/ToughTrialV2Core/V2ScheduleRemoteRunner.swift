import Foundation

public struct V2ScheduleRemoteRunResult: Equatable, Sendable {
    public var processedCount: Int
    public var pendingCount: Int
    public var conflictRetries: Int
}

public enum V2ScheduleRemoteRunner {
    /// A SHA conflict always re-reads the request state before another model call.
    public static func run<Transport: V2PlanningHTTPTransport, Client: V2ScheduleClient>(
        github: V2GitHubScheduleClient<Transport>, client: Client,
        maximumRequests: Int = 100, maximumConflictRetries: Int = 3,
        at date: Date = Date()
    ) async throws -> V2ScheduleRemoteRunResult {
        var processed = 0
        var conflicts = 0
        while true {
            try Task.checkCancellation()
            let revision = try await github.read()
            let document = try V2ScheduleMarkdown.decode(revision.content)
            let pending = document.remoteRequests.filter { $0.status == .pending }.count
            guard pending > 0, processed < maximumRequests else {
                return .init(processedCount: processed, pendingCount: pending, conflictRetries: conflicts)
            }
            guard let updated = try await V2ScheduleRemoteProcessor.processNext(in: document, using: client, at: date) else {
                return .init(processedCount: processed, pendingCount: 0, conflictRetries: conflicts)
            }
            try Task.checkCancellation()
            do {
                _ = try await github.write(content: V2ScheduleMarkdown.encode(updated), expectedSHA: revision.sha)
                processed += 1
            } catch V2GitHubScheduleError.conflict {
                guard conflicts < maximumConflictRetries else { throw V2GitHubScheduleError.conflict }
                conflicts += 1
            }
        }
    }
}

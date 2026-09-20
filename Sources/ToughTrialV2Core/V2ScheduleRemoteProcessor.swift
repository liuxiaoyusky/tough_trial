import Foundation

/// Processes explicit requests only. Persist the returned document atomically with its request status.
public enum V2ScheduleRemoteProcessor {
    public static func processNext<Client: V2ScheduleClient>(
        in document: V2ScheduleDocument,
        using client: Client,
        at date: Date = Date()
    ) async throws -> V2ScheduleDocument? {
        try V2ScheduleMarkdown.validate(document)
        guard let index = document.remoteRequests.firstIndex(where: { $0.status == .pending }) else { return nil }
        let request = document.remoteRequests[index]
        let snapshot = V2AppSnapshot(taskContexts: document.taskContexts, tasks: document.tasks,
            planItems: document.planItems, executionSegments: document.executionSegments)
        let outcome = try await client.generate(.init(userText: request.prompt, snapshot: snapshot,
            referenceDate: request.createdAt == .distantPast ? date : request.createdAt,
            timeZoneIdentifier: document.timeZoneIdentifier))
        try Task.checkCancellation()
        var updated = document
        switch outcome {
        case let .clarification(question):
            updated.remoteRequests[index].status = .needsClarification
            updated.remoteRequests[index].result = question
        case let .proposal(proposal):
            let engine = V2Engine(snapshot: snapshot)
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: document.timeZoneIdentifier)!
            let receipt = try engine.applyScheduleProposal(proposal, requestID: request.id, at: date, calendar: calendar)
            updated.tasks = engine.snapshot.tasks
            updated.planItems = engine.snapshot.planItems
            updated.remoteRequests[index].status = .processed
            // Report actual committed changes, never the model's unverified completion claim.
            updated.remoteRequests[index].result = receipt.changes.isEmpty
                ? "日程已符合要求，无需重复修改。"
                : "已更新 \(receipt.changes.count) 项任务或排期。\n\(receipt.summary)"
        }
        updated.remoteRequests[index].processedAt = max(date, request.createdAt)
        try V2ScheduleMarkdown.validate(updated)
        return updated
    }
}

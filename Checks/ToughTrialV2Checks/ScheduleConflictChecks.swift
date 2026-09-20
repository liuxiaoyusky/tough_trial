import Foundation
import ToughTrialV2Core

private actor ConflictTransport: V2PlanningHTTPTransport {
    let payload: Data
    var request: URLRequest?
    init(payload: Data) { self.payload = payload }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        self.request = request
        return (payload, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

func checkScheduleConflictAIContractApplyUndoAndStaleProtection() async throws {
    let date = Date(timeIntervalSince1970: 1_788_825_600)
    let task = V2Task(id: "task", title: "准备演示", note: "原要求", createdAt: date, updatedAt: date)
    let engine = V2Engine(snapshot: .init(tasks: [task]))
    let base = try engine.prepareScheduleDocument(timeZoneIdentifier: "UTC")
    let location = V2GitHubScheduleLocation(owner: "test", repository: "test", branch: "main", path: "schedule.md")
    try engine.configureScheduleGitHub(location)
    let github = V2GitHubScheduleClient(location: location, token: "fixture", transport: RemoteGitHubTransport(content: try V2ScheduleMarkdown.encode(base)))
    let initial = try engine.beginScheduleSync()
    try engine.acceptScheduleSync(await V2ScheduleSynchronizer.synchronize(initial, using: github), attempt: initial)
    _ = try engine.applyScheduleProposal(.init(summary: "改备注", operations: [.init(kind: .updateTask, targetID: task.id, note: "保留 3 个示例")]), requestID: "edit", at: date)
    var remote = base
    remote.tasks[0].note = "总共不超过 2 小时"
    let concurrent = V2GitHubScheduleClient(location: location, token: "fixture", transport: RemoteGitHubTransport(content: try V2ScheduleMarkdown.encode(remote)))
    let attempt = try engine.beginScheduleSync()
    try engine.acceptScheduleSync(await V2ScheduleSynchronizer.synchronize(attempt, using: concurrent), attempt: attempt)
    let conflict = engine.snapshot.scheduleDocumentState!.github!.conflict!
    require(conflict.conflicts.count == 1, "Concurrent notes must retain one concrete conflict")
    let rows: [[String: Any]] = [["id": conflict.conflicts[0].id, "choice": "mergeText", "text": "保留 3 个示例；总共不超过 2 小时"]]
    let output: [String: Any] = ["kind": "resolution", "conflictID": conflict.id, "resolutions": rows]
    func response(_ output: [String: Any]) throws -> Data {
        let text = String(decoding: try JSONSerialization.data(withJSONObject: output), as: UTF8.self)
        return try JSONSerialization.data(withJSONObject: ["request_id": "metadata", "choices": [["finish_reason": "stop", "message": ["content": text, "reasoning_content": "ignored"]]]])
    }
    let transport = ConflictTransport(payload: try response(output))
    let client = V2OpenAICompatibleConflictClient(configuration: .init(endpoint: URL(string: "https://example.com/chat/completions")!, apiKey: "secret-only-header", model: "fixture"), transport: transport, guidance: "保留双方要求")
    let outcome = try await client.resolve(conflict)
    guard case let .resolution(resolutions) = outcome else { fatalError("Valid AI result must become controlled resolutions") }
    let request = await transport.request!
    let body = String(decoding: request.httpBody!, as: UTF8.self)
    require(!body.contains("secret-only-header") && body.contains("保留双方要求"), "User guidance is sent while credentials stay out of the payload")
    let before = engine.snapshot
    let changed = V2Engine(snapshot: before)
    _ = try changed.createTask(title: "模型处理期间新增")
    let latest = changed.snapshot
    do {
        try changed.applyScheduleConflictResolution(conflictID: conflict.id, resolutions: resolutions)
        fatalError("Late AI resolution must not overwrite a newer local document")
    } catch V2ScheduleConflictResolutionError.stale { }
    require(changed.snapshot == latest, "Rejected stale resolution must leave the latest state intact")
    try engine.applyScheduleConflictResolution(conflictID: conflict.id, resolutions: resolutions)
    require(engine.snapshot.tasks[0].note == "保留 3 个示例；总共不超过 2 小时", "Validated conflict result must update the existing task")
    require(engine.snapshot.scheduleDocumentState?.github?.conflict == nil && engine.snapshot.scheduleDocumentState?.github?.requiresRetry == true,
        "Resolution clears this conflict while queuing its upload")
    _ = try engine.restoreScheduleDocumentVersion(id: conflict.id)
    require(engine.snapshot.tasks == before.tasks, "Conflict processing must be undoable")

    var wrong = output
    wrong["conflictID"] = "stale-id"
    do { _ = try client.decodeResponse(response(wrong), conflict: conflict); fatalError("Wrong conflict version must reject") }
    catch V2ScheduleConflictResolutionError.invalidChoice { }
    var extra = output
    extra["resolutions"] = rows + [["id": "unrelated-task:title", "choice": "local"]]
    do { _ = try client.decodeResponse(response(extra), conflict: conflict); fatalError("AI must not affect unlisted fields") }
    catch V2ScheduleConflictResolutionError.invalidChoice { }
    let clarification = try client.decodeResponse(response(["kind": "clarification", "conflictID": conflict.id, "question": "保留三点还是四点？"]), conflict: conflict)
    require(clarification == .clarification("保留三点还是四点？"), "Ambiguous timing must remain a concrete question")
    require(engine.snapshot.tasks == before.tasks, "Decoding a clarification must not mutate tasks")
}

func checkScheduleConflictCannotRewriteExecutionFacts() throws {
    let start = Date(timeIntervalSince1970: 1_788_825_600)
    let segment = V2ExecutionSegment(id: "fact", titleSnapshot: "真实执行", startAt: start,
        endAt: start.addingTimeInterval(60), endReason: .stopped, source: .normal)
    let base = V2ScheduleDocument(id: "protected", timeZoneIdentifier: "UTC", taskContexts: [], tasks: [], planItems: [], executionSegments: [segment])
    var remote = base
    remote.executionSegments[0].endAt = start.addingTimeInterval(120)
    let merged = try V2ScheduleMerge.merge(base: base, local: base, remote: remote)
    let bundle = V2ScheduleSyncConflict(base: base, local: base, remote: remote, remoteSHA: String(repeating: "a", count: 40), conflicts: merged.conflicts)
    let id = bundle.conflicts[0].id
    do {
        _ = try V2ScheduleConflictResolver.resolve(bundle, using: [.init(id: id, choice: .remote)])
        fatalError("AI may not replace known execution timestamps")
    } catch V2ScheduleConflictResolutionError.invalidChoice { }
    let protected = try V2ScheduleConflictResolver.resolve(bundle, using: [.init(id: id, choice: .base)])
    require(protected.executionSegments == [segment], "A valid fact resolution preserves the original execution")
}

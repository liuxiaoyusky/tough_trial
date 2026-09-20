import Foundation
import ToughTrialV2Core

private actor RemoteScheduleClient: V2ScheduleClient {
    nonisolated let providerLabel = "fixture"
    let outcome: V2ScheduleOutcome
    var count = 0
    init(_ outcome: V2ScheduleOutcome) { self.outcome = outcome }
    func generate(_ request: V2ScheduleRequest) async throws -> V2ScheduleOutcome {
        count += 1
        return outcome
    }
}

func checkRemoteRequestsRoundTripMergeAndProcessing() async throws {
    let date = Date(timeIntervalSince1970: 1_788_825_600)
    var base = V2ScheduleDocument(id: "remote", timeZoneIdentifier: "Asia/Shanghai", taskContexts: [],
        tasks: [], planItems: [], executionSegments: [], remoteRequests: [
            .init(id: "request-1", prompt: "整理明天的准备工作\n不要安排晚上\n", createdAt: date)
        ])
    let text = try V2ScheduleMarkdown.encode(base)
    let decoded = try V2ScheduleMarkdown.decode(text)
    require(decoded == base, "Multiline remote requests must round-trip with their identity")
    var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(base)) as! [String: Any]
    legacy.removeValue(forKey: "remoteRequests")
    let old = try JSONDecoder().decode(V2ScheduleDocument.self, from: JSONSerialization.data(withJSONObject: legacy))
    require(old.remoteRequests.isEmpty, "Old document JSON loads without requests")
    let client = RemoteScheduleClient(.proposal(.init(summary: "准备材料", operations: [
        .init(kind: .createTask, localID: "prep", title: "准备材料", note: "不要安排晚上")
    ])))
    let processed = try await V2ScheduleRemoteProcessor.processNext(in: base, using: client, at: date)!
    require(processed.tasks.count == 1 && processed.remoteRequests[0].status == .processed,
        "Task changes and processed status must be returned in the same document")
    let restarted = try V2ScheduleMarkdown.decode(V2ScheduleMarkdown.encode(processed))
    require(restarted == processed, "Processed result and task IDs survive a file restart")
    let again = try await V2ScheduleRemoteProcessor.processNext(in: restarted, using: client, at: date)
    let callCount = await client.count
    require(again == nil && callCount == 1, "Repeated triggers must not call AI or recreate tasks")
    var edited = base
    edited.remoteRequests[0].prompt = "改为后天，别遗漏限制"
    let concurrent = try V2ScheduleMerge.merge(base: base, local: edited, remote: processed)
    require(concurrent.conflicts.contains { $0.objectType == .remoteRequest }, "Editing a request while it is processed must retain a conflict")
    require(concurrent.document.remoteRequests[0].status == .pending && concurrent.document.remoteRequests[0].result == nil,
        "A processing result must never attach to a different prompt")
    var rewritten = processed
    rewritten.remoteRequests[0].prompt = "新问题"
    let immutable = try V2ScheduleMerge.merge(base: processed, local: processed, remote: rewritten)
    require(immutable.document.remoteRequests == processed.remoteRequests && !immutable.conflicts.isEmpty,
        "Processed request identity is immutable; follow-ups need a new ID")
    let clarifier = RemoteScheduleClient(.clarification(question: "是哪个准备任务？"))
    let clarified = try await V2ScheduleRemoteProcessor.processNext(in: base, using: clarifier, at: date)!
    require(clarified.tasks.isEmpty && clarified.remoteRequests[0].status == .needsClarification,
        "Clarification must not modify schedule tasks")
    base.remoteRequests.append(base.remoteRequests[0])
    do {
        _ = try V2ScheduleMarkdown.encode(base)
        fatalError("Duplicate remote request IDs must be rejected")
    } catch V2ScheduleMarkdownError.duplicateID { }
}

actor RemoteGitHubTransport: V2PlanningHTTPTransport {
    var content: String
    var revision = 1
    var replacementOnFirstWrite: String?
    var writes = 0
    var offline = false
    func setOffline(_ value: Bool) { offline = value }
    init(content: String, replacementOnFirstWrite: String? = nil) {
        self.content = content
        self.replacementOnFirstWrite = replacementOnFirstWrite
    }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if offline { throw URLError(.notConnectedToInternet) }
        var status = 200
        var object: [String: Any]
        if request.httpMethod == "PUT" {
            writes += 1
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            if let replacement = replacementOnFirstWrite {
                content = replacement
                replacementOnFirstWrite = nil
                revision += 1
            }
            if body["sha"] as? String != String(format: "%040x", revision) {
                status = 409
                object = [:]
            } else {
                content = String(decoding: Data(base64Encoded: body["content"] as! String)!, as: UTF8.self)
                revision += 1
                object = ["content": ["sha": String(format: "%040x", revision)]]
            }
        } else {
            object = ["type": "file", "encoding": "base64", "sha": String(format: "%040x", revision),
                "content": Data(content.utf8).base64EncodedString()]
        }
        return (try JSONSerialization.data(withJSONObject: object),
            HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

func checkRemoteRunnerRereadsConcurrentCompletion() async throws {
    let date = Date(timeIntervalSince1970: 1_788_825_600)
    let base = V2ScheduleDocument(id: "race", timeZoneIdentifier: "UTC", taskContexts: [], tasks: [],
        planItems: [], executionSegments: [], remoteRequests: [.init(id: "one", prompt: "新增测试任务", createdAt: date)])
    let proposal = V2ScheduleOutcome.proposal(.init(summary: "测试任务", operations: [.init(kind: .createTask, title: "测试任务")]))
    let otherClient = RemoteScheduleClient(proposal)
    let competing = try await V2ScheduleRemoteProcessor.processNext(in: base, using: otherClient, at: date)!
    let competingText = try V2ScheduleMarkdown.encode(competing)
    let transport = RemoteGitHubTransport(content: try V2ScheduleMarkdown.encode(base), replacementOnFirstWrite: competingText)
    let github = V2GitHubScheduleClient(location: .init(owner: "test", repository: "test", branch: "main", path: "schedule.md"), token: "fixture", transport: transport)
    let client = RemoteScheduleClient(proposal)
    let result = try await V2ScheduleRemoteRunner.run(github: github, client: client, at: date)
    let calls = await client.count
    let content = await transport.content
    require(result.processedCount == 0 && result.pendingCount == 0 && result.conflictRetries == 1,
        "A competing completion must be discovered by re-reading after SHA conflict")
    require(calls == 1 && content == competingText, "Must preserve the other client's task IDs without another AI call or duplicate task")

    let normalTransport = RemoteGitHubTransport(content: try V2ScheduleMarkdown.encode(base))
    let normalGitHub = V2GitHubScheduleClient(location: github.location, token: "fixture", transport: normalTransport)
    let first = try await V2ScheduleRemoteRunner.run(github: normalGitHub, client: client, at: date)
    let second = try await V2ScheduleRemoteRunner.run(github: normalGitHub, client: client, at: date)
    let writes = await normalTransport.writes
    require(first.processedCount == 1 && second.processedCount == 0 && writes == 1,
        "A normal run writes request status with tasks exactly once across repeat runs")
}

import Foundation
import ToughTrialV2Core

private actor ScheduleClientRecordingTransport: V2PlanningHTTPTransport {
    private let responseData: Data
    private let statusCode: Int
    private let headerFields: [String: String]?
    private var capturedRequest: URLRequest?

    init(
        responseData: Data,
        statusCode: Int = 200,
        headerFields: [String: String]? = nil
    ) {
        self.responseData = responseData
        self.statusCode = statusCode
        self.headerFields = headerFields
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        capturedRequest = request
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headerFields
        )!
        return (responseData, response)
    }

    func lastRequest() -> URLRequest? {
        capturedRequest
    }
}

private func scheduleClientRequest() -> V2ScheduleRequest {
    let referenceDate = Date(timeIntervalSince1970: 1_788_823_800)
    let planDate = Date(timeIntervalSince1970: 1_788_825_600)
    let startAt = Date(timeIntervalSince1970: 1_788_879_600)
    let endAt = Date(timeIntervalSince1970: 1_788_881_400)
    let task = V2Task(
        id: "task-run",
        contextID: "context-health",
        title: "跑步",
        note: "每次至少 30 分钟",
        status: .notStarted,
        createdAt: referenceDate,
        updatedAt: referenceDate
    )
    let planItem = V2PlanItem(
        id: "plan-run",
        date: planDate,
        startAt: startAt,
        endAt: endAt,
        taskID: "task-run",
        title: "跑步",
        status: .planned
    )
    let context = V2TaskContext(
        id: "context-health",
        title: "健康",
        colorName: "blue",
        createdAt: referenceDate,
        updatedAt: referenceDate
    )
    return V2ScheduleRequest(
        userText: "把跑步安排到明天 16:00，不要改其他安排；数量保持 3 次",
        conversation: [
            V2AgentConversationMessage(role: .user, text: "我想安排本周训练"),
            V2AgentConversationMessage(role: .assistant, text: "要保留哪些限制？"),
        ],
        snapshot: V2AppSnapshot(
            taskContexts: [context],
            tasks: [task],
            planItems: [planItem]
        ),
        referenceDate: referenceDate,
        timeZoneIdentifier: "Asia/Shanghai"
    )
}

private func scheduleResponse(_ object: [String: Any]) throws -> Data {
    let content = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return try JSONSerialization.data(
        withJSONObject: [
            "choices": [["message": ["content": String(data: content, encoding: .utf8)!]]],
        ],
        options: [.sortedKeys]
    )
}

private func scheduleProposalObject(
    operations: [[String: Any]] = [[
        "kind": "createTask",
        "localID": "new-task",
        "title": "准备训练鞋",
        "note": "保留雨天改室内的限制",
    ]]
) -> [String: Any] {
    [
        "kind": "proposal",
        "summary": "已整理日程变更",
        "operations": operations,
    ]
}

func checkScheduleClientRequestShapeAndProposal() async throws {
    let response = try scheduleResponse(scheduleProposalObject())
    let transport = ScheduleClientRecordingTransport(responseData: response)
    let client = V2OpenAICompatibleScheduleClient(
        configuration: .init(
            endpoint: URL(string: "https://example.com/v1/chat/completions")!,
            apiKey: "schedule-secret",
            model: "test-schedule",
            providerLabel: "Test Schedule"
        ),
        transport: transport
    )

    let outcome = try await client.generate(scheduleClientRequest())
    guard case let .proposal(proposal) = outcome else {
        fatalError("A valid schedule response should decode as a proposal")
    }
    require(proposal.summary == "已整理日程变更", "Proposal summary should be preserved")
    require(proposal.operations.count == 1, "Proposal operations should be preserved")
    require(
        proposal.operations[0].kind == .createTask
            && proposal.operations[0].localID == "new-task",
        "Proposal operation should decode through the shared schedule operation type"
    )

    guard let request = await transport.lastRequest(),
          let body = request.httpBody,
          let object = try JSONSerialization.jsonObject(with: body) as? [String: Any],
          let messages = object["messages"] as? [[String: Any]],
          let userContent = messages.last?["content"] as? String,
          let payload = try JSONSerialization.jsonObject(with: Data(userContent.utf8)) as? [String: Any]
    else {
        fatalError("The schedule request should contain a JSON user payload")
    }

    require(request.httpMethod == "POST", "Schedule requests should use POST")
    require(request.value(forHTTPHeaderField: "Authorization") == "Bearer schedule-secret", "API key belongs in the authorization header")
    require(request.timeoutInterval > 0, "Schedule requests should set a finite timeout")
    require(object["model"] as? String == "test-schedule", "Schedule requests should carry the configured model")
    require(payload["user_text"] as? String == scheduleClientRequest().userText, "User text should be preserved")
    require(payload["time_zone"] as? String == "Asia/Shanghai", "The request should carry the timezone identifier")
    require(payload["reference_date"] as? String == "2026-09-08", "The request should carry the local reference day")
    require(
        payload["reference_instant"] is String,
        "The request should retain the reference instant alongside the local day"
    )
    require(userContent.contains("task-run") && userContent.contains("plan-run"), "Known task and plan IDs should be visible to the model")
    require(userContent.contains("我想安排本周训练") && userContent.contains("要保留哪些限制？"), "Conversation messages should be forwarded")
    require(!userContent.contains("scheduleReceipts") && !userContent.contains("receipts"), "Schedule context must not include receipt history")
    require(!String(data: body, encoding: .utf8)!.contains("schedule-secret"), "API keys must not appear in the request body")
    let systemPrompt = messages.first?["content"] as? String ?? ""
    require(
        systemPrompt.contains("明确要求") && systemPrompt.contains("不要使用 Markdown"),
        "The system prompt should constrain proposal intent and JSON formatting"
    )
}

func checkScheduleClientDecodesEveryOperation() throws {
    let fixtures: [[String: Any]] = [
        ["kind": "createTask", "localID": "new", "title": "新任务"],
        ["kind": "updateTask", "targetID": "task-run", "title": "更新任务"],
        ["kind": "scheduleTask", "targetID": "task-run", "day": "2026-09-08", "startMinute": 960, "durationMinutes": 30],
        ["kind": "reschedulePlanItem", "targetID": "plan-run", "day": "2026-09-09", "startMinute": 1_020],
        ["kind": "cancelPlanItem", "targetID": "plan-run"],
        ["kind": "completeTask", "targetID": "task-run"],
        ["kind": "restoreTask", "targetID": "task-run"],
        ["kind": "archiveTask", "targetID": "task-run"],
    ]
    let client = V2OpenAICompatibleScheduleClient(
        configuration: .init(
            endpoint: URL(string: "https://example.com/v1/chat/completions")!,
            apiKey: "secret",
            model: "model"
        ),
        transport: ScheduleClientRecordingTransport(responseData: Data())
    )
    let outcome = try client.decodeResponse(
        scheduleResponse(scheduleProposalObject(operations: fixtures)),
        request: scheduleClientRequest()
    )
    guard case let .proposal(proposal) = outcome else {
        fatalError("All schedule operations should decode as a proposal")
    }
    require(proposal.operations.map(\.kind) == [
        .createTask,
        .updateTask,
        .scheduleTask,
        .reschedulePlanItem,
        .cancelPlanItem,
        .completeTask,
        .restoreTask,
        .archiveTask,
    ], "Every supported schedule operation kind should decode")
}

func checkScheduleClientDecodesClarification() throws {
    let client = V2OpenAICompatibleScheduleClient(
        configuration: .init(
            endpoint: URL(string: "https://example.com/v1/chat/completions")!,
            apiKey: "secret",
            model: "model"
        ),
        transport: ScheduleClientRecordingTransport(responseData: Data())
    )
    let response = try scheduleResponse([
        "kind": "clarification",
        "question": "要安排哪一天？",
    ])
    let outcome = try client.decodeResponse(response, request: scheduleClientRequest())
    guard case let .clarification(question) = outcome else {
        fatalError("Clarification output should decode as a question")
    }
    require(question == "要安排哪一天？", "Clarification question should be preserved")
}

func checkScheduleClientParsesWallClockTime() throws {
    let client = V2OpenAICompatibleScheduleClient(configuration: .init(
        endpoint: URL(string: "https://example.com/chat/completions")!, apiKey: "fixture", model: "fixture"))
    for (time, minute) in [("00:00", 0), ("16:00", 960), ("17:45", 1065), ("23:59", 1439)] {
        let operation: [String: Any] = ["kind": "scheduleTask", "targetID": "task-run", "day": "2026-09-08", "startTime": time]
        let outcome = try client.decodeResponse(scheduleResponse(scheduleProposalObject(operations: [operation])), request: scheduleClientRequest())
        guard case let .proposal(proposal) = outcome else { fatalError("Valid clock time must produce a proposal") }
        require(proposal.operations[0].startMinute == minute, "Clock conversion must use deterministic arithmetic")
    }
    for time in ["24:00", "16:60", "4:00", "16：00", "１６:００", "16:00Z", " 16:00"] {
        let operation: [String: Any] = ["kind": "scheduleTask", "targetID": "task-run", "day": "2026-09-08", "startTime": time]
        do {
            _ = try client.decodeResponse(scheduleResponse(scheduleProposalObject(operations: [operation])), request: scheduleClientRequest())
            fatalError("Malformed wall clock time must reject")
        } catch is V2ScheduleClientError { }
    }
    let both: [String: Any] = ["kind": "scheduleTask", "targetID": "task-run", "day": "2026-09-08", "startTime": "16:00", "startMinute": 1020]
    do {
        _ = try client.decodeResponse(scheduleResponse(scheduleProposalObject(operations: [both])), request: scheduleClientRequest())
        fatalError("Conflicting time representations must reject")
    } catch is V2ScheduleClientError { }
}

func checkScheduleGLMCodingCompatibility() throws {
    let cases: [(String, String, Bool)] = [
        ("https://open.bigmodel.cn/api/coding/paas/v4/chat/completions", "glm-5.3-flash", true),
        ("https://api.z.ai/api/coding/paas/v4/chat/completions", "glm-5.3", true),
        ("https://open.bigmodel.cn/api/paas/v4/chat/completions", "glm-5.3-flash", true),
        ("https://open.bigmodel.cn.example.com/api/coding/paas/v4/chat/completions", "glm-5.3-flash", false),
        ("https://example.com/chat/completions", "glm-5.3-flash", false),
        ("https://open.bigmodel.cn/api/coding/paas/v4/chat/completions", "another-model", false)
    ]
    for (url, model, expected) in cases {
        let client = V2OpenAICompatibleScheduleClient(configuration: .init(
            endpoint: URL(string: url)!, apiKey: "fixture-key", model: model))
        let request = try client.makeURLRequest(for: scheduleClientRequest())
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        require((body["thinking"] as? [String: String]) == (expected ? ["type": "enabled"] : nil),
                "Only verified GLM endpoints and models receive GLM thinking fields")
        require(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-key", "GLM must use Bearer authentication")
        require((body["reasoning_effort"] as? String) == (expected ? "low" : nil) && body["enable_thinking"] == nil, "GLM 5.3 uses its supported low effort field")
        require(!String(decoding: request.httpBody!, as: UTF8.self).contains("fixture-key"), "GLM credentials must stay out of the payload")
    }
}

func checkScheduleClientRejectsInvalidOutputAndHTTPFailures() async throws {
    let configuration = V2OpenAICompatibleAgentConfiguration(
        endpoint: URL(string: "https://example.com/v1/chat/completions")!,
        apiKey: "secret",
        model: "model"
    )
    let client = V2OpenAICompatibleScheduleClient(
        configuration: configuration,
        transport: ScheduleClientRecordingTransport(responseData: Data())
    )

    let invalidObjects: [[String: Any]] = [
        ["kind": "other", "summary": "x", "operations": []],
        ["kind": "clarification", "question": ""],
        ["kind": "proposal", "summary": "", "operations": []],
        ["kind": "proposal", "summary": "x", "operations": [["kind": "unknown", "targetID": "task-run"]]],
        ["kind": "proposal", "summary": "x", "operations": [["kind": "createTask", "targetID": "task-run", "day": "2026-09-08", "title": "bad"]]],
        ["kind": "proposal", "summary": "x", "operations": [["kind": "completeTask", "targetID": "task-run", "title": "bad"]]],
        ["kind": "proposal", "summary": "x", "operations": [["kind": "updateTask", "targetID": "missing", "title": "bad"]]],
        ["kind": "proposal", "summary": "x", "operations": [["kind": "createTask", "localID": "new", "title": "bad", "contextID": "missing"]]],
        ["kind": "proposal", "summary": "x", "operations": [["kind": "cancelPlanItem", "targetID": "missing"]]],
    ]

    for object in invalidObjects {
        do {
            _ = try client.decodeResponse(
                scheduleResponse(object),
                request: scheduleClientRequest()
            )
            fatalError("Invalid schedule response should be rejected: \(object)")
        } catch V2ScheduleClientError.invalidOutput {
            // Expected.
        }
    }

    let unknownField = try scheduleResponse([
        "kind": "proposal",
        "summary": "x",
        "operations": [["kind": "createTask", "title": "x", "unexpected": true]],
    ])
    do {
        _ = try client.decodeResponse(unknownField, request: scheduleClientRequest())
        fatalError("Unknown operation fields should be rejected")
    } catch V2ScheduleClientError.invalidOutput {
        // Expected.
    }

    let fenced = Data("```json\n{\"kind\":\"clarification\",\"question\":\"x\"}\n```".utf8)
    do {
        _ = try client.decodeResponse(fenced, request: scheduleClientRequest())
        fatalError("Markdown fences should not be accepted as structured output")
    } catch V2ScheduleClientError.invalidOutput {
        // Expected.
    }

    do {
        _ = try client.decodeResponse(Data("{".utf8), request: scheduleClientRequest())
        fatalError("Malformed JSON should be rejected")
    } catch V2ScheduleClientError.invalidOutput {
        // Expected.
    }

    let tooMany = Array(repeating: ["kind": "createTask", "localID": "new", "title": "x"], count: 101)
    do {
        _ = try client.decodeResponse(
            scheduleResponse(scheduleProposalObject(operations: tooMany)),
            request: scheduleClientRequest()
        )
        fatalError("More than 100 operations should be rejected")
    } catch V2ScheduleClientError.invalidOutput {
        // Expected.
    }

    let errorTransport = ScheduleClientRecordingTransport(
        responseData: Data(#"{"error":{"message":"API key secret-should-not-echo"}}"#.utf8),
        statusCode: 503
    )
    let errorClient = V2OpenAICompatibleScheduleClient(
        configuration: configuration,
        transport: errorTransport
    )
    do {
        _ = try await errorClient.generate(scheduleClientRequest())
        fatalError("Non-2xx responses should fail")
    } catch let error as V2ScheduleClientError {
        guard case let .requestFailed(statusCode, message) = error else {
            fatalError("HTTP failures should use the schedule client request error")
        }
        require(statusCode == 503, "HTTP failures should preserve status codes")
        require(!message.contains("secret-should-not-echo"), "HTTP errors must not echo server error text")
    }
}

func checkScheduleClientRejectsInvalidConfigurationAndBounds() async throws {
    let request = scheduleClientRequest()
    let invalidConfigurations = [
        V2OpenAICompatibleAgentConfiguration(
            endpoint: URL(string: "http://example.com/v1/chat/completions")!,
            apiKey: "secret",
            model: "model"
        ),
        V2OpenAICompatibleAgentConfiguration(
            endpoint: URL(string: "https://example.com/v1/chat/completions")!,
            apiKey: " ",
            model: "model"
        ),
        V2OpenAICompatibleAgentConfiguration(
            endpoint: URL(string: "https://example.com/v1/chat/completions")!,
            apiKey: "secret",
            model: " "
        ),
    ]
    for configuration in invalidConfigurations {
        let client = V2OpenAICompatibleScheduleClient(
            configuration: configuration,
            transport: ScheduleClientRecordingTransport(responseData: Data())
        )
        do {
            _ = try client.makeURLRequest(for: request)
            fatalError("Invalid configuration should be rejected")
        } catch V2ScheduleClientError.invalidConfiguration {
            // Expected.
        }
    }

    let oversized = Data(repeating: 0x20, count: 1_048_577)
    let client = V2OpenAICompatibleScheduleClient(
        configuration: .init(
            endpoint: URL(string: "https://example.com/v1/chat/completions")!,
            apiKey: "secret",
            model: "model"
        ),
        transport: ScheduleClientRecordingTransport(responseData: oversized)
    )
    do {
        _ = try await client.generate(request)
        fatalError("Responses over the bound should be rejected")
    } catch V2ScheduleClientError.payloadTooLarge {
        // Expected.
    }
}

func checkScheduleClientProviderMetadataAndCoreValidation() throws {
    let client = V2OpenAICompatibleScheduleClient(
        configuration: .init(endpoint: URL(string: "https://example.com/v1/chat/completions")!, apiKey: "secret", model: "model"),
        transport: ScheduleClientRecordingTransport(responseData: Data())
    )
    let content = try JSONSerialization.data(withJSONObject: scheduleProposalObject(operations: [
        ["kind": "reschedulePlanItem", "targetID": "plan-run", "durationMinutes": 45],
    ]))
    let envelope: [String: Any] = [
        "request_id": "provider-request", "service_tier": "default",
        "choices": [["finish_reason": "stop", "provider_metadata": [:], "message": [
            "content": String(decoding: content, as: UTF8.self), "reasoning_content": "ignored",
        ]]],
    ]
    let outcome = try client.decodeResponse(JSONSerialization.data(withJSONObject: envelope), request: scheduleClientRequest())
    guard case let .proposal(proposal) = outcome else { fatalError("Metadata must not discard a valid proposal") }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    let engine = V2Engine(snapshot: scheduleClientRequest().snapshot)
    _ = try engine.applyScheduleProposal(proposal, requestID: "duration-only", at: scheduleClientRequest().referenceDate, calendar: calendar)
    let plan = engine.snapshot.planItems[0]
    require(plan.startAt == scheduleClientRequest().snapshot.planItems[0].startAt, "Duration-only edits preserve the start")
    require(plan.endAt!.timeIntervalSince(plan.startAt!) == 45 * 60, "Validated proposal must execute with the requested duration")

    for operation: [String: Any] in [
        ["kind": "createTask", "localID": "task-run", "title": "ID collision"],
        ["kind": "updateTask", "targetID": "task-run", "parentID": "task-run"],
    ] {
        do {
            _ = try client.decodeResponse(scheduleResponse(scheduleProposalObject(operations: [operation])), request: scheduleClientRequest())
            fatalError("Core must reject alias collision or cyclic hierarchy before returning a proposal")
        } catch V2ScheduleClientError.invalidOutput { }
    }
    var truncated = envelope
    truncated["choices"] = [["finish_reason": "length", "message": ["content": String(decoding: content, as: UTF8.self)]]]
    do {
        _ = try client.decodeResponse(JSONSerialization.data(withJSONObject: truncated), request: scheduleClientRequest())
        fatalError("A truncated response must not apply even a syntactically valid prefix")
    } catch V2ScheduleClientError.invalidOutput { }
}

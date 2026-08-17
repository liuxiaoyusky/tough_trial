import Foundation
import ToughTrialV2Core

func checkAIPlanningClients() async throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    let referenceDate = calendar.date(from: DateComponents(year: 2026, month: 7, day: 27))!
    let baseRequest = V2PlanningRequest(
        userPrompt: "这周想跑 10 公里",
        conversationIdentifier: "planning-conversation-123",
        referenceDate: referenceDate,
        timeZoneIdentifier: "Asia/Tokyo",
        tasks: [
            V2PlanningTaskContext(
                id: "task-existing",
                title: "跑步",
                kind: .maintenance,
                status: .notStarted
            ),
        ],
        conversation: [
            V2PlanningConversationMessage(role: .user, text: "这周想跑 10 公里"),
            V2PlanningConversationMessage(role: .agent, text: "周末更适合哪一天？"),
        ]
    )
    let snapshotEngine = V2Engine(
        snapshot: V2AppSnapshot(
            tasks: [
                V2Task(
                    id: "task-existing",
                    title: "跑步",
                    kind: .maintenance,
                    createdAt: referenceDate,
                    updatedAt: referenceDate
                ),
            ]
        )
    )
    let validator = V2PlanningOutcomeValidator()

    func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: referenceDate)!
    }

    func time(onDay offset: Int, hour: Int, minute: Int = 0) -> Date {
        calendar.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: day(offset)
        )!
    }

    let fixtures = [
        V2PlanningValidationFixture(
            id: "C1",
            name: "澄清",
            outcome: .clarification(
                V2PlanningClarification(
                    question: "这周希望跑几次？",
                    suggestedReplies: ["两次", "三次"]
                )
            ),
            shouldPass: true
        ),
        V2PlanningValidationFixture(
            id: "C2",
            name: "简单日计划",
            outcome: .proposal(
                V2PlanningProposal(
                    message: "先放到今天，具体怎么做由你决定。",
                    draft: planningDraft(
                        id: "draft-day",
                        title: "今日计划",
                        scheduleItems: [
                            V2PlanDraftScheduleItem(
                                id: "plan-today",
                                date: day(0),
                                title: "整理今天的重点"
                            ),
                        ]
                    )
                )
            ),
            shouldPass: true
        ),
        V2PlanningValidationFixture(
            id: "C3",
            name: "周周期目标",
            outcome: .proposal(
                V2PlanningProposal(
                    message: "按三次候选安排拆开，不锁定执行方式。",
                    draft: planningDraft(
                        id: "draft-weekly",
                        title: "本周跑步",
                        taskChanges: [
                            V2PlanDraftTaskChange(
                                id: "run-week",
                                title: "本周跑 10 公里",
                                kind: .maintenance
                            ),
                        ],
                        scheduleItems: [1, 3, 5].enumerated().map { index, offset in
                            V2PlanDraftScheduleItem(
                                id: "run-\(index + 1)",
                                date: day(offset),
                                proposedTaskID: "run-week",
                                title: "轻松跑"
                            )
                        }
                    )
                )
            ),
            shouldPass: true
        ),
        V2PlanningValidationFixture(
            id: "C4",
            name: "只拆解",
            outcome: .proposal(
                V2PlanningProposal(
                    message: "只拆细任务，暂时不安排时间。",
                    draft: planningDraft(
                        id: "draft-breakdown",
                        title: "建立稳定选题系统",
                        taskChanges: [
                            V2PlanDraftTaskChange(
                                id: "topic-root",
                                title: "建立稳定选题系统",
                                kind: .goal
                            ),
                            V2PlanDraftTaskChange(
                                id: "topic-benchmark",
                                title: "建立对标账号库",
                                parentID: "topic-root"
                            ),
                        ]
                    )
                )
            ),
            shouldPass: true
        ),
        V2PlanningValidationFixture(
            id: "C5",
            name: "大目标与短任务并存",
            outcome: .proposal(
                V2PlanningProposal(
                    message: "长期目标和现实维护都保留为候选，不强行归类。",
                    draft: planningDraft(
                        id: "draft-mixed",
                        title: "目标与维护",
                        taskChanges: [
                            V2PlanDraftTaskChange(
                                id: "goal-ai",
                                title: "建立 AI 基础能力",
                                kind: .goal
                            ),
                            V2PlanDraftTaskChange(
                                id: "pay-electricity",
                                title: "交电费",
                                kind: .maintenance
                            ),
                        ],
                        scheduleItems: [
                            V2PlanDraftScheduleItem(
                                id: "pay-tonight",
                                date: day(0),
                                proposedTaskID: "pay-electricity",
                                title: "交电费"
                            ),
                        ]
                    )
                )
            ),
            shouldPass: true
        ),
        V2PlanningValidationFixture(
            id: "C6",
            name: "已知任务引用",
            outcome: .proposal(
                V2PlanningProposal(
                    message: "只安排已有任务。",
                    draft: planningDraft(
                        id: "draft-known-reference",
                        title: "安排跑步",
                        scheduleItems: [
                            V2PlanDraftScheduleItem(
                                id: "known-reference",
                                date: day(1),
                                taskID: "task-existing",
                                title: "跑步"
                            ),
                        ]
                    )
                )
            ),
            shouldPass: true
        ),
        V2PlanningValidationFixture(
            id: "C7",
            name: "未知任务引用",
            outcome: .proposal(
                V2PlanningProposal(
                    message: "这个引用不能进入草稿。",
                    draft: planningDraft(
                        id: "draft-unknown-reference",
                        title: "错误引用",
                        scheduleItems: [
                            V2PlanDraftScheduleItem(
                                id: "unknown-reference",
                                date: day(1),
                                taskID: "hallucinated-task",
                                title: "不存在的任务"
                            ),
                        ]
                    )
                )
            ),
            shouldPass: false
        ),
        V2PlanningValidationFixture(
            id: "C8",
            name: "越界时间",
            outcome: .proposal(
                V2PlanningProposal(
                    message: "这个时间超出了离线验证窗口。",
                    draft: planningDraft(
                        id: "draft-out-of-range",
                        title: "越界计划",
                        scheduleItems: [
                            V2PlanDraftScheduleItem(
                                id: "outside-window",
                                date: day(367),
                                startAt: time(onDay: 367, hour: 9),
                                endAt: time(onDay: 367, hour: 10),
                                title: "超出范围"
                            ),
                        ]
                    )
                )
            ),
            shouldPass: false
        ),
        V2PlanningValidationFixture(
            id: "C9",
            name: "空草稿",
            outcome: .proposal(
                V2PlanningProposal(
                    message: "没有可用变更。",
                    draft: planningDraft(
                        id: "draft-empty",
                        title: "空草稿"
                    )
                )
            ),
            shouldPass: false
        ),
    ]

    let p0CaseIDs = fixtures.map(\.id) + ["C10"]
    require(
        p0CaseIDs == (1...10).map { "C\($0)" },
        "P0 validation fixtures must keep stable C1-C10 IDs"
    )
    for fixture in fixtures {
        let snapshotBefore = snapshotEngine.snapshot
        do {
            let validated = try validator.validate(fixture.outcome, for: baseRequest)
            require(
                fixture.shouldPass,
                "\(fixture.id) \(fixture.name) should have been rejected"
            )
            require(
                validated == fixture.outcome,
                "\(fixture.id) validation should preserve accepted outcomes"
            )
        } catch V2PlanningClientError.invalidOutput {
            require(
                !fixture.shouldPass,
                "\(fixture.id) \(fixture.name) should have passed validation"
            )
        }
        require(
            snapshotEngine.snapshot == snapshotBefore,
            "\(fixture.id) validation must not mutate V2AppSnapshot"
        )
    }

    let decoratedInvalidClient = V2ValidatedPlanningClient(
        client: V2FixedPlanningClient(outcome: fixtures[6].outcome)
    )
    await requirePlanningFailureKeepsSnapshot(
        snapshotEngine,
        label: "provider-independent decorator invalid output",
        expected: .invalidOutput
    ) {
        _ = try await decoratedInvalidClient.generate(baseRequest)
    }

    let deterministic = V2ValidatedPlanningClient(client: V2DeterministicPlanningClient())
    let first = try await deterministic.generate(baseRequest)
    guard case .clarification(let clarification) = first else {
        fatalError("Local planning should clarify before drafting")
    }
    require(!clarification.question.isEmpty, "Local clarification should contain a question")

    var confirmedRequest = baseRequest
    confirmedRequest.clarificationResponse = "分三次完成"
    let confirmed = try await deterministic.generate(confirmedRequest)
    guard case .proposal(let localProposal) = confirmed else {
        fatalError("Local planning should return a proposal after clarification")
    }
    require(
        !localProposal.draft.taskChanges.isEmpty && !localProposal.draft.scheduleItems.isEmpty,
        "Local running proposal should include both task breakdown and schedule items"
    )

    let configuration = V2RemotePlanningConfiguration(
        endpoint: URL(string: "https://offline.invalid/v1/responses")!,
        apiKey: "fake-key-never-sent",
        model: "fake-model"
    )
    let structured: [String: Any] = [
        "kind": "proposal",
        "message": "把已有跑步任务放到明天。",
        "suggested_replies": [],
        "title": "明日跑步",
        "summary": "只安排已知任务，不创建新任务。",
        "decisions": ["不强制具体时刻"],
        "task_changes": [],
        "schedule_items": [
            [
                "temporary_id": "run-plan-1",
                "day_offset": 1,
                "start_minute": NSNull(),
                "duration_minutes": NSNull(),
                "existing_task_id": "task-existing",
                "proposed_task_id": NSNull(),
                "title": "跑步",
            ],
        ],
    ]
    let successTransport = V2FakePlanningTransport(
        result: .response(
            statusCode: 200,
            data: try planningResponseData(structuredOutput: structured)
        )
    )
    let remote = V2ValidatedPlanningClient(
        client: V2RemotePlanningClient(
            configuration: configuration,
            transport: successTransport
        )
    )
    let remoteOutcome = try await remote.generate(baseRequest)
    guard case .proposal(let remoteProposal) = remoteOutcome else {
        fatalError("Valid fake transport output should decode as a proposal")
    }
    require(
        remoteProposal.draft.scheduleItems.first?.taskID == "task-existing",
        "Remote schedule should preserve its known-task reference"
    )

    let capturedRequests = await successTransport.recordedRequests()
    require(capturedRequests.count == 1, "Fake transport should receive exactly one request")
    let capturedRequest = capturedRequests[0]
    require(capturedRequest.url == configuration.endpoint, "Remote request should use configured endpoint")
    require(capturedRequest.httpMethod == "POST", "Remote planning should use POST")
    require(
        capturedRequest.value(forHTTPHeaderField: "Authorization") == "Bearer fake-key-never-sent",
        "Remote request should carry the configured bearer token"
    )
    let requestBody = try JSONSerialization.jsonObject(with: capturedRequest.httpBody!) as! [String: Any]
    require(requestBody["store"] as? Bool == false, "Remote planning requests must disable response storage")
    require(requestBody["model"] as? String == "fake-model", "Remote request should use configured model")
    let inputText = requestBody["input"] as! String
    let input = try JSONSerialization.jsonObject(with: Data(inputText.utf8)) as! [String: Any]
    require(input["user_prompt"] as? String == baseRequest.userPrompt, "Remote request should preserve user prompt")
    let inputTasks = input["tasks"] as! [[String: Any]]
    require(
        inputTasks.first?["id"] as? String == "task-existing",
        "Remote request should preserve known task IDs"
    )
    let inputConversation = input["conversation"] as! [[String: Any]]
    require(
        inputConversation.map { $0["text"] as? String }
            == ["这周想跑 10 公里", "周末更适合哪一天？"],
        "Remote planning should receive the visible conversation context"
    )
    let text = requestBody["text"] as! [String: Any]
    let format = text["format"] as! [String: Any]
    require(format["type"] as? String == "json_schema", "Remote planning must request strict JSON schema output")
    require(format["strict"] as? Bool == true, "Remote planning schema must be strict")

    let compatibleConfiguration = V2OpenAICompatiblePlanningConfiguration(
        endpoint: URL(string: "https://api.siliconflow.cn/v1/chat/completions")!,
        apiKey: "fake-compatible-key",
        model: "fake-compatible-model",
        providerLabel: "硅基流动"
    )
    let compatibleTransport = V2FakePlanningTransport(
        result: .response(
            statusCode: 200,
            data: try chatPlanningResponseData(structuredOutput: structured)
        )
    )
    let compatibleClient = V2ValidatedPlanningClient(
        client: V2OpenAICompatiblePlanningClient(
            configuration: compatibleConfiguration,
            transport: compatibleTransport
        )
    )
    let compatibleOutcome = try await compatibleClient.generate(baseRequest)
    guard case .proposal(let compatibleProposal) = compatibleOutcome else {
        fatalError("OpenAI-compatible output should decode as a proposal")
    }
    require(
        compatibleProposal.draft.scheduleItems.first?.taskID == "task-existing",
        "OpenAI-compatible planning should preserve its known-task reference"
    )
    require(
        compatibleClient.providerLabel == "硅基流动",
        "OpenAI-compatible planning should expose its configured provider label"
    )

    let compatibleRequests = await compatibleTransport.recordedRequests()
    require(compatibleRequests.count == 1, "OpenAI-compatible transport should receive one request")
    let compatibleRequest = compatibleRequests[0]
    require(
        compatibleRequest.url == compatibleConfiguration.endpoint,
        "OpenAI-compatible request should use the configured endpoint"
    )
    require(
        compatibleRequest.value(forHTTPHeaderField: "Authorization") == "Bearer fake-compatible-key",
        "OpenAI-compatible request should carry the configured bearer token"
    )
    let compatibleBody = try JSONSerialization.jsonObject(
        with: compatibleRequest.httpBody!
    ) as! [String: Any]
    require(
        compatibleBody["model"] as? String == "fake-compatible-model",
        "OpenAI-compatible request should use the configured model"
    )
    require(
        compatibleBody["stream"] as? Bool == false,
        "OpenAI-compatible planning should wait for a complete validated JSON response"
    )
    require(
        compatibleBody["prompt_cache_key"] == nil,
        "Generic OpenAI-compatible requests must not receive provider-specific cache fields"
    )
    let responseFormat = compatibleBody["response_format"] as! [String: Any]
    require(
        responseFormat["type"] as? String == "json_object",
        "OpenAI-compatible planning should request JSON object mode"
    )
    let messages = compatibleBody["messages"] as! [[String: Any]]
    require(
        messages.map { $0["role"] as? String } == ["system", "user"],
        "OpenAI-compatible request should use the common system/user message contract"
    )
    let compatibleUserContent = messages[1]["content"] as! String
    let compatiblePayload = try JSONSerialization.jsonObject(
        with: Data(compatibleUserContent.utf8)
    ) as! [String: Any]
    let compatibleInput = compatiblePayload["request"] as! [String: Any]
    require(
        compatibleInput["user_prompt"] as? String == baseRequest.userPrompt,
        "OpenAI-compatible request should preserve the user prompt"
    )
    let compatibleConversation = compatibleInput["conversation"] as! [[String: Any]]
    require(
        compatibleConversation.map { $0["role"] as? String } == ["user", "agent"],
        "OpenAI-compatible planning should receive prior conversation roles"
    )
    require(
        compatiblePayload["output_schema"] is [String: Any],
        "OpenAI-compatible request should include the planning output contract"
    )

    let kimiConfiguration = V2OpenAICompatiblePlanningConfiguration(
        endpoint: URL(string: "https://api.kimi.com/coding/v1/chat/completions")!,
        apiKey: "fake-kimi-key",
        model: "k3-256k",
        providerLabel: "Kimi Coding Plan",
        usesPromptCacheKey: true
    )
    let kimiClient = V2OpenAICompatiblePlanningClient(
        configuration: kimiConfiguration,
        transport: compatibleTransport
    )
    let kimiRequest = try kimiClient.makeURLRequest(for: baseRequest)
    let kimiBody = try JSONSerialization.jsonObject(
        with: kimiRequest.httpBody!
    ) as! [String: Any]
    require(
        kimiBody["prompt_cache_key"] as? String == "planning-conversation-123",
        "Kimi Coding Plan should receive one stable cache key per planning conversation"
    )

    let compatibleFailureTransport = V2FakePlanningTransport(
        result: .response(
            statusCode: 401,
            data: try JSONSerialization.data(
                withJSONObject: ["error": ["message": "invalid api key"]],
                options: [.sortedKeys]
            )
        )
    )
    let compatibleFailureClient = V2ValidatedPlanningClient(
        client: V2OpenAICompatiblePlanningClient(
            configuration: compatibleConfiguration,
            transport: compatibleFailureTransport
        )
    )
    await requirePlanningFailureKeepsSnapshot(
        snapshotEngine,
        label: "OpenAI-compatible HTTP failure",
        expected: .httpStatus(401)
    ) {
        _ = try await compatibleFailureClient.generate(baseRequest)
    }
    let compatibleFailureRequestCount = await compatibleFailureTransport.recordedRequests().count
    require(
        compatibleFailureRequestCount == 1,
        "OpenAI-compatible failure check should make exactly one request"
    )

    let refusalTransport = V2FakePlanningTransport(
        result: .response(
            statusCode: 200,
            data: try planningRefusalResponseData(message: "无法处理这项请求")
        )
    )
    let refusalClient = V2ValidatedPlanningClient(
        client: V2RemotePlanningClient(
            configuration: configuration,
            transport: refusalTransport
        )
    )
    await requirePlanningFailureKeepsSnapshot(
        snapshotEngine,
        label: "C10 model refusal",
        expected: .refused
    ) {
        _ = try await refusalClient.generate(baseRequest)
    }

    let httpFailureTransport = V2FakePlanningTransport(
        result: .response(
            statusCode: 503,
            data: try JSONSerialization.data(
                withJSONObject: ["error": ["message": "temporary unavailable"]],
                options: [.sortedKeys]
            )
        )
    )
    let httpFailureClient = V2ValidatedPlanningClient(
        client: V2RemotePlanningClient(
            configuration: configuration,
            transport: httpFailureTransport
        )
    )
    await requirePlanningFailureKeepsSnapshot(
        snapshotEngine,
        label: "C10 HTTP failure",
        expected: .httpStatus(503)
    ) {
        _ = try await httpFailureClient.generate(baseRequest)
    }

    let invalidResponseTransport = V2FakePlanningTransport(
        result: .response(statusCode: 200, data: Data("{".utf8))
    )
    let invalidResponseClient = V2ValidatedPlanningClient(
        client: V2RemotePlanningClient(
            configuration: configuration,
            transport: invalidResponseTransport
        )
    )
    await requirePlanningFailureKeepsSnapshot(
        snapshotEngine,
        label: "C10 malformed model output",
        expected: .invalidOutput
    ) {
        _ = try await invalidResponseClient.generate(baseRequest)
    }

    let offlineTransport = V2FakePlanningTransport(result: .offline)
    let offlineClient = V2ValidatedPlanningClient(
        client: V2RemotePlanningClient(
            configuration: configuration,
            transport: offlineTransport
        )
    )
    await requirePlanningFailureKeepsSnapshot(
        snapshotEngine,
        label: "C10 offline transport",
        expected: .transport
    ) {
        _ = try await offlineClient.generate(baseRequest)
    }

    let refusalRequestCount = await refusalTransport.recordedRequests().count
    let httpFailureRequestCount = await httpFailureTransport.recordedRequests().count
    let invalidResponseRequestCount = await invalidResponseTransport.recordedRequests().count
    let offlineRequestCount = await offlineTransport.recordedRequests().count
    require(
        refusalRequestCount == 1
            && httpFailureRequestCount == 1
            && invalidResponseRequestCount == 1
            && offlineRequestCount == 1,
        "C10 failure checks must use injected fake transports exactly once"
    )
}

private struct V2PlanningValidationFixture {
    var id: String
    var name: String
    var outcome: V2PlanningOutcome
    var shouldPass: Bool
}

private struct V2FixedPlanningClient: V2PlanningClient {
    let providerLabel = "固定测试 Provider"
    var outcome: V2PlanningOutcome

    func generate(_ request: V2PlanningRequest) async throws -> V2PlanningOutcome {
        outcome
    }
}

private actor V2FakePlanningTransport: V2PlanningHTTPTransport {
    enum Result: Sendable {
        case response(statusCode: Int, data: Data)
        case offline
    }

    private let result: Result
    private var requests: [URLRequest] = []

    init(result: Result) {
        self.result = result
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        switch result {
        case .response(let statusCode, let data):
            guard let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            ) else {
                fatalError("Unable to build fake HTTP response")
            }
            return (data, response)
        case .offline:
            throw URLError(.notConnectedToInternet)
        }
    }

    func recordedRequests() -> [URLRequest] {
        requests
    }
}

private enum V2ExpectedPlanningFailure {
    case invalidOutput
    case refused
    case httpStatus(Int)
    case transport
}

private func requirePlanningFailureKeepsSnapshot(
    _ engine: V2Engine,
    label: String,
    expected: V2ExpectedPlanningFailure,
    operation: () async throws -> Void
) async {
    let snapshotBefore = engine.snapshot
    do {
        try await operation()
        fatalError("\(label) should fail")
    } catch {
        switch expected {
        case .invalidOutput:
            guard case V2PlanningClientError.invalidOutput = error else {
                fatalError("\(label) should return invalidOutput, got \(error)")
            }
        case .refused:
            guard case V2PlanningClientError.refused = error else {
                fatalError("\(label) should return refused, got \(error)")
            }
        case .httpStatus(let expectedStatus):
            guard case V2PlanningClientError.requestFailed(let statusCode, _) = error else {
                fatalError("\(label) should return requestFailed, got \(error)")
            }
            require(statusCode == expectedStatus, "\(label) should preserve HTTP status")
        case .transport:
            require(error is URLError, "\(label) should preserve the transport error")
        }
    }
    require(engine.snapshot == snapshotBefore, "\(label) must not mutate V2AppSnapshot")
}

private func planningDraft(
    id: String,
    title: String,
    taskChanges: [V2PlanDraftTaskChange] = [],
    scheduleItems: [V2PlanDraftScheduleItem] = []
) -> V2PlanDraft {
    V2PlanDraft(
        id: id,
        userPrompt: "P0 fixture",
        title: title,
        summary: "离线验证 fixture",
        decisions: [],
        taskChanges: taskChanges,
        scheduleItems: scheduleItems
    )
}

private func planningResponseData(structuredOutput: [String: Any]) throws -> Data {
    let structuredData = try JSONSerialization.data(withJSONObject: structuredOutput, options: [.sortedKeys])
    let structuredText = String(decoding: structuredData, as: UTF8.self)
    let envelope: [String: Any] = [
        "output": [
            [
                "type": "message",
                "content": [
                    [
                        "type": "output_text",
                        "text": structuredText,
                    ],
                ],
            ],
        ],
    ]
    return try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
}

private func chatPlanningResponseData(structuredOutput: [String: Any]) throws -> Data {
    let structuredData = try JSONSerialization.data(
        withJSONObject: structuredOutput,
        options: [.sortedKeys]
    )
    let structuredText = String(decoding: structuredData, as: UTF8.self)
    let envelope: [String: Any] = [
        "choices": [
            [
                "index": 0,
                "message": [
                    "role": "assistant",
                    "content": structuredText,
                ],
                "finish_reason": "stop",
            ],
        ],
    ]
    return try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
}

private func planningRefusalResponseData(message: String) throws -> Data {
    let envelope: [String: Any] = [
        "output": [
            [
                "type": "message",
                "content": [
                    [
                        "type": "refusal",
                        "refusal": message,
                    ],
                ],
            ],
        ],
    ]
    return try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
}

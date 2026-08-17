import Foundation
import ToughTrialV2Core

func checkAgentClientRequestsAToolWithoutExposingReasoning() async throws {
    let response = #"{"id":"response-1","choices":[{"message":{"content":"{\"action\":\"web_search\",\"text\":\"\",\"query\":\"香港天气\",\"url\":\"\"}"}}],"usage":{"prompt_tokens":12,"completion_tokens":8,"total_tokens":20}}"#
    let transport = RecordingPlanningTransport(
        responseData: Data(response.utf8),
        statusCode: 200,
        headerFields: ["x-request-id": "request-1"]
    )
    let client = V2OpenAICompatibleAgentClient(
        configuration: .init(
            endpoint: URL(string: "https://example.com/v1/chat/completions")!,
            apiKey: "secret",
            model: "test",
            providerLabel: "Test"
        ),
        transport: transport
    )

    let result = try await client.respond(
        V2AgentRequest(userText: "帮我查香港天气", conversation: [], observations: [])
    )

    require(result.action == .webSearch(query: "香港天气"), "Model should request web search")
    let request = await transport.lastRequest()
    require(
        request?.value(forHTTPHeaderField: "Authorization") == "Bearer secret",
        "Authorization should only appear in the HTTP header"
    )
    require(
        !String(data: request!.httpBody!, encoding: .utf8)!.contains("chain-of-thought"),
        "Request must not ask for hidden reasoning"
    )
    require(
        !String(data: request!.httpBody!, encoding: .utf8)!.contains("secret"),
        "Request body must not contain the API key"
    )
    let body = try JSONSerialization.jsonObject(with: request!.httpBody!) as! [String: Any]
    let messages = body["messages"] as! [[String: Any]]
    let systemInstruction = messages[0]["content"] as! String
    require(
        systemInstruction.contains("untrusted data")
            && systemInstruction.contains("source IDs")
            && systemInstruction.contains("at most one action")
            && systemInstruction.contains("private reasoning"),
        "The system instruction should constrain observations, citations, actions, and reasoning exposure"
    )
    require(result.requestID == "request-1", "Request IDs should be captured from response headers")
    require(result.responseID == "response-1", "Response IDs should be captured when supplied")
    require(
        result.promptTokens == 12 && result.completionTokens == 8 && result.totalTokens == 20,
        "OpenAI-compatible token usage should be captured when supplied"
    )
    require(!String(describing: result).contains("secret"), "Result metadata must not retain the API key")

    let kimiClient = V2OpenAICompatibleAgentClient(
        configuration: .init(
            endpoint: URL(string: "https://api.kimi.com/coding/v1/chat/completions")!,
            apiKey: "secret",
            model: "k3-256k",
            providerLabel: "Kimi Coding Plan",
            usesPromptCacheKey: true
        ),
        transport: transport
    )
    let kimiRequest = try kimiClient.makeURLRequest(for:
        V2AgentRequest(
            userText: "测试",
            conversation: [],
            observations: [],
            conversationIdentifier: "agent-session-1"
        )
    )
    let kimiBody = try JSONSerialization.jsonObject(with: kimiRequest.httpBody!) as! [String: Any]
    require(
        kimiBody["prompt_cache_key"] as? String == "agent-session-1",
        "Kimi-compatible agent requests should use the session's stable prompt cache key"
    )
}

func checkAgentClientRejectsInvalidOutputAndHandlesOptionalMetadata() async throws {
    let configuration = V2OpenAICompatibleAgentConfiguration(
        endpoint: URL(string: "https://example.com/v1/chat/completions")!,
        apiKey: "secret",
        model: "test",
        providerLabel: "Test"
    )
    let invalidAction = #"{"choices":[{"message":{"content":"{\"action\":\"web_search\",\"text\":\"unexpected\",\"query\":\"香港天气\",\"url\":\"\"}"}}]}"#
    let invalidClient = V2OpenAICompatibleAgentClient(
        configuration: configuration,
        transport: RecordingPlanningTransport(responseData: Data(invalidAction.utf8), statusCode: 200)
    )
    do {
        _ = try await invalidClient.respond(
            V2AgentRequest(userText: "帮我查香港天气", conversation: [], observations: [])
        )
        fatalError("An action with unexpected non-empty fields must fail")
    } catch V2AgentClientError.invalidOutput {
        // Expected: the envelope must describe exactly one action.
    }

    let metadataFree = #"{"choices":[{"message":{"content":"{\"action\":\"answer\",\"text\":\"可以\",\"query\":\"\",\"url\":\"\"}"}}]}"#
    let metadataFreeClient = V2OpenAICompatibleAgentClient(
        configuration: configuration,
        transport: RecordingPlanningTransport(responseData: Data(metadataFree.utf8), statusCode: 200)
    )
    let metadataFreeResult = try await metadataFreeClient.respond(
        V2AgentRequest(userText: "可以吗", conversation: [], observations: [])
    )
    require(metadataFreeResult.action == .answer(text: "可以"), "Responses without metadata should still work")
    require(
        metadataFreeResult.requestID == nil
            && metadataFreeResult.responseID == nil
            && metadataFreeResult.totalTokens == nil,
        "Optional provider metadata should remain optional"
    )

    let malformedClient = V2OpenAICompatibleAgentClient(
        configuration: configuration,
        transport: RecordingPlanningTransport(responseData: Data("{".utf8), statusCode: 200)
    )
    do {
        _ = try await malformedClient.respond(
            V2AgentRequest(userText: "测试", conversation: [], observations: [])
        )
        fatalError("Malformed JSON must fail")
    } catch V2AgentClientError.invalidOutput {
        // Expected: malformed provider JSON has no fallback answer.
    }

    let refusal = #"{"choices":[{"message":{"refusal":"无法处理"}}]}"#
    let refusalClient = V2OpenAICompatibleAgentClient(
        configuration: configuration,
        transport: RecordingPlanningTransport(responseData: Data(refusal.utf8), statusCode: 200)
    )
    do {
        _ = try await refusalClient.respond(
            V2AgentRequest(userText: "测试", conversation: [], observations: [])
        )
        fatalError("A provider refusal must fail")
    } catch let error as V2AgentClientError {
        guard case .refused = error else {
            fatalError("Provider refusal should use the localized agent error, got \(error)")
        }
    }

    let httpFailureClient = V2OpenAICompatibleAgentClient(
        configuration: configuration,
        transport: RecordingPlanningTransport(
            responseData: Data(#"{"error":{"message":"temporary unavailable"}}"#.utf8),
            statusCode: 503
        )
    )
    do {
        _ = try await httpFailureClient.respond(
            V2AgentRequest(userText: "测试", conversation: [], observations: [])
        )
        fatalError("An HTTP failure must fail")
    } catch let error as V2AgentClientError {
        guard case let .requestFailed(statusCode, _) = error else {
            fatalError("HTTP failures should use the localized agent error, got \(error)")
        }
        require(statusCode == 503, "HTTP failures should preserve the status code")
    }

    try checkAgentClientDecodesEveryValidActionAndRejectsHTTPWebRead()
}

func checkAgentClientDecodesEveryValidActionAndRejectsHTTPWebRead() throws {
    struct ValidActionFixture {
        var name: String
        var envelope: [String: String]
        var expected: V2AgentAction
    }

    let httpsURL = URL(string: "https://example.com/article")!
    let fixtures = [
        ValidActionFixture(
            name: "answer",
            envelope: ["action": "answer", "text": "可以", "query": "", "url": ""],
            expected: .answer(text: "可以")
        ),
        ValidActionFixture(
            name: "web_search",
            envelope: ["action": "web_search", "text": "", "query": "香港天气", "url": ""],
            expected: .webSearch(query: "香港天气")
        ),
        ValidActionFixture(
            name: "web_read",
            envelope: ["action": "web_read", "text": "", "query": "", "url": httpsURL.absoluteString],
            expected: .webRead(url: httpsURL)
        ),
        ValidActionFixture(
            name: "local_search",
            envelope: ["action": "local_search", "text": "", "query": "我的任务", "url": ""],
            expected: .localSearch(query: "我的任务")
        ),
        ValidActionFixture(
            name: "plan",
            envelope: ["action": "plan", "text": "", "query": "安排明天", "url": ""],
            expected: .plan(query: "安排明天")
        ),
    ]
    let client = V2OpenAICompatibleAgentClient(
        configuration: .init(
            endpoint: URL(string: "https://example.com/v1/chat/completions")!,
            apiKey: "secret",
            model: "test",
            providerLabel: "Test"
        ),
        transport: RecordingPlanningTransport(responseData: Data(), statusCode: 200)
    )

    for fixture in fixtures {
        let result = try client.decodeResponse(agentActionResponseData(fixture.envelope))
        require(result.action == fixture.expected, "\(fixture.name) should decode its valid action envelope")
    }

    do {
        _ = try client.decodeResponse(
            agentActionResponseData(
                ["action": "web_read", "text": "", "query": "", "url": "http://example.com/article"]
            )
        )
        fatalError("HTTP web_read URLs must fail")
    } catch V2AgentClientError.invalidOutput {
        // Expected: web reads may only target HTTPS URLs.
    }
}

private func agentActionResponseData(_ action: [String: String]) throws -> Data {
    let content = String(
        data: try JSONSerialization.data(withJSONObject: action, options: [.sortedKeys]),
        encoding: .utf8
    )!
    return try JSONSerialization.data(
        withJSONObject: ["choices": [["message": ["content": content]]]],
        options: [.sortedKeys]
    )
}

private actor RecordingPlanningTransport: V2PlanningHTTPTransport {
    private let responseData: Data
    private let statusCode: Int
    private let headerFields: [String: String]?
    private var capturedRequest: URLRequest?

    init(
        responseData: Data,
        statusCode: Int,
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

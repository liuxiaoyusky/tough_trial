import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import ToughTrialV2Core

private struct ToolWireTransport: V2PlanningHTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) { throw URLError(.badServerResponse) }
}

final class V2ToolWireTests: XCTestCase {
    private typealias Client = V2OpenAICompatibleAgentClient<ToolWireTransport>
    private var client: Client { .init(configuration: .init(endpoint: URL(string: "https://example.com/v1/chat/completions")!, apiKey: "fixture", model: "fixture"), transport: ToolWireTransport()) }

    func testOrdinaryTextAndFencedAnswerAreDisplayOnly() throws {
        func decode(_ content: String) throws -> V2AgentAction {
            try client.decodeResponse(JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": content]]]])).action
        }
        XCTAssertEqual(try decode("可以，我们先梳理一下你的想法。"), .answer(text: "可以，我们先梳理一下你的想法。"))
        XCTAssertEqual(try decode("```json\n{\"action\":\"answer\",\"text\":\"可以\"}\n```"), .answer(text: "可以"))
        XCTAssertThrowsError(try decode("{\"action\":\"tool\","))
    }

    func testNativeBatchIsPreservedAsMatchedProviderMessages() throws {
        let catalog = V2Engine().registeredToolCatalog()
        let name = Client.wireName(for: "core.tasks.create")
        let calls: [[String: Any]] = (0..<2).map { index in
            ["id": "call_\(index)", "type": "function", "function": ["name": name, "arguments": "{\"title\":\"测试\(index)\"}"]]
        }
        let data = try JSONSerialization.data(withJSONObject: ["choices": [["message": [
            "content": NSNull(), "tool_calls": calls, "reasoning_details": "opaque-fixture"
        ]]]])
        let result = try client.decodeResponse(data, catalog: catalog)
        guard case let .toolCall(first) = result.action else { return XCTFail("Expected native call") }
        XCTAssertEqual(first.modelCallID, "call_0")
        XCTAssertEqual(result.additionalToolCalls.map(\.modelCallID), ["call_1"])
        let exchange = V2AgentToolExchange(assistantMessage: try XCTUnwrap(result.continuationMessage), results: [
            .init(callID: "call_0", content: "first result"), .init(callID: "call_1", content: "second result")
        ])
        let request = V2AgentRequest(userText: "创建测试", conversation: [], observations: [], toolCatalog: catalog, toolExchanges: [exchange])
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(client.makeURLRequest(for: request).httpBody)) as? [String: Any])
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.suffix(3).compactMap { $0["role"] as? String }, ["assistant", "tool", "tool"])
        XCTAssertEqual(messages[messages.count - 3]["reasoning_details"] as? String, "opaque-fixture")
        XCTAssertEqual(messages.suffix(2).compactMap { $0["tool_call_id"] as? String }, ["call_0", "call_1"])
        XCTAssertEqual(messages.suffix(2).compactMap { $0["content"] as? String }, ["first result", "second result"])

        var invalidCalls = calls
        invalidCalls[1]["function"] = ["name": "unknown", "arguments": "{}"]
        let invalid = try JSONSerialization.data(withJSONObject: ["choices": [["message": ["tool_calls": invalidCalls]]]])
        XCTAssertThrowsError(try client.decodeResponse(invalid, catalog: catalog), "Validate the whole batch before exposing any action")
    }

    func testPortableFunctionIdentifiersAndNoCustomTransportFields() throws {
        let catalog = V2Engine().registeredToolCatalog()
        let request = V2AgentRequest(userText: "记录", conversation: [], observations: [], toolCatalog: catalog)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(client.makeURLRequest(for: request).httpBody)) as? [String: Any])
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let instruction = try XCTUnwrap(messages.first?["content"] as? String)
        XCTAssertTrue(instruction.contains("Registered tools use native API function calls"))
        XCTAssertFalse(instruction.contains("For a registered command use action"))
        let tools = try XCTUnwrap(body["tools"] as? [[String: Any]])
        for tool in tools {
            let function = try XCTUnwrap(tool["function"] as? [String: Any])
            let name = try XCTUnwrap(function["name"] as? String)
            XCTAssertNotNil(name.range(of: #"^[a-zA-Z0-9_-]{1,64}$"#, options: .regularExpression))
        }
        XCTAssertNil(body["tool_catalog_revision"])
        XCTAssertEqual(body["parallel_tool_calls"] as? Bool, false)
        let name = Client.wireName(for: String(repeating: "long.module.id", count: 20))
        XCTAssertLessThanOrEqual(name.count, 64)
    }

    func testProviderAliasReturnsExactNamespacedToolAndRejectsUnknown() throws {
        let catalog = V2Engine().registeredToolCatalog()
        func response(_ names: [String]) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["choices": [["message": ["tool_calls": names.map {
                ["id": "provider-id", "function": ["name": $0, "arguments": #"{"title":"取快递"}"#]]
            }]]]])
        }
        let name = Client.wireName(for: "core.tasks.create")
        let result = try client.decodeResponse(response([name]), catalog: catalog)
        guard case let .toolCall(call) = result.action else { return XCTFail("tool result expected") }
        XCTAssertEqual(call.toolID, "core.tasks.create")
        XCTAssertThrowsError(try client.decodeResponse(response(["unknown"]), catalog: catalog))
        XCTAssertThrowsError(try client.decodeResponse(response([name, name]), catalog: catalog))
    }
}

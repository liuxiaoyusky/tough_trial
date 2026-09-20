import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import ToughTrialV2Core

final class V2AssistantWebCapabilityTests: XCTestCase {
    private typealias Client = V2OpenAICompatibleAgentClient<FixtureTransport>

    func testDisabledWebCapabilityIsDeclaredToTheModelWithTheSettingsPath() throws {
        let client = Client(
            configuration: .init(
                endpoint: URL(string: "https://example.com/v1/chat/completions")!,
                apiKey: "fixture",
                model: "fixture"
            ),
            transport: FixtureTransport()
        )
        let request = V2AgentRequest(
            userText: "查一下今天的新闻",
            conversation: [],
            observations: [],
            webAvailable: false
        )

        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: XCTUnwrap(client.makeURLRequest(for: request).httpBody))
                as? [String: Any]
        )
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let system = try XCTUnwrap(messages.first?["content"] as? String)
        let user = try XCTUnwrap(messages.last?["content"] as? String)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(user.utf8)) as? [String: Any])

        XCTAssertEqual(payload["web_available"] as? Bool, false)
        XCTAssertTrue(system.contains("网页只读能力当前不可用"))
        XCTAssertTrue(system.contains("网页搜索已停用"))
        XCTAssertTrue(system.contains("功能与插件→网页搜索"))
        XCTAssertFalse(system.contains("功能与插件→网页浏览"))
        XCTAssertFalse(system.contains("创建任务"))
    }

    func testEnabledWebCapabilityIsDeclaredToTheModel() throws {
        let client = Client(
            configuration: .init(
                endpoint: URL(string: "https://example.com/v1/chat/completions")!,
                apiKey: "fixture",
                model: "fixture"
            ),
            transport: FixtureTransport()
        )
        let request = V2AgentRequest(
            userText: "查一下今天的新闻",
            conversation: [],
            observations: [],
            webAvailable: true
        )

        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: XCTUnwrap(client.makeURLRequest(for: request).httpBody))
                as? [String: Any]
        )
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let system = try XCTUnwrap(messages.first?["content"] as? String)
        let userContent = try XCTUnwrap(messages.last?["content"] as? String)
        let userPayload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: XCTUnwrap(userContent.data(using: .utf8))) as? [String: Any]
        )

        XCTAssertEqual(userPayload["web_available"] as? Bool, true)
        XCTAssertTrue(system.contains("网页只读能力当前可用"))
        XCTAssertFalse(system.contains("网页搜索已停用"))
    }
}

private struct FixtureTransport: V2PlanningHTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        throw URLError(.notConnectedToInternet)
    }
}

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import ToughTrialV2Core

private struct ContextWireTransport: V2PlanningHTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) { throw URLError(.badServerResponse) }
}

final class V2AssistantContextWireTests: XCTestCase {
    func testEveryModelRouteSerializesASeparateContextEnvelope() throws {
        let config = V2OpenAICompatibleAgentConfiguration(endpoint: URL(string: "https://example.com/v1/chat/completions")!, apiKey: "fixture", model: "fixture")
        let chat = V2OpenAICompatibleAgentClient(configuration: config, transport: ContextWireTransport())
        let schedule = V2OpenAICompatibleScheduleClient(configuration: config, transport: ContextWireTransport())
        let now = Date()
        let context = V2AssistantContext(sourceTask: .init(id: "selected-id", title: "漫剧课"), referenceState: .available,
            memories: [.init(id: "memory-id", kind: .preference, statement: "每段结束写笔记", origin: .explicitUser, createdAt: now, updatedAt: now)],
            compactSummary: "旧消息摘录", compactRevision: 2, coveredMessageIDs: ["old-message"])
        let requests = [
            try chat.makeURLRequest(for: .init(userText: "帮我拆分", conversation: [], observations: [], context: context)),
            try schedule.makeURLRequest(for: .init(userText: "帮我拆分", snapshot: .empty, referenceDate: Date(), timeZoneIdentifier: "Asia/Hong_Kong", context: context))
        ]
        for request in requests {
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
            let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
            let content = try XCTUnwrap(messages.last?["content"] as? String)
            let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(content.utf8)) as? [String: Any])
            let sentContext = try XCTUnwrap(payload["context"] as? [String: Any])
            XCTAssertEqual((sentContext["sourceTask"] as? [String: Any])?["id"] as? String, "selected-id")
            XCTAssertEqual(sentContext["compactRevision"] as? Int, 2)
            XCTAssertEqual((sentContext["memories"] as? [[String: Any]])?.first?["id"] as? String, "memory-id")
        }
    }
}

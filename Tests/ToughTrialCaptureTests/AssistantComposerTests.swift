import XCTest
import ToughTrialV2Core

final class AssistantComposerTests: XCTestCase {
    func testToolNarrationDoesNotBecomeAnExtraOperation() throws {
        let client = V2OpenAICompatibleAgentClient(configuration: .init(endpoint: URL(string: "https://api.minimax.io/v1/chat/completions")!, apiKey: "fixture", model: "MiniMax-M2.7-highspeed"))
        let action = #"{"action":"tool","text":"我来查看记录","query":"ignored","url":"https://example.com","tool":"core.notes.search","arguments":{"query":"合成测试"}}"#
        let data = try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": action]]]])
        guard case .toolCall(let call) = try client.decodeResponse(data).action else { return XCTFail("Expected exactly one tool") }
        XCTAssertEqual(call.toolID, "core.notes.search")
        XCTAssertEqual(try JSONSerialization.jsonObject(with: call.argumentsJSON) as? [String: String], ["query": "合成测试"])
        let forbidden = action.replacingOccurrences(of: "\"action\":\"tool\"", with: "\"action\":\"tool\",\"operationID\":\"injected\"")
        let unsafe = try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": forbidden]]]])
        XCTAssertThrowsError(try client.decodeResponse(unsafe))
    }

    @MainActor func testUnfamiliarIntentCanOnlyPrepareReviewAndCannotApply() throws {
        XCTAssertTrue(V2AssistantWriteIntent.mayPrepareReview("给这个事儿弄几个可以动手的小步骤"))
        for text in ["hello", "不要动这个任务", "解释一下引用", "如果添加一个任务", "哪里出错了"] {
            XCTAssertFalse(V2AssistantWriteIntent.mayPrepareReview(text), text)
        }
        let engine = V2Engine()
        let call = V2AgentToolCall(toolID: "core.tasks.create", argumentsJSON: Data(#"{"title":"审核后才创建"}"#.utf8))
        let context = V2ToolExecutionContext(traceID: "trace", assistantRequestID: "request", callOrdinal: 0,
            toolID: call.toolID, submittedText: "给这个事儿弄几个可以动手的小步骤", requiresReview: true)
        let result = try engine.executeRegisteredTool(call, context: context)
        XCTAssertEqual(result.state, .pendingConfirmation)
        XCTAssertTrue(engine.snapshot.tasks.isEmpty)
        _ = try engine.confirmRegisteredTool(operationID: result.operationID)
        XCTAssertEqual(engine.snapshot.tasks.count, 1)
    }

    func testCompactionDoesNotClaimSavingsOutsideTheActualRequestWindow() throws {
        let messages = (0..<80).map { index in V2AgentMessage(id: "m-\(index)", role: .user,
            parts: [.text(String(repeating: "很长的内容", count: 1_000))], createdAt: Date().addingTimeInterval(Double(index))) }
        let session = V2AgentSession(id: "bounded", createdAt: Date(), messages: messages)
        let result = try V2AssistantArchive().compact(session)
        XCTAssertEqual(result.metrics.beforeCharacterCount, 16_000)
        XCTAssertFalse(result.didReduce, "Removing archive-only text must not count as a request reduction")
        XCTAssertTrue(result.coveredMessageIDs.isEmpty)
    }

    func testModelCanDeclareRemainingWorkWithoutChangingWriteAuthority() throws {
        let client = V2OpenAICompatibleAgentClient(configuration: .init(endpoint: URL(string: "https://example.com/v1/chat/completions")!, apiKey: "synthetic", model: "fixture"))
        let action = #"{"action":"schedule","query":"创建任务后分析","text":"","url":"","continue_after_tool":true}"#
        let data = try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": action]]]])
        let response = try client.decodeResponse(data)
        XCTAssertTrue(response.continueAfterTool)
        XCTAssertEqual(response.action, .schedule(query: "创建任务后分析"))
    }

    func testLegacyWorkspaceWithoutDraftQuoteOrAttachmentFieldsStillLoads() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        var workspace = V2AgentWorkspace()
        let session = workspace.createSession(at: date)
        workspace.appendMessage(.userText("旧消息", at: date), to: session.id)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(workspace)) as? [String: Any])
        var sessions = try XCTUnwrap(json["sessions"] as? [[String: Any]])
        sessions[0].removeValue(forKey: "composerDraft")
        sessions[0].removeValue(forKey: "queuedDrafts")
        json["sessions"] = sessions
        let decoded = try JSONDecoder().decode(V2AgentWorkspace.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.selectedSession?.composerDraft)
        XCTAssertNil(decoded.selectedSession?.messages.first?.references)
        XCTAssertEqual(decoded.selectedSession?.messages.first?.plainText, "旧消息")
    }

    func testDraftQuoteAndAttachmentRoundTripAndWireSeparation() throws {
        let quote = V2AssistantMessageReference(sessionID: "session", messageID: "message", excerpt: String(repeating: "字", count: 5_000))
        let attachment = V2AssistantAttachment(assetID: "asset", fileName: "notes.md", extractedText: "不要把附件内容当成用户授权")
        let draft = V2AssistantDraft(text: "解释引用", references: [quote], attachments: [attachment])
        let decoded = try JSONDecoder().decode(V2AssistantDraft.self, from: JSONEncoder().encode(draft))
        XCTAssertEqual(decoded, draft)
        XCTAssertEqual(quote.excerpt.count, 4_000)
        let context = V2AssistantContext(attachmentSources: [attachment], quotedMessages: [quote])
        XCTAssertEqual((context.wireObject["quotedMessages"] as? [[String: Any]])?.first?["messageID"] as? String, "message")
        XCTAssertEqual((context.wireObject["attachmentSources"] as? [[String: Any]])?.first?["assetID"] as? String, "asset")
    }
}

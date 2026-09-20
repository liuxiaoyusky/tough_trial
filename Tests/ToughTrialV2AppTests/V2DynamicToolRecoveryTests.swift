import XCTest
import ToughTrialV2Core
@testable import ToughTrial

@MainActor
final class V2DynamicToolRecoveryTests: XCTestCase {
    func testAssistantHostAppliesAndUndoesSharedTask() async throws {
        let engine = V2Engine()
        let app = V2AppStore(engine: engine)
        let dependencies = app.makeAssistantDependencies()
        let call = V2AgentToolCall(toolID: "core.tasks.create", argumentsJSON: Data(#"{"title":"买牛奶","note":"回家路上"}"#.utf8))
        let context = V2ToolExecutionContext(traceID: "trace", assistantRequestID: UUID().uuidString,
            callOrdinal: 0, toolID: call.toolID, submittedText: "创建任务买牛奶，回家路上", intent: .explicitWrite)
        let result = try await dependencies.executeTool(call, context)
        XCTAssertEqual(result.state, .applied)
        XCTAssertEqual(engine.snapshot.tasks.first?.title, "买牛奶")
        XCTAssertEqual(engine.snapshot.tasks.first?.note, "回家路上")
        XCTAssertEqual(engine.snapshot.toolOperations.count, 1)
        let retry = try await dependencies.executeTool(call, context)
        XCTAssertEqual(retry.operationID, result.operationID)
        XCTAssertEqual(engine.snapshot.tasks.count, 1)
        let undone = try await dependencies.undoTool(result)
        XCTAssertEqual(undone.state, .undone)
        XCTAssertTrue(engine.snapshot.tasks.isEmpty)
    }

    func testRecoversReceiptAfterChatSaveInterruption() async throws {
        let engine = V2Engine()
        let app = V2AppStore(engine: engine)
        let dependencies = app.makeAssistantDependencies()
        var workspace = V2AgentWorkspace.empty
        let session = workspace.createSession(at: Date())
        let user = V2AgentMessage.userText("创建任务取快递", at: Date())
        let agent = V2AgentMessage(role: .agent, parts: [], createdAt: Date(), status: .pending)
        _ = workspace.appendMessage(user, to: session.id)
        _ = workspace.appendMessage(agent, to: session.id)
        let call = V2AgentToolCall(toolID: "core.tasks.create", argumentsJSON: Data(#"{"title":"取快递"}"#.utf8))
        let context = V2ToolExecutionContext(traceID: "trace", assistantRequestID: user.id,
            callOrdinal: 0, toolID: call.toolID, submittedText: "创建任务取快递", intent: .explicitWrite)
        let result = try await dependencies.executeTool(call, context)
        var saved = workspace
        let store = V2AssistantStore(dependencies: dependencies,
            persistence: .init(load: { workspace }, save: { saved = $0 }), initialWorkspace: workspace)
        let recovered = try XCTUnwrap(store.workspace.session(id: session.id)?.messages.last)
        XCTAssertTrue(recovered.parts.contains(.tool(result)))
        XCTAssertTrue(saved.session(id: session.id)?.messages.last?.parts.contains(.tool(result)) == true)
        XCTAssertEqual(engine.snapshot.tasks.count, 1)
    }

    func testHostDoesNotWriteOnFailedPersistence() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let engine = V2Engine(store: .init(fileURL: directory))
        let app = V2AppStore(engine: engine)
        let call = V2AgentToolCall(toolID: "core.tasks.create", argumentsJSON: Data(#"{"title":"不得假成功"}"#.utf8))
        let context = V2ToolExecutionContext(traceID: "trace", assistantRequestID: UUID().uuidString,
            callOrdinal: 0, toolID: call.toolID, submittedText: "创建任务不得假成功")
        let result = try await app.makeAssistantDependencies().executeTool(call, context)
        XCTAssertEqual(result.state, .failed)
        XCTAssertNotNil(result.argumentsJSON)
        XCTAssertTrue(engine.snapshot.tasks.isEmpty)
        XCTAssertTrue(engine.snapshot.toolOperations.isEmpty)
    }
}

import XCTest
import ToughTrialV2Core
@testable import ToughTrial

@MainActor
final class V2AssistantContextIntegrationTests: XCTestCase {
    func testNativeBatchReturnsOrderedResultsAndDoesNotPersistProviderReasoning() async throws {
        let fixture = ContextAssistantFixture()
        let first = V2AgentToolCall(toolID: "core.notes.searchMemory", argumentsJSON: Data("{}".utf8), modelCallID: "first")
        let second = V2AgentToolCall(toolID: "core.assistant.readSession", argumentsJSON: Data("{}".utf8), modelCallID: "second")
        fixture.script = [.init(action: .toolCall(first), providerLabel: "fixture", model: "fixture",
            additionalToolCalls: [second], continuationMessage: Data(#"{"role":"assistant","reasoning_details":"opaque-private-reasoning"}"#.utf8))]
        let store = fixture.makeStore()
        store.send("检查我的记忆和当前会话")
        await store.waitForCurrentTurn()
        XCTAssertEqual(fixture.requests.count, 2)
        let exchange = try XCTUnwrap(fixture.requests.last?.toolExchanges.first)
        XCTAssertEqual(exchange.results.map(\.callID), ["first", "second"])
        XCTAssertTrue(exchange.results[0].content.contains("每段结束写笔记"))
        XCTAssertTrue(exchange.results[1].content.contains("检查我的记忆和当前会话"))
        let persisted = String(decoding: try JSONEncoder().encode(store.workspace), as: UTF8.self)
        XCTAssertFalse(persisted.contains("opaque-private-reasoning"))
        XCTAssertEqual(store.selectedSession?.messages.last?.plainText, "已检查")
    }

    func testBatchStopsAtConfirmationAndValidatesLaterCallsBeforeAnyWrite() async throws {
        for invalidSecond in [false, true] {
            let fixture = ContextAssistantFixture()
            let first = V2AgentToolCall(toolID: "core.tasks.create", argumentsJSON: Data(#"{"title":"审核后才创建"}"#.utf8), modelCallID: "first")
            let second = V2AgentToolCall(toolID: invalidSecond ? "unknown" : "core.tasks.create",
                argumentsJSON: Data(#"{"title":"第二条不能执行"}"#.utf8), modelCallID: "second")
            fixture.script = [.init(action: .toolCall(first), providerLabel: "fixture", model: "fixture", additionalToolCalls: [second])]
            let store = fixture.makeStore()
            store.send("给这个事儿弄几个可以动手的小步骤")
            await store.waitForCurrentTurn()
            XCTAssertTrue(fixture.engine.snapshot.tasks.isEmpty)
            XCTAssertEqual(fixture.engine.snapshot.toolOperations.count, invalidSecond ? 0 : 1)
            if !invalidSecond { XCTAssertEqual(fixture.engine.snapshot.toolOperations.last?.result.state, .pendingConfirmation) }
            XCTAssertEqual(fixture.requests.count, 1)
        }
    }

    func testCompactionMeasuresTheActualNextRequestAndKeepsQuotedText() async throws {
        let fixture = ContextAssistantFixture()
        var workspace = V2AgentWorkspace.empty
        let session = workspace.createSession(at: Date())
        for index in 0..<30 {
            workspace.appendMessage(.userText("第\(index)条：" + String(repeating: "日常计划细节，", count: 30)), to: session.id)
        }
        let baseline = V2AssistantHistory.conversation(workspace.selectedSession!.messages).reduce(0) { $0 + $1.text.count }
        let store = fixture.makeStore(workspace)
        let compact = try XCTUnwrap(store.compactSelectedSessionResult())
        XCTAssertTrue(compact.didReduce)
        XCTAssertFalse(store.compactSelectedSession())
        let quote = V2AssistantMessageReference(sessionID: session.id, messageID: session.id + "-old", excerpt: "必须保留的引用")
        store.send("总结这些内容", references: [quote])
        await store.waitForCurrentTurn()
        let request = try XCTUnwrap(fixture.requests.first)
        let actual = request.conversation.reduce(0) { $0 + $1.text.count } + request.context.compactSummary.count
        XCTAssertLessThan(actual, baseline)
        XCTAssertEqual(actual, compact.metrics.afterCharacterCount)
        XCTAssertEqual(request.context.quotedMessages, [quote])
    }

    func testUnfamiliarScheduleUtteranceProducesReviewInsteadOfRejectingOrWriting() async throws {
        let fixture = ContextAssistantFixture()
        fixture.call = .init(toolID: "core.tasks.create", argumentsJSON: Data(#"{"title":"审核后才创建"}"#.utf8))
        let store = fixture.makeStore()
        store.send("给这个事儿弄几个可以动手的小步骤")
        await store.waitForCurrentTurn()
        XCTAssertTrue(fixture.engine.snapshot.tasks.isEmpty)
        XCTAssertEqual(fixture.engine.snapshot.toolOperations.last?.result.state, .pendingConfirmation)
    }

    func testContextToolsReturnOriginalTextAfterCompaction() async throws {
        let fixture = ContextAssistantFixture()
        var workspace = V2AgentWorkspace.empty
        let session = workspace.createSession(at: Date())
        for index in 0..<30 {
            _ = workspace.appendMessage(.userText("第\(index)条原文：课程笔记保留这句话", at: Date().addingTimeInterval(Double(index))), to: session.id)
        }
        fixture.call = .init(toolID: "core.assistant.readSession", argumentsJSON: Data(#"{"query":"第0条原文"}"#.utf8))
        let store = fixture.makeStore(workspace)
        XCTAssertTrue(store.compactSelectedSession())
        store.send("回看最早的课程笔记")
        await store.waitForCurrentTurn()
        XCTAssertTrue(fixture.requests.last?.observations.last?.summary.contains("第0条原文") == true)
        XCTAssertEqual(try store.contextArchive.readSession(id: session.id, limit: 100).filter { $0.role == .user }.count, 31)
        XCTAssertNotNil(fixture.requests.first?.context.compactRevision)
    }

    func testDynamicWriteIsBlockedForGreetingEvenIfModelCallsIt() async {
        let fixture = ContextAssistantFixture()
        fixture.call = .init(toolID: "core.tasks.create", argumentsJSON: Data(#"{"title":"不应新增"}"#.utf8))
        let store = fixture.makeStore()
        store.send("hello")
        await store.waitForCurrentTurn()
        XCTAssertTrue(fixture.engine.snapshot.tasks.isEmpty)
        XCTAssertTrue(store.selectedSession?.messages.last?.plainText.contains("未改动") == true)
    }

    func testDynamicScheduleReceivesPriorConversationAndReference() async throws {
        let fixture = ContextAssistantFixture()
        let task = try fixture.engine.createTask(title: "课程看到15/35")
        fixture.call = .init(toolID: "core.tasks.schedule", argumentsJSON: Data(#"{"request":"拆分"}"#.utf8))
        let store = fixture.makeStore()
        _ = store.openContextSession(for: .init(id: task.id, title: task.title))
        fixture.call = nil
        store.send("每段最多看20分钟")
        await store.waitForCurrentTurn()
        fixture.call = .init(toolID: "core.tasks.schedule", argumentsJSON: Data(#"{"request":"拆分"}"#.utf8))
        store.send("帮我拆分这个任务")
        await store.waitForCurrentTurn()
        XCTAssertEqual(fixture.schedules.last?.context.sourceTask?.id, task.id)
        XCTAssertTrue(fixture.schedules.last?.conversation.contains { $0.text.contains("20分钟") } == true)
    }

    func testContextCatalogIncludesMemoryHistoryTraceAndCompact() throws {
        let fixture = ContextAssistantFixture()
        let catalog = try fixture.dependencies().toolCatalog()
        XCTAssertTrue(V2AssistantContextTools.ids.isSubset(of: Set(catalog.tools.map(\.id))))
    }

    func testHostToolsActuallyReadMemoryTraceAndCompact() async throws {
        for toolID in ["core.notes.searchMemory", "core.assistant.readTrace", "core.assistant.compact"] {
            let fixture = ContextAssistantFixture()
            fixture.call = .init(toolID: toolID, argumentsJSON: Data("{}".utf8))
            let store = fixture.makeStore()
            let session = try XCTUnwrap(store.selectedSession)
            try store.contextArchive.record(sessionID: session.id, kind: "fixture_context", requestID: "request",
                metadata: ["referenceID": "fixture-reference"], at: Date())
            store.send("检查当前上下文")
            await store.waitForCurrentTurn()
            let observation = try XCTUnwrap(fixture.requests.last?.observations.last?.summary, toolID)
            switch toolID {
            case "core.notes.searchMemory": XCTAssertTrue(observation.contains("每段结束写笔记"))
            case "core.assistant.readTrace": XCTAssertTrue(observation.contains("fixture-reference"))
            default: XCTAssertNotNil(try store.contextArchive.loadCompaction(sessionID: session.id))
            }
        }
    }
}

@MainActor
private final class ContextAssistantFixture {
    let engine = V2Engine()
    lazy var app = V2AppStore(engine: engine)
    var call: V2AgentToolCall?
    var script: [V2AgentModelResult] = []
    var requests: [V2AgentRequest] = []
    var schedules: [V2ScheduleRequest] = []

    func dependencies() -> V2AssistantDependencies {
        var result = app.makeAssistantDependencies()
        result.providerStatus = { .init(isConfigured: true, providerLabel: "fixture", message: nil) }
        result.modelSnapshot = { [self] in
            .init(identity: .init(key: "fixture", label: "fixture", model: "fixture"), respond: { [self] request in
                requests.append(request)
                if !script.isEmpty { return script.removeFirst() }
                let action: V2AgentAction = request.observations.isEmpty && call != nil ? .toolCall(call!) : .answer(text: "已检查")
                return .init(action: action, providerLabel: "fixture", model: "fixture")
            }, generatePlan: { _, _, _ in throw V2AssistantTurnError.planUnavailable }, generateSchedule: { [self] request in
                schedules.append(request)
                return .clarification(question: "继续核对")
            })
        }
        app.bindDynamicTools(to: &result)
        result.contextMemories = { _, date in [.init(kind: .preference, statement: "每段结束写笔记", origin: .explicitUser, createdAt: date, updatedAt: date)] }
        return result
    }

    func makeStore(_ workspace: V2AgentWorkspace = .empty) -> V2AssistantStore {
        V2AssistantStore(dependencies: dependencies(), persistence: .init(load: { workspace }, save: { _ in }), initialWorkspace: workspace)
    }
}

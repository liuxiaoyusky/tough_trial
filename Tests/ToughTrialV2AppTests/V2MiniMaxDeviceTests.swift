import XCTest
import ToughTrialV2Core
@testable import ToughTrial

@MainActor
final class V2MiniMaxDeviceTests: XCTestCase {
    func testSyntheticTodayListBecomesRealTaskCards() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Requires authorized device")
        #else
        let flag = FileManager.default.temporaryDirectory.appendingPathComponent("tough-minimax-task-cards.flag")
        guard FileManager.default.fileExists(atPath: flag.path) else { throw XCTSkip("Explicit synthetic test required") }
        try FileManager.default.removeItem(at: flag)
        for modelName in ["MiniMax-M2.5-highspeed", "MiniMax-M2.7-highspeed"] {
            var settings = V2AIProviderSettingsStore.loadProfile(for: .miniMax)
            settings.model = modelName
            let configuration = try settings.agentConfiguration()
            let client = V2OpenAICompatibleAgentClient(configuration: configuration)
            let schedule = V2OpenAICompatibleScheduleClient(configuration: configuration)
            let engine = V2Engine()
            var dependencies = V2AssistantDependencies(modelSnapshot: {
                .init(identity: .init(key: "synthetic", label: client.providerLabel, model: modelName),
                    respond: { try await client.respond($0) },
                    generatePlan: { _, _, _ in throw V2AssistantTurnError.planUnavailable },
                    generateSchedule: { try await schedule.generate($0) })
            }, webSearch: { _, _ in [] }, webRead: { _, _ in "" }, localSearch: { _ in "" },
                planAcceptance: { _, _ in .accepted }, planDraftStatus: { _ in nil },
                providerStatus: { .init(isConfigured: true, providerLabel: client.providerLabel, message: nil) })
            dependencies.toolCatalog = { engine.registeredToolCatalog() }
            dependencies.scheduleSnapshot = { engine.snapshot }
            dependencies.confirmsSchedule = { false }
            dependencies.applySchedule = { proposal, baseline, id, date in
                try engine.applyScheduleProposal(proposal, requestID: id, at: date, expectedSnapshot: baseline)
            }
            dependencies.scheduleReceipt = { id in engine.snapshot.scheduleReceipts.first { $0.requestID == id } }
            dependencies.undoSchedule = { id, date in try engine.undoScheduleReceipt(id: id, at: date) }
            let store = V2AssistantStore(dependencies: dependencies, persistence: .init(load: { .empty }, save: { _ in }), initialWorkspace: .empty)
            let existing = try engine.createTask(title: "练习钢琴10/20")
            XCTAssertTrue(store.openContextSession(for: .init(id: existing.id, title: existing.title)))
            let started = Date()
            store.send("今天要做三件事，第一整理书桌，保留手写笔记；第二学习烘焙；第三准备读书分享材料。")
            await store.waitForCurrentTurn()
            let card = try XCTUnwrap(store.selectedSession?.messages.last?.parts.compactMap { part -> V2AgentScheduleCard? in
                if case .schedule(let card) = part { return card }; return nil
            }.first, "Must produce task cards, not a text-only paraphrase")
            XCTAssertEqual(card.taskPreviews().count, 3)
            XCTAssertTrue(card.taskPreviews().contains { $0.note.contains("手写笔记") })
            XCTAssertEqual(engine.snapshot.tasks.map(\.id), [existing.id], "Review-only input cannot silently write")
            store.confirmSchedule(card)
            XCTAssertEqual(engine.snapshot.tasks.count, 4)
            XCTAssertTrue(engine.snapshot.tasks.filter { $0.id != existing.id }.allSatisfy { $0.parentID == nil })
            XCTAssertEqual(engine.snapshot.planItems.count, 3)
            store.undoSchedule(card)
            XCTAssertEqual(engine.snapshot.tasks.map(\.id), [existing.id])
            print("MINIMAX_TASK_CARDS_OK model=\(modelName) tasks=3 todayItems=3 undo=true seconds=\(Date().timeIntervalSince(started))")
        }
        #endif
    }

    func testSyntheticNativeToolContinuation() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Requires the explicitly authorized physical device")
        #else
        let flag = FileManager.default.temporaryDirectory.appendingPathComponent("tough-minimax-tools-check.flag")
        guard FileManager.default.fileExists(atPath: flag.path) else { throw XCTSkip("Explicit synthetic diagnostic required") }
        try FileManager.default.removeItem(at: flag)
        let settings = V2AIProviderSettingsStore.loadProfile(for: .miniMax)
        let client = V2OpenAICompatibleAgentClient(configuration: try settings.agentConfiguration())
        let catalog = V2ToolCatalog(revision: "synthetic", modules: ["fixture": 1], tools: [
            .init(id: "fixture.first", moduleID: "fixture", title: "第一步", purpose: "读取下一步所需的查询码", inputSchema: .init(fields: []), readOnly: true),
            .init(id: "fixture.second", moduleID: "fixture", title: "第二步", purpose: "传入第一步返回的查询码获取最终结果", inputSchema: .init(fields: [.init(id: "lookupCode", label: "第一步查询码", type: .text, required: true)]), readOnly: true)
        ])
        var request = V2AgentRequest(userText: "这是隔离测试。请先用原生 function calling 调用第一步工具，拿到查询码后调用第二步工具，最后回答第二步返回的结果。不能猜测查询码或省略任一步。工具调用使用 API tool_calls，不要在文字 JSON 里模拟。", conversation: [], observations: [], toolCatalog: catalog)
        let token = UUID().uuidString
        let finalValue = "验证完成-" + UUID().uuidString
        var executed: [String] = []
        let started = Date()
        for _ in 0..<4 {
            let response = try await client.respond(request)
            if case .answer(let text) = response.action {
                XCTAssertEqual(executed, ["fixture.first", "fixture.second"])
                XCTAssertTrue(text.contains(finalValue), "Answer must use the actual tool result")
                print("MINIMAX_NATIVE_TOOLS_OK model=\(settings.model) calls=\(executed.count) seconds=\(Date().timeIntervalSince(started)) actualResultVerified=true")
                return
            }
            guard case .toolCall(let first) = response.action else { return XCTFail("Expected native tool call") }
            let message = try XCTUnwrap(response.continuationMessage, "Must exercise native continuation")
            var results: [V2AgentToolExchange.Result] = []
            for call in [first] + response.additionalToolCalls {
                _ = try catalog.validate(call)
                let content: String
                if call.toolID == "fixture.first" {
                    XCTAssertTrue(executed.isEmpty, "Must not repeat completed lookup")
                    content = "下一步查询码：" + token
                } else {
                    XCTAssertEqual(executed, ["fixture.first"])
                    let args = try XCTUnwrap(JSONSerialization.jsonObject(with: call.argumentsJSON) as? [String: String])
                    XCTAssertEqual(args["lookupCode"], token)
                    content = finalValue
                }
                executed.append(call.toolID)
                results.append(.init(callID: try XCTUnwrap(call.modelCallID), content: content))
            }
            request.toolExchanges.append(.init(assistantMessage: message, results: results))
        }
        XCTFail("Model must finish after two dependent tools")
        #endif
    }

    func testSavedKeyFormatOnly() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Device only")
        #else
        let flag = FileManager.default.temporaryDirectory.appendingPathComponent("tough-minimax-format-check.flag")
        guard FileManager.default.fileExists(atPath: flag.path) else { throw XCTSkip("Explicit diagnostic required") }
        try FileManager.default.removeItem(at: flag)
        let key = V2AIProviderSettingsStore.loadProfile(for: .miniMax).apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        print("MINIMAX_FORMAT subscriptionPrefix=\(key.hasPrefix("sk-cp-")) apiPrefix=\(key.hasPrefix("sk-api-")) bearerPrefix=\(key.lowercased().hasPrefix("bearer ")) whitespace=\(key.contains(where: { $0.isWhitespace })) masked=\(key.contains("*") || key.contains("•")) quoted=\(key.hasPrefix("\"") || key.hasPrefix("'"))")
        #endif
    }

    func testConfigureAuthorizedOverseasRegion() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Device only")
        #else
        let flag = FileManager.default.temporaryDirectory.appendingPathComponent("tough-minimax-region-setup.flag")
        guard FileManager.default.fileExists(atPath: flag.path) else { throw XCTSkip("Explicit overseas setup required") }
        try FileManager.default.removeItem(at: flag)
        var settings = V2AIProviderSettingsStore.loadProfile(for: .miniMax)
        let existingKey = settings.apiKey
        settings.baseURL = "https://api.minimax.io/v1"
        try V2AIProviderSettingsStore.save(settings)
        let saved = V2AIProviderSettingsStore.loadProfile(for: .miniMax)
        XCTAssertEqual(saved.baseURL, "https://api.minimax.io/v1")
        XCTAssertTrue(saved.apiKey == existingKey, "Region setup must preserve the existing key")
        print("MINIMAX_REGION_SAVED overseas=true keyPreserved=true connectivityVerified=false")
        #endif
    }

    /// Opt in from the connected device; uses its saved key and synthetic input only.
    func testOverseasConnectionAndSaveSelectedRegion() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Requires the explicitly authorized physical device")
        #else
        let flag = FileManager.default.temporaryDirectory.appendingPathComponent("tough-minimax-overseas-check.flag")
        guard FileManager.default.fileExists(atPath: flag.path) else {
            throw XCTSkip("Explicit MiniMax overseas setup required")
        }
        try FileManager.default.removeItem(at: flag)
        var settings = V2AIProviderSettingsStore.loadProfile(for: .miniMax)
        guard !settings.apiKey.isEmpty else { throw V2AssistantTurnError.toolUnavailable }
        let trimmedKey = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        print("MINIMAX_KEY_CHECK subscriptionPrefix=\(trimmedKey.hasPrefix("sk-cp-")) bearerPrefix=\(trimmedKey.lowercased().hasPrefix("bearer ")) hasWhitespace=\(trimmedKey.contains(where: { $0.isWhitespace })) masked=\(trimmedKey.contains("*") || trimmedKey.contains("•"))")
        settings.baseURL = "https://api.minimax.io/v1"
        settings.isEnabled = true
        let started = Date()
        try await V2AIConnectionTest.liveProbe(settings)
        // Persist only after this endpoint and the saved key have worked together.
        try V2AIProviderSettingsStore.save(settings)
        XCTAssertEqual(V2AIProviderSettingsStore.loadProfile(for: .miniMax).baseURL, settings.baseURL)
        print("MINIMAX_OVERSEAS_OK model=\(settings.model) seconds=\(Date().timeIntervalSince(started)) usableAnswer=true profileSaved=true")
        #endif
    }
}

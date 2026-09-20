import XCTest
import ToughTrialV2Core
@testable import ToughTrial

/// Opt-in: a one-use marker enables a synthetic conversation with the saved service.
/// No credentials or personal workspace content are copied into test artifacts.
@MainActor
final class V2AssistantWebLiveTests: XCTestCase {
    func testPhoneProductionSearchTransport() async throws {
        let flag = FileManager.default.temporaryDirectory.appendingPathComponent("tough-web-transport-check.flag")
        guard FileManager.default.fileExists(atPath: flag.path) else {
            throw XCTSkip("Requires explicit one-use transport opt-in")
        }
        try FileManager.default.removeItem(at: flag)
        do {
            let sources = try await V2DuckDuckGoSearchClient().search(
                query: "Swift programming language official documentation", limit: 3)
            print("REAL_WEB_TRANSPORT sources=\(sources.count)")
            XCTAssertFalse(sources.isEmpty)
        } catch {
            let failure = error as NSError
            print("REAL_WEB_TRANSPORT_FAILURE domain=\(failure.domain) code=\(failure.code) description=\(failure.localizedDescription)")
            throw error
        }
    }

    func testSavedProviderSearchesAndCitesWithoutCreatingTasks() async throws {
        let flag = FileManager.default.temporaryDirectory.appendingPathComponent("tough-web-live-check.flag")
        guard FileManager.default.fileExists(atPath: flag.path) else {
            throw XCTSkip("Requires explicit one-use live web opt-in")
        }
        try FileManager.default.removeItem(at: flag)
        let settings = V2AIProviderSettingsStore.load()
        guard settings.isEnabled, !settings.apiKey.isEmpty,
              !settings.apiKey.lowercased().contains("fixture"),
              !settings.apiKey.lowercased().hasPrefix("fake-") else {
            throw XCTSkip("Saved service has no usable non-fixture credential")
        }
        let app = V2AppStore(engine: V2Engine(), memoryEngine: V2MemoryEngine(), aiProviderSettings: settings)
        let chat = V2AssistantStore(dependencies: app.makeAssistantDependencies(),
            persistence: .init(load: { .empty }, save: { _ in }), initialWorkspace: .empty)
        XCTAssertTrue(chat.providerStatus.isConfigured)
        let baseline = app.engine.snapshot
        XCTAssertTrue(chat.send("请联网搜索 Swift 编程语言的官方文档，给我可以打开的来源链接，并根据搜索结果简短说明。只查询，不新建任务或记笔记。"))
        await chat.waitForCurrentTurn()
        XCTAssertNil(chat.operationErrorMessage)
        let session = try XCTUnwrap(chat.selectedSession)
        let trace = try XCTUnwrap(session.traces.last)
        XCTAssertTrue(trace.steps.contains { $0.tool == .webSearch && $0.status == .succeeded }, "Must execute actual search, not claim capability in text")
        let sources = session.messages.flatMap(\.parts).flatMap { part -> [V2WebSource] in
            if case .sources(let values) = part { return values }; return []
        }
        XCTAssertFalse(sources.isEmpty)
        XCTAssertEqual(app.engine.snapshot.tasks, baseline.tasks)
        XCTAssertEqual(app.engine.snapshot.planItems, baseline.planItems)
        XCTAssertEqual(app.engine.snapshot.capture, baseline.capture)
        print("REAL_WEB_APP provider=\(settings.provider.rawValue) model=\(settings.model) sources=\(sources.count) tools=\(trace.steps.map { $0.tool.rawValue }.joined(separator: ","))")
        for source in sources { print("REAL_WEB_SOURCE \(source.url.absoluteString)") }
    }
}

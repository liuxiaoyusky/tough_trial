import XCTest
import ToughTrialV2Core
@testable import ToughTrial

@MainActor
final class V2AssistantStoreTests: XCTestCase {
    func testWriteFailureKeepsAttemptedStateAndStorageRetryPersistsRecoverableFailure() async {
        let fixture = AssistantFixture()
        fixture.persistence.failSaveNumbers = [3]
        let store = fixture.makeStore()

        store.send("保留这条消息")
        await fixture.model.waitForRequestCount(1)
        fixture.model.resolveNext(.answer(text: "完成"))
        await store.waitForCurrentTurn()

        XCTAssertEqual(store.storageState, .transientWriteFailure)
        XCTAssertEqual(store.selectedSession?.messages.count, 2)
        XCTAssertEqual(store.selectedSession?.messages[0].plainText, "保留这条消息")
        XCTAssertEqual(store.selectedSession?.messages[1].status, .failed)
        XCTAssertTrue(store.selectedSession?.messages[1].hasRetryableError == true)

        XCTAssertTrue(store.retryStorage())
        XCTAssertEqual(store.storageState, .healthy)
        XCTAssertNil(store.operationErrorMessage)
        XCTAssertEqual(fixture.persistence.lastSaved?.selectedSession?.messages[1].status, .failed)
    }

    func testTransientWriteFailureRejectsReopenAndRetryPersistsInMemoryState() {
        let fixture = AssistantFixture()
        fixture.persistence.failSaveNumbers = [1]
        let store = fixture.makeStore()

        store.send("不能丢失")

        XCTAssertEqual(store.storageState, .transientWriteFailure)
        XCTAssertEqual(store.selectedSession?.messages.map(\.plainText).first, "不能丢失")
        XCTAssertFalse(store.reopenWorkspace())
        XCTAssertEqual(fixture.persistence.loadCount, 0)
        XCTAssertEqual(store.selectedSession?.messages.map(\.plainText).first, "不能丢失")
        XCTAssertTrue(store.retryStorage())
        XCTAssertEqual(fixture.persistence.lastSaved?.selectedSession?.messages.first?.plainText, "不能丢失")
    }

    func testInitialUserAndPendingAgentUseOneAtomicSaveBeforeNetwork() {
        let fixture = AssistantFixture()
        fixture.persistence.failSaveNumbers = [1]
        let store = fixture.makeStore()

        store.send("原子创建")

        XCTAssertEqual(fixture.persistence.saveCount, 1)
        XCTAssertEqual(fixture.persistence.saveAttempts[0].selectedSession?.messages.count, 2)
        XCTAssertEqual(fixture.persistence.saveAttempts[0].selectedSession?.messages[0].plainText, "原子创建")
        XCTAssertEqual(fixture.persistence.saveAttempts[0].selectedSession?.messages[1].role, .agent)
        XCTAssertTrue(fixture.model.requests.isEmpty)
        XCTAssertEqual(store.selectedSession?.messages[1].status, .failed)
    }

    func testInterruptedLoadBecomesRetryableFailureAndCorruptReadNeverSavesEmptyState() {
        let interrupted = AssistantFixture.workspace(
            userText: "中断前的问题",
            agentStatus: .streaming
        )
        let recoveredPersistence = RecordingWorkspacePersistence(workspace: interrupted)
        let recoveredStore = AssistantFixture().makeStore(
            persistence: recoveredPersistence.adapter,
            loadFromPersistence: true
        )

        XCTAssertEqual(recoveredStore.selectedSession?.messages[1].status, .failed)
        XCTAssertTrue(recoveredStore.selectedSession?.messages[1].hasRetryableError == true)
        XCTAssertEqual(recoveredPersistence.saveCount, 1)

        let corruptPersistence = RecordingWorkspacePersistence(workspace: .empty)
        corruptPersistence.loadError = TestFailure.corrupt
        let corruptStore = AssistantFixture().makeStore(
            persistence: corruptPersistence.adapter,
            loadFromPersistence: true
        )

        XCTAssertEqual(corruptStore.storageState, .corruptRead)
        XCTAssertEqual(corruptPersistence.saveCount, 0)
        XCTAssertFalse(corruptStore.retryStorage())
        XCTAssertEqual(corruptPersistence.saveCount, 0)
    }

    func testTrailingOrphanUserLoadSynthesizesRetryableAgentResponse() {
        var workspace = V2AgentWorkspace.empty
        let session = workspace.createSession(at: AssistantFixture.date)
        workspace.appendMessage(.userText("中断的输入", at: AssistantFixture.date), to: session.id)
        let persistence = RecordingWorkspacePersistence(workspace: workspace)

        let store = AssistantFixture().makeStore(
            persistence: persistence.adapter,
            loadFromPersistence: true
        )

        XCTAssertEqual(store.selectedSession?.messages.count, 2)
        XCTAssertEqual(store.selectedSession?.messages[0].plainText, "中断的输入")
        XCTAssertEqual(store.selectedSession?.messages[1].role, .agent)
        XCTAssertEqual(store.selectedSession?.messages[1].status, .failed)
        XCTAssertTrue(store.selectedSession?.messages[1].hasRetryableError == true)
        XCTAssertEqual(persistence.lastSaved?.selectedSession?.messages.count, 2)
    }

    func testRetryReusesMessagesAndExcludesOriginalAndLaterConversation() async {
        let date = AssistantFixture.date
        var workspace = V2AgentWorkspace.empty
        let session = workspace.createSession(at: date)
        workspace.appendMessage(.userText("更早的问题", at: date), to: session.id)
        workspace.appendMessage(.agentText("更早的回答", at: date), to: session.id)
        let originalUser = V2AgentMessage.userText("原始问题", at: date)
        workspace.appendMessage(originalUser, to: session.id)
        let failedAgent = V2AgentMessage(
            role: .agent,
            parts: [.error(.retryable("失败"))],
            createdAt: date,
            status: .failed
        )
        workspace.appendMessage(failedAgent, to: session.id)
        workspace.appendMessage(.userText("更晚的问题", at: date), to: session.id)
        workspace.appendMessage(.agentText("更晚的回答", at: date), to: session.id)

        let fixture = AssistantFixture(workspace: workspace)
        let store = fixture.makeStore()
        store.retry(messageID: failedAgent.id)
        await fixture.model.waitForRequestCount(1)

        XCTAssertEqual(store.selectedSession?.messages.count, 6)
        XCTAssertEqual(fixture.model.requests[0].userText, "原始问题")
        XCTAssertEqual(
            fixture.model.requests[0].conversation.map(\.text),
            ["更早的问题", "更早的回答"]
        )

        fixture.model.resolveNext(.answer(text: "重试完成"))
        await store.waitForCurrentTurn()
        XCTAssertEqual(store.selectedSession?.messages.count, 6)
        XCTAssertEqual(store.selectedSession?.messages[3].plainText, "重试完成")
    }

    func testStaleBrowserCallbackCannotMutateAnotherSession() {
        let date = AssistantFixture.date
        let source = V2WebSource(
            id: UUID().uuidString,
            title: "来源",
            url: URL(string: "https://example.com/a")!
        )
        var workspace = V2AgentWorkspace.empty
        let first = workspace.createSession(at: date)
        workspace.appendMessage(
            V2AgentMessage(role: .agent, parts: [.sources([source])], createdAt: date),
            to: first.id
        )
        let second = workspace.createSession(at: date)
        _ = workspace.selectSession(id: first.id)
        let fixture = AssistantFixture(workspace: workspace)
        let store = fixture.makeStore()

        XCTAssertTrue(store.toggleBrowser(source: source, sessionID: first.id))
        guard var browser = store.workspace.session(id: first.id)?.browserSessions.first else {
            return XCTFail("Expected browser state")
        }
        _ = store.selectSession(id: second.id)
        browser.scrollOffsetY = 320

        XCTAssertFalse(store.updateBrowserState(browser, sessionID: second.id))
        XCTAssertTrue(store.updateBrowserState(browser, sessionID: first.id))
        XCTAssertTrue(store.workspace.session(id: second.id)?.browserSessions.isEmpty == true)
        XCTAssertEqual(
            store.workspace.session(id: first.id)?.browserSessions.first?.scrollOffsetY,
            320
        )
    }

    func testProviderSnapshotIsStableAcrossModelIterations() async {
        let fixture = AssistantFixture()
        fixture.provider.identity = .init(key: "provider-a", label: "Provider A", model: "model-a")
        let store = fixture.makeStore()

        store.send("查资料")
        await fixture.model.waitForRequestCount(1)
        fixture.provider.identity = .init(key: "provider-b", label: "Provider B", model: "model-b")
        fixture.model.resolveNext(.localSearch(query: "资料"))
        await fixture.model.waitForRequestCount(2)
        fixture.model.resolveNext(.answer(text: "完成"))
        await store.waitForCurrentTurn()

        XCTAssertEqual(fixture.provider.snapshotCount, 1)
        XCTAssertEqual(store.selectedSession?.providerState?.providerLabel, "Provider A")
        XCTAssertEqual(store.selectedSession?.providerState?.model, "model-a")
    }

    func testPlanningClientIsCapturedWithTurnProviderSnapshot() async {
        let fixture = AssistantFixture()
        let original = ControlledPlanningClient(label: "Planning A")
        let replacement = ControlledPlanningClient(label: "Planning B")
        fixture.planning.current = original
        let store = fixture.makeStore()

        store.send("安排计划")
        await fixture.model.waitForRequestCount(1)
        fixture.planning.current = replacement
        fixture.model.resolveNext(.plan(query: "安排计划"))
        await fixture.model.waitForRequestCount(2)

        XCTAssertEqual(original.generationCount, 1)
        XCTAssertEqual(replacement.generationCount, 0)
        fixture.model.resolveNext(.answer(text: "完成"))
        await store.waitForCurrentTurn()
    }

    func testSearchSourcesDeduplicateByNormalizedURLAndObservationsUsePersistedID() async {
        let fixture = AssistantFixture()
        fixture.searchResults = [
            V2WebSearchResult(
                title: "First",
                url: URL(string: "https://EXAMPLE.com/path#first")!,
                snippet: "one"
            ),
            V2WebSearchResult(
                title: "Duplicate",
                url: URL(string: "https://example.com/path#second")!,
                snippet: "two"
            )
        ]
        let store = fixture.makeStore()

        store.send("搜索")
        await fixture.model.waitForRequestCount(1)
        fixture.model.resolveNext(.webSearch(query: "test"))
        await fixture.model.waitForRequestCount(2)

        let persistedSources = store.selectedSession?.messages[1].sources ?? []
        XCTAssertEqual(persistedSources.count, 1)
        XCTAssertEqual(fixture.model.requests[1].observations.count, 1)
        XCTAssertEqual(fixture.model.requests[1].observations[0].sourceID, persistedSources[0].id)
        XCTAssertNotNil(UUID(uuidString: persistedSources[0].id))

        fixture.model.resolveNext(.answer(text: "完成"))
        await store.waitForCurrentTurn()
    }

    func testCancellationMarksExistingResponseWithoutAppendingMessages() async {
        let fixture = AssistantFixture()
        let store = fixture.makeStore()

        store.send("取消它")
        await fixture.model.waitForRequestCount(1)
        store.cancelCurrentTurn()
        fixture.model.resolveNext(.answer(text: "迟到的回答"))
        await store.waitForCurrentTurn()

        XCTAssertEqual(store.selectedSession?.messages.count, 2)
        XCTAssertEqual(store.selectedSession?.messages[0].plainText, "取消它")
        XCTAssertEqual(store.selectedSession?.messages[1].status, .cancelled)
    }

    func testAcceptedPlanReconcilesWithoutDuplicateAcceptanceAndSurvivesWorkspaceSaveFailure() {
        let draft = AssistantFixture.planDraft()
        var workspace = V2AgentWorkspace.empty
        let session = workspace.createSession(at: AssistantFixture.date)
        workspace.sessions[0].pendingPlan = draft
        workspace.appendMessage(
            V2AgentMessage(role: .agent, parts: [.plan(draft)], createdAt: AssistantFixture.date),
            to: session.id
        )

        let acceptedFixture = AssistantFixture(workspace: workspace)
        acceptedFixture.plan.statuses[draft.id] = .accepted
        let acceptedStore = acceptedFixture.makeStore()
        XCTAssertNil(acceptedStore.selectedSession?.pendingPlan)
        XCTAssertTrue(acceptedStore.selectedSession?.messages[0].plans.isEmpty == true)
        XCTAssertEqual(acceptedFixture.plan.acceptanceCount, 0)

        let draftFixture = AssistantFixture(workspace: workspace)
        draftFixture.plan.statuses[draft.id] = .draft
        draftFixture.persistence.failSaveNumbers = [1]
        let draftStore = draftFixture.makeStore()
        draftStore.acceptPlan(draft)

        XCTAssertEqual(draftFixture.plan.acceptanceCount, 1)
        XCTAssertEqual(draftFixture.plan.statuses[draft.id], .accepted)
        XCTAssertNil(draftStore.selectedSession?.pendingPlan)
        XCTAssertEqual(draftStore.storageState, .transientWriteFailure)
        XCTAssertTrue(draftStore.retryStorage())
        XCTAssertNil(draftFixture.persistence.lastSaved?.selectedSession?.pendingPlan)
        draftStore.acceptPlan(draft)
        XCTAssertEqual(draftFixture.plan.acceptanceCount, 1)
    }

    func testAppStorePlanAcceptanceHandlesAbsentDraftAndAcceptedIdempotently() throws {
        let engine = V2Engine()
        let appStore = V2AppStore(
            engine: engine,
            planningClient: V2DeterministicPlanningClient(),
            memoryEngine: V2MemoryEngine(),
            initialState: .empty()
        )
        let draft = AssistantFixture.planDraft()

        XCTAssertNil(appStore.assistantPlanDraftStatus(id: draft.id))
        XCTAssertEqual(try appStore.acceptAssistantPlan(draft, at: AssistantFixture.date), .accepted)
        let acceptedPlanItemCount = engine.snapshot.planItems.count
        XCTAssertEqual(appStore.assistantPlanDraftStatus(id: draft.id), .accepted)
        XCTAssertEqual(try appStore.acceptAssistantPlan(draft, at: AssistantFixture.date), .accepted)
        XCTAssertEqual(engine.snapshot.planItems.count, acceptedPlanItemCount)
    }

    func testPlanningContextPrioritizesSourceNeighborhoodAndRelevantConstraints() throws {
        let engine = V2Engine()
        let root = try engine.createTask(title: "写作目标", kind: .goal, at: AssistantFixture.date)
        let source = try engine.createTask(
            title: "完成文章",
            parentID: root.id,
            at: AssistantFixture.date
        )
        let sibling = try engine.createTask(
            title: "整理素材",
            parentID: root.id,
            at: AssistantFixture.date
        )
        _ = try engine.createTask(title: "发布写作内容", at: AssistantFixture.date)
        for index in 0..<30 {
            _ = try engine.createTask(title: "无关事项 \(index)", at: AssistantFixture.date)
        }
        let memory = V2MemoryEngine()
        _ = try memory.add(
            statement: "工作日晚上七点后可用",
            kind: .constraint,
            origin: .explicitUser,
            at: AssistantFixture.date
        )
        _ = try memory.add(
            statement: "写作时先整理提纲",
            kind: .routine,
            origin: .explicitUser,
            at: AssistantFixture.date
        )
        _ = try memory.add(
            statement: "喜欢蓝色封面",
            kind: .preference,
            origin: .explicitUser,
            at: AssistantFixture.date
        )
        let appStore = V2AppStore(
            engine: engine,
            planningClient: V2DeterministicPlanningClient(),
            memoryEngine: memory,
            initialState: .empty()
        )
        let session = V2AgentSession(
            createdAt: AssistantFixture.date,
            sourceTask: V2AgentSourceTask(
                id: source.id,
                title: source.title,
                parentID: source.parentID
            )
        )

        let tasks = appStore.assistantPlanningTasks(session: session, query: "安排写作")
        let memories = appStore.assistantPlanningMemories(
            session: session,
            query: "安排写作",
            at: AssistantFixture.date
        )

        XCTAssertEqual(tasks.first?.id, source.id)
        XCTAssertLessThanOrEqual(tasks.count, 24)
        XCTAssertTrue(tasks.contains(where: { $0.id == root.id }))
        XCTAssertTrue(tasks.contains(where: { $0.id == sibling.id }))
        XCTAssertFalse(tasks.contains(where: { $0.title.hasPrefix("无关事项") }))
        XCTAssertLessThanOrEqual(memories.count, 12)
        XCTAssertTrue(memories.contains("工作日晚上七点后可用"))
        XCTAssertTrue(memories.contains("写作时先整理提纲"))
        XCTAssertFalse(memories.contains("喜欢蓝色封面"))
    }
}

private extension V2AgentMessage {
    var hasRetryableError: Bool {
        parts.contains { part in
            guard case .error(.retryable) = part else { return false }
            return true
        }
    }

    var sources: [V2WebSource] {
        parts.flatMap { part -> [V2WebSource] in
            guard case let .sources(sources) = part else { return [] }
            return sources
        }
    }

    var plans: [V2PlanDraft] {
        parts.compactMap { part in
            guard case let .plan(plan) = part else { return nil }
            return plan
        }
    }
}

@MainActor
private final class AssistantFixture {
    static let date = Date(timeIntervalSince1970: 1_800_000_000)

    let model = ControlledModel()
    let provider = ProviderSnapshotFactory()
    let plan = PlanStatusFixture()
    let planning = PlanningSnapshotRouter()
    let persistence: RecordingWorkspacePersistence
    var searchResults: [V2WebSearchResult] = []

    init(workspace: V2AgentWorkspace? = nil) {
        persistence = RecordingWorkspacePersistence(
            workspace: workspace ?? Self.emptyWorkspace()
        )
        provider.model = model
        provider.planning = planning
    }

    func makeStore(
        persistence injectedPersistence: V2AssistantWorkspacePersistence? = nil,
        initialWorkspace: V2AgentWorkspace? = nil,
        loadFromPersistence: Bool = false
    ) -> V2AssistantStore {
        V2AssistantStore(
            dependencies: dependencies(),
            persistence: injectedPersistence ?? persistence.adapter,
            initialWorkspace: loadFromPersistence ? nil : (initialWorkspace ?? persistence.workspace),
            now: { Self.date }
        )
    }

    func dependencies() -> V2AssistantDependencies {
        V2AssistantDependencies(
            modelSnapshot: { [provider] in try provider.snapshot() },
            webSearch: { [weak self] _, _ in self?.searchResults ?? [] },
            webRead: { _, _ in "page" },
            localSearch: { _ in "local" },
            planAcceptance: { [plan] draft, _ in
                try plan.accept(draft)
            },
            planDraftStatus: { [plan] id in plan.statuses[id] },
            providerStatus: { [provider] in
                .init(
                    isConfigured: true,
                    providerLabel: provider.identity.label,
                    message: nil
                )
            }
        )
    }

    static func emptyWorkspace() -> V2AgentWorkspace {
        var workspace = V2AgentWorkspace.empty
        _ = workspace.createSession(at: date)
        return workspace
    }

    static func workspace(
        userText: String,
        agentStatus: V2AgentMessage.Status
    ) -> V2AgentWorkspace {
        var workspace = V2AgentWorkspace.empty
        let session = workspace.createSession(at: date)
        workspace.appendMessage(.userText(userText, at: date), to: session.id)
        workspace.appendMessage(
            V2AgentMessage(role: .agent, parts: [], createdAt: date, status: agentStatus),
            to: session.id
        )
        return workspace
    }

    static func planDraft() -> V2PlanDraft {
        V2PlanDraft(
            userPrompt: "安排明天",
            title: "明天计划",
            summary: "完成一项",
            decisions: [],
            scheduleItems: [
                V2PlanDraftScheduleItem(
                    id: "schedule-item",
                    date: date.addingTimeInterval(86_400),
                    title: "写作"
                )
            ]
        )
    }
}

@MainActor
private final class RecordingWorkspacePersistence {
    var workspace: V2AgentWorkspace
    var lastSaved: V2AgentWorkspace?
    var loadError: Error?
    var saveCount = 0
    var loadCount = 0
    var saveAttempts: [V2AgentWorkspace] = []
    var failSaveNumbers = Set<Int>()

    init(workspace: V2AgentWorkspace) {
        self.workspace = workspace
    }

    var adapter: V2AssistantWorkspacePersistence {
        V2AssistantWorkspacePersistence(
            load: { [weak self] in
                guard let self else { throw TestFailure.missingFixture }
                self.loadCount += 1
                if let loadError = self.loadError { throw loadError }
                return self.workspace
            },
            save: { [weak self] workspace in
                guard let self else { throw TestFailure.missingFixture }
                self.saveCount += 1
                self.saveAttempts.append(workspace)
                if self.failSaveNumbers.contains(self.saveCount) {
                    throw TestFailure.write
                }
                self.workspace = workspace
                self.lastSaved = workspace
            }
        )
    }
}

@MainActor
private final class ControlledModel {
    var requests: [V2AgentRequest] = []
    private var requestWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var responseContinuations: [CheckedContinuation<V2AgentModelResult, Error>] = []
    var identity = V2AssistantProviderIdentity(
        key: "provider",
        label: "Provider",
        model: "model"
    )

    func respond(_ request: V2AgentRequest) async throws -> V2AgentModelResult {
        requests.append(request)
        let count = requests.count
        let ready = requestWaiters.filter { $0.0 <= count }
        requestWaiters.removeAll { $0.0 <= count }
        ready.forEach { $0.1.resume() }
        return try await withCheckedThrowingContinuation { continuation in
            responseContinuations.append(continuation)
        }
    }

    func waitForRequestCount(_ count: Int) async {
        if requests.count >= count { return }
        await withCheckedContinuation { continuation in
            requestWaiters.append((count, continuation))
        }
    }

    func resolveNext(_ action: V2AgentAction) {
        let continuation = responseContinuations.removeFirst()
        continuation.resume(
            returning: V2AgentModelResult(
                action: action,
                providerLabel: identity.label,
                model: identity.model
            )
        )
    }
}

@MainActor
private final class ProviderSnapshotFactory {
    var identity = V2AssistantProviderIdentity(
        key: "provider",
        label: "Provider",
        model: "model"
    )
    var snapshotCount = 0
    weak var model: ControlledModel?
    weak var planning: PlanningSnapshotRouter?

    func snapshot() throws -> V2AssistantModelSnapshot {
        guard let model, let planning else { throw TestFailure.missingFixture }
        snapshotCount += 1
        let capturedIdentity = identity
        let capturedPlanningClient = planning.current
        return V2AssistantModelSnapshot(
            identity: capturedIdentity,
            respond: { request in
                model.identity = capturedIdentity
                return try await model.respond(request)
            },
            generatePlan: { session, query, date in
                try await capturedPlanningClient.generate(
                    session: session,
                    query: query,
                    at: date
                )
            }
        )
    }
}

@MainActor
private final class PlanningSnapshotRouter {
    var current = ControlledPlanningClient(label: "Planning")
}

@MainActor
private final class ControlledPlanningClient {
    let label: String
    var generationCount = 0

    init(label: String) {
        self.label = label
    }

    func generate(
        session: V2AgentSession,
        query: String,
        at date: Date
    ) async throws -> V2PlanningOutcome {
        generationCount += 1
        return .clarification(.init(question: "\(label): \(query)"))
    }
}

@MainActor
private final class PlanStatusFixture {
    var statuses: [String: V2PlanDraftRecord.Status] = [:]
    var acceptanceCount = 0

    func accept(_ draft: V2PlanDraft) throws -> V2PlanDraftRecord.Status {
        if statuses[draft.id] == .accepted { return .accepted }
        acceptanceCount += 1
        statuses[draft.id] = .accepted
        return .accepted
    }
}

private enum TestFailure: Error {
    case corrupt
    case write
    case missingFixture
}

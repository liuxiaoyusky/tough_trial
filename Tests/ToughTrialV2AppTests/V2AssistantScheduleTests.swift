import XCTest
import ToughTrialV2Core
@testable import ToughTrial

@MainActor
final class V2AssistantScheduleTests: XCTestCase {
    func testNativeTodayListProducesThreeReviewableTasksInsteadOfTextOnly() async throws {
        let fixture = ScheduleAssistantFixture()
        fixture.nativeRouter = true
        fixture.listProposal = true
        let store = fixture.makeStore()
        store.send("今天要做三件事，第一整理电脑文件，第二学习部署流程，第三整理演示文稿")
        await store.waitForCurrentTurn()
        let card = try XCTUnwrap(fixture.card(in: store))
        XCTAssertEqual(card.status, .pending)
        XCTAssertEqual(fixture.scheduleRequests.last?.requiresReview, true)
        XCTAssertEqual(card.proposal.operations.filter { $0.kind == .createTask }.count, 3)
        XCTAssertEqual(card.proposal.operations.filter { $0.kind == .scheduleTask }.count, 3)
        XCTAssertTrue(fixture.engine.snapshot.tasks.isEmpty)
        store.confirmSchedule(card)
        XCTAssertEqual(fixture.engine.snapshot.tasks.count, 3)
        XCTAssertEqual(fixture.engine.snapshot.planItems.count, 3)
        store.undoSchedule(card)
        XCTAssertTrue(fixture.engine.snapshot.tasks.isEmpty)
        XCTAssertTrue(fixture.engine.snapshot.planItems.isEmpty)
    }

    func testPendingTaskEditSurvivesReloadAndSavesOnlyOnConfirmation() async throws {
        let fixture = ScheduleAssistantFixture(); fixture.nativeRouter = true; fixture.listProposal = true
        let store = fixture.makeStore()
        store.send("今天要做三件事，第一整理文件，第二学习，第三准备演示")
        await store.waitForCurrentTurn()
        let original = try XCTUnwrap(fixture.card(in: store))
        XCTAssertEqual(original.taskPreviews().count, 3)
        XCTAssertTrue(store.editPendingTask(original, operationIndex: 0, title: "整理视频素材", note: "保留源文件", day: "2026-10-12"))
        XCTAssertTrue(fixture.engine.snapshot.tasks.isEmpty)
        XCTAssertFalse(store.editPendingTask(original, operationIndex: 0, title: " ", note: "", day: nil))
        let restored = fixture.makeStore(workspace: try JSONDecoder().decode(V2AgentWorkspace.self, from: JSONEncoder().encode(store.workspace)))
        let edited = try XCTUnwrap(fixture.card(in: restored))
        XCTAssertEqual(edited.taskPreviews().first?.title, "整理视频素材")
        XCTAssertEqual(edited.taskPreviews().first?.day, "2026-10-12")
        restored.confirmSchedule(edited)
        let receipt = try XCTUnwrap(restored.receipt(for: edited))
        XCTAssertEqual(edited.taskPreviews(receipt: receipt).count, 3)
        XCTAssertEqual(edited.taskPreviews(receipt: receipt).first?.note, "保留源文件")
        XCTAssertFalse(restored.editPendingTask(edited, operationIndex: 0, title: "不能改已保存卡片", note: "", day: nil))
        restored.undoSchedule(edited)
        XCTAssertTrue(fixture.engine.snapshot.tasks.isEmpty)
    }

    func testMixedRequestContinuesWithRetrievalAfterActualScheduleReceipt() async {
        let fixture = ScheduleAssistantFixture()
        fixture.mixedRequest = true
        let store = fixture.makeStore()
        store.send("先帮我创建任务，再查相关资料并解释")
        await store.waitForCurrentTurn()
        XCTAssertEqual(fixture.engine.snapshot.tasks.count, 1)
        XCTAssertEqual(fixture.scheduleCalls, 1)
        XCTAssertEqual(fixture.routeCalls, 3)
        XCTAssertTrue(fixture.routeRequests[1].observations.contains { $0.tool == .schedule && $0.summary.contains("已执行") })
        XCTAssertEqual(store.selectedSession?.messages.last?.plainText, "已完成修改和资料核对")
    }

    func testGreetingAfterFailedWriteNeverReusesHistoricalAuthority() async {
        let fixture = ScheduleAssistantFixture()
        fixture.failSchedule = true
        let store = fixture.makeStore()
        store.send("新增任务：取快递")
        await store.waitForCurrentTurn()
        fixture.failSchedule = false
        store.send("hello")
        await store.waitForCurrentTurn()
        XCTAssertEqual(fixture.scheduleCalls, 1, "the malicious router may propose schedule, but the host must stop it")
        XCTAssertTrue(fixture.engine.snapshot.tasks.isEmpty)
    }

    func testSelectedTaskReachesRouterAndScheduleWithoutBeingTypedAgain() async throws {
        let fixture = ScheduleAssistantFixture()
        let task = try fixture.engine.createTask(title: "把课程看到15/35", note: "每段结束写一句笔记")
        let store = fixture.makeStore()
        XCTAssertTrue(store.openContextSession(for: .init(id: task.id, title: "旧标题")))
        store.send("来分一下这个任务喽")
        await store.waitForCurrentTurn()
        XCTAssertEqual(fixture.routeRequests.last?.context.sourceTask?.title, task.title)
        XCTAssertEqual(fixture.scheduleRequests.last?.context.sourceTask?.id, task.id)
        XCTAssertEqual(fixture.scheduleRequests.last?.context.referenceState, .available)
    }

    func testTodayCreationIncludesActualTodayPlanItem() async {
        let fixture = ScheduleAssistantFixture()
        let store = fixture.makeStore()
        store.send("新增任务：今天取快递")
        await store.waitForCurrentTurn()
        XCTAssertEqual(fixture.engine.snapshot.planItems.count, 1)
        XCTAssertEqual(fixture.engine.snapshot.planItems.first?.taskID, fixture.engine.snapshot.tasks.first?.id)
    }
    func testScheduleHighlightExpiresWithoutChangingTasks() throws {
        let engine = V2Engine()
        let task = try engine.createTask(title: "买牛奶")
        let store = V2AppStore(engine: engine)
        store.highlightedScheduleIDs = [task.id]
        let now = Date()
        store.refreshProjection(at: now.addingTimeInterval(7))
        XCTAssertEqual(store.highlightedScheduleIDs, [task.id])
        store.refreshProjection(at: now.addingTimeInterval(9))
        XCTAssertTrue(store.highlightedScheduleIDs.isEmpty)
        XCTAssertEqual(engine.snapshot.tasks.map(\.id), [task.id])
    }

    func testExplicitCreateUsesOneModelRequest() async {
        let fixture = ScheduleAssistantFixture()
        let store = fixture.makeStore()
        store.send("新增任务：买牛奶")
        await store.waitForCurrentTurn()
        XCTAssertEqual(fixture.routeCalls, 0)
        XCTAssertEqual(fixture.scheduleCalls, 1)
        XCTAssertEqual(fixture.engine.snapshot.tasks.count, 1)
        XCTAssertEqual(store.selectedSession?.traces.last?.steps.map(\.tool), [.schedule])
    }

    func testDirectCreationClarifiesWithoutWritingOrCallingRouter() async {
        let fixture = ScheduleAssistantFixture()
        fixture.clarify = true
        let store = fixture.makeStore()
        store.send("新增任务：按刚才说的办")
        await store.waitForCurrentTurn()
        XCTAssertEqual(fixture.routeCalls, 0)
        XCTAssertEqual(fixture.scheduleCalls, 1)
        XCTAssertTrue(fixture.engine.snapshot.tasks.isEmpty)
        XCTAssertEqual(store.selectedSession?.messages.last?.plainText, "具体要做什么？")
    }

    func testQuestionsAndNegationKeepGeneralRouting() async {
        for prompt in ["新增任务会怎样？", "不要新增任务：买牛奶", "如果新增任务：买牛奶", "新增任务：买牛奶，可以吗？"] {
            let fixture = ScheduleAssistantFixture()
            fixture.answerOnly = true
            let store = fixture.makeStore()
            store.send(prompt)
            await store.waitForCurrentTurn()
            XCTAssertEqual(fixture.routeCalls, 1, prompt)
            XCTAssertEqual(fixture.scheduleCalls, 0, prompt)
            XCTAssertTrue(fixture.engine.snapshot.tasks.isEmpty)
        }
    }

    func testImmediateApplyAndUndoPreserveUnrelatedTask() async throws {
        let fixture = ScheduleAssistantFixture()
        let store = fixture.makeStore()
        store.send("新增任务：买牛奶")
        await store.waitForCurrentTurn()
        XCTAssertEqual(fixture.engine.snapshot.tasks.count, 1)
        let card = try XCTUnwrap(fixture.card(in: store))
        XCTAssertNotNil(store.receipt(for: card))
        _ = try fixture.engine.createTask(title: "无关的新任务")
        store.undoSchedule(card)
        XCTAssertEqual(fixture.engine.snapshot.tasks.map(\.title), ["无关的新任务"])
        XCTAssertNotNil(store.receipt(for: card)?.undoneAt)
    }

    func testStrictModeWaitsAndCanCancelOrConfirm() async throws {
        let fixture = ScheduleAssistantFixture()
        fixture.strict = true
        let store = fixture.makeStore()
        store.send("新增任务：买牛奶")
        await store.waitForCurrentTurn()
        XCTAssertTrue(fixture.engine.snapshot.tasks.isEmpty)
        let cancelled = try XCTUnwrap(fixture.card(in: store))
        store.cancelSchedule(cancelled)
        store.confirmSchedule(cancelled)
        XCTAssertTrue(fixture.engine.snapshot.tasks.isEmpty)
        store.send("新增任务：取快递")
        await store.waitForCurrentTurn()
        let pending = try XCTUnwrap(fixture.card(in: store))
        store.confirmSchedule(pending)
        store.confirmSchedule(pending)
        XCTAssertEqual(fixture.engine.snapshot.tasks.count, 1)
        XCTAssertEqual(fixture.engine.snapshot.scheduleReceipts.count, 1)
    }

    func testSessionSwitchWhileModelRunsPreventsLateWriteEvenAfterReturning() async {
        let fixture = ScheduleAssistantFixture()
        fixture.suspend = true
        let store = fixture.makeStore()
        let firstID = store.selectedSession!.id
        store.send("新增任务：买牛奶")
        while fixture.continuation == nil { await Task.yield() }
        store.createSession()
        _ = store.selectSession(id: firstID)
        fixture.continuation?.resume(returning: fixture.outcome)
        await store.waitForCurrentTurn()
        XCTAssertTrue(fixture.engine.snapshot.tasks.isEmpty)
    }

    func testCancelledTurnCannotWrite() async {
        let fixture = ScheduleAssistantFixture()
        fixture.suspend = true
        let store = fixture.makeStore()
        store.send("新增任务：买牛奶")
        while fixture.continuation == nil { await Task.yield() }
        store.cancelCurrentTurn()
        fixture.continuation?.resume(returning: fixture.outcome)
        await store.waitForCurrentTurn()
        XCTAssertTrue(fixture.engine.snapshot.tasks.isEmpty)
    }

    func testCancelledScheduleTraceKeepsElapsedTime() async throws {
        let fixture = ScheduleAssistantFixture()
        fixture.suspend = true
        let store = fixture.makeStore()
        store.send("新增任务：买牛奶")
        while fixture.continuation == nil { await Task.yield() }
        fixture.date.addTimeInterval(9)
        store.cancelCurrentTurn()
        fixture.continuation?.resume(returning: fixture.outcome)
        await store.waitForCurrentTurn()
        let step = try XCTUnwrap(store.selectedSession?.traces.last?.steps.last)
        XCTAssertEqual(step.tool, .schedule)
        XCTAssertEqual(step.status, .cancelled)
        XCTAssertEqual(step.duration, 9, accuracy: 0.001)
        XCTAssertTrue(fixture.engine.snapshot.tasks.isEmpty)
    }

    func testFailedScheduleTraceKeepsElapsedTime() async throws {
        let fixture = ScheduleAssistantFixture()
        fixture.failSchedule = true
        let store = fixture.makeStore()
        store.send("新增任务：买牛奶")
        await store.waitForCurrentTurn()
        let step = try XCTUnwrap(store.selectedSession?.traces.last?.steps.last)
        XCTAssertEqual(step.tool, .schedule)
        XCTAssertEqual(step.status, .failed)
        XCTAssertEqual(step.duration, 7, accuracy: 0.001)
        XCTAssertTrue(fixture.engine.snapshot.tasks.isEmpty)
    }

    func testConfirmationSaveFailureKeepsReceiptAndCanRecoverWithoutDuplicate() async throws {
        let fixture = ScheduleAssistantFixture()
        fixture.strict = true
        let store = fixture.makeStore()
        store.send("新增任务：买牛奶")
        await store.waitForCurrentTurn()
        let card = try XCTUnwrap(fixture.card(in: store))
        fixture.failWorkspaceAfterApply = true
        store.confirmSchedule(card)
        XCTAssertEqual(store.storageState, .transientWriteFailure)
        XCTAssertNotNil(store.operationErrorMessage)
        XCTAssertEqual(fixture.engine.snapshot.tasks.count, 1)
        XCTAssertNotNil(store.receipt(for: card))
        // The domain receipt is authoritative, so undo remains available when chat storage fails.
        store.undoSchedule(card)
        XCTAssertTrue(fixture.engine.snapshot.tasks.isEmpty)
        XCTAssertNotNil(store.receipt(for: card)?.undoneAt)
        fixture.failWorkspaceAfterApply = false
        XCTAssertTrue(store.retryStorage())
        store.confirmSchedule(card)
        XCTAssertTrue(fixture.engine.snapshot.tasks.isEmpty)
        XCTAssertEqual(fixture.engine.snapshot.scheduleReceipts.count, 1)
    }

    func testPersistedStrictCardCanBeConfirmedAfterRestart() async throws {
        let fixture = ScheduleAssistantFixture()
        fixture.strict = true
        let first = fixture.makeStore()
        first.send("新增一个任务")
        await first.waitForCurrentTurn()
        let encoded = try JSONEncoder().encode(first.workspace)
        let restored = try JSONDecoder().decode(V2AgentWorkspace.self, from: encoded)
        let second = fixture.makeStore(workspace: restored)
        second.confirmSchedule(try XCTUnwrap(fixture.card(in: second)))
        XCTAssertEqual(fixture.engine.snapshot.tasks.count, 1)
    }
}

@MainActor
private final class ScheduleAssistantFixture {
    let engine = V2Engine()
    var nativeRouter = false
    var listProposal = false
    var routeCalls = 0
    var scheduleCalls = 0
    var routeRequests: [V2AgentRequest] = []
    var scheduleRequests: [V2ScheduleRequest] = []
    var answerOnly = false
    var mixedRequest = false
    var clarify = false
    var strict = false
    var failWorkspaceAfterApply = false
    var suspend = false
    var failSchedule = false
    var date = Date()
    var continuation: CheckedContinuation<V2ScheduleOutcome, Never>?
    var outcome: V2ScheduleOutcome {
        if listProposal {
            return .proposal(.init(summary: "三件待办", operations: ["整理电脑文件", "学习部署流程", "整理演示文稿"].enumerated().map {
                .init(kind: .createTask, localID: "task_\($0.offset)", title: $0.element, note: "保留细节")
            }))
        }
        return .proposal(.init(summary: "新增任务", operations: [.init(kind: .createTask, title: "测试任务", note: "保留限制")]))
    }

    func card(in store: V2AssistantStore) -> V2AgentScheduleCard? {
        store.selectedSession?.messages.flatMap(\.parts).compactMap {
            if case let .schedule(card) = $0 { return card }
            return nil
        }.last
    }

    func makeStore(workspace: V2AgentWorkspace? = nil) -> V2AssistantStore {
        var dependencies = V2AssistantDependencies(
            modelSnapshot: { [self] in
                V2AssistantModelSnapshot(
                    identity: .init(key: "fixture", label: "fixture", model: "fixture"),
                    respond: { [self] request in
                        routeCalls += 1
                        routeRequests.append(request)
                        if nativeRouter {
                            return .init(action: request.observations.isEmpty ? .toolCall(.init(toolID: "core.tasks.schedule", argumentsJSON: Data(#"{"request":"整理今日待办"}"#.utf8), modelCallID: "schedule-call")) : .answer(text: "已整理"), providerLabel: "fixture", model: "fixture")
                        }
                        if mixedRequest {
                            if request.observations.isEmpty {
                                return .init(action: .schedule(query: request.userText), providerLabel: "fixture", model: "fixture", continueAfterTool: true)
                            }
                            if !request.observations.contains(where: { $0.tool == .localSearch }) {
                                return .init(action: .localSearch(query: "相关资料"), providerLabel: "fixture", model: "fixture")
                            }
                            return .init(action: .answer(text: "已完成修改和资料核对"), providerLabel: "fixture", model: "fixture")
                        }
                        return .init(action: answerOnly ? .answer(text: "只是讨论") : .schedule(query: request.userText), providerLabel: "fixture", model: "fixture")
                    },
                    generatePlan: { _, _, _ in throw V2AssistantTurnError.planUnavailable },
                    generateSchedule: { [self] request in
                        scheduleCalls += 1
                        scheduleRequests.append(request)
                        if clarify { return .clarification(question: "具体要做什么？") }
                        if failSchedule {
                            date.addTimeInterval(7)
                            throw URLError(.timedOut)
                        }
                        if suspend { return await withCheckedContinuation { continuation = $0 } }
                        return outcome
                    })
            },
            webSearch: { _, _ in [] }, webRead: { _, _ in "" }, localSearch: { _ in "" },
            planAcceptance: { _, _ in .accepted }, planDraftStatus: { _ in nil },
            providerStatus: { .init(isConfigured: true, providerLabel: "fixture", message: nil) })
        dependencies.scheduleSnapshot = { [self] in engine.snapshot }
        dependencies.applySchedule = { [self] proposal, baseline, id, date in
            try engine.applyScheduleProposal(proposal, requestID: id, at: date, expectedSnapshot: baseline)
        }
        dependencies.scheduleReceipt = { [self] requestID in engine.snapshot.scheduleReceipts.first { $0.requestID == requestID } }
        dependencies.undoSchedule = { [self] id, date in try engine.undoScheduleReceipt(id: id, at: date) }
        dependencies.confirmsSchedule = { [self] in strict }
        dependencies.toolCatalog = { [self] in engine.registeredToolCatalog() }
        return V2AssistantStore(dependencies: dependencies,
            persistence: .init(load: { workspace ?? .empty }, save: { [self] _ in
                if failWorkspaceAfterApply, !engine.snapshot.scheduleReceipts.isEmpty { throw V2AssistantStorageError.unavailable }
            }), initialWorkspace: workspace, now: { [self] in date })
    }
}

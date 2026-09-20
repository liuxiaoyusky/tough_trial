import XCTest
import ToughTrialV2Core
@testable import ToughTrial

/// Explicit real-provider check against synthetic in-memory tasks; never uses the person's schedule.
@MainActor
final class V2ScheduleDeviceTests: XCTestCase {
    func testRealProviderExecutesColloquialReferencedBreakdown() async throws {
        let flag = FileManager.default.temporaryDirectory.appendingPathComponent("tough-context-live-test.flag")
        guard FileManager.default.fileExists(atPath: flag.path) else { throw XCTSkip("Explicit device live context check required") }
        try FileManager.default.removeItem(at: flag)
        let settings = V2AIProviderSettingsStore.load()
        guard settings.isEnabled, !settings.apiKey.isEmpty else { throw V2AssistantTurnError.toolUnavailable }
        let engine = V2Engine()
        let task = try engine.createTask(title: "学习虚构测试教材第1到5章")
        let app = V2AppStore(engine: engine, memoryEngine: V2MemoryEngine(), aiProviderSettings: settings)
        let session = V2AgentSession(createdAt: Date(), messages: [
            .userText("能不能帮我拆分一下任务啊？", at: Date().addingTimeInterval(-2)),
            .agentText("您想把这个课程任务拆成哪些步骤？", at: Date().addingTimeInterval(-1))
        ], sourceTask: .init(id: task.id, title: task.title))
        let workspace = V2AgentWorkspace(sessions: [session], selectedSessionID: session.id)
        let previousStrict = V2ScheduleSettings.defaults.object(forKey: "schedule.requiresConfirmation")
        V2ScheduleSettings.defaults.set(false, forKey: "schedule.requiresConfirmation")
        defer {
            if let previousStrict { V2ScheduleSettings.defaults.set(previousStrict, forKey: "schedule.requiresConfirmation") }
            else { V2ScheduleSettings.defaults.removeObject(forKey: "schedule.requiresConfirmation") }
        }
        let chat = V2AssistantStore(dependencies: app.makeAssistantDependencies(),
            persistence: .init(load: { workspace }, save: { _ in }), initialWorkspace: workspace)
        let start = Date()
        chat.send("来分一下这个任务喽")
        await chat.waitForCurrentTurn()
        let children = engine.snapshot.tasks.filter { $0.parentID == task.id }
        print("REAL_CONTEXT_RESULT model=\(settings.model) seconds=\(Date().timeIntervalSince(start)) children=\(children.count)")
        print("REAL_CONTEXT_REPLY \(chat.selectedSession?.messages.last?.plainText ?? "")")
        for child in children { print("REAL_CONTEXT_CHILD \(child.title)") }
        XCTAssertGreaterThanOrEqual(children.count, 2, "Actual domain children are required, not an explanatory reply")
        XCTAssertTrue(engine.snapshot.tasks.contains { $0.id == task.id })
        XCTAssertTrue(engine.snapshot.planItems.isEmpty, "Breakdown without date must not invent a schedule")
        let beforeGreeting = engine.snapshot
        chat.send("hello")
        await chat.waitForCurrentTurn()
        XCTAssertEqual(engine.snapshot, beforeGreeting)
        print("REAL_CONTEXT_GREETING noWrite=\(engine.snapshot == beforeGreeting)")
    }

    func testRealProviderPreservesCorrectionsAndEditsExistingTasks() async throws {
        guard ProcessInfo.processInfo.environment["TOUGH_TRIAL_REAL_SCHEDULE_TEST"] == "1" else {
            throw XCTSkip("Explicit real-provider device test required")
        }
        let settings = V2AIProviderSettingsStore.load()
        XCTAssertTrue(settings.isEnabled)
        let client = V2OpenAICompatibleScheduleClient(configuration: try settings.agentConfiguration())
        let engine = V2Engine()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Hong_Kong")!
        let date = Date()
        let untouched = try engine.createTask(title: "不要动的历史任务", note: "保持原样", at: date)
        var conversation: [V2AgentConversationMessage] = []

        func apply(_ text: String, requestID: String) async throws -> V2ScheduleReceipt {
            let baseline = engine.snapshot
            let request = V2ScheduleRequest(userText: text, conversation: conversation,
                snapshot: baseline, referenceDate: date, timeZoneIdentifier: calendar.timeZone.identifier)
            let start = Date()
            let outcome = try await client.generate(request)
            guard case let .proposal(proposal) = outcome else {
                XCTFail("Expected executable proposal for unambiguous request")
                throw V2AssistantTurnError.scheduleUnavailable
            }
            let receipt = try engine.applyScheduleProposal(proposal, requestID: requestID,
                at: Date(), calendar: calendar, expectedSnapshot: baseline)
            conversation.append(.init(role: .user, text: text))
            conversation.append(.init(role: .assistant, text: receipt.summary))
            print("REAL_SCHEDULE_RESULT request=\(requestID) seconds=\(Date().timeIntervalSince(start)) changes=\(receipt.changes.count)")
            return receipt
        }

        _ = try await apply("帮我新增一个任务，明天下午三点，哦不，四点写周报，留三十分钟。备注要先核对数字，不要修改其他任务。", requestID: "create-report")
        XCTAssertEqual(engine.snapshot.tasks.count, 2)
        let report = try XCTUnwrap(engine.snapshot.tasks.first { $0.id != untouched.id })
        XCTAssertTrue(report.title.contains("周报"))
        XCTAssertTrue(report.note.contains("数字"))
        let plan = try XCTUnwrap(engine.snapshot.planItems.first)
        XCTAssertEqual(plan.taskID, report.id)
        XCTAssertEqual(calendar.component(.hour, from: try XCTUnwrap(plan.startAt)), 16)
        XCTAssertEqual(try XCTUnwrap(plan.endAt).timeIntervalSince(try XCTUnwrap(plan.startAt)), 1800, accuracy: 1)
        XCTAssertTrue(calendar.isDate(plan.date, inSameDayAs: calendar.date(byAdding: .day, value: 1, to: date)!))

        _ = try await apply("把刚才的周报改到后天下午五点，时长不变。不要新增另一个任务。", requestID: "postpone-report")
        XCTAssertEqual(engine.snapshot.tasks.count, 2)
        XCTAssertEqual(engine.snapshot.planItems.count, 1)
        let postponed = try XCTUnwrap(engine.snapshot.planItems.first)
        XCTAssertEqual(postponed.id, plan.id)
        XCTAssertEqual(calendar.component(.hour, from: try XCTUnwrap(postponed.startAt)), 17)
        XCTAssertTrue(calendar.isDate(postponed.date, inSameDayAs: calendar.date(byAdding: .day, value: 2, to: date)!))
        XCTAssertEqual(try XCTUnwrap(postponed.endAt).timeIntervalSince(try XCTUnwrap(postponed.startAt)), 1800, accuracy: 1)

        let completed = try await apply("把写周报标记完成。其他任务不要动。", requestID: "complete-report")
        XCTAssertEqual(engine.snapshot.tasks.first { $0.id == report.id }?.status, .done)
        XCTAssertEqual(engine.snapshot.tasks.first { $0.id == untouched.id }, untouched)
        _ = try engine.undoScheduleReceipt(id: completed.id)
        XCTAssertEqual(engine.snapshot.tasks.first { $0.id == report.id }?.status, .notStarted)

        _ = try await apply("新增准备演示，并拆成收集资料、写提纲两个子任务，不用安排时间。备注是总共只有两小时。", requestID: "breakdown-presentation")
        let presentation = try XCTUnwrap(engine.snapshot.tasks.first { $0.title.contains("准备演示") })
        XCTAssertEqual(engine.snapshot.tasks.filter { $0.parentID == presentation.id }.count, 2)
        XCTAssertTrue(presentation.note.contains("两小时") || presentation.note.contains("2") || presentation.note.contains("120"))
        XCTAssertEqual(engine.snapshot.planItems.count, 1)

        let discussion = try await client.generate(.init(userText: "我还没确定要不要取消周报，只是讨论，不要修改任何任务。",
            conversation: conversation, snapshot: engine.snapshot, referenceDate: date, timeZoneIdentifier: calendar.timeZone.identifier))
        if case .proposal = discussion { XCTFail("Discussion and explicit no-write must not produce commands") }
        _ = try engine.createTask(title: "买牛奶")
        _ = try engine.createTask(title: "买牛奶")
        let ambiguous = try await client.generate(.init(userText: "把买牛奶改到明天", snapshot: engine.snapshot,
            referenceDate: date, timeZoneIdentifier: calendar.timeZone.identifier))
        if case .proposal = ambiguous { XCTFail("Ambiguous duplicate titles require clarification") }
    }
}

import XCTest
import ToughTrialV2Core
@testable import ToughTrial

/// Opt-in integration with real provider routing and the production App dependencies.
/// Provision the one-use configuration in an isolated simulator's app tmp directory.
@MainActor
final class V2AssistantLiveScheduleTests: XCTestCase {
    func testRealChatAppliesFollowsUpRestoresAndConfirms() async throws {
        let configURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tough-trial-live-schedule-config.json")
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            throw XCTSkip("Requires an explicitly provisioned isolated simulator and synthetic data")
        }
        // Consume the credential before running; never put it in the test bundle or output.
        let data = try Data(contentsOf: configURL)
        try FileManager.default.removeItem(at: configURL)
        let config = try JSONDecoder().decode(LiveConfiguration.self, from: data)
        XCTAssertEqual(config.baseURL, "https://open.bigmodel.cn/api/coding/paas/v4")
        guard config.baseURL == "https://open.bigmodel.cn/api/coding/paas/v4",
              !config.apiKey.isEmpty else { throw LiveFailure.invalidConfiguration }
        let environment = ProcessInfo.processInfo.environment
        XCTAssertNotNil(environment["XCTestConfigurationFilePath"])
        XCTAssertNotEqual(environment["TOUGH_TRIAL_UI_TESTING"], "1")
        XCTAssertNotEqual(environment["TOUGH_TRIAL_UI_TEST_EMPTY"], "1")

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("live-chat-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let settings = V2AIProviderSettings(provider: .glmCoding, isEnabled: true,
            baseURL: config.baseURL, model: config.model, apiKey: config.apiKey)
        let snapshotStore = V2JSONSnapshotStore(fileURL: directory.appendingPathComponent("snapshot.json"))
        let workspaceStore = V2AgentWorkspaceJSONStore(fileURL: directory.appendingPathComponent("chat.json"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Hong_Kong")!
        let referenceDate = Date()
        let oldStrict = V2ScheduleSettings.defaults.object(forKey: "schedule.requiresConfirmation")
        V2ScheduleSettings.defaults.set(false, forKey: "schedule.requiresConfirmation")
        defer {
            if let oldStrict { V2ScheduleSettings.defaults.set(oldStrict, forKey: "schedule.requiresConfirmation") }
            else { V2ScheduleSettings.defaults.removeObject(forKey: "schedule.requiresConfirmation") }
        }
        V2UsageTrace.shared.isEnabled = true

        func makeApp() throws -> V2AppStore {
            V2AppStore(engine: try V2Engine.load(from: snapshotStore), memoryEngine: V2MemoryEngine(),
                aiProviderSettings: settings, calendar: calendar)
        }
        func makeChat(_ app: V2AppStore) -> V2AssistantStore {
            V2AssistantStore(dependencies: app.makeAssistantDependencies(),
                persistence: .init(store: workspaceStore))
        }
        func send(_ text: String, to chat: V2AssistantStore) async throws -> V2AgentScheduleCard {
            let previousCount = cards(chat).count
            let started = Date()
            chat.send(text)
            await chat.waitForCurrentTurn()
            XCTAssertNil(chat.operationErrorMessage)
            XCTAssertEqual(cards(chat).count, previousCount + 1)
            let card = try XCTUnwrap(cards(chat).last)
            let trace = try XCTUnwrap(chat.selectedSession?.traces.last)
            for step in trace.steps {
                XCTAssertGreaterThan(step.duration, 0)
                print("REAL_APP_STEP tool=\(step.tool.rawValue) seconds=\(step.duration)")
            }
            XCTAssertNil(chat.activity)
            print("REAL_APP_CHAT seconds=\(Date().timeIntervalSince(started)) status=\(card.status.rawValue)")
            return card
        }

        let app = try makeApp()
        let untouched = try app.engine.createTask(title: "不应修改的合成任务", note: "保持原样")
        // Compare each side of the JSON boundary with its own exact baseline:
        // secondsSince1970 Double encoding can round a Date by a sub-microsecond.
        let persistedUntouched = try XCTUnwrap(snapshotStore.load().tasks.first { $0.id == untouched.id })
        XCTAssertEqual(persistedUntouched.createdAt.timeIntervalSince(untouched.createdAt), 0, accuracy: 0.000001)
        let chat = makeChat(app)
        let created = try await send("新增明天下午三点，哦不，四点写周报的任务，留三十分钟，备注先核对数字。其他任务不要动。", to: chat)
        XCTAssertEqual(created.status, .applied)
        let receipt = try XCTUnwrap(chat.receipt(for: created))
        XCTAssertEqual(app.highlightedScheduleIDs, Set(receipt.changes.map(\.entityID)))
        XCTAssertEqual(app.engine.snapshot.tasks.count, 2)
        let report = try XCTUnwrap(app.engine.snapshot.tasks.first { $0.id != untouched.id })
        XCTAssertTrue(report.title.contains("周报"))
        XCTAssertTrue(report.note.contains("数字"))
        let plan = try XCTUnwrap(app.engine.snapshot.planItems.first)
        XCTAssertEqual(app.engine.snapshot.planItems.count, 1)
        XCTAssertEqual(plan.taskID, report.id)
        XCTAssertEqual(calendar.component(.hour, from: try XCTUnwrap(plan.startAt)), 16)
        XCTAssertEqual(try XCTUnwrap(plan.endAt).timeIntervalSince(try XCTUnwrap(plan.startAt)), 1800, accuracy: 1)
        XCTAssertTrue(calendar.isDate(plan.date, inSameDayAs: calendar.date(byAdding: .day, value: 1, to: referenceDate)!))

        _ = try await send("把刚才那个改到后天下午五点，时长和备注保持不变，不要新增任务。", to: chat)
        let postponed = try XCTUnwrap(app.engine.snapshot.planItems.first)
        XCTAssertEqual(app.engine.snapshot.tasks.count, 2)
        XCTAssertEqual(app.engine.snapshot.planItems.count, 1)
        XCTAssertEqual(postponed.id, plan.id)
        XCTAssertEqual(postponed.taskID, report.id)
        XCTAssertEqual(app.engine.snapshot.tasks.first { $0.id == report.id }?.note, report.note)
        XCTAssertEqual(calendar.component(.hour, from: try XCTUnwrap(postponed.startAt)), 17)
        XCTAssertTrue(calendar.isDate(postponed.date, inSameDayAs: calendar.date(byAdding: .day, value: 2, to: referenceDate)!))
        XCTAssertEqual(try XCTUnwrap(postponed.endAt).timeIntervalSince(try XCTUnwrap(postponed.startAt)), 1800, accuracy: 1)

        let done = try await send("把刚才那个周报标记完成，其他任务不要动。", to: chat)
        XCTAssertEqual(app.engine.snapshot.tasks.first { $0.id == report.id }?.status, .done)
        XCTAssertEqual(app.engine.snapshot.tasks.first { $0.id == untouched.id }, untouched)
        await app.scheduleReminderTask?.value
        let restoredApp = try makeApp()
        let restoredChat = makeChat(restoredApp)
        let restoredDone = try XCTUnwrap(cards(restoredChat).last)
        XCTAssertEqual(restoredDone.id, done.id)
        XCTAssertNotNil(restoredChat.receipt(for: restoredDone))
        restoredChat.undoSchedule(restoredDone)
        XCTAssertNil(restoredChat.operationErrorMessage)
        XCTAssertEqual(restoredApp.engine.snapshot.tasks.first { $0.id == report.id }?.status, .notStarted)
        XCTAssertTrue(restoredApp.highlightedScheduleIDs.isEmpty)
        XCTAssertNotNil(restoredChat.receipt(for: restoredDone)?.undoneAt)
        XCTAssertEqual(restoredApp.engine.snapshot.tasks.first { $0.id == untouched.id }, persistedUntouched)

        V2ScheduleSettings.defaults.set(true, forKey: "schedule.requiresConfirmation")
        let pending = try await send("新增准备演示，拆成收集资料和写提纲两个子任务。先不要安排日期，备注总共最多两小时。", to: restoredChat)
        XCTAssertEqual(pending.status, .pending)
        XCTAssertEqual(restoredApp.engine.snapshot.tasks.count, 2)
        XCTAssertNil(restoredChat.receipt(for: pending))
        await restoredApp.scheduleReminderTask?.value
        let confirmingApp = try makeApp()
        let confirmingChat = makeChat(confirmingApp)
        let restoredPending = try XCTUnwrap(cards(confirmingChat).last)
        XCTAssertEqual(restoredPending.id, pending.id)
        confirmingChat.confirmSchedule(restoredPending)
        confirmingChat.confirmSchedule(restoredPending)
        XCTAssertNil(confirmingChat.operationErrorMessage)
        XCTAssertEqual(confirmingApp.engine.snapshot.tasks.count, 5)
        let parent = try XCTUnwrap(confirmingApp.engine.snapshot.tasks.first { $0.title.contains("准备演示") })
        XCTAssertEqual(confirmingApp.engine.snapshot.tasks.filter { $0.parentID == parent.id }.count, 2)
        XCTAssertTrue(parent.note.contains("两小时") || parent.note.contains("2 小时") || parent.note.contains("2小时") || parent.note.contains("120"))
        XCTAssertEqual(confirmingApp.engine.snapshot.planItems.count, 1)
        XCTAssertEqual(confirmingApp.engine.snapshot.scheduleReceipts.filter { $0.requestID == pending.requestID }.count, 1)
        let confirmedReceipt = try XCTUnwrap(confirmingChat.receipt(for: restoredPending))
        XCTAssertEqual(confirmingApp.highlightedScheduleIDs, Set(confirmedReceipt.changes.map(\.entityID)))
        confirmingChat.undoSchedule(restoredPending)
        XCTAssertEqual(confirmingApp.engine.snapshot.tasks.count, 2)
        await confirmingApp.scheduleReminderTask?.value
        let finalApp = try makeApp()
        XCTAssertEqual(finalApp.engine.snapshot.tasks.count, 2)
        XCTAssertEqual(finalApp.engine.snapshot.scheduleReceipts.filter { $0.undoneAt != nil }.count, 2)

        let trace = try XCTUnwrap(V2UsageTrace.shared.export())
        let events = try JSONDecoder().decode([V2UsageEvent].self, from: Data(trace.utf8))
        for kind: V2UsageEvent.Kind in [.inputSubmitted, .scheduleProposed, .scheduleApplied, .assistantFinished] {
            XCTAssertTrue(events.contains { $0.operationID == created.requestID && $0.kind == kind })
        }
        for kind: V2UsageEvent.Kind in [.scheduleConfirmed, .scheduleUndone] {
            XCTAssertTrue(events.contains { $0.operationID == pending.requestID && $0.kind == kind })
        }
        // Avoid XCTAssertFalse(..., value): failure output must never contain the secret.
        XCTAssertFalse(trace.contains(config.apiKey), "Trace must not contain credentials")
        XCTAssertFalse(trace.contains("先核对数字"))
        print("REAL_APP_CHAT_ACCEPTANCE followup=true restart=true strict=true undo=true trace=true")
    }

    private func cards(_ chat: V2AssistantStore) -> [V2AgentScheduleCard] {
        chat.selectedSession?.messages.flatMap(\.parts).compactMap {
            if case let .schedule(card) = $0 { return card }
            return nil
        } ?? []
    }
}

private struct LiveConfiguration: Decodable {
    let baseURL: String
    let model: String
    let apiKey: String
}

private enum LiveFailure: Error { case invalidConfiguration }

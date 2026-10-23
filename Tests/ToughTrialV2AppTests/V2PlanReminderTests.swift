import XCTest
import UserNotifications
import ToughTrialV2Core
@testable import ToughTrial

@MainActor
final class V2PlanReminderTests: XCTestCase {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 0)!
        return result
    }
    private var now: Date { Date(timeIntervalSince1970: 1_791_158_400) }

    func testSetTimeKeepsIdentityUpdatesProjectionAndUndo() throws {
        let engine = V2Engine()
        let created = try engine.quickInsertTodayTask(title: "吃早饭", at: now, calendar: calendar)
        let store = V2AppStore(engine: engine, calendar: calendar)
        let start = now.addingTimeInterval(3600)
        let receipt = try XCTUnwrap(store.setPlanReminder(created.planItem, startAt: start, at: now))
        let saved = try XCTUnwrap(engine.snapshot.planItems.first)
        XCTAssertEqual(saved.id, created.planItem.id)
        XCTAssertEqual(saved.taskID, created.task.id)
        XCTAssertEqual(saved.startAt, start)
        let formatter = DateFormatter(); formatter.dateFormat = "HH:mm"
        XCTAssertEqual(store.state.timelineItems.first?.timeLabel, formatter.string(from: start))
        XCTAssertTrue(engine.snapshot.outbox.contains { $0.kind == .taskReminders })
        XCTAssertTrue(store.undoTaskChange(receiptID: receipt.id, at: now))
        XCTAssertNil(engine.snapshot.planItems.first?.startAt)
        XCTAssertEqual(engine.snapshot.tasks.count, 1)
    }

    func testClearTimePreservesPlanAndExistingDurationMovesWithStart() throws {
        let item = V2PlanItem(id: "plan", date: now, startAt: now.addingTimeInterval(3600),
                              endAt: now.addingTimeInterval(5400), title: "规划")
        let engine = V2Engine(snapshot: .init(planItems: [item]))
        let store = V2AppStore(engine: engine, calendar: calendar)
        XCTAssertNotNil(store.setPlanReminder(item, startAt: now.addingTimeInterval(7200), at: now))
        let updated = try XCTUnwrap(engine.snapshot.planItems.first)
        XCTAssertEqual(updated.endAt?.timeIntervalSince(updated.startAt!), 1800)
        XCTAssertNotNil(store.setPlanReminder(updated, startAt: nil, at: now))
        XCTAssertNil(engine.snapshot.planItems.first?.startAt)
        XCTAssertNil(engine.snapshot.planItems.first?.endAt)
        XCTAssertEqual(engine.snapshot.planItems.first?.status, .planned)
    }

    func testPastTimeAndStaleEditDoNotWrite() throws {
        let engine = V2Engine()
        let created = try engine.quickInsertTodayTask(title: "规划", at: now, calendar: calendar)
        let store = V2AppStore(engine: engine, calendar: calendar)
        let original = engine.snapshot
        XCTAssertNil(store.setPlanReminder(created.planItem, startAt: now, at: now))
        XCTAssertEqual(engine.snapshot, original)
        XCTAssertNotNil(store.setPlanReminder(created.planItem, startAt: now.addingTimeInterval(3600), at: now))
        let changed = engine.snapshot
        XCTAssertNil(store.setPlanReminder(created.planItem, startAt: now.addingTimeInterval(7200), at: now))
        XCTAssertEqual(engine.snapshot, changed)
        XCTAssertNotNil(store.errorMessage)
    }

    func testListExcludesPastDoneCanceledArchivedAndRunningPlans() throws {
        let active = V2Task(id: "active", title: "执行中", createdAt: now, updatedAt: now)
        let done = V2Task(id: "done", title: "已完成", status: .done, createdAt: now, updatedAt: now)
        let archived = V2Task(id: "archived", title: "归档", status: .archived, createdAt: now, updatedAt: now)
        let items: [V2PlanItem] = [
            .init(id: "untimed", date: now, title: "今日待安排"),
            .init(id: "future", date: now.addingTimeInterval(86400), title: "未来"),
            .init(id: "past", date: now.addingTimeInterval(-86400), title: "昨天"),
            .init(id: "done", date: now, taskID: done.id, title: done.title),
            .init(id: "archived", date: now, taskID: archived.id, title: archived.title),
            .init(id: "canceled", date: now, title: "取消", status: .canceled),
            .init(id: "completed", date: now, title: "完成", status: .completed),
            .init(id: "running", date: now, taskID: active.id, title: active.title)
        ]
        let engine = V2Engine(snapshot: .init(tasks: [active, done, archived], planItems: items))
        _ = try engine.startExecution(taskID: active.id, title: active.title,
                                      source: .normal, at: now, createdFromPlanItemID: "running")
        let store = V2AppStore(engine: engine, calendar: calendar)
        XCTAssertEqual(store.planReminderItems(at: now).map(\.id), ["untimed", "future"])
        XCTAssertNil(store.setPlanReminder(items.last!, startAt: now.addingTimeInterval(3600), at: now))
    }

    func testNotificationReplacementAndClearCancelOnlyOwnedRequests() async throws {
        let center = PlanNotificationFixture()
        let service = V2NotificationService(center: center)
        let item = V2PlanItem(id: "plan", date: now, startAt: now.addingTimeInterval(3600), title: "吃早饭")
        center.requests["finance-test"] = UNNotificationRequest(identifier: "finance-test", content: UNMutableNotificationContent(), trigger: nil)
        try await service.rebuildOwned(planItems: [item], now: now, calendar: calendar)
        let request = try XCTUnwrap(center.requests["v2-plan-plan"])
        XCTAssertEqual(request.content.title, "吃早饭")
        let trigger = try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)
        XCTAssertEqual(trigger.dateComponents.hour, 1)
        XCTAssertEqual(trigger.dateComponents.minute, 0)
        XCTAssertEqual(request.content.userInfo["planItemID"] as? String, "plan")
        var moved = item; moved.startAt = now.addingTimeInterval(7200)
        try await service.rebuildOwned(planItems: [moved], now: now, calendar: calendar)
        XCTAssertEqual((center.requests["v2-plan-plan"]?.trigger as? UNCalendarNotificationTrigger)?.dateComponents.hour, 2)
        moved.startAt = nil
        try await service.rebuildOwned(planItems: [moved], now: now, calendar: calendar)
        XCTAssertNil(center.requests["v2-plan-plan"])
        XCTAssertNotNil(center.requests["finance-test"])
    }

    func testDeniedPermissionPreservesSavedTimeAndHasNoNotification() async throws {
        let center = PlanNotificationFixture(); center.status = .denied
        let service = V2NotificationService(center: center)
        let engine = V2Engine()
        let created = try engine.quickInsertTodayTask(title: "早饭", at: now, calendar: calendar)
        let store = V2AppStore(engine: engine, notificationService: service, calendar: calendar)
        XCTAssertNotNil(store.setPlanReminder(created.planItem, startAt: now.addingTimeInterval(3600), at: now))
        do {
            _ = try await store.enablePlanReminders(at: now)
            XCTFail("Denied permission should not report enabled")
        } catch {
            XCTAssertEqual((error as? LocalizedError)?.errorDescription, V2NativeCapabilityError.notificationsDenied.errorDescription)
        }
        await store.scheduleReminderTask?.value
        XCTAssertEqual(engine.snapshot.planItems.first?.startAt, now.addingTimeInterval(3600))
        XCTAssertTrue(center.requests.isEmpty)
    }

    func testOnlyEarliest32FuturePlannedItemsAreScheduled() async throws {
        let center = PlanNotificationFixture()
        let service = V2NotificationService(center: center)
        var items = (1...40).reversed().map { minute in
            V2PlanItem(id: "\(minute)", date: now, startAt: now.addingTimeInterval(Double(minute * 60)), title: "任务 \(minute)")
        }
        items.append(.init(id: "past", date: now, startAt: now.addingTimeInterval(-60), title: "过期"))
        items.append(.init(id: "done", date: now, startAt: now.addingTimeInterval(30), title: "完成", status: .completed))
        let count = try await service.requestAndSchedule(planItems: items, now: now, calendar: calendar)
        XCTAssertEqual(count, 32)
        XCTAssertEqual(Set(center.requests.keys), Set((1...32).map { "v2-plan-\($0)" }))
    }

    func testUndoWhilePermissionDialogIsOpenDoesNotScheduleStaleTime() async throws {
        let center = PlanNotificationFixture()
        let service = V2NotificationService(center: center)
        let engine = V2Engine()
        let created = try engine.quickInsertTodayTask(title: "规划", at: now, calendar: calendar)
        let store = V2AppStore(engine: engine, notificationService: service, calendar: calendar)
        let receipt = try XCTUnwrap(store.setPlanReminder(created.planItem, startAt: now.addingTimeInterval(3600), at: now))
        center.onRequest = { XCTAssertTrue(store.undoTaskChange(receiptID: receipt.id, at: self.now)) }
        let count = try await store.enablePlanReminders(at: now)
        await store.scheduleReminderTask?.value
        XCTAssertEqual(count, 0)
        XCTAssertNil(engine.snapshot.planItems.first?.startAt)
        XCTAssertTrue(center.requests.isEmpty)
    }

    func testPreviouslyDeniedNotificationsCanRebuildSavedPlans() async throws {
        let center = PlanNotificationFixture(); center.status = .denied
        let service = V2NotificationService(center: center)
        let item = V2PlanItem(id: "plan", date: now, startAt: now.addingTimeInterval(3600), title: "规划")
        do {
            try await service.rebuildOwned(planItems: [item], now: now, calendar: calendar)
            XCTFail("Denied notifications must report pending")
        } catch {}
        center.status = .authorized
        try await service.rebuildOwned(planItems: [item], now: now, calendar: calendar)
        XCTAssertNotNil(center.requests["v2-plan-plan"])
    }

    func testReminderTimeSurvivesRestart() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = V2JSONSnapshotStore(fileURL: directory.appendingPathComponent("snapshot.json"))
        let engine = V2Engine(store: file)
        let created = try engine.quickInsertTodayTask(title: "早饭", at: now, calendar: calendar)
        let store = V2AppStore(engine: engine, calendar: calendar)
        let start = now.addingTimeInterval(3600)
        XCTAssertNotNil(store.setPlanReminder(created.planItem, startAt: start, at: now))
        let restored = try V2Engine.load(from: file)
        XCTAssertEqual(restored.snapshot.planItems.first?.id, created.planItem.id)
        XCTAssertEqual(restored.snapshot.planItems.first?.startAt, start)
        XCTAssertEqual(restored.snapshot.tasks.count, 1)
    }

    func testActualSystemNotificationIsQueued() async throws {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else {
            throw XCTSkip("System notification permission has not been granted on this test device")
        }
        let service = V2NotificationService()
        let current = Date()
        let start = Calendar.current.dateInterval(of: .minute, for: current)!.start.addingTimeInterval(120)
        let item = V2PlanItem(id: "native-reminder-" + UUID().uuidString,
            date: Calendar.current.startOfDay(for: start), startAt: start, title: "合成提醒测试")
        defer { service.cancel(planIDs: [item.id]) }
        let count = try await service.scheduleIfAuthorized(planItems: [item], now: current)
        XCTAssertEqual(count, 1)
        let pending = await center.pendingNotificationRequests()
        let request = try XCTUnwrap(pending.first { $0.identifier == "v2-plan-" + item.id })
        XCTAssertEqual(request.content.title, item.title)
        let trigger = try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)
        XCTAssertEqual(trigger.nextTriggerDate()?.timeIntervalSince1970, start.timeIntervalSince1970)
    }
}

@MainActor
private final class PlanNotificationFixture: V2PlanNotificationCenter {
    var status = UNAuthorizationStatus.authorized
    var requests: [String: UNNotificationRequest] = [:]
    var onRequest: (() -> Void)?
    func requestAuthorization() async throws -> Bool { onRequest?(); return status != .denied }
    func authorizationStatus() async -> UNAuthorizationStatus { status }
    func pendingRequests() async -> [UNNotificationRequest] { Array(requests.values) }
    func add(_ request: UNNotificationRequest) async throws { requests[request.identifier] = request }
    func remove(identifiers: [String]) { for id in identifiers { requests[id] = nil } }
}

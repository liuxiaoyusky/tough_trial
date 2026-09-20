import XCTest
import ToughTrialV2Core
@testable import ToughTrial

@MainActor
final class V2TodayQueueTests: XCTestCase {
    func testPausePromotesQueueHeadAndContinueCreatesNewSegment() throws {
        let engine = V2Engine()
        let base = Calendar.current.startOfDay(for: Date()).addingTimeInterval(3600)
        let a = try engine.quickInsertTodayTask(title: "A", at: base)
        let b = try engine.quickInsertTodayTask(title: "B", at: base)
        let store = V2AppStore(engine: engine)
        let aItem = try XCTUnwrap(store.state.timelineItems.first { $0.taskID == a.task.id })
        let bItem = try XCTUnwrap(store.state.timelineItems.first { $0.taskID == b.task.id })
        store.startTodayItem(aItem, at: base)
        store.startTodayItem(bItem, at: base.addingTimeInterval(60))
        let bSession = try XCTUnwrap(store.todayRunningSessions.first)
        XCTAssertEqual(bSession.taskID, b.task.id)
        XCTAssertTrue(store.todayPlannedItems.isEmpty)
        let aSegment = try XCTUnwrap(engine.snapshot.executionSegments.first { $0.taskID == a.task.id })
        store.pauseTodaySession(bSession.id, at: base.addingTimeInterval(120))
        XCTAssertEqual(store.todayRunningSessions.first?.taskID, a.task.id)
        XCTAssertEqual(engine.snapshot.executionSegments.first { $0.id == aSegment.id }?.startAt, base)
        XCTAssertEqual(engine.snapshot.executionSegments.count, 2)
        XCTAssertEqual(store.todayPlannedItems.first?.taskID, b.task.id)
        XCTAssertEqual(store.todayPlannedItems.first?.isDone, false)
        store.startTodayItem(bItem, at: base.addingTimeInterval(180))
        XCTAssertEqual(engine.snapshot.executionSegments.count, 3)
        XCTAssertEqual(store.todayRunningSessions.first?.totalElapsedSeconds, 60)
        store.refreshProjection(at: base.addingTimeInterval(240))
        XCTAssertEqual(store.todayRunningSessions.first?.totalElapsedSeconds, 120)
    }

    func testCompleteRetainsPlanAndRestoreDoesNotStartTimer() throws {
        let engine = V2Engine()
        let now = Date()
        let created = try engine.quickInsertTodayTask(title: "完成测试", at: now)
        let store = V2AppStore(engine: engine)
        let item = try XCTUnwrap(store.state.timelineItems.first { $0.taskID == created.task.id })
        store.startTodayItem(item, at: now)
        store.completeTodaySession(try XCTUnwrap(store.todayRunningSessions.first), at: now.addingTimeInterval(60))
        XCTAssertTrue(store.todayRunningSessions.isEmpty)
        let completed = try XCTUnwrap(store.todayPlannedItems.first)
        XCTAssertTrue(completed.isDone)
        XCTAssertEqual(engine.snapshot.executionSegments.first?.endAt, now.addingTimeInterval(60))
        store.restoreTodayItem(completed, at: now.addingTimeInterval(70))
        XCTAssertEqual(store.todayPlannedItems.first?.isDone, false)
        XCTAssertTrue(store.todayRunningSessions.isEmpty)
    }

    func testLifetimeIncludesYesterdayButTodayDoesNot() throws {
        let engine = V2Engine()
        let dayStart = Calendar.current.startOfDay(for: Date())
        let now = dayStart.addingTimeInterval(3600)
        let created = try engine.quickInsertTodayTask(title: "跨天", at: now)
        let old = try engine.startExecution(taskID: created.task.id, title: "跨天", source: .normal, at: dayStart.addingTimeInterval(-120))
        try engine.stopExecutionSession(sessionID: old.logicalSessionID, at: dayStart.addingTimeInterval(-60))
        let store = V2AppStore(engine: engine)
        store.refreshProjection(at: now)
        store.startTodayItem(try XCTUnwrap(store.state.timelineItems.first), at: now)
        store.refreshProjection(at: now.addingTimeInterval(30))
        let active = try XCTUnwrap(store.todayRunningSessions.first)
        XCTAssertEqual(active.totalElapsedSeconds, 30)
        XCTAssertEqual(store.lifetimeSeconds(for: active, at: now.addingTimeInterval(30)), 90)
    }
}

import XCTest
import ToughTrialV2Core
@testable import ToughTrial

@MainActor
final class V2TodayQueueTests: XCTestCase {
    func testTaskListGroupsFollowExecutionCompletionRestoreAndUndo() throws {
        let engine = V2Engine()
        let now = Date()
        let a = try engine.quickInsertTodayTask(title: "写作", at: now)
        let b = try engine.quickInsertTodayTask(title: "资料", at: now)
        let c = try engine.quickInsertTodayTask(title: "阅读", at: now)
        let store = V2AppStore(engine: engine)
        func ids(_ group: V2TaskListGroup) -> Set<String> {
            let started = Set(engine.snapshot.executionSegments.compactMap(\.taskID))
            return Set(store.state.flattenTasks().filter { $0.status.listGroup(hasExecution: started.contains($0.id)) == group }.map(\.id))
        }
        XCTAssertEqual(ids(.notStarted), [a.task.id, b.task.id, c.task.id])
        let aItem = try XCTUnwrap(store.state.timelineItems.first { $0.taskID == a.task.id })
        let bItem = try XCTUnwrap(store.state.timelineItems.first { $0.taskID == b.task.id })
        store.startTodayItem(aItem, at: now)
        store.startTodayItem(bItem, at: now.addingTimeInterval(1))
        XCTAssertEqual(ids(.inProgress), [a.task.id, b.task.id])
        XCTAssertEqual(ids(.notStarted), [c.task.id])
        store.pauseTodaySession(try XCTUnwrap(store.todayRunningSessions.first { $0.taskID == b.task.id }).id,
                                at: now.addingTimeInterval(2))
        XCTAssertEqual(store.state.flattenTasks().first { $0.id == b.task.id }?.status, .planned)
        XCTAssertEqual(ids(.inProgress), [a.task.id, b.task.id])
        let completed = try XCTUnwrap(store.setTaskCompletion(taskID: b.task.id, completed: true, at: now.addingTimeInterval(3)))
        XCTAssertEqual(ids(.completed), [b.task.id])
        XCTAssertEqual(ids(.inProgress), [a.task.id])
        XCTAssertTrue(store.undoTaskChange(receiptID: completed.id, at: now.addingTimeInterval(4)))
        XCTAssertEqual(store.state.flattenTasks().first { $0.id == b.task.id }?.status, .planned)
        XCTAssertEqual(ids(.inProgress), [a.task.id, b.task.id])
        XCTAssertNotNil(store.setTaskCompletion(taskID: b.task.id, completed: true, at: now.addingTimeInterval(5)))
        XCTAssertNotNil(store.setTaskCompletion(taskID: b.task.id, completed: false, at: now.addingTimeInterval(6)))
        XCTAssertEqual(ids(.notStarted), [c.task.id])
        XCTAssertEqual(ids(.inProgress), [a.task.id, b.task.id])
        XCTAssertEqual(store.todayRunningSessions.map(\.taskID), [a.task.id])

        // Completion wins over a retained open timer; grouping must not close that timer.
        XCTAssertNotNil(store.setTaskCompletion(taskID: a.task.id, completed: true, at: now.addingTimeInterval(7)))
        XCTAssertEqual(ids(.completed), [a.task.id])
        XCTAssertEqual(ids(.inProgress), [b.task.id])
        XCTAssertNil(engine.snapshot.executionSegments.first { $0.taskID == a.task.id }?.endAt)
    }

    func testTaskListGroupsRetainExplicitPauseAndRestoredExecutionHistory() throws {
        let engine = V2Engine()
        let now = Date()
        let task = try engine.createTask(title: "真正暂停的任务", at: now)
        let execution = try engine.startExecution(taskID: task.id, title: task.title, source: .normal, at: now)
        try engine.pauseExecutionSession(sessionID: execution.logicalSessionID, at: now.addingTimeInterval(1))
        let store = V2AppStore(engine: engine)
        let paused = try XCTUnwrap(store.state.flattenTasks().first)
        XCTAssertEqual(paused.status, .paused)
        XCTAssertEqual(paused.status.listGroup(hasExecution: true), .inProgress)
        XCTAssertNotNil(store.setTaskCompletion(taskID: task.id, completed: true, at: now.addingTimeInterval(2)))
        XCTAssertEqual(store.state.flattenTasks().first?.status.listGroup(hasExecution: true), .completed)
        XCTAssertNotNil(store.setTaskCompletion(taskID: task.id, completed: false, at: now.addingTimeInterval(3)))
        XCTAssertEqual(store.state.flattenTasks().first?.status.listGroup(hasExecution: true), .inProgress)
        XCTAssertTrue(store.todayRunningSessions.isEmpty)
        XCTAssertEqual(engine.snapshot.executionSegments.count, 1)
    }

    func testTaskListGroupsKeepEveryChildOnceAndExcludeArchivedTasks() throws {
        let engine = V2Engine()
        let now = Date()
        let parent = try engine.createTask(title: "学习", at: now)
        let child = try engine.createTask(title: "练习", parentID: parent.id, at: now)
        let archived = try engine.createTask(title: "旧任务", at: now)
        try engine.archiveTask(id: archived.id, at: now)
        try engine.completeTask(id: child.id, at: now)
        let store = V2AppStore(engine: engine)
        let flat = store.state.flattenTasks()
        let grouped = V2TaskListGroup.allCases.flatMap { group in flat.filter { $0.status.listGroup == group } }
        XCTAssertEqual(grouped.map(\.id), [parent.id, child.id])
        XCTAssertEqual(Set(grouped.map(\.id)).count, grouped.count)
        XCTAssertEqual(engine.snapshot.tasks.first { $0.id == child.id }?.parentID, parent.id)
        XCTAssertNil(engine.snapshot.tasks.first { $0.id == archived.id }?.status.listGroup)
        XCTAssertEqual(V2TaskListGroup.allCases, [.inProgress, .notStarted, .completed])
    }

    func testUnifiedTimelineKeepsOtherRunningWorkAndQuietCompletedItems() throws {
        let engine = V2Engine()
        let now = Calendar.current.startOfDay(for: Date()).addingTimeInterval(3600)
        let a = try engine.quickInsertTodayTask(title: "A", at: now)
        let b = try engine.quickInsertTodayTask(title: "B", at: now)
        let c = try engine.quickInsertTodayTask(title: "C", at: now)
        let store = V2AppStore(engine: engine)
        let aItem = try XCTUnwrap(store.state.timelineItems.first { $0.taskID == a.task.id })
        let bItem = try XCTUnwrap(store.state.timelineItems.first { $0.taskID == b.task.id })
        store.startTodayItem(aItem, at: now)
        store.startTodayItem(bItem, at: now.addingTimeInterval(60))
        let aSegment = try XCTUnwrap(engine.snapshot.executionSegments.first { $0.taskID == a.task.id })
        XCTAssertEqual(Set(store.todayTimelineItems.compactMap(\.taskID)), [a.task.id, c.task.id])
        XCTAssertEqual(store.todayRunningSession(for: aItem)?.id, aSegment.logicalSessionID)
        XCTAssertNil(store.todayRunningSession(for: try XCTUnwrap(store.todayTimelineItems.first { $0.taskID == c.task.id })))

        store.completeTodaySession(try XCTUnwrap(store.todayRunningSessions.first), at: now.addingTimeInterval(120))
        XCTAssertEqual(store.todayRunningSessions.first?.taskID, a.task.id)
        XCTAssertNil(engine.snapshot.executionSegments.first { $0.id == aSegment.id }?.endAt)
        let completed = try XCTUnwrap(store.todayTimelineItems.first { $0.taskID == b.task.id })
        XCTAssertTrue(completed.isDone)
        XCTAssertNil(store.state.selectedTimelineItemID)
        XCTAssertEqual(Set(store.todayTimelineItems.compactMap(\.taskID)), [b.task.id, c.task.id])
        store.restoreTodayItem(completed, at: now.addingTimeInterval(130))
        XCTAssertEqual(store.todayTimelineItems.first { $0.taskID == b.task.id }?.isDone, false)
        XCTAssertEqual(store.todayRunningSessions.count, 1)
        XCTAssertEqual(engine.snapshot.executionSegments.count, 2)
    }

    func testUnifiedTimelineMatchesOtherUnlinkedSession() throws {
        let engine = V2Engine()
        let now = Date()
        let a = try engine.startExecution(taskID: nil, title: "自由专注 A", source: .normal, at: now)
        let b = try engine.startExecution(taskID: nil, title: "自由专注 B", source: .normal, at: now.addingTimeInterval(1))
        let store = V2AppStore(engine: engine)
        store.refreshProjection(at: now.addingTimeInterval(2))
        let primary = try XCTUnwrap(store.todayRunningSessions.first)
        let otherID = primary.id == a.logicalSessionID ? b.logicalSessionID : a.logicalSessionID
        let other = try XCTUnwrap(store.todayTimelineItems.first)
        XCTAssertEqual(store.todayTimelineItems.count, 1)
        XCTAssertEqual(other.kind, .executionRecord)
        XCTAssertEqual(store.todayRunningSession(for: other)?.id, otherID)
        store.pauseTodaySession(primary.id, at: now.addingTimeInterval(3))
        XCTAssertEqual(store.todayRunningSessions.first?.id, otherID)
        XCTAssertEqual(store.todayTimelineItems.count, 1)
        XCTAssertNil(store.todayRunningSession(for: try XCTUnwrap(store.todayTimelineItems.first)))
    }

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
        XCTAssertEqual(store.todayTimelineItems.map(\.taskID), [a.task.id])
        let aSegment = try XCTUnwrap(engine.snapshot.executionSegments.first { $0.taskID == a.task.id })
        store.pauseTodaySession(bSession.id, at: base.addingTimeInterval(120))
        XCTAssertEqual(store.todayRunningSessions.first?.taskID, a.task.id)
        XCTAssertEqual(engine.snapshot.executionSegments.first { $0.id == aSegment.id }?.startAt, base)
        XCTAssertEqual(engine.snapshot.executionSegments.count, 2)
        XCTAssertEqual(store.todayTimelineItems.first?.taskID, b.task.id)
        XCTAssertEqual(store.todayTimelineItems.first?.isDone, false)
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
        let completed = try XCTUnwrap(store.todayTimelineItems.first)
        XCTAssertTrue(completed.isDone)
        XCTAssertEqual(engine.snapshot.executionSegments.first?.endAt, now.addingTimeInterval(60))
        store.restoreTodayItem(completed, at: now.addingTimeInterval(70))
        XCTAssertEqual(store.todayTimelineItems.first?.isDone, false)
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

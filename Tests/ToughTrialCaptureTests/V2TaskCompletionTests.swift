import XCTest
import ToughTrialV2Core

final class V2TaskCompletionTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private func date(dayOffset: Int = 0, hour: Int = 9) -> Date {
        let base = calendar.date(from: DateComponents(year: 2026, month: 9, day: 11, hour: hour))!
        return calendar.date(byAdding: .day, value: dayOffset, to: base)!
    }

    private func snapshot(
        taskStatus: V2Task.Status,
        completedAt: Date?,
        sameDayStatuses: [V2PlanItem.Status],
        futureStatus: V2PlanItem.Status,
        withOpenExecution: Bool
    ) -> V2AppSnapshot {
        let now = date(hour: 9)
        let day = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: day)!
        let context = V2TaskContext(
            id: "context",
            title: "上下文",
            colorName: "blue",
            createdAt: now,
            updatedAt: now
        )
        let parent = V2Task(
            id: "parent",
            contextID: context.id,
            title: "父任务",
            createdAt: now,
            updatedAt: now
        )
        let task = V2Task(
            id: "task",
            contextID: context.id,
            parentID: parent.id,
            title: "目标任务",
            note: "原备注",
            kind: .commitment,
            status: taskStatus,
            createdAt: now,
            updatedAt: now,
            completedAt: completedAt
        )
        let child = V2Task(
            id: "child",
            contextID: context.id,
            parentID: task.id,
            title: "子任务",
            createdAt: now,
            updatedAt: now
        )
        let todayItems = sameDayStatuses.enumerated().map { index, status in
            V2PlanItem(
                id: "today-" + String(index),
                date: day,
                taskID: task.id,
                title: "今日排期 " + String(index),
                status: status
            )
        }
        let future = V2PlanItem(
            id: "future",
            date: tomorrow,
            taskID: task.id,
            title: "未来排期",
            status: futureStatus
        )
        let unrelated = V2PlanItem(
            id: "unrelated",
            date: day,
            taskID: parent.id,
            title: "其他任务"
        )
        let execution = V2ExecutionSegment(
            id: "open-segment",
            taskID: task.id,
            titleSnapshot: task.title,
            startAt: now.addingTimeInterval(-600),
            source: .normal
        )
        return V2AppSnapshot(
            taskContexts: [context],
            tasks: [parent, task, child],
            planItems: todayItems + [future, unrelated],
            executionSegments: withOpenExecution ? [execution] : []
        )
    }

    private func engine(for snapshot: V2AppSnapshot, store: V2JSONSnapshotStore? = nil) -> V2Engine {
        V2Engine(snapshot: snapshot, store: store, reconcileExecutions: false)
    }

    private func temporaryStore() -> (root: URL, store: V2JSONSnapshotStore) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("tough-trial-task-completion-\(UUID().uuidString)", isDirectory: true)
        return (root, V2JSONSnapshotStore(fileURL: root.appendingPathComponent("snapshot.json")))
    }

    func testCompletesAllSameDayItemsPreservesFutureAndLeavesExecutionOpen() throws {
        let at = date(hour: 18)
        let before = snapshot(
            taskStatus: .active,
            completedAt: nil,
            sameDayStatuses: [.planned, .convertedToExecution, .canceled, .completed],
            futureStatus: .planned,
            withOpenExecution: true
        )
        let engine = engine(for: before)

        let receipt = try engine.setTaskCompletion(taskID: "task", completed: true, at: at, calendar: calendar)

        XCTAssertEqual(engine.snapshot.tasks.first(where: { $0.id == "task" })?.status, .done)
        XCTAssertEqual(engine.snapshot.tasks.first(where: { $0.id == "task" })?.completedAt, at)
        XCTAssertEqual(
            engine.snapshot.planItems.filter { $0.taskID == "task" && calendar.isDate($0.date, inSameDayAs: at) }
                .sorted { $0.id < $1.id }.map(\.status),
            [.completed, .completed, .canceled, .completed]
        )
        XCTAssertEqual(engine.snapshot.planItems.first(where: { $0.id == "future" })?.status, .planned)
        XCTAssertEqual(engine.snapshot.planItems.first(where: { $0.id == "unrelated" })?.status, .planned)
        XCTAssertEqual(engine.snapshot.tasks.first(where: { $0.id == "child" })?.status, .notStarted)
        XCTAssertEqual(engine.snapshot.executionSegments, before.executionSegments)
        XCTAssertNil(engine.snapshot.executionSegments.first?.endAt)
        XCTAssertEqual(Set(receipt.changes.map(\.entityID)), ["task", "today-0", "today-1"])
        XCTAssertTrue(receipt.requestID.hasPrefix("task-completion:"))
    }

    func testRestoreOnlyChangesSameDayItemsAndKeepsOpenExecution() throws {
        let doneAt = date(hour: 12)
        let restoreAt = date(hour: 18)
        let before = snapshot(
            taskStatus: .done,
            completedAt: doneAt,
            sameDayStatuses: [.completed, .convertedToExecution, .canceled, .planned],
            futureStatus: .completed,
            withOpenExecution: true
        )
        let engine = engine(for: before)

        let receipt = try engine.setTaskCompletion(taskID: "task", completed: false, at: restoreAt, calendar: calendar)

        XCTAssertEqual(engine.snapshot.tasks.first(where: { $0.id == "task" })?.status, .active)
        XCTAssertNil(engine.snapshot.tasks.first(where: { $0.id == "task" })?.completedAt)
        XCTAssertEqual(
            engine.snapshot.planItems.filter { $0.taskID == "task" && calendar.isDate($0.date, inSameDayAs: restoreAt) }
                .sorted { $0.id < $1.id }.map(\.status),
            [.planned, .planned, .canceled, .planned]
        )
        XCTAssertEqual(engine.snapshot.planItems.first(where: { $0.id == "future" })?.status, .completed)
        XCTAssertEqual(engine.snapshot.executionSegments, before.executionSegments)
        XCTAssertNil(engine.snapshot.executionSegments.first?.endAt)
        XCTAssertEqual(Set(receipt.changes.map(\.entityID)), ["task", "today-0", "today-1"])
    }

    func testReceiptSurvivesReloadUndoRestoresStateAndLaterEditConflicts() throws {
        let at = date(hour: 18)
        let initial = snapshot(
            taskStatus: .active,
            completedAt: nil,
            sameDayStatuses: [.planned, .convertedToExecution, .canceled],
            futureStatus: .planned,
            withOpenExecution: true
        )
        let (root, store) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: root) }
        try store.save(initial)

        let engine = try V2Engine.load(from: store)
        let receipt = try engine.setTaskCompletion(taskID: "task", completed: true, at: at, calendar: calendar)
        let reloaded = try V2Engine.load(from: store)
        let undone = try reloaded.undoScheduleReceipt(id: receipt.id, at: date(hour: 19))

        XCTAssertEqual(undone.id, receipt.id)
        XCTAssertNotNil(undone.undoneAt)
        let restored = try V2Engine.load(from: store)
        XCTAssertEqual(restored.snapshot.tasks, initial.tasks)
        XCTAssertEqual(restored.snapshot.planItems, initial.planItems)
        XCTAssertEqual(restored.snapshot.executionSegments, initial.executionSegments)
        XCTAssertEqual(restored.snapshot.scheduleReceipts.first?.id, receipt.id)
        XCTAssertNotNil(restored.snapshot.scheduleReceipts.first?.undoneAt)

        try store.save(initial)
        let conflictingEngine = try V2Engine.load(from: store)
        let conflictingReceipt = try conflictingEngine.setTaskCompletion(
            taskID: "task", completed: true, at: at, calendar: calendar
        )
        let current = try XCTUnwrap(conflictingEngine.snapshot.tasks.first(where: { $0.id == "task" }))
        _ = try conflictingEngine.updateTask(
            id: current.id,
            title: "后续编辑",
            note: current.note,
            parentID: current.parentID,
            contextID: current.contextID,
            kind: current.kind,
            at: date(hour: 20)
        )

        XCTAssertThrowsError(try conflictingEngine.undoScheduleReceipt(id: conflictingReceipt.id, at: date(hour: 21))) { error in
            XCTAssertEqual(error as? V2EngineError, .scheduleReceiptConflict("task"))
        }
        XCTAssertEqual(conflictingEngine.snapshot.tasks.first(where: { $0.id == "task" })?.title, "后续编辑")
        XCTAssertNil(conflictingEngine.snapshot.scheduleReceipts.first?.undoneAt)
        let persistedConflict = try V2Engine.load(from: store)
        XCTAssertEqual(persistedConflict.snapshot.tasks.first(where: { $0.id == "task" })?.title, "后续编辑")
        XCTAssertNil(persistedConflict.snapshot.scheduleReceipts.first?.undoneAt)
    }

    func testPersistenceFailureDoesNotPartiallyWriteCompletion() throws {
        let at = date(hour: 18)
        let initial = snapshot(
            taskStatus: .active,
            completedAt: nil,
            sameDayStatuses: [.planned],
            futureStatus: .planned,
            withOpenExecution: true
        )
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("tough-trial-task-completion-block-\(UUID().uuidString)")
        try Data("blocker".utf8).write(to: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let engine = engine(
            for: initial,
            store: V2JSONSnapshotStore(fileURL: root.appendingPathComponent("snapshot.json"))
        )

        XCTAssertThrowsError(try engine.setTaskCompletion(taskID: "task", completed: true, at: at, calendar: calendar))
        XCTAssertEqual(engine.snapshot, initial)
    }

    func testSameStateCompletionIsIdempotentWithReusableEmptyReceipt() throws {
        let at = date(hour: 18)
        let initial = snapshot(
            taskStatus: .active,
            completedAt: nil,
            sameDayStatuses: [.planned, .canceled],
            futureStatus: .planned,
            withOpenExecution: false
        )
        let engine = engine(for: initial)

        let first = try engine.setTaskCompletion(taskID: "task", completed: true, at: at, calendar: calendar)
        let firstTask = try XCTUnwrap(engine.snapshot.tasks.first(where: { $0.id == "task" }))
        let second = try engine.setTaskCompletion(
            taskID: "task", completed: true, at: at.addingTimeInterval(60), calendar: calendar
        )
        let third = try engine.setTaskCompletion(
            taskID: "task", completed: true, at: at.addingTimeInterval(120), calendar: calendar
        )

        XCTAssertFalse(first.changes.isEmpty)
        XCTAssertTrue(second.changes.isEmpty)
        XCTAssertEqual(third.id, second.id)
        XCTAssertEqual(engine.snapshot.tasks.first(where: { $0.id == "task" }), firstTask)
        XCTAssertEqual(engine.snapshot.planItems.filter { $0.taskID == "task" }.first?.status, .completed)
        XCTAssertEqual(engine.snapshot.scheduleReceipts.count, 2)
    }

    func testMissingAndArchivedTasksAreRejected() throws {
        let at = date(hour: 18)
        let testEngine = engine(for: snapshot(
            taskStatus: .active,
            completedAt: nil,
            sameDayStatuses: [],
            futureStatus: .planned,
            withOpenExecution: false
        ))

        XCTAssertThrowsError(try testEngine.setTaskCompletion(taskID: "missing", completed: true, at: at, calendar: calendar)) { error in
            XCTAssertEqual(error as? V2EngineError, .taskNotFound("missing"))
        }

        let archivedTask = V2Task(
            id: "archived",
            title: "已归档",
            status: .archived,
            createdAt: at,
            updatedAt: at,
            archivedAt: at
        )
        let archivedEngine = self.engine(for: V2AppSnapshot(tasks: [archivedTask]))
        XCTAssertThrowsError(try archivedEngine.setTaskCompletion(taskID: archivedTask.id, completed: false, at: at, calendar: calendar)) { error in
            XCTAssertEqual(error as? V2EngineError, .taskArchived(archivedTask.id))
        }
    }
}

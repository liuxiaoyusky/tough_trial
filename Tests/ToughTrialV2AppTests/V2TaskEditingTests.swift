import XCTest
import ToughTrialV2Core
@testable import ToughTrial

@MainActor
final class V2TaskEditingTests: XCTestCase {
    func testEditPreservesIdentityPlacementExecutionAndCanUndo() throws {
        let engine = V2Engine()
        let context = try engine.createTaskContext(title: "学习", colorName: "blue")
        let parent = try engine.createTask(title: "目标", contextID: context.id)
        let created = try engine.createTask(title: "原任务", parentID: parent.id, kind: .commitment, note: "原备注")
        _ = try engine.startExecution(taskID: created.id, title: created.title, source: .normal)
        let original = try XCTUnwrap(engine.snapshot.tasks.first { $0.id == created.id })
        let execution = engine.snapshot.executionSegments
        let store = V2AppStore(engine: engine)
        let receipt = try XCTUnwrap(store.editTask(original, title: "新标题", note: "新备注"))
        let edited = try XCTUnwrap(engine.snapshot.tasks.first { $0.id == original.id })
        XCTAssertEqual(edited.title, "新标题")
        XCTAssertEqual(edited.note, "新备注")
        XCTAssertEqual(edited.parentID, original.parentID)
        XCTAssertEqual(edited.contextID, original.contextID)
        XCTAssertEqual(edited.kind, original.kind)
        XCTAssertEqual(edited.status, original.status)
        XCTAssertEqual(engine.snapshot.tasks.count, 2)
        XCTAssertEqual(engine.snapshot.executionSegments, execution)
        XCTAssertTrue(store.undoTaskChange(receiptID: receipt.id))
        XCTAssertEqual(engine.snapshot.tasks.first { $0.id == original.id }, original)
    }

    func testStaleOrBlankEditCannotOverwriteLaterData() throws {
        let engine = V2Engine()
        let original = try engine.createTask(title: "原任务")
        let store = V2AppStore(engine: engine)
        XCTAssertNil(store.editTask(original, title: " \n ", note: "不可写"))
        XCTAssertEqual(engine.snapshot.tasks.first, original)
        XCTAssertNotNil(store.editTask(original, title: "其他入口的新内容", note: ""))
        let before = engine.snapshot
        XCTAssertNil(store.editTask(original, title: "旧草稿", note: "不可覆盖"))
        XCTAssertEqual(engine.snapshot, before)
        XCTAssertNotNil(store.errorMessage)
    }

    func testTaskCreationRetainsNoteAndDoesNotAddSchedule() throws {
        let engine = V2Engine()
        let parent = try engine.createTask(title: "父任务")
        let store = V2AppStore(engine: engine)
        XCTAssertTrue(store.createTaskFromTasks(title: "新增", note: "备注", parentTaskID: parent.id))
        let task = try XCTUnwrap(engine.snapshot.tasks.last)
        XCTAssertEqual(task.note, "备注")
        XCTAssertEqual(task.parentID, parent.id)
        XCTAssertTrue(engine.snapshot.planItems.isEmpty)
    }

    func testArchivedTaskCannotBeEditedAndUndoPreservesLaterChanges() throws {
        let engine = V2Engine()
        let original = try engine.createTask(title: "原任务")
        let store = V2AppStore(engine: engine)
        let receipt = try XCTUnwrap(store.editTask(original, title: "已改", note: ""))
        try engine.archiveTask(id: original.id)
        let before = engine.snapshot
        XCTAssertNil(store.editTask(original, title: "覆盖归档", note: ""))
        XCTAssertFalse(store.undoTaskChange(receiptID: receipt.id))
        XCTAssertEqual(engine.snapshot, before)
    }
    func testRenameRefreshesTodayAndCalendarWithoutRewritingHistory() throws {
        let engine = V2Engine()
        let date = Date()
        let pair = try engine.quickInsertTodayTask(title: "旧名称", at: date)
        let store = V2AppStore(engine: engine)
        XCTAssertNotNil(store.editTask(pair.task, title: "新名称", note: "", at: date))
        XCTAssertEqual(store.state.timelineItems.first { $0.taskID == pair.task.id }?.title, "新名称")
        XCTAssertEqual(store.state.scheduledTasks.first { $0.taskID == pair.task.id }?.title, "新名称")
        XCTAssertEqual(engine.snapshot.planItems.first?.title, "旧名称", "Keep the original schedule record")
    }

    func testEditPersistsAcrossReloadAndStorageFailureKeepsOriginal() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let disk = V2JSONSnapshotStore(fileURL: folder.appendingPathComponent("tasks.json"))
        let engine = V2Engine(store: disk)
        let original = try engine.createTask(title: "原任务")
        let store = V2AppStore(engine: engine)
        XCTAssertNotNil(store.editTask(original, title: "持久修改", note: "持久备注"))
        let loaded = try V2Engine.load(from: disk)
        XCTAssertEqual(loaded.snapshot.tasks.first?.id, original.id)
        XCTAssertEqual(loaded.snapshot.tasks.first?.title, "持久修改")
        XCTAssertEqual(loaded.snapshot.tasks.first?.note, "持久备注")
        let broken = V2Engine(snapshot: loaded.snapshot, store: V2JSONSnapshotStore(fileURL: folder))
        let brokenStore = V2AppStore(engine: broken)
        let baseline = broken.snapshot
        XCTAssertNil(brokenStore.editTask(try XCTUnwrap(baseline.tasks.first), title: "失败修改", note: ""))
        XCTAssertEqual(broken.snapshot, baseline)
        XCTAssertNotNil(brokenStore.errorMessage)
    }

    func testUnifiedEntryNotesPreserveTodayAndSelectedDateDefaults() throws {
        let engine = V2Engine()
        let store = V2AppStore(engine: engine)
        let now = Date()
        let future = Calendar.current.date(byAdding: .day, value: 3, to: now)!
        XCTAssertTrue(store.quickAddTodayTask(title: "今日", note: "今日备注", at: now))
        XCTAssertTrue(store.quickAddScheduledTask(title: "未来", note: "未来备注", on: future))
        XCTAssertEqual(engine.snapshot.tasks.map(\.note), ["今日备注", "未来备注"])
        XCTAssertEqual(engine.snapshot.planItems.map(\.date), [Calendar.current.startOfDay(for: now), Calendar.current.startOfDay(for: future)])
        XCTAssertTrue(store.createTaskFromTasks(title: "收件箱", note: "不排期", parentTaskID: nil))
        XCTAssertEqual(engine.snapshot.tasks.last?.note, "不排期")
        XCTAssertEqual(engine.snapshot.planItems.count, 2)
    }

    func testTaskKindClassificationOnlyChangesCurrentTaskAndCanUndo() throws {
        let engine = V2Engine()
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let context = try engine.createTaskContext(title: "写作", colorName: "blue", at: date)
        let parent = try engine.createTask(title: "长期目标", contextID: context.id, kind: .goal, at: date)
        let target = try engine.createTask(
            title: "整理章节",
            parentID: parent.id,
            kind: .commitment,
            note: "保留原文",
            at: date
        )
        let descendant = try engine.createTask(
            title: "校对引文",
            parentID: target.id,
            kind: .maintenance,
            note: "子任务",
            at: date
        )
        let planItem = try engine.addTaskToToday(taskID: target.id, date: date)
        _ = try engine.startExecution(taskID: target.id, title: target.title, source: .normal, at: date)
        let original = try XCTUnwrap(engine.snapshot.tasks.first { $0.id == target.id })
        let originalDescendant = try XCTUnwrap(engine.snapshot.tasks.first { $0.id == descendant.id })
        let originalSegments = engine.snapshot.executionSegments
        let originalPlanItems = engine.snapshot.planItems

        let store = V2AppStore(engine: engine)
        let receipt = try XCTUnwrap(store.editTask(
            original,
            title: original.title,
            note: original.note,
            classification: V2TaskClassification(kind: .goal),
            at: date.addingTimeInterval(60)
        ))
        let edited = try XCTUnwrap(engine.snapshot.tasks.first { $0.id == target.id })

        XCTAssertEqual(edited.kind, .goal)
        XCTAssertEqual(edited.id, original.id)
        XCTAssertEqual(edited.title, original.title)
        XCTAssertEqual(edited.note, original.note)
        XCTAssertEqual(edited.parentID, original.parentID)
        XCTAssertEqual(edited.contextID, original.contextID)
        XCTAssertEqual(edited.status, original.status)
        XCTAssertEqual(edited.createdAt, original.createdAt)
        XCTAssertEqual(edited.archivedAt, original.archivedAt)
        XCTAssertEqual(edited.completedAt, original.completedAt)
        XCTAssertEqual(edited.sourceReference, original.sourceReference)
        XCTAssertEqual(edited.updatedAt, date.addingTimeInterval(60))
        XCTAssertEqual(engine.snapshot.tasks.first { $0.id == descendant.id }, originalDescendant)
        XCTAssertEqual(engine.snapshot.executionSegments, originalSegments)
        XCTAssertEqual(engine.snapshot.planItems, originalPlanItems)
        XCTAssertTrue(receipt.changes.allSatisfy { $0.entityID == target.id })
        XCTAssertEqual(planItem, originalPlanItems.first)

        XCTAssertTrue(store.undoTaskChange(receiptID: receipt.id))
        XCTAssertEqual(engine.snapshot.tasks.first { $0.id == target.id }, original)
        XCTAssertEqual(engine.snapshot.tasks.first { $0.id == descendant.id }, originalDescendant)
    }

    func testTaskKindCanBeClearedToUnclassified() throws {
        let engine = V2Engine()
        let original = try engine.createTask(title: "待整理", kind: .commitment)
        let store = V2AppStore(engine: engine)

        let receipt = try XCTUnwrap(store.editTask(
            original,
            title: original.title,
            note: original.note,
            classification: V2TaskClassification(kind: nil)
        ))
        XCTAssertNil(engine.snapshot.tasks.first { $0.id == original.id }?.kind)
        XCTAssertTrue(store.undoTaskChange(receiptID: receipt.id))
        XCTAssertEqual(engine.snapshot.tasks.first { $0.id == original.id }?.kind, .commitment)
    }

    func testStaleKindClassificationCannotOverwriteLaterChange() throws {
        let engine = V2Engine()
        let original = try engine.createTask(title: "原任务", kind: .commitment)
        let store = V2AppStore(engine: engine)
        _ = try engine.updateTask(
            id: original.id,
            title: original.title,
            note: "后来修改",
            parentID: original.parentID,
            contextID: original.contextID,
            kind: .maintenance
        )
        let before = engine.snapshot

        XCTAssertNil(store.editTask(
            original,
            title: "旧草稿",
            note: original.note,
            classification: V2TaskClassification(kind: .goal)
        ))
        XCTAssertEqual(engine.snapshot, before)
        XCTAssertTrue(store.errorMessage?.contains("其他地方修改") == true)
    }

    func testKindClassificationUndoRefusesToOverwriteLaterEdit() throws {
        let engine = V2Engine()
        let original = try engine.createTask(title: "原任务", kind: .commitment)
        let store = V2AppStore(engine: engine)
        let receipt = try XCTUnwrap(store.editTask(
            original,
            title: original.title,
            note: original.note,
            classification: V2TaskClassification(kind: .goal)
        ))
        let classified = try XCTUnwrap(engine.snapshot.tasks.first { $0.id == original.id })
        XCTAssertNotNil(store.editTask(classified, title: "后续标题", note: classified.note))

        XCTAssertFalse(store.undoTaskChange(receiptID: receipt.id))
        XCTAssertEqual(engine.snapshot.tasks.first { $0.id == original.id }?.kind, .goal)
        XCTAssertEqual(engine.snapshot.tasks.first { $0.id == original.id }?.title, "后续标题")
    }

}

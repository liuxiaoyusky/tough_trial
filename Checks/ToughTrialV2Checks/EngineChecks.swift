import Foundation
import ToughTrialV2Core

func checkEngineTaskTreeAndCompletion() throws {
    let engine = V2Engine()
    let base = Date(timeIntervalSince1970: 1_800_000_000)
    let context = try engine.createTaskContext(
        title: "Creator growth",
        colorName: "blue",
        at: base
    )
    let root = try engine.createTask(
        title: "Stable praise",
        contextID: context.id,
        kind: .goal,
        at: base
    )
    let branch = try engine.createTask(
        title: "Topic library",
        parentID: root.id,
        contextID: context.id,
        at: base.addingTimeInterval(1)
    )
    let doneLeaf = try engine.createTask(
        title: "Create benchmark accounts",
        parentID: branch.id,
        contextID: context.id,
        at: base.addingTimeInterval(2)
    )
    _ = try engine.createTask(
        title: "Collect benchmark hits",
        parentID: branch.id,
        contextID: context.id,
        at: base.addingTimeInterval(3)
    )
    let directDoneLeaf = try engine.createTask(
        title: "Publish first sample",
        parentID: root.id,
        contextID: context.id,
        at: base.addingTimeInterval(4)
    )

    _ = try engine.completeTask(id: doneLeaf.id, at: base.addingTimeInterval(10))
    _ = try engine.completeTask(id: directDoneLeaf.id, at: base.addingTimeInterval(10))

    let tree = engine.taskTree(contextID: context.id)
    let branchSignal = try engine.completionSignal(taskID: branch.id)
    let rootSignal = try engine.completionSignal(taskID: root.id)
    require(tree.count == 1, "Task tree should expose one context root")
    require(tree[0].children.count == 2, "Task tree should preserve direct child relationships")
    require(abs(branchSignal - 0.5) < 0.0001, "Branch should average child completion")
    require(abs(rootSignal - 0.75) < 0.0001, "Root should recursively average child completion")

    let maintenance = try engine.createTask(
        title: "Renew certificate",
        kind: .maintenance,
        at: base
    )
    require(maintenance.contextID == nil, "Maintenance tasks may remain isolated")
    require(engine.taskTree(contextID: nil).map(\.task.id).contains(maintenance.id), "Isolated tasks should remain queryable")

    do {
        _ = try engine.updateTask(
            id: root.id,
            title: root.title,
            note: root.note,
            parentID: doneLeaf.id,
            contextID: context.id,
            kind: root.kind,
            at: base.addingTimeInterval(20)
        )
        fatalError("Expected cycle protection")
    } catch let error as V2EngineError {
        require(error == .taskHierarchyCycle, "Moving a parent under its descendant should fail")
    }
}

func checkEngineExecutionFacts() throws {
    let engine = V2Engine()
    let base = Date(timeIntervalSince1970: 1_800_010_000)
    let task = try engine.createTask(title: "Write outline", at: base)

    let first = try engine.startExecution(
        taskID: task.id,
        title: task.title,
        source: .normal,
        at: base
    )
    let unlinkedZen = try engine.startExecution(
        taskID: nil,
        title: "Open focus",
        source: .zen,
        at: base.addingTimeInterval(60)
    )
    require(engine.openExecutionSegments().count == 2, "Linked and unlinked segments should run in parallel")

    let paused = try engine.pauseExecution(segmentID: first.id, at: base.addingTimeInterval(600))
    require(paused.endAt == base.addingTimeInterval(600), "Pausing should close the current segment")
    require(engine.snapshot.tasks.first { $0.id == task.id }?.status == .paused, "Pausing should mark the task paused")

    let resumed = try engine.resumeTaskExecution(taskID: task.id, at: base.addingTimeInterval(900))
    require(resumed.id != first.id, "Resuming should create a new fact segment")
    _ = try engine.endExecution(segmentID: resumed.id, at: base.addingTimeInterval(1_200))
    _ = try engine.endExecution(segmentID: unlinkedZen.id, at: base.addingTimeInterval(300))

    require(abs(engine.spentDuration(taskID: task.id, through: base.addingTimeInterval(2_000)) - 900) < 0.001, "Spent duration should sum closed segments")
    require(engine.snapshot.tasks.first { $0.id == task.id }?.status == .notStarted, "Ending execution should not complete the task")
    require(engine.snapshot.executionSegments.contains { $0.id == unlinkedZen.id && $0.taskID == nil }, "Unlinked Zen should remain evidence")

    _ = try engine.completeTask(id: task.id, at: base.addingTimeInterval(2_100))
    do {
        _ = try engine.startExecution(
            taskID: task.id,
            title: task.title,
            source: .normal,
            at: base.addingTimeInterval(2_200)
        )
        fatalError("Expected completed task protection")
    } catch let error as V2EngineError {
        require(error == .taskCompleted(task.id), "Completed tasks should be restored before execution")
    }

    _ = try engine.restoreTask(id: task.id, at: base.addingTimeInterval(2_300))
    let restarted = try engine.startExecution(
        taskID: task.id,
        title: task.title,
        source: .urgentInsert,
        at: base.addingTimeInterval(2_400)
    )
    require(restarted.endAt == nil, "Restored tasks should start a new open segment")
}

func checkEnginePersistenceAndRecovery() throws {
    let fileManager = FileManager.default
    let directory = fileManager.temporaryDirectory
        .appendingPathComponent("tough-trial-engine-(UUID().uuidString)", isDirectory: true)
    defer { try? fileManager.removeItem(at: directory) }

    let store = V2JSONSnapshotStore(fileURL: directory.appendingPathComponent("snapshot.json"))
    let base = Date(timeIntervalSince1970: 1_800_020_000.123456)
    let engine = try V2Engine.load(from: store)
    let context = try engine.createTaskContext(title: "Health", colorName: "teal", at: base)
    let task = try engine.createTask(
        title: "Run",
        contextID: context.id,
        kind: .goal,
        at: base
    )
    let segment = try engine.startExecution(
        taskID: task.id,
        title: task.title,
        source: .normal,
        at: base.addingTimeInterval(30)
    )
    let pausedZen = try engine.startExecution(
        taskID: nil,
        title: "Paused focus",
        source: .zen,
        at: base.addingTimeInterval(40)
    )
    _ = try engine.pauseExecutionSession(
        sessionID: pausedZen.logicalSessionID,
        at: base.addingTimeInterval(50)
    )

    let reopened = try V2Engine.load(from: store)
    require(reopened.snapshot.tasks.contains { $0.id == task.id }, "Tasks should survive engine restart")
    require(reopened.openExecutionSegments().contains { $0.id == segment.id }, "Open segments should survive engine restart")
    require(reopened.snapshot.tasks.first { $0.id == task.id }?.status == .active, "Open execution should restore linked task as active")
    let reopenedToday = reopened.todaySnapshot(
        date: base,
        now: base.addingTimeInterval(55)
    )
    require(
        reopenedToday.sessions.contains {
            $0.id == pausedZen.logicalSessionID && $0.status == .paused
        },
        "Paused logical sessions should survive engine restart"
    )
    let resumedZen = try reopened.resumeExecutionSession(
        sessionID: pausedZen.logicalSessionID,
        at: base.addingTimeInterval(60)
    )
    require(
        resumedZen.logicalSessionID == pausedZen.logicalSessionID,
        "Resuming after restart should preserve logical session identity"
    )
    try reopened.stopExecutionSession(
        sessionID: pausedZen.logicalSessionID,
        at: base.addingTimeInterval(70)
    )
    let storedSnapshot = try store.load()
    require(storedSnapshot == reopened.snapshot, "JSON round trip should preserve the snapshot")

    _ = try reopened.completeTask(id: task.id, at: base.addingTimeInterval(90))
    let reopenedCompleted = try V2Engine.load(from: store)
    require(reopenedCompleted.openExecutionSegments().contains { $0.id == segment.id }, "Completing a task must not erase an open execution fact")
    require(reopenedCompleted.snapshot.tasks.first { $0.id == task.id }?.status == .done, "Restart recovery must preserve explicit task completion")

    let corruptURL = directory.appendingPathComponent("corrupt.json")
    let corruptData = Data("{not-json".utf8)
    try corruptData.write(to: corruptURL)
    let corruptStore = V2JSONSnapshotStore(fileURL: corruptURL)
    do {
        _ = try corruptStore.load()
        fatalError("Expected corrupt JSON to fail")
    } catch {
        let remainingData = try Data(contentsOf: corruptURL)
        require(remainingData == corruptData, "Failed reads must not overwrite corrupt evidence")
    }
}

func checkTodayProjectionUsesDurableFacts() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let base = calendar.date(from: DateComponents(
        year: 2027,
        month: 1,
        day: 15,
        hour: 9
    ))!
    let engine = V2Engine()
    let inserted = try engine.quickInsertTodayTask(
        title: "Handle urgent form",
        at: base,
        calendar: calendar
    )

    var today = engine.todaySnapshot(date: base, now: base, calendar: calendar)
    require(today.items.count == 1, "Urgent insert should appear in Today")
    require(today.items[0].taskID == inserted.task.id, "Today item should link the durable task")
    require(today.sessions.isEmpty, "A planned task should not look like execution")

    let running = try engine.startExecution(
        taskID: inserted.task.id,
        title: inserted.task.title,
        source: .urgentInsert,
        at: base.addingTimeInterval(10)
    )
    today = engine.todaySnapshot(
        date: base,
        now: base.addingTimeInterval(70),
        calendar: calendar
    )
    require(today.sessions.count == 1, "Open execution should project into the live tray")
    require(abs(today.sessions[0].currentDuration - 60) < 0.001, "Live elapsed time should derive from timestamps")
    require(abs(today.items[0].spentDuration - 60) < 0.001, "Today item should read execution facts")

    _ = try engine.pauseExecutionSession(
        sessionID: running.logicalSessionID,
        at: base.addingTimeInterval(80)
    )
    today = engine.todaySnapshot(
        date: base,
        now: base.addingTimeInterval(90),
        calendar: calendar
    )
    require(today.sessions[0].status == .paused, "Paused execution should survive as a tray session")

    let resumed = try engine.resumeExecutionSession(
        sessionID: running.logicalSessionID,
        at: base.addingTimeInterval(100)
    )
    require(resumed.logicalSessionID == running.logicalSessionID, "Resume should preserve the logical session")
    try engine.stopExecutionSession(
        sessionID: running.logicalSessionID,
        at: base.addingTimeInterval(160)
    )
    today = engine.todaySnapshot(
        date: base,
        now: base.addingTimeInterval(170),
        calendar: calendar
    )
    require(today.sessions.isEmpty, "Stopped execution should leave the live tray")
    require(abs(today.items[0].spentDuration - 130) < 0.001, "Pause and resume segments should sum without paused time")

    let openZen = try engine.startExecution(
        taskID: nil,
        title: "Unlinked focus",
        source: .zen,
        at: base.addingTimeInterval(200)
    )
    _ = try engine.pauseExecutionSession(
        sessionID: openZen.logicalSessionID,
        at: base.addingTimeInterval(220)
    )
    today = engine.todaySnapshot(
        date: base,
        now: base.addingTimeInterval(230),
        calendar: calendar
    )
    require(today.sessions.contains { $0.id == openZen.logicalSessionID && $0.status == .paused }, "Unlinked Zen should remain resumable")
    _ = try engine.resumeExecutionSession(
        sessionID: openZen.logicalSessionID,
        at: base.addingTimeInterval(240)
    )
    try engine.stopExecutionSession(
        sessionID: openZen.logicalSessionID,
        at: base.addingTimeInterval(260)
    )
    today = engine.todaySnapshot(
        date: base,
        now: base.addingTimeInterval(270),
        calendar: calendar
    )
    require(today.items.contains { $0.kind == .executionRecord && $0.title == "Unlinked focus" }, "Stopped unlinked Zen should remain Today evidence")
}

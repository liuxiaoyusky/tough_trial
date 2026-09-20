import Foundation
import ToughTrialV2Core

func checkScheduleCommandAtomicRollback() throws {
    let base = Date(timeIntervalSince1970: 1_900_000_000)
    let engine = V2Engine()
    let before = engine.snapshot

    let proposal = V2ScheduleProposal(
        summary: "先新增，再验证失败会整体回滚",
        operations: [
            V2ScheduleOperation(
                kind: .createTask,
                localID: "new-task",
                title: "准备演示"
            ),
            V2ScheduleOperation(
                kind: .updateTask,
                targetID: "missing-task",
                title: "不存在的任务"
            ),
        ]
    )

    do {
        _ = try engine.applyScheduleProposal(
            proposal,
            requestID: "request-atomic-rollback",
            at: base
        )
        fatalError("A failed operation should roll back the whole proposal")
    } catch V2EngineError.taskNotFound("missing-task") {
        // Expected: the second operation fails after the first staged write.
    }

    require(engine.snapshot == before, "A failed proposal must not mutate the live snapshot")
}

func checkScheduleCommandAppliesAndPersistsReceipt() throws {
    let base = Date(timeIntervalSince1970: 1_900_100_000)
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("tough-trial-schedule-command-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = V2JSONSnapshotStore(fileURL: directory.appendingPathComponent("snapshot.json"))
    let engine = try V2Engine.load(from: store)
    let existing = try engine.createTask(title: "准备报告", at: base)

    let receipt = try engine.applyScheduleProposal(
        V2ScheduleProposal(
            summary: "准备并安排报告",
            operations: [
                V2ScheduleOperation(
                    kind: .updateTask,
                    targetID: existing.id,
                    title: "准备季度报告",
                    note: "保留原始数据"
                ),
                V2ScheduleOperation(
                    kind: .createTask,
                    localID: "report-review",
                    title: "复核报告"
                ),
                V2ScheduleOperation(
                    kind: .scheduleTask,
                    localID: "report-review",
                    day: "2030-01-03",
                    startMinute: 10 * 60,
                    durationMinutes: 45
                ),
                V2ScheduleOperation(
                    kind: .completeTask,
                    targetID: existing.id
                ),
            ]
        ),
        requestID: "request-persisted-1",
        at: base
    )

    require(receipt.requestID == "request-persisted-1", "Receipt should retain request ID")
    require(receipt.summary == "准备并安排报告", "Receipt should retain the normalized summary")
    require(receipt.changes.count == 3, "Receipt should include the updated task, created task, and plan item")
    require(engine.snapshot.scheduleReceipts == [receipt], "The receipt should be in the same snapshot")
    require(engine.snapshot.tasks.first(where: { $0.id == existing.id })?.status == .done, "The task should be completed")
    let createdTask = engine.snapshot.tasks.first { $0.title == "复核报告" }
    let createdPlan = engine.snapshot.planItems.first { $0.taskID == createdTask?.id }
    require(createdPlan?.startAt != nil && createdPlan?.endAt != nil, "The scheduled task should keep its time range")
    require(createdPlan?.sourceDraftID == nil, "Direct schedule commands should not invent a draft source")

    let repeated = try engine.applyScheduleProposal(
        V2ScheduleProposal(summary: "different retry", operations: []),
        requestID: receipt.requestID,
        at: base.addingTimeInterval(1)
    )
    require(repeated == receipt, "A repeated request ID should return the original receipt")
    require(engine.snapshot.scheduleReceipts.count == 1, "A repeated request ID must not append another receipt")

    let reopened = try V2Engine.load(from: store)
    require(reopened.snapshot.scheduleReceipts == [receipt], "A receipt should survive restart")
    let repeatedAfterRestart = try reopened.applyScheduleProposal(
        V2ScheduleProposal(summary: "retry after restart", operations: []),
        requestID: receipt.requestID,
        at: base.addingTimeInterval(2)
    )
    require(repeatedAfterRestart == receipt, "Request ID idempotency should survive restart")
}

func checkScheduleCommandUndoPreservesUnrelatedAndRejectsConflict() throws {
    let base = Date(timeIntervalSince1970: 1_900_200_000)
    let engine = V2Engine()
    let original = try engine.createTask(title: "原始标题", at: base)

    let receipt = try engine.applyScheduleProposal(
        V2ScheduleProposal(
            summary: "修改标题",
            operations: [
                V2ScheduleOperation(
                    kind: .updateTask,
                    targetID: original.id,
                    title: "AI 修改标题"
                ),
            ]
        ),
        requestID: "request-undo-1",
        at: base.addingTimeInterval(1)
    )
    let unrelated = try engine.createTask(title: "后续无关任务", at: base.addingTimeInterval(2))

    let undone = try engine.undoScheduleReceipt(id: receipt.id, at: base.addingTimeInterval(3))
    require(undone.undoneAt == base.addingTimeInterval(3), "Undo should mark the receipt")
    require(
        engine.snapshot.tasks.first(where: { $0.id == original.id })?.title == "原始标题",
        "Undo should restore the affected task"
    )
    require(
        engine.snapshot.tasks.contains(where: { $0.id == unrelated.id }),
        "Undo should preserve an unrelated task created later"
    )
    require(engine.snapshot.scheduleReceipts.first?.undoneAt != nil, "Undo state should persist in the snapshot")

    do {
        _ = try engine.undoScheduleReceipt(id: receipt.id, at: base.addingTimeInterval(4))
        fatalError("Undoing the same receipt twice should fail explicitly")
    } catch V2EngineError.scheduleReceiptAlreadyUndone(receipt.id) {
        // Expected: a receipt has one undo transition.
    }

    let secondReceipt = try engine.applyScheduleProposal(
        V2ScheduleProposal(
            summary: "再次修改标题",
            operations: [
                V2ScheduleOperation(
                    kind: .updateTask,
                    targetID: original.id,
                    title: "第二次 AI 修改"
                ),
            ]
        ),
        requestID: "request-undo-2",
        at: base.addingTimeInterval(5)
    )
    _ = try engine.updateTask(
        id: original.id,
        title: "用户手动修改",
        note: "保留这个修改",
        parentID: nil,
        contextID: nil,
        kind: nil,
        at: base.addingTimeInterval(6)
    )
    let beforeConflictUndo = engine.snapshot
    do {
        _ = try engine.undoScheduleReceipt(id: secondReceipt.id, at: base.addingTimeInterval(7))
        fatalError("Undo should reject an affected task changed after the receipt")
    } catch V2EngineError.scheduleReceiptConflict(original.id) {
        // Expected: current task no longer equals the receipt after-state.
    }
    require(engine.snapshot == beforeConflictUndo, "A rejected undo must not mutate the snapshot")
}

func checkScheduleCommandArchiveUndoRestoresDescendantsAndKeepsExecution() throws {
    let base = Date(timeIntervalSince1970: 1_900_300_000)
    let engine = V2Engine()
    let context = try engine.createTaskContext(title: "研究", colorName: "blue", at: base)
    let root = try engine.createTask(title: "完成研究", contextID: context.id, at: base)
    let child = try engine.createTask(
        title: "整理资料",
        parentID: root.id,
        contextID: context.id,
        at: base.addingTimeInterval(1)
    )
    let leaf = try engine.createTask(
        title: "阅读论文",
        parentID: child.id,
        contextID: context.id,
        at: base.addingTimeInterval(2)
    )
    let segment = try engine.startExecution(
        taskID: leaf.id,
        title: leaf.title,
        source: .normal,
        at: base.addingTimeInterval(3)
    )
    let beforeTasks = engine.snapshot.tasks

    let receipt = try engine.applyScheduleProposal(
        V2ScheduleProposal(
            summary: "归档整个研究分支",
            operations: [
                V2ScheduleOperation(kind: .archiveTask, targetID: root.id),
            ]
        ),
        requestID: "request-archive-undo",
        at: base.addingTimeInterval(4)
    )
    require(receipt.changes.count == 3, "Archive receipt should include every affected descendant")
    require(engine.snapshot.tasks.allSatisfy { $0.status == .archived }, "The whole branch should be archived")
    require(
        engine.snapshot.executionSegments.first(where: { $0.id == segment.id }) ==
            V2ExecutionSegment(
                id: segment.id,
                sessionID: segment.sessionID,
                taskID: segment.taskID,
                titleSnapshot: segment.titleSnapshot,
                startAt: segment.startAt,
                endAt: segment.endAt,
                endReason: segment.endReason,
                source: segment.source,
                createdFromPlanItemID: segment.createdFromPlanItemID,
                note: segment.note
            ),
        "Archiving should not close or rewrite an execution segment"
    )

    _ = try engine.undoScheduleReceipt(id: receipt.id, at: base.addingTimeInterval(5))
    require(engine.snapshot.tasks == beforeTasks, "Undo should restore the root and all descendants exactly")
    require(
        engine.snapshot.executionSegments.first(where: { $0.id == segment.id }) == segment,
        "Undo should preserve the real execution evidence"
    )
}

func checkScheduleCommandReschedulePreservesPlanIdentityAndExecutionEvidence() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let base = calendar.date(from: DateComponents(year: 2030, month: 2, day: 1, hour: 9))!
    let engine = V2Engine()
    let task = try engine.createTask(title: "实地访谈", at: base)
    let planItem = try engine.addTaskToToday(taskID: task.id, date: base, calendar: calendar)
    let segment = try engine.startExecution(
        taskID: task.id,
        title: task.title,
        source: .normal,
        at: base.addingTimeInterval(30),
        createdFromPlanItemID: planItem.id
    )

    let receipt = try engine.applyScheduleProposal(
        V2ScheduleProposal(
            summary: "延期到明天上午",
            operations: [
                V2ScheduleOperation(
                    kind: .reschedulePlanItem,
                    targetID: planItem.id,
                    day: "2030-02-02",
                    startMinute: 10 * 60,
                    durationMinutes: 60
                ),
            ]
        ),
        requestID: "request-reschedule-1",
        at: base.addingTimeInterval(60),
        calendar: calendar
    )
    let rescheduled = engine.snapshot.planItems.first { $0.id == planItem.id }
    require(rescheduled?.id == planItem.id, "Rescheduling must retain the plan item ID")
    require(rescheduled?.taskID == task.id, "Rescheduling must retain the linked task ID")
    require(
        rescheduled?.startAt == calendar.date(bySettingHour: 10, minute: 0, second: 0, of: rescheduled!.date),
        "Rescheduling should apply the requested start time"
    )
    require(
        rescheduled?.endAt?.timeIntervalSince(rescheduled!.startAt!) == 60 * 60,
        "Rescheduling should apply the requested duration"
    )
    require(
        engine.snapshot.executionSegments.first(where: { $0.id == segment.id })?.createdFromPlanItemID == planItem.id,
        "Rescheduling must preserve the execution provenance link"
    )
    require(
        engine.snapshot.executionSegments.first(where: { $0.id == segment.id }) == segment,
        "Rescheduling must not rewrite actual execution evidence"
    )

    _ = try engine.undoScheduleReceipt(id: receipt.id, at: base.addingTimeInterval(120))
    let restored = engine.snapshot.planItems.first { $0.id == planItem.id }
    require(restored == planItem, "Undo should restore the original plan item without changing its ID")
}

func checkScheduleCommandRejectsStaleExpectedSnapshotButAllowsUnrelatedChanges() throws {
    let base = Date(timeIntervalSince1970: 1_900_400_000)
    let engine = V2Engine()
    let task = try engine.createTask(title: "待处理", at: base)
    let baseline = engine.snapshot
    _ = try engine.updateTask(
        id: task.id,
        title: "用户先改了",
        note: "",
        parentID: nil,
        contextID: nil,
        kind: nil,
        at: base.addingTimeInterval(1)
    )
    let beforeStaleApply = engine.snapshot

    do {
        _ = try engine.applyScheduleProposal(
            V2ScheduleProposal(
                summary: "AI 修改",
                operations: [
                    V2ScheduleOperation(kind: .updateTask, targetID: task.id, title: "AI 修改")
                ]
            ),
            requestID: "request-stale-1",
            at: base.addingTimeInterval(2),
            expectedSnapshot: baseline
        )
        fatalError("A changed affected task should reject a stale expected snapshot")
    } catch V2EngineError.staleScheduleProposal(task.id) {
        // Expected: the task changed while the proposal was being prepared.
    }
    require(engine.snapshot == beforeStaleApply, "A stale proposal must not mutate the snapshot")

    let independentEngine = V2Engine()
    let independentTask = try independentEngine.createTask(title: "保持不变", at: base)
    let independentBaseline = independentEngine.snapshot
    _ = try independentEngine.createTask(title: "后来新增的无关任务", at: base.addingTimeInterval(1))
    _ = try independentEngine.applyScheduleProposal(
        V2ScheduleProposal(
            summary: "只修改原任务",
            operations: [
                V2ScheduleOperation(
                    kind: .updateTask,
                    targetID: independentTask.id,
                    title: "原任务已更新"
                )
            ]
        ),
        requestID: "request-stale-2",
        at: base.addingTimeInterval(2),
        expectedSnapshot: independentBaseline
    )
    require(
        independentEngine.snapshot.tasks.contains { $0.title == "后来新增的无关任务" },
        "A stale baseline check should allow unrelated later additions"
    )
}

func checkScheduleCommandContextBaselineAndDSTRules() throws {
    let base = Date(timeIntervalSince1970: 1_900_500_000)
    let context = V2TaskContext(
        id: "context-a",
        title: "项目 A",
        colorName: "blue",
        createdAt: base,
        updatedAt: base
    )
    let task = V2Task(
        id: "task-a",
        contextID: context.id,
        title: "原任务",
        createdAt: base,
        updatedAt: base
    )
    let baseline = V2AppSnapshot(taskContexts: [context], tasks: [task])
    let unchangedContextEngine = V2Engine(snapshot: baseline)
    _ = try unchangedContextEngine.applyScheduleProposal(
        V2ScheduleProposal(
            summary: "同一分组内修改",
            operations: [
                V2ScheduleOperation(
                    kind: .updateTask,
                    targetID: task.id,
                    title: "修改后的任务",
                    contextID: context.id
                ),
            ]
        ),
        requestID: "request-context-unchanged",
        at: base.addingTimeInterval(1),
        expectedSnapshot: baseline
    )

    var changedContext = context
    changedContext.title = "用户改名后的分组"
    changedContext.updatedAt = base.addingTimeInterval(1)
    let changedContextEngine = V2Engine(
        snapshot: V2AppSnapshot(taskContexts: [changedContext], tasks: [task])
    )
    do {
        _ = try changedContextEngine.applyScheduleProposal(
            V2ScheduleProposal(
                summary: "基线分组已变化",
                operations: [
                    V2ScheduleOperation(
                        kind: .updateTask,
                        targetID: task.id,
                        title: "不应覆盖",
                        contextID: context.id
                    ),
                ]
            ),
            requestID: "request-context-changed",
            at: base.addingTimeInterval(2),
            expectedSnapshot: baseline
        )
        fatalError("A changed affected context should reject the stale proposal")
    } catch V2EngineError.staleScheduleProposal(context.id) {
        // Expected: the context changed while the proposal was pending.
    }

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    let springDay = calendar.date(from: DateComponents(year: 2030, month: 3, day: 10))!
    let dstEngine = V2Engine()
    let dstTask = try dstEngine.createTask(title: "DST 测试", at: springDay)
    _ = try dstEngine.applyScheduleProposal(
        V2ScheduleProposal(
            summary: "夏令时上午九点",
            operations: [
                V2ScheduleOperation(
                    kind: .scheduleTask,
                    targetID: dstTask.id,
                    day: "2030-03-10",
                    startMinute: 9 * 60,
                    durationMinutes: 60
                ),
            ]
        ),
        requestID: "request-dst-wall-clock",
        at: springDay,
        calendar: calendar
    )
    let dstPlan = dstEngine.snapshot.planItems[0]
    let dstStartComponents = calendar.dateComponents([.hour, .minute], from: dstPlan.startAt!)
    require(dstStartComponents.hour == 9 && dstStartComponents.minute == 0, "DST scheduling should keep 09:00 wall time")
    require(dstPlan.endAt!.timeIntervalSince(dstPlan.startAt!) == 60 * 60, "DST scheduling should preserve duration")
}

func checkScheduleCommandPreservesOvernightDelayAndRejectsAliasCollisions() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let base = calendar.date(from: DateComponents(year: 2030, month: 3, day: 1))!
    let task = V2Task(id: "task", title: "跨午夜任务", createdAt: base, updatedAt: base)
    let oldNextDay = calendar.date(byAdding: .day, value: 1, to: base)!
    let plan = V2PlanItem(
        id: "plan",
        date: base,
        startAt: calendar.date(bySettingHour: 23, minute: 0, second: 0, of: base),
        endAt: calendar.date(bySettingHour: 0, minute: 30, second: 0, of: oldNextDay),
        taskID: task.id,
        title: task.title
    )
    let engine = V2Engine(snapshot: V2AppSnapshot(tasks: [task], planItems: [plan]))
    _ = try engine.applyScheduleProposal(
        V2ScheduleProposal(
            summary: "延期但保留跨午夜时长",
            operations: [
                V2ScheduleOperation(
                    kind: .reschedulePlanItem,
                    targetID: plan.id,
                    day: "2030-03-03"
                ),
            ]
        ),
        requestID: "request-overnight-delay",
        at: base,
        calendar: calendar
    )
    let moved = engine.snapshot.planItems[0]
    require(moved.endAt! > moved.startAt!, "Overnight delay must keep end after start")
    let movedEnd = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: moved.endAt!)
    require(
        movedEnd.year == 2030 && movedEnd.month == 3 && movedEnd.day == 4
            && movedEnd.hour == 0 && movedEnd.minute == 30,
        "Overnight delay should preserve the end day offset"
    )

    let context = V2TaskContext(
        id: "context-id",
        title: "分组",
        colorName: "blue",
        createdAt: base,
        updatedAt: base
    )
    let collisionSnapshot = V2AppSnapshot(
        taskContexts: [context],
        tasks: [task],
        planItems: [plan]
    )
    for collisionID in [task.id, plan.id, context.id] {
        let collisionEngine = V2Engine(snapshot: collisionSnapshot)
        do {
            _ = try collisionEngine.applyScheduleProposal(
                V2ScheduleProposal(
                    summary: "别名冲突",
                    operations: [
                        V2ScheduleOperation(
                            kind: .createTask,
                            localID: collisionID,
                            title: "不应新增"
                        ),
                    ]
                ),
                requestID: "request-alias-\(collisionID)",
                at: base
            )
            fatalError("A local alias must not shadow an existing ID")
        } catch V2EngineError.duplicateScheduleLocalID(collisionID) {
            // Expected: task, plan-item, and context IDs share one namespace for aliases.
        }
    }
}

func checkScheduleCommandUndoRejectsLaterContextChild() throws {
    let base = Date(timeIntervalSince1970: 1_900_600_000)
    let engine = V2Engine()
    let contextA = try engine.createTaskContext(title: "A", colorName: "blue", at: base)
    let contextB = try engine.createTaskContext(title: "B", colorName: "green", at: base)
    let parent = try engine.createTask(title: "父任务", contextID: contextA.id, at: base)
    let receipt = try engine.applyScheduleProposal(
        V2ScheduleProposal(
            summary: "移动父任务分组",
            operations: [
                V2ScheduleOperation(
                    kind: .updateTask,
                    targetID: parent.id,
                    contextID: contextB.id
                ),
            ]
        ),
        requestID: "request-context-undo",
        at: base.addingTimeInterval(1)
    )
    let child = try engine.createTask(
        title: "后来新增的子任务",
        parentID: parent.id,
        at: base.addingTimeInterval(2)
    )
    let beforeUndo = engine.snapshot
    do {
        _ = try engine.undoScheduleReceipt(id: receipt.id, at: base.addingTimeInterval(3))
        fatalError("Undo must reject a later child whose context would become inconsistent")
    } catch V2EngineError.scheduleReceiptDanglingReference(child.id) {
        // Expected: restoring the parent would leave the later child in context B.
    }
    require(engine.snapshot == beforeUndo, "A rejected undo must leave the later child and parent unchanged")
}

func checkScheduleCommandLoadsLegacySnapshotWithoutReceipts() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("tough-trial-legacy-schedule-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appendingPathComponent("snapshot.json")
    let store = V2JSONSnapshotStore(fileURL: fileURL)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .secondsSince1970
    var object = try JSONSerialization.jsonObject(
        with: encoder.encode(V2AppSnapshot()),
        options: []
    ) as! [String: Any]
    object.removeValue(forKey: "scheduleReceipts")
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(
        to: fileURL,
        options: .atomic
    )

    let restored = try store.load()
    require(restored.scheduleReceipts.isEmpty, "Legacy snapshots without receipts should decode as an empty list")
}

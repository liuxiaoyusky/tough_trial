import Foundation
import ToughTrialV2Core

func checkWeeklyRunningPlanExecutionRecallLoop() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let base = calendar.date(from: DateComponents(
        year: 2027,
        month: 4,
        day: 12,
        hour: 9
    ))!
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("tough-trial-e2e-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    var conversation = V2PrototypeState.empty()
    conversation.beginPlanPrompt(
        "这周想跑 10 公里",
        at: base,
        calendar: calendar
    )
    require(conversation.currentPlanDraft == nil, "Clarification must not create durable-looking content")
    conversation.confirmPlanClarification(
        "可以",
        at: base,
        calendar: calendar
    )
    guard let draft = conversation.currentPlanDraft else {
        fatalError("The running conversation should produce a draft")
    }
    require(draft.taskChanges.count == 4, "Running draft should propose one parent and three leaf tasks")
    require(draft.scheduleItems.count == 3, "Running draft should propose three scheduled runs")

    let store = V2JSONSnapshotStore(fileURL: directory.appendingPathComponent("snapshot.json"))
    let engine = try V2Engine.load(from: store)
    let snapshotBeforeSave = engine.snapshot
    let record = draft.durableRecord(at: base)
    require(record.mode == .mixed, "The running draft should adapt to mixed mode")

    _ = try engine.savePlanDraft(record, at: base, calendar: calendar)
    require(engine.snapshot.tasks == snapshotBeforeSave.tasks, "Saving a draft must not create tasks")
    require(engine.snapshot.planItems == snapshotBeforeSave.planItems, "Saving a draft must not create plan items")

    let accepted = try engine.acceptPlanDraft(
        id: record.id,
        at: base.addingTimeInterval(10),
        calendar: calendar
    )
    require(accepted.createdTasks.count == 4, "Confirmation should create the running task tree")
    require(accepted.createdPlanItems.count == 3, "Confirmation should create three plan items")

    guard let firstPlan = accepted.createdPlanItems.sorted(by: { $0.date < $1.date }).first else {
        fatalError("Expected a first planned run")
    }
    let firstDay = firstPlan.date
    let today = engine.todaySnapshot(
        date: firstDay,
        now: firstDay.addingTimeInterval(18 * 3_600),
        calendar: calendar
    )
    guard let todayItem = today.items.first(where: { $0.planItemID == firstPlan.id }) else {
        fatalError("Accepted plan should appear in Today on its scheduled day")
    }
    require(todayItem.taskID == firstPlan.taskID, "Today should retain the leaf task identity")
    require(todayItem.title == firstPlan.title, "Today should show the concrete run, not only its parent")

    let executionStart = firstDay.addingTimeInterval(19 * 3_600)
    let session = try engine.startExecution(
        taskID: todayItem.taskID,
        title: todayItem.title,
        source: .normal,
        at: executionStart,
        createdFromPlanItemID: todayItem.planItemID
    )
    _ = try engine.pauseExecutionSession(
        sessionID: session.logicalSessionID,
        at: executionStart.addingTimeInterval(600)
    )
    _ = try engine.resumeExecutionSession(
        sessionID: session.logicalSessionID,
        at: executionStart.addingTimeInterval(900)
    )
    try engine.stopExecutionSession(
        sessionID: session.logicalSessionID,
        at: executionStart.addingTimeInterval(1_800)
    )

    let evidence = engine.recallEvidence(
        date: firstDay,
        now: firstDay.addingTimeInterval(23 * 3_600),
        calendar: calendar
    )
    guard let event = evidence.executionEvents.first(where: {
        $0.createdFromPlanItemIDs.contains(firstPlan.id)
    }) else {
        fatalError("Recall should expose the planned execution event")
    }
    require(abs(event.duration - 1_500) < 0.001, "Paused time should not count as execution")
    require(
        !evidence.deviation.plannedButNotExecuted.contains { $0.id == firstPlan.id },
        "Executed plan must not appear as missed"
    )
    require(
        !evidence.deviation.executedWithoutPlan.contains { $0.id == event.id },
        "Planned execution must not appear as unplanned"
    )

    _ = try engine.saveRecallEntry(
        date: firstDay,
        text: "第一次跑步按计划完成，暂停时间没有计入用时。",
        references: V2RecallReferences(
            taskIDs: event.taskID.map { [$0] } ?? [],
            segmentIDs: event.segmentIDs,
            planItemIDs: event.createdFromPlanItemIDs
        ),
        at: firstDay.addingTimeInterval(23 * 3_600),
        calendar: calendar
    )

    let reopened = try V2Engine.load(from: store)
    let reopenedEvidence = reopened.recallEvidence(
        date: firstDay,
        now: firstDay.addingTimeInterval(23 * 3_600),
        calendar: calendar
    )
    require(
        reopenedEvidence.savedEntry?.referencedPlanItemIDs == [firstPlan.id],
        "The plan-to-execution-to-recall provenance should survive restart"
    )
}

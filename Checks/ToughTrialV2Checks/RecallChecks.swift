import Foundation
import ToughTrialV2Core

func checkRecallEvidenceAndDeviation() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let base = calendar.date(from: DateComponents(
        year: 2027,
        month: 3,
        day: 8,
        hour: 9
    ))!
    let engine = V2Engine()
    let plannedTask = try engine.createTask(title: "Write outline", at: base)
    let missedTask = try engine.createTask(title: "Read paper", at: base)
    let unplannedTask = try engine.createTask(title: "Handle urgent form", at: base)
    let plannedItem = try engine.addTaskToToday(
        taskID: plannedTask.id,
        date: base,
        calendar: calendar
    )
    let missedItem = try engine.addTaskToToday(
        taskID: missedTask.id,
        date: base,
        calendar: calendar
    )

    let plannedSession = try engine.startExecution(
        taskID: plannedTask.id,
        title: plannedTask.title,
        source: .normal,
        at: base,
        createdFromPlanItemID: plannedItem.id
    )
    _ = try engine.pauseExecutionSession(
        sessionID: plannedSession.logicalSessionID,
        at: base.addingTimeInterval(600)
    )
    _ = try engine.resumeExecutionSession(
        sessionID: plannedSession.logicalSessionID,
        at: base.addingTimeInterval(1_200)
    )
    try engine.stopExecutionSession(
        sessionID: plannedSession.logicalSessionID,
        at: base.addingTimeInterval(1_800)
    )

    let unplannedSegment = try engine.startExecution(
        taskID: unplannedTask.id,
        title: unplannedTask.title,
        source: .urgentInsert,
        at: base.addingTimeInterval(2_000)
    )
    _ = try engine.endExecution(
        segmentID: unplannedSegment.id,
        at: base.addingTimeInterval(2_600)
    )
    let zenSegment = try engine.startExecution(
        taskID: nil,
        title: "Open focus",
        source: .zen,
        at: base.addingTimeInterval(3_000)
    )
    _ = try engine.endExecution(
        segmentID: zenSegment.id,
        at: base.addingTimeInterval(3_300)
    )

    let snapshotBeforeQuery = engine.snapshot
    let evidence = engine.recallEvidence(
        date: base,
        now: base.addingTimeInterval(24 * 3_600),
        calendar: calendar
    )
    require(engine.snapshot == snapshotBeforeQuery, "Recall queries must not mutate durable state")
    require(evidence.executionEvents.count == 3, "Recall should expose three logical execution events")
    require(evidence.planItems.count == 2, "Recall should expose the day's accepted plan items")

    let plannedEvent = evidence.executionEvents.first { $0.taskID == plannedTask.id }
    require(plannedEvent?.segmentIDs.count == 2, "Pause and resume segments should group into one recall event")
    require(abs((plannedEvent?.duration ?? 0) - 1_200) < 0.001, "Paused time must not count as execution")
    require(
        evidence.deviation.plannedButNotExecuted.map(\.id) == [missedItem.id],
        "Only the plan without execution should appear as planned-but-not-executed"
    )
    require(
        evidence.deviation.executedWithoutPlan.contains { $0.taskID == unplannedTask.id },
        "An unplanned linked task should appear as executed-without-plan"
    )
    require(
        evidence.deviation.executedWithoutPlan.contains { $0.taskID == nil && $0.source == .zen },
        "Unlinked Zen must remain visible as unplanned evidence"
    )
    require(
        !evidence.deviation.executedWithoutPlan.contains { $0.taskID == plannedTask.id },
        "A planned execution must not be reported as unplanned"
    )
    require(
        engine.planDeviation(date: base, now: base.addingTimeInterval(24 * 3_600), calendar: calendar) == evidence.deviation,
        "The dedicated deviation query should share the evidence rules"
    )
}

func checkRecallEntryPersistenceAndReferenceValidation() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let base = calendar.date(from: DateComponents(
        year: 2027,
        month: 3,
        day: 9,
        hour: 8
    ))!
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("tough-trial-recall-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = V2JSONSnapshotStore(fileURL: directory.appendingPathComponent("snapshot.json"))
    let engine = try V2Engine.load(from: store)
    let task = try engine.createTask(title: "Prepare meeting", at: base)
    let planItem = try engine.addTaskToToday(taskID: task.id, date: base, calendar: calendar)
    let segment = try engine.startExecution(
        taskID: task.id,
        title: task.title,
        source: .normal,
        at: base,
        createdFromPlanItemID: planItem.id
    )
    _ = try engine.endExecution(segmentID: segment.id, at: base.addingTimeInterval(900))
    let references = V2RecallReferences(
        taskIDs: [task.id, task.id],
        segmentIDs: [segment.id, segment.id],
        planItemIDs: [planItem.id, planItem.id]
    )

    let first = try engine.saveRecallEntry(
        date: base,
        text: "  The meeting preparation took longer than expected.\n",
        references: references,
        at: base.addingTimeInterval(1_000),
        calendar: calendar
    )
    require(first.referencedTaskIDs == [task.id], "Recall task references should de-duplicate without reordering")
    require(first.referencedSegmentIDs == [segment.id], "Recall segment references should de-duplicate")
    require(first.referencedPlanItemIDs == [planItem.id], "Recall plan references should de-duplicate")
    require(first.text.hasPrefix("  "), "Recall should preserve the user's text formatting")

    let revised = try engine.saveRecallEntry(
        date: base.addingTimeInterval(3_600),
        text: "Preparation was useful, but the scope was too broad.",
        references: V2RecallReferences(segmentIDs: [segment.id]),
        at: base.addingTimeInterval(1_100),
        calendar: calendar
    )
    require(revised.id == first.id, "Saving the same day again should update the daily entry")
    require(revised.createdAt == first.createdAt, "Updating a daily entry should preserve creation time")
    require(engine.snapshot.recallEntries.count == 1, "A day should keep one current recall entry")

    let reopened = try V2Engine.load(from: store)
    let reopenedEvidence = reopened.recallEvidence(
        date: base,
        now: base.addingTimeInterval(2_000),
        calendar: calendar
    )
    require(reopenedEvidence.savedEntry?.id == first.id, "The daily recall entry should survive restart")
    require(reopenedEvidence.savedEntry?.text == revised.text, "The latest recall text should survive restart")

    try reopened.archiveTask(id: task.id, at: base.addingTimeInterval(2_100))
    _ = try reopened.updateRecallEntry(
        id: first.id,
        text: "Historical references remain valid after task archival.",
        references: V2RecallReferences(taskIDs: [task.id], segmentIDs: [segment.id]),
        at: base.addingTimeInterval(2_200)
    )

    let snapshotBeforeFailure = reopened.snapshot
    do {
        _ = try reopened.updateRecallEntry(
            id: first.id,
            text: "This must not be saved.",
            references: V2RecallReferences(segmentIDs: ["missing-segment"]),
            at: base.addingTimeInterval(2_300)
        )
        fatalError("Expected missing evidence protection")
    } catch let error as V2EngineError {
        require(error == .segmentNotFound("missing-segment"), "Missing evidence should be reported precisely")
    }
    require(reopened.snapshot == snapshotBeforeFailure, "Invalid references must roll back the recall update")

    do {
        _ = try reopened.updateRecallEntry(
            id: first.id,
            text: "  \n\t",
            references: V2RecallReferences(taskIDs: [task.id], segmentIDs: [segment.id]),
            at: base.addingTimeInterval(2_400)
        )
        fatalError("Expected blank recall protection")
    } catch let error as V2EngineError {
        require(error == .blankRecallText, "Blank recall text should be rejected precisely")
    }
    require(reopened.snapshot == snapshotBeforeFailure, "Blank text must roll back the recall update")
}

func checkRecallEvidenceClipsCrossDayExecution() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let firstDay = calendar.date(from: DateComponents(
        year: 2027,
        month: 3,
        day: 10,
        hour: 23,
        minute: 30
    ))!
    let secondDay = firstDay.addingTimeInterval(3_600)
    let engine = V2Engine()
    let task = try engine.createTask(title: "Late migration", at: firstDay)
    let segment = try engine.startExecution(
        taskID: task.id,
        title: task.title,
        source: .normal,
        at: firstDay
    )
    _ = try engine.endExecution(segmentID: segment.id, at: secondDay)

    let firstEvidence = engine.recallEvidence(
        date: firstDay,
        now: secondDay.addingTimeInterval(60),
        calendar: calendar
    )
    let secondEvidence = engine.recallEvidence(
        date: secondDay,
        now: secondDay.addingTimeInterval(60),
        calendar: calendar
    )
    require(abs((firstEvidence.executionEvents.first?.duration ?? 0) - 1_800) < 0.001, "Day one should contain only its 30 minutes")
    require(abs((secondEvidence.executionEvents.first?.duration ?? 0) - 1_800) < 0.001, "Day two should contain only its 30 minutes")
    require(
        firstEvidence.executionEvents.first?.id != secondEvidence.executionEvents.first?.id,
        "The same session should produce date-specific evidence records"
    )
}

func checkRecallDeviationWaitsUntilPlansAreDue() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let now = calendar.date(from: DateComponents(
        year: 2027,
        month: 3,
        day: 11,
        hour: 12
    ))!
    let today = calendar.startOfDay(for: now)
    let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
    let engine = V2Engine()
    let task = try engine.createTask(title: "Prepare release", at: today)
    let draft = V2PlanDraftRecord(
        id: "recall-due-time-draft",
        mode: .scheduleOnly,
        userPrompt: "Arrange release preparation",
        summary: "One elapsed slot, one future slot, and two date-only plans",
        proposedPlanItems: [
            V2ProposedPlanItem(
                id: "elapsed-slot",
                date: today,
                startAt: now.addingTimeInterval(-3_600),
                endAt: now.addingTimeInterval(-1_800),
                taskID: task.id,
                title: "Review elapsed slot"
            ),
            V2ProposedPlanItem(
                id: "future-slot",
                date: today,
                startAt: now.addingTimeInterval(1_800),
                endAt: now.addingTimeInterval(3_600),
                taskID: task.id,
                title: "Review future slot"
            ),
            V2ProposedPlanItem(
                id: "today-date-only",
                date: today,
                taskID: task.id,
                title: "Today without a time"
            ),
            V2ProposedPlanItem(
                id: "tomorrow-date-only",
                date: tomorrow,
                taskID: task.id,
                title: "Tomorrow without a time"
            )
        ],
        createdAt: today,
        updatedAt: today
    )
    _ = try engine.savePlanDraft(draft, at: today, calendar: calendar)
    let acceptance = try engine.acceptPlanDraft(id: draft.id, at: today, calendar: calendar)
    let elapsed = acceptance.createdPlanItems.first { $0.title == "Review elapsed slot" }!
    let future = acceptance.createdPlanItems.first { $0.title == "Review future slot" }!
    let todayDateOnly = acceptance.createdPlanItems.first { $0.title == "Today without a time" }!

    let currentDeviation = engine.planDeviation(date: today, now: now, calendar: calendar)
    require(
        currentDeviation.plannedButNotExecuted.map(\.id) == [elapsed.id],
        "Today should only judge an explicitly ended slot as missing"
    )

    let afterFutureSlot = engine.planDeviation(
        date: today,
        now: now.addingTimeInterval(3_601),
        calendar: calendar
    )
    require(
        Set(afterFutureSlot.plannedButNotExecuted.map(\.id)) == [elapsed.id, future.id],
        "A timed plan should become judgeable only after its end"
    )
    require(
        !afterFutureSlot.plannedButNotExecuted.contains { $0.id == todayDateOnly.id },
        "A date-only plan should wait until the day ends"
    )

    let futureDeviation = engine.planDeviation(date: tomorrow, now: now, calendar: calendar)
    require(futureDeviation.plannedButNotExecuted.isEmpty, "A future day must not be judged early")

    let completedDayDeviation = engine.planDeviation(
        date: today,
        now: tomorrow,
        calendar: calendar
    )
    require(
        completedDayDeviation.plannedButNotExecuted.count == 3,
        "Every unmatched plan becomes judgeable after its day ends"
    )
}

import Foundation
import ToughTrialV2Core

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fatalError(message)
    }
}

func requireContains(_ value: String, _ fragment: String, _ message: String) {
    require(value.contains(fragment), message)
}

func checkActiveSessionLifecycle() {
    var state = V2PrototypeState.sample()
    let originalTimelineCount = state.timelineItems.count

    let started = state.startSession(
        taskID: V2PrototypeState.runningTaskID,
        title: "跑步",
        startedAtLabel: "09:30"
    )

    require(started, "Starting a valid linked session should succeed")

    guard let session = state.activeSessions.last else {
        fatalError("Expected an active session")
    }

    require(session.status == .running, "New sessions should start running")

    state.toggleSession(session.id)
    require(
        state.activeSessions.first { $0.id == session.id }?.status == .paused,
        "Toggle should pause a running session"
    )

    state.toggleSession(session.id)
    require(
        state.activeSessions.first { $0.id == session.id }?.status == .running,
        "Toggle should resume a paused session"
    )

    state.endSession(session.id, totalElapsed: 25, endLabel: "09:55")

    require(state.activeSessions.count == 2, "Ending the new session should leave sample live tray sessions")
    let runningTask = state.flattenTasks().first { $0.id == V2PrototypeState.runningTaskID }
    require(runningTask?.spentMinutes == 25, "Running task should accumulate 25 spent minutes")
    require(runningTask?.status != .done, "Ending a timing session should not complete the linked task")
    require(state.timelineItems.count == originalTimelineCount + 1, "Ending a session should append a timeline item")
    require(state.timelineItems.last?.isDone == false, "Ended session record should not be marked as task completion")
    requireContains(state.timelineItems.last?.detail ?? "", "25", "Ended session detail should include elapsed minutes")
}

func checkCompletingTimelineItemCompletesLinkedTask() {
    var state = V2PrototypeState.sample()

    let completed = state.completeTimelineItem("timeline-writing-current")

    require(completed, "Completing an existing timeline item should succeed")
    require(
        state.timelineItems.first { $0.id == "timeline-writing-current" }?.isDone == true,
        "Completing a timeline item should mark that item done"
    )
    require(
        state.flattenTasks().first { $0.id == V2PrototypeState.writingTaskID }?.status == .done,
        "Completing a linked timeline item should mark the task done"
    )
}

func checkRestoringCompletedTimelineItemReopensLinkedTask() {
    var state = V2PrototypeState.sample()

    _ = state.completeTimelineItem("timeline-writing-current")
    let restored = state.restoreTimelineItem("timeline-writing-current")

    require(restored, "Restoring an existing completed timeline item should succeed")
    require(
        state.timelineItems.first { $0.id == "timeline-writing-current" }?.isDone == false,
        "Restoring a completed timeline item should mark that item not done"
    )
    require(
        state.flattenTasks().first { $0.id == V2PrototypeState.writingTaskID }?.status == .active,
        "Restoring a linked item with a running session should reopen the task as active"
    )
}

func checkInvalidSessionTaskIDDoesNotMutate() {
    var state = V2PrototypeState.sample()
    let originalSessions = state.activeSessions
    let originalTasks = state.tasks

    let started = state.startSession(
        taskID: "missing-task",
        title: "不存在",
        startedAtLabel: "10:00"
    )

    require(!started, "Starting with an invalid linked task ID should fail")
    require(state.activeSessions == originalSessions, "Invalid task ID should not append a session")
    require(state.tasks == originalTasks, "Invalid task ID should not mutate tasks")
}

func checkDuplicateLinkedSessionDoesNotMutate() {
    var state = V2PrototypeState.sample()

    let firstStarted = state.startSession(
        taskID: V2PrototypeState.runningTaskID,
        title: "跑步",
        startedAtLabel: "09:30"
    )

    require(firstStarted, "Starting a valid running session should succeed")

    let timelineAfterFirstStart = state.timelineItems
    let tasksAfterFirstStart = state.tasks

    let secondStarted = state.startSession(
        taskID: V2PrototypeState.runningTaskID,
        title: "跑步",
        startedAtLabel: "09:45"
    )

    require(!secondStarted, "Starting a duplicate linked running session should fail")
    require(state.activeSessions.count == 3, "Duplicate linked session should not append another active session")
    require(state.timelineItems == timelineAfterFirstStart, "Duplicate linked session should not mutate timeline items")
    require(state.tasks == tasksAfterFirstStart, "Duplicate linked session should not mutate tasks")
}

func checkMultipleActiveSessions() {
    var state = V2PrototypeState.sample()

    let started = state.startSession(
        taskID: V2PrototypeState.runningTaskID,
        title: "跑步",
        startedAtLabel: "18:30"
    )

    require(started, "Starting one more valid session should succeed")
    require(state.activeSessions.count == 3, "Sample live tray plus one valid start should leave three active sessions")

    guard let runningID = state.activeSessions.last?.id else {
        fatalError("Expected newly started active session")
    }

    state.endSession(runningID, totalElapsed: 15, endLabel: "09:45")

    require(state.activeSessions.count == 2, "Ending one session should leave sample live tray sessions")
    require(state.activeSessions.contains { $0.taskID == V2PrototypeState.writingTaskID }, "Ending one session should not remove writing")
    require(state.activeSessions.contains { $0.taskID == V2PrototypeState.readingTaskID }, "Ending one session should not remove reading")
}

func checkFocusingActiveSessionMovesItToPrimary() {
    var state = V2PrototypeState.sample()
    let readingSessionID = state.activeSessions[1].id

    let focused = state.focusActiveSession(readingSessionID)

    require(focused, "Focusing an existing active session should succeed")
    require(state.activeSessions.first?.id == readingSessionID, "Focused session should become the primary session")
    require(state.selectedTaskID == V2PrototypeState.readingTaskID, "Focusing a linked session should select its task")
    require(
        state.activeSessions.contains { $0.taskID == V2PrototypeState.writingTaskID },
        "Focusing should keep the previous primary session in the active tray"
    )
}

func checkSampleSupportsTodayLiveTrayPrototype() {
    let state = V2PrototypeState.sample()

    require(state.activeSessions.count == 2, "Sample state should show one running and one paused live tray item")
    require(state.activeSessions[0].taskID == V2PrototypeState.writingTaskID, "First sample session should be linked to writing")
    require(state.activeSessions[0].status == .running, "First sample session should be running")
    require(state.activeSessions[1].taskID == V2PrototypeState.readingTaskID, "Second sample session should be linked to reading")
    require(state.activeSessions[1].status == .paused, "Second sample session should be paused")
}

func checkSampleSupportsTaskStructureMap() {
    let state = V2PrototypeState.sample()

    require(!state.tasks.isEmpty, "Sample state should expose at least one root task context")
    require(
        state.tasks.contains { !$0.children.isEmpty },
        "Sample task structure should include first-level branches"
    )
    require(
        state.tasks.flatMap(\.children).contains { !$0.children.isEmpty },
        "Sample task structure should include a branch with detail children"
    )
    require(
        state.tasks.flatMap(\.children).flatMap(\.children).contains { !$0.children.isEmpty },
        "Sample task structure should include third-level leaf branches"
    )
    require(
        state.flattenTasks().contains { $0.status == .done },
        "Sample task structure should include completed nodes for subtle status rendering"
    )

    let benchmark = state.flattenTasks().first { $0.id == "task-benchmark-accounts" }
    let hitBreakdown = state.flattenTasks().first { $0.id == "task-hit-breakdown" }
    require(benchmark?.completionSignal == 1, "All-done child nodes should fill their parent")
    require(
        abs((hitBreakdown?.completionSignal ?? -1) - (1.0 / 3.0)) < 0.0001,
        "Partially done child nodes should fill their parent proportionally"
    )
}

func checkTaskCompletionSignalUsesLeafDoneAndChildAverage() {
    let doneLeaf = V2TaskNode(
        id: "done-leaf",
        title: "Done leaf",
        subtitle: "",
        goal: "Test",
        colorName: "blue",
        status: .done,
        spentMinutes: 0
    )
    let plannedLeaf = V2TaskNode(
        id: "planned-leaf",
        title: "Planned leaf",
        subtitle: "",
        goal: "Test",
        colorName: "blue",
        status: .planned,
        spentMinutes: 0
    )
    let halfDoneParent = V2TaskNode(
        id: "half-parent",
        title: "Half parent",
        subtitle: "",
        goal: "Test",
        colorName: "blue",
        status: .planned,
        spentMinutes: 0,
        children: [doneLeaf, plannedLeaf]
    )
    let root = V2TaskNode(
        id: "root",
        title: "Root",
        subtitle: "",
        goal: "Test",
        colorName: "blue",
        status: .planned,
        spentMinutes: 0,
        children: [halfDoneParent, doneLeaf]
    )

    require(doneLeaf.completionSignal == 1, "Done leaf should have completion signal 1")
    require(plannedLeaf.completionSignal == 0, "Unfinished leaf should have completion signal 0")
    require(abs(halfDoneParent.completionSignal - 0.5) < 0.0001, "Parent should average child signals")
    require(abs(root.completionSignal - 0.75) < 0.0001, "Parent averaging should recurse through child parents")
    require(root.containsTask(id: "planned-leaf"), "Parent task lookup should find nested children")
    require(!plannedLeaf.containsTask(id: "done-leaf"), "Leaf task lookup should not match sibling nodes")
}

func checkQuickAddTodayTask() {
    var state = V2PrototypeState.sample()
    let originalTaskCount = state.flattenTasks().count
    let originalTimelineCount = state.timelineItems.count

    state.quickAddTodayTask(title: "整理维护")

    require(state.flattenTasks().count == originalTaskCount + 1, "Quick add should append a task")
    require(state.timelineItems.count == originalTimelineCount + 1, "Quick add should append a today timeline item")
    require(state.selectedTaskID == state.timelineItems.last?.taskID, "Quick add should select the new task")
    require(state.taskTitle(for: state.selectedTaskID ?? "") == "整理维护", "Quick add should use the provided task title")
    requireContains(state.timelineItems.last?.detail ?? "", "可并行", "Quick add detail should mention 可并行")
}

func checkScheduledTaskModelAndQuickAddIsolation() {
    var state = V2PrototypeState.sample()
    let originalTaskCount = state.flattenTasks().count
    let originalTimelineItems = state.timelineItems
    let originalScheduleCount = state.scheduledTasks.count
    let calendar = Calendar(identifier: .gregorian)
    let date = calendar.date(from: DateComponents(year: 2026, month: 7, day: 24, hour: 17))!

    state.quickAddScheduledTask(title: "临时维护", on: date, calendar: calendar)

    require(state.flattenTasks().count == originalTaskCount + 1, "Scheduled quick add should create a task")
    require(state.scheduledTasks.count == originalScheduleCount + 1, "Scheduled quick add should create a placement")
    require(state.timelineItems == originalTimelineItems, "Future scheduling must not mutate today's execution timeline")
    require(state.scheduledTasks.last?.placement == .allDay, "Date-only quick add should remain all-day until refined")
    require(
        calendar.isDate(state.scheduledTasks.last?.date ?? Date.distantPast, inSameDayAs: date),
        "Scheduled quick add should preserve the selected day"
    )
    require(state.selectedTaskID == state.scheduledTasks.last?.taskID, "Scheduled quick add should select its task")
}

func checkPlanPromptDraftIsolation() {
    var state = V2PrototypeState.sample()
    let originalTimelineItems = state.timelineItems

    state.sendPlanPrompt("明天安排写作和阅读")

    require(state.currentPlanDraft != nil, "Plan prompt should create a current draft")
    require(state.planMessages.last?.role == .agent, "Plan prompt should append an agent message")
    require(state.timelineItems == originalTimelineItems, "Plan prompt should not mutate timeline items")
}

func checkPlanConversationClarifiesBeforeDraft() {
    var state = V2PrototypeState.empty()
    let calendar = Calendar(identifier: .gregorian)
    let date = calendar.date(from: DateComponents(year: 2026, month: 7, day: 21, hour: 9))!

    state.beginPlanPrompt("这周想跑 10 公里", at: date, calendar: calendar)

    require(state.planConversationPhase == .clarifying, "A new plan prompt should enter clarification")
    require(state.planScope == "本周", "The planning range should be inferred without a required picker")
    require(state.currentPlanDraft == nil, "Clarification must not create a durable-looking draft early")

    state.confirmPlanClarification("可以", at: date, calendar: calendar)

    require(state.planConversationPhase == .reviewingDraft, "A confirmed clarification should reveal the draft")
    require(state.currentPlanDraft?.scheduleItems.count == 3, "The running example should produce three draft rows")
    require(state.planMessages.count == 2, "The draft state should replace the question instead of stacking every state")
}

func checkAcceptPlanDraft() {
    var state = V2PrototypeState.sample()
    let originalTimelineCount = state.timelineItems.count

    state.sendPlanPrompt("安排下午")
    state.acceptCurrentPlanDraft()

    require(state.savedPlanDrafts.count == 1, "Accepting a plan should save the draft")
    require(state.currentPlanDraft == nil, "Accepting a plan should clear currentPlanDraft")
    require(state.timelineItems.count == originalTimelineCount + 1, "Accepting a plan should append a timeline item")
}

func checkSaveThenAcceptPlanDraftDoesNotDuplicate() {
    var state = V2PrototypeState.sample()

    state.sendPlanPrompt("安排下午")
    state.saveCurrentPlanDraft()
    state.acceptCurrentPlanDraft()

    require(state.savedPlanDrafts.count == 1, "Save then accept should keep one saved draft")
}

func checkRecallReferenceAndFullscreen() {
    var state = V2PrototypeState.sample()
    let referenceID = V2PrototypeState.recallDeviationID

    state.insertRecallReference(referenceID)
    state.insertRecallReference(referenceID)

    require(state.selectedRecallReferenceIDs == [referenceID], "Recall reference IDs should be tracked once")
    requireContains(state.recallDraft, "偏离", "Recall draft should include evidence text")

    let originalFullscreen = state.isRecallFullscreen
    state.toggleRecallFullscreen()
    require(state.isRecallFullscreen != originalFullscreen, "Recall fullscreen should toggle")

    state.applyRecallDraft()
    require(state.appliedRecallText.contains("偏离"), "Applying recall should persist draft text")
}

func checkRecallDatesAreIsolated() {
    var state = V2PrototypeState.sample()

    state.setRecallDraft("今天事实", for: "今天")
    state.setRecallDraft("昨天事实", for: "昨天")
    state.insertRecallReference(V2PrototypeState.recallDeviationID, for: "昨天")
    state.applyRecallDraft(for: "昨天")

    require(state.recallDraft(for: "今天") == "今天事实", "Today recall draft should remain isolated")
    requireContains(state.recallDraft(for: "昨天"), "昨天事实", "Yesterday recall draft should keep its own text")
    requireContains(state.recallDraft(for: "昨天"), "偏离", "Yesterday recall draft should receive selected evidence")
    require(state.selectedRecallReferenceIDs(for: "今天").isEmpty, "Today selected references should remain isolated")
    require(
        state.selectedRecallReferenceIDs(for: "昨天") == [V2PrototypeState.recallDeviationID],
        "Yesterday selected references should be tracked separately"
    )
    requireContains(state.appliedRecallText(for: "昨天"), "偏离", "Applying yesterday recall should persist yesterday text")
    require(state.appliedRecallText(for: "今天").isEmpty, "Applying yesterday recall should not persist today text")
}

checkActiveSessionLifecycle()
checkCompletingTimelineItemCompletesLinkedTask()
checkRestoringCompletedTimelineItemReopensLinkedTask()
checkInvalidSessionTaskIDDoesNotMutate()
checkDuplicateLinkedSessionDoesNotMutate()
checkMultipleActiveSessions()
checkFocusingActiveSessionMovesItToPrimary()
checkSampleSupportsTodayLiveTrayPrototype()
checkSampleSupportsTaskStructureMap()
checkTaskCompletionSignalUsesLeafDoneAndChildAverage()
checkQuickAddTodayTask()
checkScheduledTaskModelAndQuickAddIsolation()
checkPlanPromptDraftIsolation()
checkPlanConversationClarifiesBeforeDraft()
checkAcceptPlanDraft()
checkSaveThenAcceptPlanDraftDoesNotDuplicate()
checkRecallReferenceAndFullscreen()
checkRecallDatesAreIsolated()
try checkEngineTaskTreeAndCompletion()
try checkEngineExecutionFacts()
try checkEnginePersistenceAndRecovery()
try checkTodayProjectionUsesDurableFacts()
try checkSchedulePlanDraftLifecycle()
try checkBreakdownPlanDraftCreatesTreeAtomically()
try checkPlanDraftFailureRollsBackAndDiscardStaysClean()
try checkMixedPlanDraftCreatesLinkedTreeAndScheduleAtomically()
try checkRecallEvidenceAndDeviation()
try checkRecallEntryPersistenceAndReferenceValidation()
try checkRecallEvidenceClipsCrossDayExecution()
try checkRecallDeviationWaitsUntilPlansAreDue()
try checkRecallReferenceCandidatesStayEvidenceBacked()
try checkWeeklyRunningPlanExecutionRecallLoop()
try await checkAIPlanningClients()
try checkMemoryPersistenceCorrectionAndForget()
try checkTemporaryMemoryExpiryAndCorruptionBoundary()

print("ToughTrialV2Checks passed")

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
        taskID: V2PrototypeState.writingTaskID,
        title: "写作",
        startedAtLabel: "09:30"
    )

    require(started, "Starting a valid linked session should succeed")

    guard let session = state.activeSessions.first else {
        fatalError("Expected an active session")
    }

    require(session.status == .running, "New sessions should start running")

    state.toggleSession(session.id)
    require(state.activeSessions.first?.status == .paused, "Toggle should pause a running session")

    state.toggleSession(session.id)
    require(state.activeSessions.first?.status == .running, "Toggle should resume a paused session")

    state.endSession(session.id, totalElapsed: 25, endLabel: "09:55")

    require(state.activeSessions.isEmpty, "Ending the only session should clear activeSessions")
    let writingTask = state.flattenTasks().first { $0.id == V2PrototypeState.writingTaskID }
    require(writingTask?.spentMinutes == 67, "Writing task should accumulate 42 + 25 spent minutes")
    require(writingTask?.status != .done, "Ending a timing session should not complete the linked task")
    require(state.timelineItems.count == originalTimelineCount + 1, "Ending a session should append a timeline item")
    require(state.timelineItems.last?.isDone == false, "Ended session record should not be marked as task completion")
    requireContains(state.timelineItems.last?.detail ?? "", "25", "Ended session detail should include elapsed minutes")
}

func checkCompletingTimelineItemCompletesLinkedTask() {
    var state = V2PrototypeState.sample()

    let completed = state.completeTimelineItem("timeline-writing-start")

    require(completed, "Completing an existing timeline item should succeed")
    require(
        state.timelineItems.first { $0.id == "timeline-writing-start" }?.isDone == true,
        "Completing a timeline item should mark that item done"
    )
    require(
        state.flattenTasks().first { $0.id == V2PrototypeState.writingTaskID }?.status == .done,
        "Completing a linked timeline item should mark the task done"
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
        taskID: V2PrototypeState.writingTaskID,
        title: "写作",
        startedAtLabel: "09:30"
    )

    require(firstStarted, "Starting a valid writing session should succeed")

    let timelineAfterFirstStart = state.timelineItems
    let tasksAfterFirstStart = state.tasks

    let secondStarted = state.startSession(
        taskID: V2PrototypeState.writingTaskID,
        title: "写作",
        startedAtLabel: "09:45"
    )

    require(!secondStarted, "Starting a duplicate linked writing session should fail")
    require(state.activeSessions.count == 1, "Duplicate linked session should not append another active session")
    require(state.timelineItems == timelineAfterFirstStart, "Duplicate linked session should not mutate timeline items")
    require(state.tasks == tasksAfterFirstStart, "Duplicate linked session should not mutate tasks")
}

func checkMultipleActiveSessions() {
    var state = V2PrototypeState.sample()

    let firstStarted = state.startSession(
        taskID: V2PrototypeState.writingTaskID,
        title: "写作",
        startedAtLabel: "09:30"
    )
    let secondStarted = state.startSession(
        taskID: V2PrototypeState.runningTaskID,
        title: "跑步",
        startedAtLabel: "18:30"
    )

    require(firstStarted && secondStarted, "Starting two valid sessions should succeed")
    require(state.activeSessions.count == 2, "Two valid starts should leave two active sessions")

    guard let firstID = state.activeSessions.first?.id else {
        fatalError("Expected first active session")
    }

    state.endSession(firstID, totalElapsed: 15, endLabel: "09:45")

    require(state.activeSessions.count == 1, "Ending one session should leave the other active")
    require(state.activeSessions.first?.taskID == V2PrototypeState.runningTaskID, "Ending one session should not remove another")
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

func checkPlanPromptDraftIsolation() {
    var state = V2PrototypeState.sample()
    let originalTimelineItems = state.timelineItems

    state.sendPlanPrompt("明天安排写作和阅读")

    require(state.currentPlanDraft != nil, "Plan prompt should create a current draft")
    require(state.planMessages.last?.role == .agent, "Plan prompt should append an agent message")
    require(state.timelineItems == originalTimelineItems, "Plan prompt should not mutate timeline items")
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

checkActiveSessionLifecycle()
checkCompletingTimelineItemCompletesLinkedTask()
checkInvalidSessionTaskIDDoesNotMutate()
checkDuplicateLinkedSessionDoesNotMutate()
checkMultipleActiveSessions()
checkQuickAddTodayTask()
checkPlanPromptDraftIsolation()
checkAcceptPlanDraft()
checkSaveThenAcceptPlanDraftDoesNotDuplicate()
checkRecallReferenceAndFullscreen()

print("ToughTrialV2Checks passed")

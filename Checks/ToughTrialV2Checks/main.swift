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

    state.startSession(
        taskID: V2PrototypeState.writingTaskID,
        title: "写作",
        startedAtLabel: "09:30"
    )

    guard let session = state.activeSession else {
        fatalError("Expected an active session")
    }

    require(session.status == .running, "New sessions should start running")

    state.toggleSession(session.id)
    require(state.activeSession?.status == .paused, "Toggle should pause a running session")

    state.toggleSession(session.id)
    require(state.activeSession?.status == .running, "Toggle should resume a paused session")

    state.endSession(session.id, totalElapsed: 25, endLabel: "09:55")

    require(state.activeSession == nil, "Ending a session should clear activeSession")
    require(
        state.flattenTasks().first { $0.id == V2PrototypeState.writingTaskID }?.spentMinutes == 67,
        "Writing task should accumulate 42 + 25 spent minutes"
    )
    require(state.timelineItems.count == originalTimelineCount + 1, "Ending a session should append a timeline item")
    require(state.timelineItems.last?.isDone == true, "Ended session timeline item should be done")
    requireContains(state.timelineItems.last?.detail ?? "", "25", "Ended session detail should include elapsed minutes")
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
checkQuickAddTodayTask()
checkPlanPromptDraftIsolation()
checkAcceptPlanDraft()
checkRecallReferenceAndFullscreen()

print("ToughTrialV2Checks passed")

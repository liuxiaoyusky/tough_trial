public extension V2PrototypeState {
    static func empty() -> V2PrototypeState {
        V2PrototypeState(
            tasks: [],
            timelineItems: [],
            scheduledTasks: [],
            selectedTaskID: nil,
            activeSessions: [],
            planMessages: [],
            currentPlanDraft: nil,
            savedPlanDrafts: [],
            recallReferences: [],
            selectedRecallReferenceIDs: [],
            recallDraft: "",
            appliedRecallText: "",
            isRecallFullscreen: false
        )
    }
}

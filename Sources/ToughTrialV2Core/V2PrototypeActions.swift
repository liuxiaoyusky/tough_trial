public extension V2PrototypeState {
    @discardableResult
    mutating func startSession(taskID: String?, title: String, startedAtLabel: String) -> Bool {
        if let taskID, !flattenTasks().contains(where: { $0.id == taskID }) {
            return false
        }

        if let taskID, activeSessions.contains(where: { $0.taskID == taskID }) {
            return false
        }

        let sessionTaskID = taskID ?? "manual"
        activeSessions.append(
            V2ActiveSession(
                id: "session-\(sessionTaskID)-\(timelineItems.count + activeSessions.count + 1)",
                taskID: taskID,
                title: title,
                startedAtLabel: startedAtLabel,
                currentElapsed: 0,
                totalElapsed: 0,
                status: .running
            )
        )

        if let taskID {
            selectedTaskID = taskID
            updateTask(taskID) { task in
                task.status = .active
            }
        }

        return true
    }

    mutating func toggleSession(_ id: String) {
        guard let index = activeSessions.firstIndex(where: { $0.id == id }) else { return }
        activeSessions[index].status = activeSessions[index].status == .running ? .paused : .running

        if let taskID = activeSessions[index].taskID {
            let status = activeSessions[index].status
            updateTask(taskID) { task in
                task.status = status == .paused ? .paused : .active
            }
        }
    }

    mutating func endSession(_ id: String, totalElapsed: Int, endLabel: String) {
        guard let index = activeSessions.firstIndex(where: { $0.id == id }) else { return }
        let session = activeSessions.remove(at: index)

        if let taskID = session.taskID {
            updateTask(taskID) { task in
                task.spentMinutes += totalElapsed
                task.status = .planned
            }
        }

        timelineItems.append(
            V2TimelineItem(
                id: "timeline-session-\(timelineItems.count + 1)",
                timeLabel: endLabel,
                title: session.title,
                detail: "记录一次 \(totalElapsed) 分钟执行。",
                taskID: session.taskID,
                isDone: false
            )
        )
    }

    @discardableResult
    mutating func completeTimelineItem(_ id: String) -> Bool {
        guard let index = timelineItems.firstIndex(where: { $0.id == id }) else { return false }
        timelineItems[index].isDone = true

        if let taskID = timelineItems[index].taskID {
            updateTask(taskID) { task in
                task.status = .done
            }
        }

        return true
    }

    mutating func quickAddTodayTask(title: String) {
        let taskID = "task-quick-\(flattenTasks().count + 1)"
        tasks.append(
            V2TaskNode(
                id: taskID,
                title: title,
                subtitle: "快速加入今天",
                goal: "先记录，再决定是否展开",
                colorName: "teal",
                status: .planned,
                spentMinutes: 0
            )
        )
        timelineItems.append(
            V2TimelineItem(
                id: "timeline-quick-\(timelineItems.count + 1)",
                timeLabel: "今天",
                title: title,
                detail: "快速加入今天，可并行处理，不打断当前执行。",
                taskID: taskID,
                isDone: false
            )
        )
        selectedTaskID = taskID
    }

    mutating func sendPlanPrompt(_ prompt: String) {
        planMessages.append(V2PlanMessage(id: "plan-user-\(planMessages.count + 1)", role: .user, text: prompt))
        let draft = V2PlanDraft(
            title: "计划草稿",
            summary: "根据“\(prompt)”生成的低摩擦安排。",
            decisions: [
                "先保留用户输入的意图",
                "只生成草稿，等待确认后写入今天"
            ],
            scheduleItems: [
                "写作：继续推进当前主线",
                "阅读：安排在低能量时段"
            ]
        )
        currentPlanDraft = draft
        planMessages.append(
            V2PlanMessage(
                id: "plan-agent-\(planMessages.count + 1)",
                role: .agent,
                text: "我先整理成一个草稿，确认后再写入时间线。"
            )
        )
    }

    mutating func saveCurrentPlanDraft() {
        guard let draft = currentPlanDraft, !savedPlanDrafts.contains(draft) else { return }
        savedPlanDrafts.append(draft)
    }

    mutating func acceptCurrentPlanDraft() {
        guard let draft = currentPlanDraft else { return }
        saveCurrentPlanDraft()
        timelineItems.append(
            V2TimelineItem(
                id: "timeline-plan-\(timelineItems.count + 1)",
                timeLabel: "计划",
                title: draft.title,
                detail: draft.summary,
                taskID: nil,
                isDone: false
            )
        )
        currentPlanDraft = nil
    }

    mutating func insertRecallReference(_ id: String) {
        guard let reference = recallReferences.first(where: { $0.id == id }) else { return }
        if !selectedRecallReferenceIDs.contains(id) {
            selectedRecallReferenceIDs.append(id)
            appendRecallEvidence(reference)
        }
    }

    mutating func applyRecallDraft() {
        appliedRecallText = recallDraft
    }

    mutating func toggleRecallFullscreen() {
        isRecallFullscreen.toggle()
    }
}

private extension V2PrototypeState {
    mutating func updateTask(_ id: String, mutate: (inout V2TaskNode) -> Void) {
        updateTask(id, in: &tasks, mutate: mutate)
    }

    func updateTask(_ id: String, in nodes: inout [V2TaskNode], mutate: (inout V2TaskNode) -> Void) {
        for index in nodes.indices {
            if nodes[index].id == id {
                mutate(&nodes[index])
                return
            }
            updateTask(id, in: &nodes[index].children, mutate: mutate)
        }
    }

    mutating func appendRecallEvidence(_ reference: V2RecallReference) {
        let evidence = "[\(reference.kind.rawValue)] \(reference.title)：\(reference.detail)"
        if recallDraft.isEmpty {
            recallDraft = evidence
        } else {
            recallDraft += "\n\(evidence)"
        }
    }
}

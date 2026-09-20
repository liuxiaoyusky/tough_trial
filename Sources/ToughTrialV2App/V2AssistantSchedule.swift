import Foundation
import ToughTrialV2Core

extension V2AssistantStore {
    func executeSchedule(_ query: String, turn: inout TurnState) async throws {
        try V2PluginStore.shared.validate(turn.moduleTicket)
        let ticket = try V2PluginStore.shared.ticket(["assistant", "tasks"])
        let started = now()
        beginStep(.schedule, turn: &turn, at: started)
        guard selectionRevision == turn.selectionRevision, workspace.selectedSessionID == turn.sessionID,
              let session = workspace.session(id: turn.sessionID) else { throw CancellationError() }
        let reviewOnly = !authorizedToWrite(turn) && V2AssistantWriteIntent.mayPrepareReview(turn.userText)
        guard authorizedToWrite(turn) || reviewOnly else {
            turn.observations.append(.init(sourceID: "write-intent", tool: .schedule,
                summary: "本轮没有明确的日程修改请求，未改动任务。请直接说出希望执行的修改。"))
            turn.activeTool = nil
            return
        }
        if let receipt = dependencies.scheduleReceipt(turn.userMessageID) {
            turn.schedule = V2AgentScheduleCard(requestID: turn.userMessageID,
                proposal: .init(summary: receipt.summary, operations: []), baseline: .empty,
                status: .applied, receiptID: receipt.id)
            turn.activeTool = nil
            return
        }
        let baseline = dependencies.scheduleSnapshot()
        let context = requestContext(for: session, before: turn.userMessageID, at: started)
        let history = conversation(from: session, before: turn.userMessageID, context: context)
        guard context.referenceState != .missing else {
            turn.observations.append(.init(sourceID: "missing-reference", tool: .schedule, summary: "当前引用任务暂不可用，请重新选择任务后再整理。"))
            turn.activeTool = nil
            return
        }
        let request = V2ScheduleRequest(userText: turn.userText,
            conversation: history,
            snapshot: baseline, referenceDate: started, timeZoneIdentifier: dependencies.timeZoneIdentifier(), context: context, requiresReview: reviewOnly)
        recordRequestContext(context, conversation: history, kind: "schedule", turn: turn)
        // Preserve the actual utterance; the routing model's query is not authority to change its meaning.
        let outcome = try await turn.modelSnapshot.generateSchedule(request)
        try Task.checkCancellation()
        try V2PluginStore.shared.validate(ticket)
        try V2PluginStore.shared.validate(turn.moduleTicket)
        guard selectionRevision == turn.selectionRevision, workspace.selectedSessionID == turn.sessionID, mayMutate else { throw CancellationError() }
        switch outcome {
        case let .clarification(question):
            turn.observations.append(.init(sourceID: "schedule-clarification", tool: .schedule, summary: question))
        case let .proposal(proposal):
            guard authorizedToWrite(turn) || reviewOnly else { throw V2AssistantTurnError.scheduleUnavailable }
            let proposal = V2AssistantScheduleContext.preservingToday(proposal, userText: turn.userText, at: started,
                timeZoneIdentifier: dependencies.timeZoneIdentifier())
            turn.schedule = .init(requestID: turn.userMessageID, proposal: proposal, baseline: baseline)
            guard persistRunningTurn(turn, at: now()) else { throw V2AssistantTurnError.persistenceUnavailable }
            V2UsageTrace.shared.record(.init(kind: .scheduleProposed, source: .assistant,
                sessionID: turn.sessionID, operationID: turn.userMessageID))
            try Task.checkCancellation()
        try V2PluginStore.shared.validate(ticket)
        try V2PluginStore.shared.validate(turn.moduleTicket)
            if !dependencies.confirmsSchedule() && !reviewOnly {
                let receipt = try dependencies.applySchedule(proposal, baseline, turn.userMessageID, now())
                turn.schedule?.status = .applied
                turn.schedule?.receiptID = receipt.id
                V2UsageTrace.shared.record(.init(kind: .scheduleApplied, source: .assistant,
                    sessionID: turn.sessionID, operationID: turn.userMessageID))
            }
        }
        turn.steps.append(.init(tool: .schedule, status: .succeeded, duration: now().timeIntervalSince(started)))
        turn.activeTool = nil
    }

    func currentTask(_ preview: V2AssistantTaskPreview) -> V2Task? {
        dependencies.scheduleSnapshot().tasks.first { $0.id == preview.taskID }
    }

    func toggleTaskCompletion(_ preview: V2AssistantTaskPreview, card: V2AgentScheduleCard) {
        guard !isRunningTurn, mayMutate, let receipt = receipt(for: card), receipt.undoneAt == nil,
              let task = currentTask(preview), task.status != .archived,
              receipt.changes.contains(where: { $0.afterTask?.id == task.id }) else { return }
        let snapshot = dependencies.scheduleSnapshot()
        let planID = receipt.changes.compactMap(\.afterPlanItem).first { $0.taskID == task.id }?.id
        let availablePlan = planID.flatMap { id in snapshot.planItems.first { $0.id == id && $0.status != .canceled }?.id }
        do {
            try dependencies.toggleTaskCompletion(task.id, availablePlan, now())
            V2UsageTrace.shared.record(.init(kind: .scheduleApplied, source: .assistant,
                sessionID: selectedSession?.id, operationID: card.requestID))
            objectWillChange.send()
            operationErrorMessage = nil
        } catch { operationErrorMessage = error.localizedDescription }
    }

    func receipt(for card: V2AgentScheduleCard) -> V2ScheduleReceipt? {
        dependencies.scheduleReceipt(card.requestID)
    }

    func confirmSchedule(_ card: V2AgentScheduleCard) {
        guard !isRunningTurn, mayMutate, let stored = selectedScheduleCard(card.id), stored.status == .pending else { return }
        do {
            try V2PluginStore.shared.require(["assistant", "tasks"])
            let receipt = try dependencies.applySchedule(stored.proposal, stored.baseline, stored.requestID, now())
            var applied = stored
            applied.status = .applied
            applied.receiptID = receipt.id
            let saved = replaceScheduleCard(applied)
            V2UsageTrace.shared.record(.init(kind: .scheduleConfirmed, source: .assistant,
                sessionID: selectedSession?.id, operationID: stored.requestID))
            if saved { operationErrorMessage = nil }
        } catch { operationErrorMessage = error.localizedDescription }
    }

    @discardableResult
    func editPendingTask(_ card: V2AgentScheduleCard, operationIndex: Int, title: String, note: String, day: String?) -> Bool {
        guard !isRunningTurn, mayMutate, var stored = selectedScheduleCard(card.id),
              stored.status == .pending, receipt(for: stored) == nil,
              stored.proposal.operations.indices.contains(operationIndex),
              stored.proposal.operations[operationIndex].kind == .createTask else { return false }
        do {
            let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { throw V2AgentClientError.invalidOutput("任务标题不能为空") }
            stored.proposal.operations[operationIndex].title = title
            stored.proposal.operations[operationIndex].note = note
            let localID = stored.proposal.operations[operationIndex].localID ?? "edited_" + UUID().uuidString
            stored.proposal.operations[operationIndex].localID = localID
            if let index = stored.proposal.operations.firstIndex(where: { $0.kind == .scheduleTask && $0.targetID == localID }) {
                if let day { stored.proposal.operations[index].day = day }
                else { stored.proposal.operations.remove(at: index) }
            } else if let day { stored.proposal.operations.append(.init(kind: .scheduleTask, targetID: localID, day: day)) }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: dependencies.timeZoneIdentifier()) ?? .current
            // Validate against the same engine on an isolated snapshot. Editing a draft never saves tasks.
            let staged = V2Engine(snapshot: stored.baseline, reconcileExecutions: false)
            _ = try staged.applyScheduleProposal(stored.proposal, requestID: stored.requestID, at: now(), calendar: calendar)
            let saved = replaceScheduleCard(stored)
            if saved { operationErrorMessage = nil }
            return saved
        } catch { operationErrorMessage = error.localizedDescription; return false }
    }

    func adjustSavedTask(_ task: V2AssistantTaskPreview, card: V2AgentScheduleCard, instruction: String) {
        guard let session = selectedSession, let taskID = task.taskID,
              let message = session.messages.first(where: { $0.parts.contains { if case .schedule(let item) = $0 { return item.id == card.id }; return false } }),
              !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        send("请调整任务「\(task.title)」：\(instruction)", references: [
            .init(sessionID: session.id, messageID: message.id, excerpt: "任务 ID：\(taskID)\n标题：\(task.title)\n备注：\(task.note)")
        ])
    }

    func cancelSchedule(_ card: V2AgentScheduleCard) {
        guard !isRunningTurn, var stored = selectedScheduleCard(card.id), receipt(for: stored) == nil else { return }
        stored.status = .cancelled
        replaceScheduleCard(stored)
    }

    func undoSchedule(_ card: V2AgentScheduleCard) {
        guard !isRunningTurn, let receipt = receipt(for: card), receipt.undoneAt == nil else { return }
        do {
            _ = try dependencies.undoSchedule(receipt.id, now())
            V2UsageTrace.shared.record(.init(kind: .scheduleUndone, source: .assistant,
                sessionID: selectedSession?.id, operationID: card.requestID))
            objectWillChange.send()
            operationErrorMessage = nil
        } catch { operationErrorMessage = error.localizedDescription }
    }

    private func selectedScheduleCard(_ id: String) -> V2AgentScheduleCard? {
        selectedSession?.messages.flatMap(\.parts).compactMap {
            if case let .schedule(card) = $0, card.id == id { return card }
            return nil
        }.last
    }

    @discardableResult
    private func replaceScheduleCard(_ card: V2AgentScheduleCard) -> Bool {
        guard let sessionID = selectedSession?.id else { return false }
        return commitWorkspace { workspace in
            guard let index = workspace.sessions.firstIndex(where: { $0.id == sessionID }) else { return }
            for messageIndex in workspace.sessions[index].messages.indices {
                for partIndex in workspace.sessions[index].messages[messageIndex].parts.indices {
                    if case let .schedule(existing) = workspace.sessions[index].messages[messageIndex].parts[partIndex], existing.id == card.id {
                        workspace.sessions[index].messages[messageIndex].parts[partIndex] = .schedule(card)
                    }
                }
            }
        }
    }
}

import Foundation
import ToughTrialV2Core

extension V2AssistantStore {
    /// Validates a model-proposed call against the exact catalog sent with the
    /// request, then lets the host perform the typed operation. The model
    /// never supplies operation identity, module identity, confirmation, or
    /// persistent entity IDs.
    func executeDynamicTool(
        _ call: V2AgentToolCall,
        turn: inout TurnState,
        at startedAt: Date
    ) async throws {
        let currentCatalog = try dependencies.toolCatalog()
        guard currentCatalog.revision == turn.toolCatalog.revision,
              currentCatalog.modules == turn.toolCatalog.modules else {
            throw V2ToolExecutionError.staleCatalog
        }
        let (descriptor, _) = try currentCatalog.validate(call)
        let toolTicket = try V2PluginStore.shared.ticket(descriptor.requiredModules)
        try V2PluginStore.shared.validate(turn.moduleTicket)

        beginStep(.other, turn: &turn, at: startedAt)
        guard let session = workspace.session(id: turn.sessionID) else { throw V2AssistantTurnError.sessionUnavailable }
        let sharedContext = requestContext(for: session, before: turn.userMessageID, at: startedAt)
        let hasWriteAuthority = authorizedToWrite(turn)
        let reviewOnly = !descriptor.readOnly && !hasWriteAuthority && V2AssistantWriteIntent.mayPrepareReview(turn.userText)
        let context = V2ToolExecutionContext(
            traceID: turn.traceID,
            assistantRequestID: turn.userMessageID,
            callOrdinal: turn.toolResults.count,
            toolID: descriptor.id,
            submittedText: turn.userText,
            sourceEvidence: [V2ToolSourceEvidence(excerpt: turn.userText)],
            intent: hasWriteAuthority || reviewOnly ? .explicitWrite : .discussion,
            requiresReview: reviewOnly,
            assistantContext: sharedContext,
            conversation: conversation(from: session, before: turn.userMessageID, context: sharedContext)
        )
        let result: V2ToolExecutionResult
        if call.toolID == "core.tasks.schedule" {
            // Both wire formats share the same durable proposal, confirmation and undo UI.
            if turn.schedule == nil { try await executeSchedule(turn.userText, turn: &turn) }
            let card = turn.schedule
            let receipt = card.flatMap { dependencies.scheduleReceipt($0.requestID) }
            let state: V2ToolExecutionState = receipt?.undoneAt != nil ? .undone
                : receipt != nil ? .applied : card != nil ? .pendingConfirmation : .needsInformation
            let summary = receipt?.summary ?? card?.proposal.summary ?? turn.observations.last?.summary ?? "请补充任务信息。"
            result = .init(toolID: call.toolID, state: state, operationID: context.operationID,
                idempotencyKey: context.idempotencyKey, summary: summary,
                observation: state == .pendingConfirmation ? "已生成待确认任务卡片，尚未保存：" + summary : summary)
        } else if V2AssistantContextTools.ids.contains(call.toolID) {
            result = try executeContextTool(call, context: context, turn: turn)
        } else if !descriptor.readOnly && !hasWriteAuthority && !reviewOnly {
            result = .init(toolID: call.toolID, state: .blocked, operationID: context.operationID,
                idempotencyKey: context.idempotencyKey, summary: "本轮没有明确的修改请求，未改动数据。")
        } else {
            recordRequestContext(sharedContext, conversation: conversation(from: session, before: turn.userMessageID, context: sharedContext), kind: call.toolID, turn: turn)
            result = try await turn.executeTool(call, context)
        }
        guard result.toolID == descriptor.id,
              result.operationID == context.operationID,
              result.idempotencyKey == context.idempotencyKey else {
            throw V2AgentClientError.invalidOutput("工具回执缺少宿主操作身份")
        }

        let boundResult = result.bound(to: call, context: context)
        turn.toolResults.append(boundResult)
        // Retain a committed business receipt even if the enclosing chat is cancelled.
        try Task.checkCancellation()
        try V2PluginStore.shared.validate(toolTicket)
        try V2PluginStore.shared.validate(turn.moduleTicket)
        turn.observations.append(
            V2AgentObservation(
                sourceID: boundResult.operationID,
                tool: .other,
                summary: "工具 \(call.toolID) 的实际结果：\n" + String((boundResult.observation ?? boundResult.summary).prefix(8_000))
            )
        )
        turn.steps.append(
            V2AgentTraceStep(
                tool: .other,
                status: .succeeded,
                duration: now().timeIntervalSince(startedAt),
                subject: .localScope(.mixed)
            )
        )
        turn.activeTool = nil
    }

    func confirmTool(_ result: V2ToolExecutionResult) {
        guard !isRunningTurn, mayMutate,
              result.state == .pendingConfirmation,
              let sessionID = selectedSession?.id else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let updated = try await dependencies.confirmTool(result)
                guard updated.operationID == result.operationID else {
                    throw V2ToolExecutionError.unsupported(result.toolID)
                }
                _ = replaceToolResult(updated, in: sessionID)
                operationErrorMessage = nil
            } catch {
                operationErrorMessage = Self.userFacingMessage(for: error)
            }
        }
    }

    func undoTool(_ result: V2ToolExecutionResult) {
        guard !isRunningTurn, mayMutate,
              result.canUndo,
              let sessionID = selectedSession?.id else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let updated = try await dependencies.undoTool(result)
                guard updated.operationID == result.operationID else {
                    throw V2ToolExecutionError.unsupported(result.toolID)
                }
                _ = replaceToolResult(updated, in: sessionID)
                operationErrorMessage = nil
            } catch {
                operationErrorMessage = Self.userFacingMessage(for: error)
            }
        }
    }

    func retryTool(_ result: V2ToolExecutionResult) {
        guard !isRunningTurn, mayMutate,
              [.failed, .conflict, .blocked].contains(result.state),
              let assistantRequestID = result.assistantRequestID,
              let argumentsJSON = result.argumentsJSON,
              let sessionID = selectedSession?.id else { return }
        let call = V2AgentToolCall(
            toolID: result.toolID,
            argumentsJSON: argumentsJSON,
            modelCallID: result.modelCallID
        )
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let catalog = try dependencies.toolCatalog()
                _ = try catalog.validate(call)
                let context = V2ToolExecutionContext(
                    traceID: UUID().uuidString,
                    assistantRequestID: assistantRequestID,
                    attemptID: UUID().uuidString,
                    callOrdinal: result.callOrdinal ?? 0,
                    toolID: result.toolID,
                    submittedText: result.submittedText ?? "",
                    sourceEvidence: result.submittedText.map { [V2ToolSourceEvidence(excerpt: $0)] } ?? [],
                    intent: V2AssistantWriteIntent.authorize(result.submittedText ?? "",
                        priorMessages: self.priorMessages(sessionID: sessionID, before: assistantRequestID),
                        hasTaskReference: self.workspace.session(id: sessionID)?.sourceTask != nil) ? .explicitWrite : .discussion,
                    assistantContext: self.workspace.session(id: sessionID).map { self.requestContext(for: $0, before: assistantRequestID, at: self.now()) },
                    conversation: self.workspace.session(id: sessionID).map { self.conversation(from: $0, before: assistantRequestID) } ?? []
                )
                let updated = try await dependencies.executeTool(call, context)
                guard updated.operationID == context.operationID else {
                    throw V2ToolExecutionError.unsupported(result.toolID)
                }
                _ = replaceToolResult(updated.bound(to: call, context: context), in: sessionID)
                operationErrorMessage = nil
            } catch {
                operationErrorMessage = Self.userFacingMessage(for: error)
            }
        }
    }

    @discardableResult
    private func replaceToolResult(_ result: V2ToolExecutionResult, in sessionID: String) -> Bool {
        commitWorkspace { workspace in
            guard let sessionIndex = workspace.sessions.firstIndex(where: { $0.id == sessionID }) else { return }
            for messageIndex in workspace.sessions[sessionIndex].messages.indices {
                for partIndex in workspace.sessions[sessionIndex].messages[messageIndex].parts.indices {
                    guard case let .tool(existing) = workspace.sessions[sessionIndex].messages[messageIndex].parts[partIndex],
                          existing.operationID == result.operationID else { continue }
                    workspace.sessions[sessionIndex].messages[messageIndex].parts[partIndex] = .tool(result)
                    workspace.sessions[sessionIndex].messages[messageIndex].updatedAt = now()
                }
            }
            workspace.sessions[sessionIndex].updatedAt = now()
        }
    }
}


extension V2AssistantStore {
    /// Business facts and conversation UI use separate stores. Reconcile the
    /// durable host receipt after a crash between those two saves.
    @discardableResult
    func reconcileToolOperations(in workspace: inout V2AgentWorkspace) -> Bool {
        var changed = false
        for session in workspace.sessions.indices {
            var requestID: String?
            for message in workspace.sessions[session].messages.indices {
                if workspace.sessions[session].messages[message].role == .user {
                    requestID = workspace.sessions[session].messages[message].id
                    continue
                }
                guard let currentRequestID = requestID else { continue }
                for result in dependencies.recoverToolOperations(currentRequestID) {
                    var parts = workspace.sessions[session].messages[message].parts
                    if let index = parts.firstIndex(where: { part in
                        if case let .tool(old) = part { return old.operationID == result.operationID }
                        return false
                    }) {
                        if parts[index] == .tool(result) { continue }
                        parts[index] = .tool(result)
                    } else { parts.append(.tool(result)) }
                    workspace.sessions[session].messages[message].parts = parts
                    changed = true
                }
                requestID = nil
            }
        }
        return changed
    }
}

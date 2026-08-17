import Foundation
import SwiftUI
import ToughTrialV2Core

@MainActor
final class V2AssistantStore: ObservableObject {
    @Published var workspace: V2AgentWorkspace
    @Published private(set) var storageState: V2AssistantStorageState
    @Published private(set) var storageIssueMessage: String?
    @Published var operationErrorMessage: String?

    var selectedSession: V2AgentSession? { workspace.selectedSession }
    var isRunningTurn: Bool { currentTurn != nil }
    var providerStatus: V2AssistantProviderStatus { dependencies.providerStatus() }

    let dependencies: V2AssistantDependencies
    let persistence: V2AssistantWorkspacePersistence
    let now: @MainActor @Sendable () -> Date
    var currentTurn: Task<Void, Never>?

    convenience init(appStore: V2AppStore) {
        let environment = ProcessInfo.processInfo.environment
        let isUITestMode = environment["TOUGH_TRIAL_UI_TEST_EMPTY"] == "1"
            || environment["TOUGH_TRIAL_UI_TESTING"] == "1"
        let persistence: V2AssistantWorkspacePersistence
        if isUITestMode {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(
                "tough-trial-assistant-ui-\(ProcessInfo.processInfo.processIdentifier).json"
            )
            try? FileManager.default.removeItem(at: url)
            persistence = V2AssistantWorkspacePersistence(
                store: V2AgentWorkspaceJSONStore(fileURL: url)
            )
        } else if let url = try? V2AgentWorkspaceJSONStore.defaultFileURL() {
            persistence = V2AssistantWorkspacePersistence(
                store: V2AgentWorkspaceJSONStore(fileURL: url)
            )
        } else {
            persistence = .unavailable
        }
        self.init(dependencies: appStore.makeAssistantDependencies(), persistence: persistence)
    }

    init(
        dependencies: V2AssistantDependencies,
        persistence: V2AssistantWorkspacePersistence,
        initialWorkspace: V2AgentWorkspace? = nil,
        now: @escaping @MainActor @Sendable () -> Date = Date.init
    ) {
        self.dependencies = dependencies
        self.persistence = persistence
        self.now = now
        workspace = initialWorkspace ?? .empty
        storageState = persistence.isAvailable ? .healthy : .unavailable

        guard persistence.isAvailable else {
            storageIssueMessage = "助手存储位置不可用；修复前不会写入会话。"
            ensureSessionInMemory()
            return
        }

        if initialWorkspace == nil {
            do {
                workspace = try persistence.load()
            } catch {
                workspace = .empty
                storageState = .corruptRead
                storageIssueMessage = "助手会话文件无法读取，原文件已保留。修复前不会覆盖。"
                ensureSessionInMemory()
                return
            }
        }

        var normalized = workspace
        let recoveredInterruptedTurns = Self.recoverInterruptedTurns(in: &normalized, at: now())
        let reconciledPlans = reconcileAcceptedArtifacts(in: &normalized)
        var changed = recoveredInterruptedTurns || reconciledPlans
        if normalized.selectedSession == nil {
            _ = normalized.createSession(at: now())
            changed = true
        }
        workspace = normalized
        if changed {
            _ = saveCurrentWorkspace()
        }
    }

    func createSession() {
        guard mayMutate else { return }
        _ = commitWorkspace { _ = $0.createSession(at: now()) }
    }

    @discardableResult
    func selectSession(id: String) -> Bool {
        guard mayMutate, workspace.session(id: id) != nil else { return false }
        return commitWorkspace { _ = $0.selectSession(id: id) }
    }

    func send(_ text: String) {
        let userText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userText.isEmpty, currentTurn == nil, mayMutate,
              let sessionID = workspace.selectedSessionID else { return }

        operationErrorMessage = nil
        let date = now()
        let userMessage = V2AgentMessage.userText(userText, at: date)
        guard commitWorkspace({ _ = $0.appendMessage(userMessage, to: sessionID) }) else {
            appendUnsavedFailureResponse(to: sessionID, at: date)
            return
        }

        do {
            let snapshot = try dependencies.modelSnapshot()
            let agentMessage = V2AgentMessage(role: .agent, parts: [], createdAt: date, status: .pending)
            var turn = makeTurn(
                sessionID: sessionID,
                userMessage: userMessage,
                agentMessage: agentMessage,
                snapshot: snapshot,
                at: date
            )
            turn.activeTool = .model
            guard commitWorkspace({ workspace in
                _ = workspace.appendMessage(agentMessage, to: sessionID)
                Self.updateTurn(in: &workspace, turn: turn, messageStatus: .pending,
                                traceStatus: .running, at: date)
            }) else {
                markTurnFailedInMemory(turn, error: V2AssistantTurnError.persistenceUnavailable, at: date)
                return
            }
            launch(turn)
        } catch {
            appendFailedResponse(to: sessionID, error: error, at: date)
        }
    }

    func retry(messageID: String) {
        guard currentTurn == nil, mayMutate else { return }
        reconcileAndPersistIfNeeded()
        guard mayMutate, let pair = retryPair(for: messageID) else { return }

        do {
            let snapshot = try dependencies.modelSnapshot()
            var turn = makeTurn(
                sessionID: pair.sessionID,
                userMessage: pair.user,
                agentMessage: pair.agent,
                snapshot: snapshot,
                at: now()
            )
            turn.activeTool = .model
            guard commitWorkspace({ workspace in
                Self.updateTurn(in: &workspace, turn: turn, messageStatus: .pending,
                                traceStatus: .running, at: now())
            }) else {
                markTurnFailedInMemory(turn, error: V2AssistantTurnError.persistenceUnavailable, at: now())
                return
            }
            launch(turn)
        } catch {
            appendErrorToExistingResponse(pair, error: error, at: now())
        }
    }

    func cancelCurrentTurn() {
        currentTurn?.cancel()
    }

    func waitForCurrentTurn() async {
        await currentTurn?.value
    }

    @discardableResult
    func retryStorage() -> Bool {
        guard storageState == .transientWriteFailure else { return false }
        _ = reconcileAcceptedArtifacts(in: &workspace)
        let saved = saveCurrentWorkspace()
        if saved { operationErrorMessage = nil }
        return saved
    }

    @discardableResult
    func reopenWorkspace() -> Bool {
        guard persistence.isAvailable, currentTurn == nil else { return false }
        do {
            var loaded = try persistence.load()
            _ = Self.recoverInterruptedTurns(in: &loaded, at: now())
            _ = reconcileAcceptedArtifacts(in: &loaded)
            if loaded.selectedSession == nil { _ = loaded.createSession(at: now()) }
            workspace = loaded
            storageState = .healthy
            storageIssueMessage = nil
            let saved = saveCurrentWorkspace()
            if saved { operationErrorMessage = nil }
            return saved
        } catch {
            storageState = .corruptRead
            storageIssueMessage = "助手会话文件仍无法读取，原文件未被覆盖。"
            return false
        }
    }

    @discardableResult
    func toggleBrowser(source: V2WebSource, sessionID: String) -> Bool {
        guard mayMutate, sessionOwns(sourceID: source.id, sessionID: sessionID) else { return false }
        return commitWorkspace { workspace in
            guard let index = workspace.sessions.firstIndex(where: { $0.id == sessionID }) else { return }
            if let browserIndex = workspace.sessions[index].browserSessions
                .firstIndex(where: { $0.sourceID == source.id }) {
                workspace.sessions[index].browserSessions[browserIndex].isExpanded.toggle()
                workspace.sessions[index].browserSessions[browserIndex].updatedAt = now()
            } else {
                workspace.sessions[index].browserSessions.append(
                    V2BrowserSessionState(
                        id: UUID().uuidString,
                        sourceID: source.id,
                        lastURL: source.url,
                        isExpanded: true,
                        updatedAt: now()
                    )
                )
            }
            workspace.sessions[index].updatedAt = now()
        }
    }

    @discardableResult
    func updateBrowserState(_ state: V2BrowserSessionState, sessionID: String) -> Bool {
        let owners = workspace.sessions.filter { session in
            session.browserSessions.contains(where: { $0.id == state.id })
        }
        guard mayMutate, owners.count == 1, owners[0].id == sessionID else { return false }
        return commitWorkspace { workspace in
            guard let index = workspace.sessions.firstIndex(where: { $0.id == sessionID }) else { return }
            if state.isFullscreen {
                for browserIndex in workspace.sessions[index].browserSessions.indices {
                    workspace.sessions[index].browserSessions[browserIndex].isFullscreen = false
                }
            }
            _ = workspace.updateBrowserState(state, in: sessionID)
        }
    }

    func acceptPlan(_ draft: V2PlanDraft) {
        guard currentTurn == nil else { return }
        reconcileAndPersistIfNeeded()
        guard mayMutate,
              let sessionID = owningSessionID(forPlanID: draft.id),
              workspace.session(id: sessionID)?.pendingPlan?.id == draft.id else { return }

        do {
            let status = dependencies.planDraftStatus(draft.id)
            if status == .discarded { throw V2AssistantTurnError.planDiscarded }
            if status != .accepted {
                let accepted = try dependencies.planAcceptance(draft, now())
                guard accepted == .accepted else { throw V2AssistantTurnError.planUnavailable }
            }
            if commitWorkspace({
                Self.clearPlanArtifact(draft.id, in: &$0, sessionID: sessionID, at: now())
            }) {
                operationErrorMessage = nil
            }
        } catch {
            operationErrorMessage = Self.userFacingMessage(for: error)
        }
    }
}

extension V2AssistantStore {
    struct RetryPair {
        var sessionID: String
        var user: V2AgentMessage
        var agent: V2AgentMessage
    }

    var mayMutate: Bool { storageState == .healthy }

    func launch(_ turn: TurnState) {
        currentTurn = Task { [weak self] in
            guard let self else { return }
            await self.runTurn(turn)
            currentTurn = nil
        }
    }

    func retryPair(for messageID: String) -> RetryPair? {
        for session in workspace.sessions {
            guard let index = session.messages.firstIndex(where: { $0.id == messageID }) else { continue }
            let agentIndex: Int
            if session.messages[index].role == .agent {
                agentIndex = index
            } else {
                agentIndex = index + 1
            }
            guard agentIndex > 0, agentIndex < session.messages.count else { return nil }
            let user = session.messages[agentIndex - 1]
            let agent = session.messages[agentIndex]
            guard user.role == .user, agent.role == .agent,
                  [.failed, .cancelled].contains(agent.status) else { return nil }
            return RetryPair(sessionID: session.id, user: user, agent: agent)
        }
        return nil
    }

    func appendFailedResponse(to sessionID: String, error: Error, at date: Date) {
        let message = Self.userFacingMessage(for: error)
        operationErrorMessage = message
        let agent = V2AgentMessage(
            role: .agent,
            parts: [.error(.retryable(message))],
            createdAt: date,
            status: .failed
        )
        _ = commitWorkspace { _ = $0.appendMessage(agent, to: sessionID) }
    }

    func appendUnsavedFailureResponse(to sessionID: String, at date: Date) {
        let message = Self.userFacingMessage(for: V2AssistantTurnError.persistenceUnavailable)
        let agent = V2AgentMessage(
            role: .agent,
            parts: [.error(.retryable(message))],
            createdAt: date,
            status: .failed
        )
        _ = workspace.appendMessage(agent, to: sessionID)
        operationErrorMessage = message
    }

    func appendErrorToExistingResponse(_ pair: RetryPair, error: Error, at date: Date) {
        let message = Self.userFacingMessage(for: error)
        operationErrorMessage = message
        var agent = pair.agent
        agent.parts = [.error(.retryable(message))]
        agent.status = .failed
        agent.updatedAt = date
        _ = commitWorkspace { _ = $0.replaceMessage(agent, in: pair.sessionID) }
    }

    func markTurnFailedInMemory(_ turn: TurnState, error: Error, at date: Date) {
        operationErrorMessage = Self.userFacingMessage(for: error)
        Self.updateTurn(
            in: &workspace,
            turn: turn,
            messageStatus: .failed,
            traceStatus: .failed,
            error: .retryable(operationErrorMessage ?? "会话保存失败。"),
            endedAt: date,
            at: date
        )
    }

    func ensureSessionInMemory() {
        if workspace.selectedSession == nil { _ = workspace.createSession(at: now()) }
    }

    func reconcileAndPersistIfNeeded() {
        var next = workspace
        guard reconcileAcceptedArtifacts(in: &next) else { return }
        workspace = next
        _ = saveCurrentWorkspace()
    }

    func reconcileAcceptedArtifacts(in workspace: inout V2AgentWorkspace) -> Bool {
        var changed = false
        for session in workspace.sessions {
            guard let draft = session.pendingPlan,
                  dependencies.planDraftStatus(draft.id) == .accepted else { continue }
            Self.clearPlanArtifact(draft.id, in: &workspace, sessionID: session.id, at: now())
            changed = true
        }
        return changed
    }

    static func clearPlanArtifact(
        _ planID: String,
        in workspace: inout V2AgentWorkspace,
        sessionID: String,
        at date: Date
    ) {
        guard let sessionIndex = workspace.sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        if workspace.sessions[sessionIndex].pendingPlan?.id == planID {
            workspace.sessions[sessionIndex].pendingPlan = nil
            workspace.sessions[sessionIndex].pendingPlanPrompt = nil
        }
        for messageIndex in workspace.sessions[sessionIndex].messages.indices {
            workspace.sessions[sessionIndex].messages[messageIndex].parts.removeAll { part in
                guard case let .plan(plan) = part else { return false }
                return plan.id == planID
            }
        }
        workspace.sessions[sessionIndex].updatedAt = date
    }

    static func recoverInterruptedTurns(in workspace: inout V2AgentWorkspace, at date: Date) -> Bool {
        var changed = false
        for sessionIndex in workspace.sessions.indices {
            for messageIndex in workspace.sessions[sessionIndex].messages.indices {
                let status = workspace.sessions[sessionIndex].messages[messageIndex].status
                guard status == .pending || status == .streaming else { continue }
                let message = "上次请求被中断，可以重试。"
                workspace.sessions[sessionIndex].messages[messageIndex].parts.removeAll {
                    if case .error = $0 { return true }
                    return false
                }
                workspace.sessions[sessionIndex].messages[messageIndex].parts = workspace
                    .sessions[sessionIndex].messages[messageIndex].parts.map { part in
                        guard case let .trace(summary) = part else { return part }
                        return .trace(
                            V2AgentTraceSummary(
                                status: .failed,
                                toolCount: summary.toolCount,
                                duration: summary.duration
                            )
                        )
                    }
                workspace.sessions[sessionIndex].messages[messageIndex].parts.append(.error(.retryable(message)))
                workspace.sessions[sessionIndex].messages[messageIndex].status = .failed
                workspace.sessions[sessionIndex].messages[messageIndex].updatedAt = date
                changed = true
            }
            for traceIndex in workspace.sessions[sessionIndex].traces.indices
                where workspace.sessions[sessionIndex].traces[traceIndex].status == .running {
                let trace = workspace.sessions[sessionIndex].traces[traceIndex]
                workspace.sessions[sessionIndex].traces[traceIndex] = V2AgentTrace(
                    id: trace.id,
                    status: .failed,
                    steps: trace.steps,
                    startedAt: trace.startedAt,
                    endedAt: date,
                    providerLabel: trace.providerLabel,
                    model: trace.model,
                    providerSessionID: trace.providerSessionID,
                    requestID: trace.requestID,
                    responseID: trace.responseID,
                    promptTokens: trace.promptTokens,
                    completionTokens: trace.completionTokens,
                    totalTokens: trace.totalTokens
                )
                changed = true
            }
        }
        return changed
    }

    func owningSessionID(forPlanID planID: String) -> String? {
        let owners = workspace.sessions.filter { $0.pendingPlan?.id == planID }
        return owners.count == 1 ? owners[0].id : nil
    }

    func sessionOwns(sourceID: String, sessionID: String) -> Bool {
        guard let session = workspace.session(id: sessionID) else { return false }
        return session.messages.contains { message in
            message.parts.contains { part in
                guard case let .sources(sources) = part else { return false }
                return sources.contains(where: { $0.id == sourceID })
            }
        }
    }

    @discardableResult
    func commitWorkspace(_ mutation: (inout V2AgentWorkspace) -> Void) -> Bool {
        guard mayMutate else { return false }
        var next = workspace
        mutation(&next)
        workspace = next
        return saveCurrentWorkspace()
    }

    @discardableResult
    func saveCurrentWorkspace() -> Bool {
        guard persistence.isAvailable, storageState != .corruptRead else { return false }
        do {
            try persistence.save(workspace)
            storageState = .healthy
            storageIssueMessage = nil
            return true
        } catch {
            storageState = .transientWriteFailure
            storageIssueMessage = "助手会话无法保存；当前状态保留在内存中，可重试存储。"
            operationErrorMessage = storageIssueMessage
            return false
        }
    }

    static func userFacingMessage(for error: Error) -> String {
        let raw = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        return String(redactCredentials(in: raw).prefix(1_000))
    }

    static func redactCredentials(in value: String) -> String {
        let patterns = [
            #"(?i)(authorization|proxy-authorization)\s*[:=]\s*(?:bearer\s+)?[^\s,;]+"#,
            #"(?i)\bbearer\s+[A-Za-z0-9._~+/=-]+"#,
            #"(?i)\b(?:x-)?api[-_ ]?key\s*[:=]\s*[^\s,;]+"#,
            #"(?i)\b(?:cookie|set-cookie)\s*[:=]\s*[^\r\n]+"#,
            #"(?i)\b(?:token|secret|password)\s*[:=]\s*[^\s,;]+"#
        ]
        return patterns.reduce(value) { output, pattern in
            guard let expression = try? NSRegularExpression(pattern: pattern) else { return output }
            return expression.stringByReplacingMatches(
                in: output,
                range: NSRange(output.startIndex..<output.endIndex, in: output),
                withTemplate: "[REDACTED]"
            )
        }
    }
}

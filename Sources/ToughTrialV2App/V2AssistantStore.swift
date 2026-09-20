import Foundation
import SwiftUI
import Combine
import ToughTrialV2Core

@MainActor
final class V2AssistantStore: ObservableObject {
    @Published var workspace: V2AgentWorkspace
    @Published private(set) var storageState: V2AssistantStorageState
    @Published private(set) var storageIssueMessage: String?
    @Published var operationErrorMessage: String?
    @Published var contextIssueMessage: String?
    let contextArchive: V2AssistantArchive
    @Published var activity: Activity?

    struct Activity {
        let messageID: String
        let tool: V2AgentTool
    }

    var selectedSession: V2AgentSession? { workspace.selectedSession }
    var isRunningTurn: Bool { currentTurn != nil }
    var providerStatus: V2AssistantProviderStatus {
        if let choice = selectedSession?.modelSelection, let status = dependencies.selectedProviderStatus { return status(choice) }
        return dependencies.providerStatus()
    }

    let dependencies: V2AssistantDependencies
    let persistence: V2AssistantWorkspacePersistence
    let now: @MainActor @Sendable () -> Date
    var currentTurn: Task<Void, Never>?
    private var moduleObservation: AnyCancellable?
    var selectionRevision = 0
    /// The visible native composer supplies a synchronous flush before desktop navigation/quit.
    var flushVisibleDraft: (@MainActor () -> Bool)?

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
        let archiveURL = isUITestMode ? nil : try? V2AgentWorkspaceJSONStore.defaultFileURL()
            .deletingLastPathComponent().appendingPathComponent("assistant-context", isDirectory: true)
        self.init(dependencies: appStore.makeAssistantDependencies(), persistence: persistence,
                  archive: V2AssistantArchive(rootURL: archiveURL))
    }

    init(
        dependencies: V2AssistantDependencies,
        persistence: V2AssistantWorkspacePersistence,
        initialWorkspace: V2AgentWorkspace? = nil,
        archive: V2AssistantArchive? = nil,
        now: @escaping @MainActor @Sendable () -> Date = Date.init
    ) {
        self.dependencies = dependencies
        self.contextArchive = archive ?? V2AssistantArchive()
        self.persistence = persistence
        self.now = now
        workspace = initialWorkspace ?? .empty
        storageState = persistence.isAvailable ? .healthy : .unavailable

        moduleObservation = NotificationCenter.default.publisher(for: .v2ModulesChanged).sink { [weak self] _ in
            if !V2PluginStore.shared.enabled("assistant") { self?.cancelCurrentTurn() }
        }

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
        let recoveryDate = now()
        let recoveredInterruptedTurns = Self.recoverInterruptedTurns(in: &normalized, at: recoveryDate)
        let recoveredBrowserPresentation = Self.recoverBrowserPresentationState(
            in: &normalized,
            at: recoveryDate
        )
        let reconciledPlans = reconcileAcceptedArtifacts(in: &normalized)
        let recoveredTools = reconcileToolOperations(in: &normalized)
        var changed = recoveredInterruptedTurns || recoveredBrowserPresentation || reconciledPlans || recoveredTools
        if normalized.selectedSession == nil {
            _ = normalized.createSession(at: now())
            changed = true
        }
        workspace = normalized
        if changed {
            _ = saveCurrentWorkspace()
        }
        syncContextArchive()
    }

    func createSession() {
        guard mayMutate else { return }
        selectionRevision += 1
        _ = commitWorkspace { _ = $0.createSession(at: now()) }
    }

    @discardableResult
    func openContextSession(for sourceTask: V2AgentSourceTask) -> Bool {
        guard mayMutate else { return false }
        if let existing = workspace.sessions
            .filter({ $0.sourceTask?.id == sourceTask.id })
            .max(by: { $0.updatedAt < $1.updatedAt }) {
            return selectSession(id: existing.id)
        }
        selectionRevision += 1
        return commitWorkspace {
            _ = $0.createSession(at: now(), sourceTask: sourceTask)
        }
    }

    @discardableResult
    func selectSession(id: String) -> Bool {
        guard mayMutate, workspace.session(id: id) != nil else { return false }
        if workspace.selectedSessionID != id { selectionRevision += 1 }
        return commitWorkspace { _ = $0.selectSession(id: id) }
    }

    @discardableResult
    func deleteSession(id: String) -> Bool {
        guard mayMutate, currentTurn == nil, workspace.sessions.count > 1,
              workspace.session(id: id) != nil else { return false }
        return commitWorkspace { _ = $0.deleteSession(id: id) }
    }

    @discardableResult
    func send(_ text: String, inputSource: V2UsageEvent.Source = .keyboard, references: [V2AssistantMessageReference] = [], attachments: [V2AssistantAttachment] = [], sessionID targetSessionID: String? = nil) -> Bool {
        guard V2PluginStore.shared.enabled("assistant") else { operationErrorMessage = "助手已停用，可在功能与插件中开启。"; return false }
        let userText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userText.isEmpty, currentTurn == nil, mayMutate,
              let sessionID = targetSessionID ?? workspace.selectedSessionID else { return false }

        operationErrorMessage = nil
        let date = now()
        var userMessage = V2AgentMessage.userText(userText, at: date)
        userMessage.references = references.isEmpty ? nil : references
        userMessage.attachments = attachments.isEmpty ? nil : attachments
        let agentMessage = V2AgentMessage(role: .agent, parts: [], createdAt: date, status: .pending)

        do {
            let snapshot = try modelSnapshot(for: sessionID)
            var turn = try makeTurn(
                sessionID: sessionID,
                userMessage: userMessage,
                agentMessage: agentMessage,
                snapshot: snapshot,
                at: date
            )
            turn.activeTool = .model
            guard commitWorkspace({ workspace in
                _ = workspace.appendMessage(userMessage, to: sessionID)
                _ = workspace.appendMessage(agentMessage, to: sessionID)
                Self.updateTurn(in: &workspace, turn: turn, messageStatus: .pending,
                                traceStatus: .running, at: date)
            }) else {
                markTurnFailedInMemory(turn, error: V2AssistantTurnError.persistenceUnavailable, at: date)
                return false
            }
            V2UsageTrace.shared.record(.init(kind: .inputSubmitted, source: inputSource,
                sessionID: sessionID, operationID: userMessage.id, characterCount: userText.count, at: date))
            launch(turn)
            return true
        } catch {
            appendFailedTurnPair(
                userMessage: userMessage,
                agentMessage: agentMessage,
                to: sessionID,
                error: error,
                at: date
            )
            return false
        }
    }

    func retry(messageID: String) {
        guard V2PluginStore.shared.enabled("assistant") else { operationErrorMessage = "助手已停用，可在功能与插件中开启。"; return }
        guard currentTurn == nil, mayMutate else { return }
        reconcileAndPersistIfNeeded()
        guard mayMutate, let pair = retryPair(for: messageID) else { return }

        do {
            let snapshot = try modelSnapshot(for: pair.sessionID)
            var turn = try makeTurn(
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
        guard persistence.isAvailable,
              storageState == .corruptRead || storageState == .unavailable,
              currentTurn == nil else { return false }
        do {
            var loaded = try persistence.load()
            let recoveryDate = now()
            _ = Self.recoverInterruptedTurns(in: &loaded, at: recoveryDate)
            _ = Self.recoverBrowserPresentationState(in: &loaded, at: recoveryDate)
            _ = reconcileAcceptedArtifacts(in: &loaded)
            _ = reconcileToolOperations(in: &loaded)
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
        guard mayMutate, Self.isSupportedWebURL(source.url),
              sessionOwns(sourceID: source.id, sessionID: sessionID) else {
            return false
        }
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
    func updateBrowserPresentation(
        browserID: String,
        sessionID: String,
        isExpanded: Bool? = nil,
        isFullscreen: Bool? = nil
    ) -> Bool {
        let owners = workspace.sessions.filter { session in
            session.browserSessions.contains(where: { $0.id == browserID })
        }
        guard mayMutate, owners.count == 1, owners[0].id == sessionID else { return false }
        return commitWorkspace { workspace in
            guard let sessionIndex = workspace.sessions.firstIndex(where: { $0.id == sessionID }),
                  let browserIndex = workspace.sessions[sessionIndex].browserSessions
                    .firstIndex(where: { $0.id == browserID }) else {
                return
            }
            if isFullscreen == true {
                for browserIndex in workspace.sessions[sessionIndex].browserSessions.indices {
                    workspace.sessions[sessionIndex].browserSessions[browserIndex].isFullscreen = false
                }
            }
            if let isExpanded {
                workspace.sessions[sessionIndex].browserSessions[browserIndex].isExpanded = isExpanded
            }
            if let isFullscreen {
                workspace.sessions[sessionIndex].browserSessions[browserIndex].isFullscreen = isFullscreen
            }
            workspace.sessions[sessionIndex].browserSessions[browserIndex].updatedAt = now()
            workspace.sessions[sessionIndex].updatedAt = now()
        }
    }

    @discardableResult
    func updateBrowserNavigation(
        _ update: V2AssistantBrowserNavigationUpdate,
        sessionID: String
    ) -> Bool {
        let owners = workspace.sessions.filter { session in
            session.browserSessions.contains(where: { $0.id == update.browserID })
        }
        guard mayMutate, owners.count == 1, owners[0].id == sessionID,
              Self.isSupportedWebURL(update.lastURL) else {
            return false
        }
        return commitWorkspace { workspace in
            guard let sessionIndex = workspace.sessions.firstIndex(where: { $0.id == sessionID }),
                  let browserIndex = workspace.sessions[sessionIndex].browserSessions
                    .firstIndex(where: { $0.id == update.browserID }) else {
                return
            }
            workspace.sessions[sessionIndex].browserSessions[browserIndex].lastURL = update.lastURL
            workspace.sessions[sessionIndex].browserSessions[browserIndex].navigationHistory =
                update.navigationHistory.filter(Self.isSupportedWebURL)
            workspace.sessions[sessionIndex].browserSessions[browserIndex].scrollOffsetY =
                max(0, update.scrollOffsetY)
            workspace.sessions[sessionIndex].browserSessions[browserIndex].updatedAt = now()
            workspace.sessions[sessionIndex].updatedAt = now()
        }
    }

    func acceptPlan(_ draft: V2PlanDraft) {
        guard currentTurn == nil, V2PluginStore.shared.enabled("assistant") else { return }
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

    @discardableResult
    func updatePlanItem(_ item: V2PlanDraftScheduleItem, in planID: String) -> Bool {
        guard currentTurn == nil, mayMutate,
              dependencies.planDraftStatus(planID) != .accepted,
              let sessionID = owningSessionID(forPlanID: planID),
              let session = workspace.session(id: sessionID),
              session.pendingPlan?.scheduleItems.contains(where: { $0.id == item.id }) == true else {
            return false
        }

        return commitWorkspace { workspace in
            guard let sessionIndex = workspace.sessions.firstIndex(where: { $0.id == sessionID }) else {
                return
            }
            if let itemIndex = workspace.sessions[sessionIndex].pendingPlan?.scheduleItems
                .firstIndex(where: { $0.id == item.id }) {
                workspace.sessions[sessionIndex].pendingPlan?.scheduleItems[itemIndex] = item
            }
            for messageIndex in workspace.sessions[sessionIndex].messages.indices {
                for partIndex in workspace.sessions[sessionIndex].messages[messageIndex].parts.indices {
                    guard case var .plan(plan) = workspace.sessions[sessionIndex]
                        .messages[messageIndex].parts[partIndex], plan.id == planID,
                        let itemIndex = plan.scheduleItems.firstIndex(where: { $0.id == item.id }) else {
                        continue
                    }
                    plan.scheduleItems[itemIndex] = item
                    workspace.sessions[sessionIndex].messages[messageIndex].parts[partIndex] = .plan(plan)
                }
            }
            workspace.sessions[sessionIndex].updatedAt = now()
        }
    }

    func isPlanAccepted(_ draft: V2PlanDraft) -> Bool {
        dependencies.planDraftStatus(draft.id) == .accepted
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
        if V2PluginStore.shared.enabled("trace"), V2UsageTrace.shared.isEnabled { do {
            try contextArchive.record(sessionID: turn.sessionID, kind: "model_selected", requestID: turn.userMessageID,
                metadata: ["provider": turn.modelSnapshot.identity.label, "model": turn.modelSnapshot.identity.model,
                           "thinking": turn.modelSnapshot.thinking?.rawValue ?? "provider_default"], at: now())
        } catch { contextIssueMessage = "模型设置已生效，但诊断记录暂时无法保存。" } }
        currentTurn = Task { [weak self] in
            guard let self else { return }
            await self.runTurn(turn)
            currentTurn = nil
            activity = nil
            if !Task.isCancelled { self.sendNextQueuedDraft(in: turn.sessionID) }
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

    func appendFailedTurnPair(
        userMessage: V2AgentMessage,
        agentMessage: V2AgentMessage,
        to sessionID: String,
        error: Error,
        at date: Date
    ) {
        let message = Self.userFacingMessage(for: error)
        operationErrorMessage = message
        var failedAgent = agentMessage
        failedAgent.parts = [.error(.retryable(message))]
        failedAgent.status = .failed
        failedAgent.updatedAt = date
        _ = commitWorkspace {
            _ = $0.appendMessage(userMessage, to: sessionID)
            _ = $0.appendMessage(failedAgent, to: sessionID)
        }
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

    func markTurnFailedInMemory(
        _ turn: TurnState,
        error: Error,
        at date: Date,
        userFacingMessage: String? = nil
    ) {
        operationErrorMessage = userFacingMessage ?? Self.userFacingMessage(for: error, tool: turn.activeTool)
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
            guard workspace.sessions[sessionIndex].messages[messageIndex].parts.contains(where: { part in
                guard case let .plan(plan) = part else { return false }
                return plan.id == planID
            }) else { continue }
            workspace.sessions[sessionIndex].messages[messageIndex].updatedAt = date
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
            if workspace.sessions[sessionIndex].messages.last?.role == .user {
                workspace.sessions[sessionIndex].messages.append(
                    V2AgentMessage(
                        role: .agent,
                        parts: [.error(.retryable("上次请求在创建回复前中断，可以重试。"))],
                        createdAt: date,
                        status: .failed
                    )
                )
                workspace.sessions[sessionIndex].updatedAt = date
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

    static func recoverBrowserPresentationState(
        in workspace: inout V2AgentWorkspace,
        at date: Date
    ) -> Bool {
        var changed = false
        for sessionIndex in workspace.sessions.indices {
            var recoveredSession = false
            for browserIndex in workspace.sessions[sessionIndex].browserSessions.indices {
                guard workspace.sessions[sessionIndex].browserSessions[browserIndex].isFullscreen else {
                    continue
                }
                workspace.sessions[sessionIndex].browserSessions[browserIndex].isFullscreen = false
                workspace.sessions[sessionIndex].browserSessions[browserIndex].isExpanded = true
                workspace.sessions[sessionIndex].browserSessions[browserIndex].updatedAt = date
                recoveredSession = true
                changed = true
            }
            if recoveredSession {
                workspace.sessions[sessionIndex].updatedAt = date
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

    static func isSupportedWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return ["http", "https"].contains(scheme) && url.host != nil
    }

    @discardableResult
    func commitWorkspace(syncArchive: Bool = true, _ mutation: (inout V2AgentWorkspace) -> Void) -> Bool {
        guard mayMutate else { return false }
        var next = workspace
        mutation(&next)
        workspace = next
        return saveCurrentWorkspace(syncArchive: syncArchive)
    }

    @discardableResult
    func saveCurrentWorkspace(syncArchive: Bool = true) -> Bool {
        guard persistence.isAvailable, storageState != .corruptRead else { return false }
        do {
            try persistence.save(workspace)
            storageState = .healthy
            storageIssueMessage = nil
            if syncArchive { syncContextArchive() }
            return true
        } catch {
            storageState = .transientWriteFailure
            storageIssueMessage = "助手会话无法保存；当前状态保留在内存中，可重试存储。"
            operationErrorMessage = storageIssueMessage
            return false
        }
    }

    static func userFacingMessage(for error: Error, tool: V2AgentTool? = nil) -> String {
        if let tool,
           let webMessage = webUserFacingMessage(for: error, tool: tool) {
            return webMessage
        }
        let raw = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        return String(redactCredentials(in: raw).prefix(1_000))
    }

    static func webUserFacingMessage(for error: Error, tool: V2AgentTool) -> String? {
        guard tool == .webSearch || tool == .webRead else { return nil }

        if let runtimeError = error as? V2ModuleRuntimeError {
            switch runtimeError {
            case let .unavailable(id, _) where id == "core.web":
                return "网页搜索已停用，请到功能与插件→网页搜索开启后重试。"
            case let .stale(id, _, _) where id == "core.web":
                return "网页搜索状态已变化，请稍后重试。"
            default:
                break
            }
        }

        if let webError = error as? V2WebToolError {
            switch webError {
            case .invalidQuery, .invalidLimit:
                return "网页搜索请求无效，请调整关键词后重试。"
            case .unsupportedURL:
                return "网页地址不受支持，请打开来源或稍后重试。"
            case let .requestFailed(statusCode):
                switch statusCode {
                case 403:
                    return "网页访问被拒绝（403），请打开来源或稍后重试。"
                case 429:
                    return "网页服务请求过多（429），请稍后重试。"
                case 408:
                    return "网页请求超时（408），请稍后重试。"
                case 500..<600:
                    return "网页服务暂时不可用（\(statusCode)），请稍后重试。"
                default:
                    return "网页请求失败（\(statusCode)），请稍后重试。"
                }
            case .invalidResponse, .unsupportedContentType, .payloadTooLarge,
                 .invalidPayload, .unsupportedMarkup, .tooManyRedirects:
                if tool == .webSearch {
                    return "网页搜索结果结构不兼容，请调整关键词或稍后重试。"
                }
                return "网页返回内容结构不兼容，请打开来源或稍后重试。"
            }
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return "网页请求超时，请稍后重试。"
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost,
                 .cannotFindHost, .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff,
                 .secureConnectionFailed, .cannotLoadFromNetwork, .resourceUnavailable:
                return "网络连接中断，请检查网络后重试。"
            default:
                return "网页请求失败，请稍后重试。"
            }
        }

        return "网页请求失败，请稍后重试。"
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

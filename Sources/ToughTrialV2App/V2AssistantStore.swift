import Foundation
import SwiftUI
import ToughTrialV2Core

struct V2AssistantProviderStatus: Equatable, Sendable {
    var isConfigured: Bool
    var providerLabel: String
    var message: String?
}

struct V2AssistantDependencies: Sendable {
    var modelResponse: @MainActor @Sendable (V2AgentRequest) async throws -> V2AgentModelResult
    var webSearch: @MainActor @Sendable (String, Int) async throws -> [V2WebSearchResult]
    var webRead: @MainActor @Sendable (URL, Int) async throws -> String
    var localSearch: @MainActor @Sendable (String) async throws -> String
    var planGeneration: @MainActor @Sendable (
        V2AgentSession,
        String,
        Date
    ) async throws -> V2PlanningOutcome
    var planAcceptance: @MainActor @Sendable (V2PlanDraft, Date) throws -> Void
    var providerStatus: @MainActor @Sendable () -> V2AssistantProviderStatus
}

@MainActor
final class V2AssistantStore: ObservableObject {
    @Published private(set) var workspace: V2AgentWorkspace
    @Published private(set) var storageIssueMessage: String?
    @Published private(set) var operationErrorMessage: String?

    var selectedSession: V2AgentSession? { workspace.selectedSession }
    var isRunningTurn: Bool { currentTurn != nil }
    var providerStatus: V2AssistantProviderStatus { dependencies.providerStatus() }

    private let dependencies: V2AssistantDependencies
    private let workspaceStore: V2AgentWorkspaceJSONStore?
    private let now: @MainActor @Sendable () -> Date
    private var canPersistWorkspace: Bool
    private var currentTurn: Task<Void, Never>?

    convenience init(appStore: V2AppStore) {
        let environment = ProcessInfo.processInfo.environment
        let isUITestMode = environment["TOUGH_TRIAL_UI_TEST_EMPTY"] == "1"
            || environment["TOUGH_TRIAL_UI_TESTING"] == "1"
        let store: V2AgentWorkspaceJSONStore?
        if isUITestMode {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "tough-trial-assistant-ui-\(ProcessInfo.processInfo.processIdentifier).json"
                )
            try? FileManager.default.removeItem(at: url)
            store = V2AgentWorkspaceJSONStore(fileURL: url)
        } else {
            store = try? V2AgentWorkspaceJSONStore(
                fileURL: V2AgentWorkspaceJSONStore.defaultFileURL()
            )
        }
        self.init(
            dependencies: appStore.makeAssistantDependencies(),
            workspaceStore: store
        )
    }

    init(
        dependencies: V2AssistantDependencies,
        workspaceStore: V2AgentWorkspaceJSONStore?,
        initialWorkspace: V2AgentWorkspace? = nil,
        now: @escaping @MainActor @Sendable () -> Date = Date.init
    ) {
        self.dependencies = dependencies
        self.workspaceStore = workspaceStore
        self.now = now

        if let initialWorkspace {
            self.workspace = initialWorkspace
            self.canPersistWorkspace = workspaceStore != nil
            self.storageIssueMessage = workspaceStore == nil
                ? "助手存储位置不可用；当前会话不会写入磁盘。"
                : nil
        } else if let workspaceStore {
            do {
                self.workspace = try workspaceStore.loadOrCreateEmpty()
                self.canPersistWorkspace = true
                self.storageIssueMessage = nil
            } catch {
                self.workspace = .empty
                self.canPersistWorkspace = false
                self.storageIssueMessage = "助手会话文件无法读取，原文件已保留。修复前不会覆盖。"
            }
        } else {
            self.workspace = .empty
            self.canPersistWorkspace = false
            self.storageIssueMessage = "助手存储位置不可用；修复前不会写入会话。"
        }

        if workspace.selectedSession == nil {
            _ = workspace.createSession(at: now())
            if canPersistWorkspace {
                do {
                    try workspaceStore?.save(workspace)
                } catch {
                    canPersistWorkspace = false
                    storageIssueMessage = "助手会话无法保存；后续写入已停用。"
                }
            }
        }
    }

    func createSession() {
        guard canPersistWorkspace else { return }
        _ = commitWorkspace { workspace in
            _ = workspace.createSession(at: now())
        }
    }

    func selectSession(id: String) {
        guard workspace.session(id: id) != nil else { return }
        guard canPersistWorkspace else { return }
        _ = commitWorkspace { workspace in
            _ = workspace.selectSession(id: id)
        }
    }

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, currentTurn == nil, canPersistWorkspace else { return }
        guard let sessionID = workspace.selectedSessionID else { return }

        operationErrorMessage = nil
        let date = now()
        let userMessage = V2AgentMessage.userText(trimmed, at: date)
        guard commitWorkspace({ workspace in
            _ = workspace.appendMessage(userMessage, to: sessionID)
        }) else { return }

        let agentMessage = V2AgentMessage(
            role: .agent,
            parts: [],
            createdAt: date,
            status: .pending
        )
        var turn = TurnState(
            sessionID: sessionID,
            userMessageID: userMessage.id,
            agentMessageID: agentMessage.id,
            userText: trimmed,
            traceID: UUID().uuidString,
            startedAt: date
        )
        turn.activeTool = .model
        guard commitWorkspace({ workspace in
            _ = workspace.appendMessage(agentMessage, to: sessionID)
            Self.updateTurn(
                in: &workspace,
                turn: turn,
                messageStatus: .pending,
                traceStatus: .running,
                at: date
            )
        }) else { return }

        currentTurn = Task { [weak self] in
            guard let self else { return }
            await self.runTurn(turn)
            self.currentTurn = nil
        }
    }

    func retry(messageID: String) {
        guard currentTurn == nil,
              let session = selectedSession,
              let index = session.messages.firstIndex(where: { $0.id == messageID })
        else { return }

        let message = session.messages[index]
        if message.role == .user {
            send(message.plainText)
            return
        }
        guard index > 0 else { return }
        let userMessage = session.messages[..<index].last { $0.role == .user }
        if let userMessage {
            send(userMessage.plainText)
        }
    }

    func cancelCurrentTurn() {
        currentTurn?.cancel()
    }

    func toggleBrowser(source: V2WebSource) {
        guard canPersistWorkspace, let sessionID = workspace.selectedSessionID else { return }
        _ = commitWorkspace { workspace in
            guard let sessionIndex = workspace.sessions.firstIndex(where: { $0.id == sessionID }) else {
                return
            }
            if let browserIndex = workspace.sessions[sessionIndex].browserSessions
                .firstIndex(where: { $0.sourceID == source.id }) {
                workspace.sessions[sessionIndex].browserSessions[browserIndex].isExpanded.toggle()
                workspace.sessions[sessionIndex].browserSessions[browserIndex].updatedAt = now()
            } else {
                workspace.sessions[sessionIndex].browserSessions.append(
                    V2BrowserSessionState(
                        id: UUID().uuidString,
                        sourceID: source.id,
                        lastURL: source.url,
                        isExpanded: true,
                        updatedAt: now()
                    )
                )
            }
            workspace.sessions[sessionIndex].updatedAt = now()
        }
    }

    func updateBrowserState(_ state: V2BrowserSessionState) {
        guard canPersistWorkspace, let sessionID = workspace.selectedSessionID else { return }
        _ = commitWorkspace { workspace in
            guard let sessionIndex = workspace.sessions.firstIndex(where: { $0.id == sessionID }) else {
                return
            }
            if state.isFullscreen {
                for index in workspace.sessions[sessionIndex].browserSessions.indices {
                    workspace.sessions[sessionIndex].browserSessions[index].isFullscreen = false
                }
            }
            _ = workspace.updateBrowserState(state, in: sessionID)
        }
    }

    func acceptPlan(_ draft: V2PlanDraft) {
        guard canPersistWorkspace,
              let sessionID = workspace.selectedSessionID,
              workspace.session(id: sessionID)?.pendingPlan?.id == draft.id
        else { return }

        do {
            try dependencies.planAcceptance(draft, now())
            guard commitWorkspace({ workspace in
                guard let index = workspace.sessions.firstIndex(where: { $0.id == sessionID }) else {
                    return
                }
                workspace.sessions[index].pendingPlan = nil
                workspace.sessions[index].pendingPlanPrompt = nil
                workspace.sessions[index].updatedAt = now()
            }) else { return }
            operationErrorMessage = nil
        } catch {
            operationErrorMessage = Self.userFacingMessage(for: error)
        }
    }
}

private extension V2AssistantStore {
    struct TurnState {
        var sessionID: String
        var userMessageID: String
        var agentMessageID: String
        var userText: String
        var traceID: String
        var startedAt: Date
        var steps: [V2AgentTraceStep] = []
        var observations: [V2AgentObservation] = []
        var sources: [V2WebSource] = []
        var plan: V2PlanDraft?
        var providerLabel: String?
        var model: String?
        var providerSessionID: String?
        var requestID: String?
        var responseID: String?
        var promptTokens: Int?
        var completionTokens: Int?
        var totalTokens: Int?
        var activeTool: V2AgentTool?

        func trace(status: V2AgentTraceStatus, endedAt: Date? = nil) -> V2AgentTrace {
            V2AgentTrace(
                id: traceID,
                status: status,
                steps: steps,
                startedAt: startedAt,
                endedAt: endedAt,
                providerLabel: providerLabel,
                model: model,
                providerSessionID: providerSessionID,
                requestID: requestID,
                responseID: responseID,
                promptTokens: promptTokens,
                completionTokens: completionTokens,
                totalTokens: totalTokens
            )
        }
    }

    func runTurn(_ initialTurn: TurnState) async {
        var turn = initialTurn
        var policy = V2AgentTurnPolicy(maximumToolCalls: 3)

        do {
            let providerStatus = dependencies.providerStatus()
            guard providerStatus.isConfigured else {
                throw V2AssistantTurnError.providerUnavailable(
                    providerStatus.message ?? "请先配置 AI 服务。"
                )
            }

            while true {
                try Task.checkCancellation()
                guard let session = workspace.session(id: turn.sessionID) else {
                    throw V2AssistantTurnError.sessionUnavailable
                }
                let request = V2AgentRequest(
                    userText: turn.userText,
                    conversation: conversation(
                        from: session,
                        excludingMessageID: turn.userMessageID
                    ),
                    observations: turn.observations,
                    conversationIdentifier: session.id
                )

                turn.activeTool = .model
                let modelStartedAt = now()
                let result = try await dependencies.modelResponse(request)
                try Task.checkCancellation()
                let modelEndedAt = now()
                turn.steps.append(
                    V2AgentTraceStep(
                        tool: .model,
                        status: .succeeded,
                        duration: modelEndedAt.timeIntervalSince(modelStartedAt)
                    )
                )
                turn.providerLabel = result.providerLabel
                turn.model = result.model
                turn.requestID = result.requestID
                turn.responseID = result.responseID
                turn.promptTokens = Self.sum(turn.promptTokens, result.promptTokens)
                turn.completionTokens = Self.sum(turn.completionTokens, result.completionTokens)
                turn.totalTokens = Self.sum(turn.totalTokens, result.totalTokens)
                turn.activeTool = nil
                guard persistRunningTurn(turn, at: modelEndedAt) else { return }

                if case let .answer(text) = result.action {
                    let answer = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !answer.isEmpty else {
                        throw V2AgentClientError.invalidOutput("回答不能为空")
                    }
                    finishTurn(&turn, text: answer, at: now())
                    return
                }

                guard policy.registerToolCall(result.action) else {
                    throw V2AssistantTurnError.toolLimitReached
                }
                try await execute(result.action, turn: &turn)
            }
        } catch is CancellationError {
            if let tool = turn.activeTool {
                turn.steps.append(
                    V2AgentTraceStep(
                        tool: tool,
                        status: .cancelled,
                        duration: 0,
                        error: V2AgentTraceError(category: .cancelled, code: .cancelled)
                    )
                )
            }
            cancelTurn(&turn, at: now())
        } catch where Task.isCancelled {
            if let tool = turn.activeTool {
                turn.steps.append(
                    V2AgentTraceStep(
                        tool: tool,
                        status: .cancelled,
                        duration: 0,
                        error: V2AgentTraceError(category: .cancelled, code: .cancelled)
                    )
                )
            }
            cancelTurn(&turn, at: now())
        } catch {
            if let tool = turn.activeTool {
                let traceError = Self.traceError(for: error, tool: tool)
                turn.steps.append(
                    V2AgentTraceStep(
                        tool: tool,
                        status: .failed,
                        duration: 0,
                        error: traceError
                    )
                )
            }
            failTurn(&turn, error: error, at: now())
        }
    }

    func execute(_ action: V2AgentAction, turn: inout TurnState) async throws {
        let startedAt = now()
        switch action {
        case .answer:
            return

        case let .webSearch(query):
            guard let safeQuery = V2AgentSafeSearchQuery(query) else {
                throw V2AgentClientError.invalidOutput("搜索词不符合安全约束")
            }
            turn.activeTool = .webSearch
            let results = try await dependencies.webSearch(query, 8)
            try Task.checkCancellation()
            let sources = results.prefix(8).compactMap(Self.source(from:))
            turn.sources.append(contentsOf: sources.filter { candidate in
                !turn.sources.contains(where: { $0.id == candidate.id })
            })
            let summary = Self.webSearchSummary(sources)
            turn.observations.append(
                V2AgentObservation(
                    sourceID: UUID().uuidString,
                    tool: .webSearch,
                    summary: summary
                )
            )
            turn.steps.append(
                V2AgentTraceStep(
                    tool: .webSearch,
                    status: .succeeded,
                    duration: now().timeIntervalSince(startedAt),
                    subject: .searchQuery(safeQuery)
                )
            )

        case let .webRead(url):
            guard let safeTraceURL = V2AgentTraceWebURL(url) else {
                throw V2WebToolError.unsupportedURL
            }
            turn.activeTool = .webRead
            let text = try await dependencies.webRead(url, 8_000)
            try Task.checkCancellation()
            let boundedText = String(text.prefix(8_000))
            let sourceID = UUID()
            let source = V2WebSource(
                id: sourceID.uuidString,
                title: url.host ?? "网页来源",
                url: url,
                snippet: String(boundedText.prefix(300)),
                siteName: url.host
            )
            turn.sources.append(source)
            turn.observations.append(
                V2AgentObservation(
                    sourceID: sourceID.uuidString,
                    tool: .webRead,
                    summary: String("来源：\(url.absoluteString)\n\(boundedText)".prefix(8_000))
                )
            )
            turn.steps.append(
                V2AgentTraceStep(
                    tool: .webRead,
                    status: .succeeded,
                    duration: now().timeIntervalSince(startedAt),
                    subject: .sourceURL(safeTraceURL)
                )
            )

        case let .localSearch(query):
            turn.activeTool = .localSearch
            let summary = try await dependencies.localSearch(query)
            try Task.checkCancellation()
            turn.observations.append(
                V2AgentObservation(
                    sourceID: UUID().uuidString,
                    tool: .localSearch,
                    summary: String(summary.prefix(4_000))
                )
            )
            turn.steps.append(
                V2AgentTraceStep(
                    tool: .localSearch,
                    status: .succeeded,
                    duration: now().timeIntervalSince(startedAt),
                    subject: .localScope(.mixed)
                )
            )

        case let .plan(query):
            guard let session = workspace.session(id: turn.sessionID) else {
                throw V2AssistantTurnError.sessionUnavailable
            }
            turn.activeTool = .plan
            let outcome = try await dependencies.planGeneration(session, query, startedAt)
            try Task.checkCancellation()
            let observationID = UUID().uuidString
            let sessionUpdate: (inout V2AgentSession) -> Void
            switch outcome {
            case let .clarification(clarification):
                turn.observations.append(
                    V2AgentObservation(
                        sourceID: observationID,
                        tool: .plan,
                        summary: String(clarification.question.prefix(1_000))
                    )
                )
                sessionUpdate = { session in
                    if session.pendingPlanPrompt == nil {
                        session.pendingPlanPrompt = session.pendingPlan?.userPrompt ?? query
                    }
                }
            case let .proposal(proposal):
                turn.plan = proposal.draft
                turn.observations.append(
                    V2AgentObservation(
                        sourceID: observationID,
                        tool: .plan,
                        summary: String(proposal.message.prefix(1_000))
                    )
                )
                sessionUpdate = { session in
                    session.pendingPlanPrompt = nil
                    session.pendingPlan = proposal.draft
                }
            }
            let subject = turn.plan.flatMap { V2AgentTraceArtifactID($0.id) }
                .map(V2AgentTraceSubject.planArtifact)
            turn.steps.append(
                V2AgentTraceStep(
                    tool: .plan,
                    status: .succeeded,
                    duration: now().timeIntervalSince(startedAt),
                    subject: subject
                )
            )
            turn.activeTool = nil
            guard persistRunningTurn(turn, at: now(), sessionUpdate: sessionUpdate) else {
                throw V2AssistantTurnError.persistenceUnavailable
            }
            return
        }
        turn.activeTool = nil
        guard persistRunningTurn(turn, at: now()) else {
            throw V2AssistantTurnError.persistenceUnavailable
        }
    }

    func persistRunningTurn(
        _ turn: TurnState,
        at date: Date,
        sessionUpdate: ((inout V2AgentSession) -> Void)? = nil
    ) -> Bool {
        commitWorkspace { workspace in
            Self.updateTurn(
                in: &workspace,
                turn: turn,
                messageStatus: .streaming,
                traceStatus: .running,
                at: date,
                sessionUpdate: sessionUpdate
            )
        }
    }

    func finishTurn(_ turn: inout TurnState, text: String, at date: Date) {
        turn.activeTool = nil
        _ = commitWorkspace { workspace in
            Self.updateTurn(
                in: &workspace,
                turn: turn,
                messageStatus: .complete,
                traceStatus: .succeeded,
                text: text,
                endedAt: date,
                at: date
            )
        }
    }

    func failTurn(_ turn: inout TurnState, error: Error, at date: Date) {
        turn.activeTool = nil
        let message = Self.userFacingMessage(for: error)
        operationErrorMessage = message
        _ = commitWorkspace { workspace in
            Self.updateTurn(
                in: &workspace,
                turn: turn,
                messageStatus: .failed,
                traceStatus: .failed,
                error: .retryable(message),
                endedAt: date,
                at: date
            )
        }
    }

    func cancelTurn(_ turn: inout TurnState, at date: Date) {
        turn.activeTool = nil
        _ = commitWorkspace { workspace in
            Self.updateTurn(
                in: &workspace,
                turn: turn,
                messageStatus: .cancelled,
                traceStatus: .cancelled,
                error: .cancelled,
                endedAt: date,
                at: date
            )
        }
    }

    static func updateTurn(
        in workspace: inout V2AgentWorkspace,
        turn: TurnState,
        messageStatus: V2AgentMessage.Status,
        traceStatus: V2AgentTraceStatus,
        text: String? = nil,
        error: V2AgentMessageError? = nil,
        endedAt: Date? = nil,
        at date: Date,
        sessionUpdate: ((inout V2AgentSession) -> Void)? = nil
    ) {
        guard let sessionIndex = workspace.sessions.firstIndex(where: { $0.id == turn.sessionID }),
              let messageIndex = workspace.sessions[sessionIndex].messages
                .firstIndex(where: { $0.id == turn.agentMessageID })
        else { return }

        let trace = turn.trace(status: traceStatus, endedAt: endedAt)
        var parts: [V2AgentMessagePart] = []
        if let text { parts.append(.text(text)) }
        parts.append(.trace(V2AgentTraceSummary(trace)))
        if !turn.sources.isEmpty { parts.append(.sources(turn.sources)) }
        if let plan = turn.plan { parts.append(.plan(plan)) }
        if let error { parts.append(.error(error)) }

        var message = workspace.sessions[sessionIndex].messages[messageIndex]
        message.parts = parts
        message.status = messageStatus
        message.updatedAt = date
        workspace.sessions[sessionIndex].messages[messageIndex] = message

        if let traceIndex = workspace.sessions[sessionIndex].traces
            .firstIndex(where: { $0.id == trace.id }) {
            workspace.sessions[sessionIndex].traces[traceIndex] = trace
        } else {
            workspace.sessions[sessionIndex].traces.append(trace)
        }
        if let providerLabel = turn.providerLabel, let model = turn.model {
            workspace.sessions[sessionIndex].providerState = V2AgentProviderState(
                providerLabel: providerLabel,
                model: model,
                remoteConversationID: workspace.sessions[sessionIndex].providerState?
                    .remoteConversationID,
                remoteResponseID: turn.responseID,
                updatedAt: date
            )
        }
        sessionUpdate?(&workspace.sessions[sessionIndex])
        workspace.sessions[sessionIndex].updatedAt = date
    }

    func commitWorkspace(_ mutation: (inout V2AgentWorkspace) -> Void) -> Bool {
        guard canPersistWorkspace, let workspaceStore else { return false }
        var next = workspace
        mutation(&next)
        do {
            try workspaceStore.save(next)
            workspace = next
            storageIssueMessage = nil
            return true
        } catch {
            canPersistWorkspace = false
            storageIssueMessage = "助手会话无法保存；原文件已保留，后续写入已停用。"
            operationErrorMessage = storageIssueMessage
            return false
        }
    }

    func conversation(
        from session: V2AgentSession,
        excludingMessageID: String
    ) -> [V2AgentConversationMessage] {
        session.messages.suffix(40).compactMap { message in
            guard message.id != excludingMessageID, message.status == .complete else { return nil }
            let text = message.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return V2AgentConversationMessage(
                role: message.role == .user ? .user : .assistant,
                text: String(text.prefix(4_000))
            )
        }
    }

    static func source(from result: V2WebSearchResult) -> V2WebSource? {
        guard let scheme = result.url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              result.url.host != nil
        else { return nil }
        return V2WebSource(
            id: UUID().uuidString,
            title: String(result.title.prefix(300)),
            url: result.url,
            snippet: String(result.snippet.prefix(800)),
            siteName: result.siteName.map { String($0.prefix(120)) }
        )
    }

    static func webSearchSummary(_ sources: [V2WebSource]) -> String {
        let lines = sources.map { source in
            "[\(source.id)] \(source.title)\n\(source.url.absoluteString)\n\(source.snippet)"
        }
        return String(lines.joined(separator: "\n\n").prefix(6_000))
    }

    static func sum(_ lhs: Int?, _ rhs: Int?) -> Int? {
        guard lhs != nil || rhs != nil else { return nil }
        return (lhs ?? 0) + (rhs ?? 0)
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
            let range = NSRange(output.startIndex..<output.endIndex, in: output)
            return expression.stringByReplacingMatches(
                in: output,
                range: range,
                withTemplate: "[REDACTED]"
            )
        }
    }

    static func traceError(for error: Error, tool: V2AgentTool) -> V2AgentTraceError {
        let category: V2AgentTraceErrorCategory
        switch tool {
        case .model:
            category = .model
        case .webSearch, .webRead:
            category = .web
        case .localSearch:
            category = .localData
        case .plan:
            category = .planning
        case .other:
            category = .network
        }

        let code: V2AgentTraceErrorCode
        if error is CancellationError {
            code = .cancelled
        } else if let agentError = error as? V2AgentClientError,
                  case let .requestFailed(statusCode, _) = agentError {
            code = Self.traceCode(for: statusCode)
        } else if let planningError = error as? V2PlanningClientError,
                  case let .requestFailed(statusCode, _) = planningError {
            code = Self.traceCode(for: statusCode)
        } else if let webError = error as? V2WebToolError {
            switch webError {
            case .invalidQuery, .invalidLimit, .unsupportedURL:
                code = .invalidRequest
            case .requestFailed(let statusCode):
                code = Self.traceCode(for: statusCode)
            case .invalidResponse, .unsupportedContentType, .payloadTooLarge,
                 .invalidPayload, .unsupportedMarkup, .tooManyRedirects:
                code = .invalidResponse
            }
        } else {
            code = .unknown
        }
        return V2AgentTraceError(category: category, code: code)
    }

    static func traceCode(for statusCode: Int) -> V2AgentTraceErrorCode {
        switch statusCode {
        case 401:
            .unauthorized
        case 403:
            .forbidden
        case 408:
            .timeout
        case 429:
            .rateLimited
        case 400..<500:
            .invalidRequest
        case 500..<600:
            .unavailable
        default:
            .unknown
        }
    }
}

private enum V2AssistantTurnError: LocalizedError {
    case providerUnavailable(String)
    case sessionUnavailable
    case persistenceUnavailable
    case toolLimitReached

    var errorDescription: String? {
        switch self {
        case let .providerUnavailable(message):
            message
        case .sessionUnavailable:
            "当前会话已不可用，请新建会话后重试。"
        case .persistenceUnavailable:
            "会话状态无法保存，已停止本次请求。"
        case .toolLimitReached:
            "本轮已达到 3 次工具调用上限，请缩小问题范围后重试。"
        }
    }
}

import Foundation
import ToughTrialV2Core

extension V2AssistantStore {
    struct TurnState {
        var sessionID: String
        var userMessageID: String
        var agentMessageID: String
        var userText: String
        var traceID: String
        var startedAt: Date
        var modelSnapshot: V2AssistantModelSnapshot
        var steps: [V2AgentTraceStep] = []
        var observations: [V2AgentObservation] = []
        var sources: [V2WebSource] = []
        var plan: V2PlanDraft?
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
                providerLabel: modelSnapshot.identity.label,
                model: modelSnapshot.identity.model,
                requestID: requestID,
                responseID: responseID,
                promptTokens: promptTokens,
                completionTokens: completionTokens,
                totalTokens: totalTokens
            )
        }
    }

    func makeTurn(
        sessionID: String,
        userMessage: V2AgentMessage,
        agentMessage: V2AgentMessage,
        snapshot: V2AssistantModelSnapshot,
        at date: Date
    ) -> TurnState {
        TurnState(
            sessionID: sessionID,
            userMessageID: userMessage.id,
            agentMessageID: agentMessage.id,
            userText: userMessage.plainText,
            traceID: UUID().uuidString,
            startedAt: date,
            modelSnapshot: snapshot
        )
    }

    func runTurn(_ initialTurn: TurnState) async {
        var turn = initialTurn
        var policy = V2AgentTurnPolicy(maximumToolCalls: 3)

        do {
            while true {
                try Task.checkCancellation()
                guard let session = workspace.session(id: turn.sessionID) else {
                    throw V2AssistantTurnError.sessionUnavailable
                }
                let request = V2AgentRequest(
                    userText: turn.userText,
                    conversation: conversation(from: session, before: turn.userMessageID),
                    observations: turn.observations,
                    conversationIdentifier: session.id
                )
                turn.activeTool = .model
                let startedAt = now()
                let result = try await turn.modelSnapshot.respond(request)
                try Task.checkCancellation()
                guard result.providerLabel == turn.modelSnapshot.identity.label,
                      result.model == turn.modelSnapshot.identity.model else {
                    throw V2AssistantTurnError.providerIdentityChanged
                }
                let endedAt = now()
                turn.steps.append(
                    V2AgentTraceStep(
                        tool: .model,
                        status: .succeeded,
                        duration: endedAt.timeIntervalSince(startedAt)
                    )
                )
                turn.requestID = result.requestID
                turn.responseID = result.responseID
                turn.promptTokens = Self.sum(turn.promptTokens, result.promptTokens)
                turn.completionTokens = Self.sum(turn.completionTokens, result.completionTokens)
                turn.totalTokens = Self.sum(turn.totalTokens, result.totalTokens)
                turn.activeTool = nil
                guard persistRunningTurn(turn, at: endedAt) else {
                    throw V2AssistantTurnError.persistenceUnavailable
                }

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
            recordCancelledStep(in: &turn)
            cancelTurn(&turn, at: now())
        } catch where Task.isCancelled {
            recordCancelledStep(in: &turn)
            cancelTurn(&turn, at: now())
        } catch {
            if let tool = turn.activeTool {
                turn.steps.append(
                    V2AgentTraceStep(
                        tool: tool,
                        status: .failed,
                        duration: 0,
                        error: Self.traceError(for: error, tool: tool)
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
            var sourceByURL: [String: V2WebSource] = [:]
            for source in turn.sources {
                if let key = Self.normalizedURLKey(source.url) { sourceByURL[key] = source }
            }
            var observedIDs = Set<String>()
            for result in results.prefix(8) {
                guard let key = Self.normalizedURLKey(result.url) else { continue }
                let source: V2WebSource
                if let existing = sourceByURL[key] {
                    source = existing
                } else {
                    guard let created = Self.source(from: result) else { continue }
                    source = created
                    sourceByURL[key] = created
                    turn.sources.append(created)
                }
                guard observedIDs.insert(source.id).inserted else { continue }
                turn.observations.append(
                    V2AgentObservation(
                        sourceID: source.id,
                        tool: .webSearch,
                        summary: Self.webSourceSummary(source)
                    )
                )
            }
            turn.steps.append(
                V2AgentTraceStep(
                    tool: .webSearch,
                    status: .succeeded,
                    duration: now().timeIntervalSince(startedAt),
                    subject: .searchQuery(safeQuery)
                )
            )
        case let .webRead(url):
            guard let safeURL = V2AgentTraceWebURL(url),
                  let normalizedKey = Self.normalizedURLKey(url) else {
                throw V2WebToolError.unsupportedURL
            }
            turn.activeTool = .webRead
            let text = try await dependencies.webRead(url, 8_000)
            try Task.checkCancellation()
            let bounded = String(text.prefix(8_000))
            let source: V2WebSource
            if let existing = turn.sources.first(where: { Self.normalizedURLKey($0.url) == normalizedKey }) {
                source = existing
            } else {
                source = V2WebSource(
                    id: UUID().uuidString,
                    title: url.host ?? "网页来源",
                    url: url,
                    snippet: String(bounded.prefix(300)),
                    siteName: url.host
                )
                turn.sources.append(source)
            }
            turn.observations.removeAll { $0.sourceID == source.id && $0.tool == .webRead }
            turn.observations.append(
                V2AgentObservation(
                    sourceID: source.id,
                    tool: .webRead,
                    summary: String("来源：\(url.absoluteString)\n\(bounded)".prefix(8_000))
                )
            )
            turn.steps.append(
                V2AgentTraceStep(
                    tool: .webRead,
                    status: .succeeded,
                    duration: now().timeIntervalSince(startedAt),
                    subject: .sourceURL(safeURL)
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
            let outcome = try await turn.modelSnapshot.generatePlan(session, query, startedAt)
            try Task.checkCancellation()
            let observationID = UUID().uuidString
            let update: (inout V2AgentSession) -> Void
            switch outcome {
            case let .clarification(clarification):
                turn.observations.append(
                    V2AgentObservation(
                        sourceID: observationID,
                        tool: .plan,
                        summary: String(clarification.question.prefix(1_000))
                    )
                )
                update = { session in
                    session.pendingPlanPrompt = session.pendingPlanPrompt
                        ?? session.pendingPlan?.userPrompt
                        ?? query
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
                update = { session in
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
            guard persistRunningTurn(turn, at: now(), sessionUpdate: update) else {
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
        commitWorkspace {
            Self.updateTurn(
                in: &$0,
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
        guard commitWorkspace({
            Self.updateTurn(in: &$0, turn: turn, messageStatus: .complete,
                            traceStatus: .succeeded, text: text, endedAt: date, at: date)
        }) else {
            markTurnFailedInMemory(turn, error: V2AssistantTurnError.persistenceUnavailable, at: date)
            return
        }
        operationErrorMessage = nil
    }

    func failTurn(_ turn: inout TurnState, error: Error, at date: Date) {
        turn.activeTool = nil
        let message = Self.userFacingMessage(for: error)
        operationErrorMessage = message
        if mayMutate {
            _ = commitWorkspace {
                Self.updateTurn(in: &$0, turn: turn, messageStatus: .failed,
                                traceStatus: .failed, error: .retryable(message),
                                endedAt: date, at: date)
            }
        } else {
            markTurnFailedInMemory(turn, error: error, at: date)
        }
    }

    func cancelTurn(_ turn: inout TurnState, at date: Date) {
        turn.activeTool = nil
        if mayMutate {
            _ = commitWorkspace {
                Self.updateTurn(in: &$0, turn: turn, messageStatus: .cancelled,
                                traceStatus: .cancelled, error: .cancelled,
                                endedAt: date, at: date)
            }
        } else {
            Self.updateTurn(in: &workspace, turn: turn, messageStatus: .cancelled,
                            traceStatus: .cancelled, error: .cancelled,
                            endedAt: date, at: date)
        }
    }

    func recordCancelledStep(in turn: inout TurnState) {
        guard let tool = turn.activeTool else { return }
        turn.steps.append(
            V2AgentTraceStep(
                tool: tool,
                status: .cancelled,
                duration: 0,
                error: V2AgentTraceError(category: .cancelled, code: .cancelled)
            )
        )
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
                .firstIndex(where: { $0.id == turn.agentMessageID }) else { return }
        let trace = turn.trace(status: traceStatus, endedAt: endedAt)
        var parts: [V2AgentMessagePart] = []
        if let text { parts.append(.text(text)) }
        parts.append(.trace(V2AgentTraceSummary(trace)))
        if !turn.sources.isEmpty { parts.append(.sources(turn.sources)) }
        if let plan = turn.plan { parts.append(.plan(plan)) }
        if let error { parts.append(.error(error)) }
        workspace.sessions[sessionIndex].messages[messageIndex].parts = parts
        workspace.sessions[sessionIndex].messages[messageIndex].status = messageStatus
        workspace.sessions[sessionIndex].messages[messageIndex].updatedAt = date
        if let traceIndex = workspace.sessions[sessionIndex].traces.firstIndex(where: { $0.id == trace.id }) {
            workspace.sessions[sessionIndex].traces[traceIndex] = trace
        } else {
            workspace.sessions[sessionIndex].traces.append(trace)
        }
        workspace.sessions[sessionIndex].providerState = V2AgentProviderState(
            providerLabel: turn.modelSnapshot.identity.label,
            model: turn.modelSnapshot.identity.model,
            remoteConversationID: nil,
            remoteResponseID: turn.responseID,
            updatedAt: date
        )
        sessionUpdate?(&workspace.sessions[sessionIndex])
        workspace.sessions[sessionIndex].updatedAt = date
    }

    func conversation(from session: V2AgentSession, before userMessageID: String) -> [V2AgentConversationMessage] {
        guard let userIndex = session.messages.firstIndex(where: { $0.id == userMessageID }) else { return [] }
        return session.messages[..<userIndex].suffix(40).compactMap { message in
            guard message.status == .complete else { return nil }
            let text = message.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return V2AgentConversationMessage(
                role: message.role == .user ? .user : .assistant,
                text: String(text.prefix(4_000))
            )
        }
    }

    static func normalizedURLKey(_ url: URL) -> String? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host?.lowercased() else { return nil }
        components.scheme = scheme
        components.host = host
        components.fragment = nil
        if (scheme == "https" && components.port == 443) || (scheme == "http" && components.port == 80) {
            components.port = nil
        }
        return components.url?.absoluteString
    }

    static func source(from result: V2WebSearchResult) -> V2WebSource? {
        guard normalizedURLKey(result.url) != nil else { return nil }
        return V2WebSource(
            id: UUID().uuidString,
            title: String(result.title.prefix(300)),
            url: result.url,
            snippet: String(result.snippet.prefix(800)),
            siteName: result.siteName.map { String($0.prefix(120)) }
        )
    }

    static func webSourceSummary(_ source: V2WebSource) -> String {
        String("[\(source.id)] \(source.title)\n\(source.url.absoluteString)\n\(source.snippet)".prefix(1_500))
    }

    static func sum(_ lhs: Int?, _ rhs: Int?) -> Int? {
        guard lhs != nil || rhs != nil else { return nil }
        return (lhs ?? 0) + (rhs ?? 0)
    }

    static func traceError(for error: Error, tool: V2AgentTool) -> V2AgentTraceError {
        let category: V2AgentTraceErrorCategory
        switch tool {
        case .model: category = .model
        case .webSearch, .webRead: category = .web
        case .localSearch: category = .localData
        case .plan: category = .planning
        case .other: category = .network
        }
        let code: V2AgentTraceErrorCode
        if error is CancellationError {
            code = .cancelled
        } else if let error = error as? V2AgentClientError,
                  case let .requestFailed(statusCode, _) = error {
            code = traceCode(for: statusCode)
        } else if let error = error as? V2PlanningClientError,
                  case let .requestFailed(statusCode, _) = error {
            code = traceCode(for: statusCode)
        } else if let error = error as? V2WebToolError {
            switch error {
            case .invalidQuery, .invalidLimit, .unsupportedURL: code = .invalidRequest
            case let .requestFailed(statusCode): code = traceCode(for: statusCode)
            case .invalidResponse, .unsupportedContentType, .payloadTooLarge,
                 .invalidPayload, .unsupportedMarkup, .tooManyRedirects: code = .invalidResponse
            }
        } else {
            code = .unknown
        }
        return V2AgentTraceError(category: category, code: code)
    }

    static func traceCode(for statusCode: Int) -> V2AgentTraceErrorCode {
        switch statusCode {
        case 401: .unauthorized
        case 403: .forbidden
        case 408: .timeout
        case 429: .rateLimited
        case 400..<500: .invalidRequest
        case 500..<600: .unavailable
        default: .unknown
        }
    }
}

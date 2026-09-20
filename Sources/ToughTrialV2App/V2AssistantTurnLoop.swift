import Foundation
import ToughTrialV2Core

extension V2AssistantStore {
    struct TurnState {
        var sessionID: String
        var selectionRevision: Int
        var userMessageID: String
        var agentMessageID: String
        var userText: String
        var traceID: String
        var startedAt: Date
        var modelSnapshot: V2AssistantModelSnapshot
        var executeTool: V2AssistantToolExecutor
        var moduleTicket: V2ModuleTicket
        var toolCatalog: V2ToolCatalog
        var steps: [V2AgentTraceStep] = []
        var observations: [V2AgentObservation] = []
        var toolExchanges: [V2AgentToolExchange] = []
        var sources: [V2WebSource] = []
        var plan: V2PlanDraft?
        var schedule: V2AgentScheduleCard?
        var toolResults: [V2ToolExecutionResult] = []
        var requestID: String?
        var responseID: String?
        var promptTokens: Int?
        var completionTokens: Int?
        var totalTokens: Int?
        var activeTool: V2AgentTool?
        var activeToolStartedAt: Date?

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
    ) throws -> TurnState {
        let toolCatalog = try dependencies.toolCatalog()
        let activeModules = V2ModuleDescriptor.builtins
            .map(\.id)
            .filter { V2PluginStore.shared.enabled($0) }
        let modules = Array(Set(["core.assistant"] + activeModules + Array(toolCatalog.modules.keys)))
        let ticket = try V2PluginStore.shared.ticket(modules)
        return TurnState(
            sessionID: sessionID,
            selectionRevision: selectionRevision,
            userMessageID: userMessage.id,
            agentMessageID: agentMessage.id,
            userText: userMessage.plainText,
            traceID: UUID().uuidString,
            startedAt: date,
            modelSnapshot: snapshot,
            executeTool: dependencies.toolExecutorForSnapshot?(snapshot) ?? dependencies.executeTool,
            moduleTicket: ticket,
            toolCatalog: toolCatalog
        )
    }

    private func finishScheduleTurn(_ turn: inout TurnState) {
        let text: String
        if let card = turn.schedule {
            if dependencies.scheduleReceipt(card.requestID)?.undoneAt != nil {
                text = "这次修改已撤销，没有再次执行。"
            } else {
                text = card.status == .applied ? "已更新日程。下面是实际修改，可整次撤销。" : "请检查下面的修改，确认后执行。"
            }
        } else {
            text = turn.observations.last?.summary ?? "请补充这次日程修改的信息。"
        }
        finishTurn(&turn, text: text, at: now())
    }

    func runTurn(_ initialTurn: TurnState) async {
        var turn = initialTurn
        var policy = V2AgentTurnPolicy(maximumToolCalls: 6)

        do {
            try V2PluginStore.shared.validate(turn.moduleTicket)
            if V2AgentTurnPolicy.canDirectlyParseCreation(turn.userText) {
                try Task.checkCancellation()
                try V2PluginStore.shared.validate(turn.moduleTicket)
                try await executeSchedule(turn.userText, turn: &turn)
                finishScheduleTurn(&turn)
                return
            }
            while true {
                try Task.checkCancellation()
                try V2PluginStore.shared.validate(turn.moduleTicket)
                guard let session = workspace.session(id: turn.sessionID) else {
                    throw V2AssistantTurnError.sessionUnavailable
                }
                let context = requestContext(for: session, before: turn.userMessageID, at: now())
                let history = conversation(from: session, before: turn.userMessageID, context: context)
                let request = V2AgentRequest(
                    userText: turn.userText,
                    conversation: history,
                    observations: turn.observations,
                    conversationIdentifier: session.id,
                    webAvailable: V2PluginStore.shared.enabled("web"),
                    toolCatalog: turn.toolCatalog,
                    context: context,
                    toolExchanges: turn.toolExchanges
                )
                recordRequestContext(context, conversation: history, kind: "chat", turn: turn)
                let startedAt = now()
                beginStep(.model, turn: &turn, at: startedAt)
                let result = try await turn.modelSnapshot.respond(request)
                try Task.checkCancellation()
                do {
                    try V2PluginStore.shared.validate(turn.moduleTicket)
                } catch let error as V2ModuleRuntimeError {
                    // A web toggle can invalidate the ticket while the model is awaiting a reply.
                    // Keep rejecting that reply, but attribute a requested web action to the right step.
                    switch error {
                    case .stale(id: "core.web", expected: _, actual: _),
                         .unavailable(id: "core.web", availability: _):
                        switch result.action {
                        case .webSearch: beginStep(.webSearch, turn: &turn, at: now())
                        case .webRead: beginStep(.webRead, turn: &turn, at: now())
                        default: break
                        }
                    default: break
                    }
                    throw error
                }
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
                let actions = [result.action] + result.additionalToolCalls.map(V2AgentAction.toolCall)
                for action in actions {
                    if case .toolCall(let call) = action { _ = try turn.toolCatalog.validate(call) }
                    guard policy.registerToolCall(action) else { throw V2AssistantTurnError.toolLimitReached }
                }
                var nativeResults: [V2AgentToolExchange.Result] = []
                for action in actions {
                    try Task.checkCancellation()
                    if case .schedule = action, turn.schedule?.status == .applied {
                        finishScheduleTurn(&turn)
                        return
                    }
                    try await execute(action, turn: &turn)
                    if case .toolCall(let call) = action, let id = call.modelCallID,
                       let receipt = turn.toolResults.last {
                        nativeResults.append(.init(callID: id, content: String((receipt.observation ?? receipt.summary).prefix(8_000))))
                    }
                    if case .schedule = action {
                        if result.continueAfterTool, let card = turn.schedule, card.status == .applied,
                           let receipt = dependencies.scheduleReceipt(card.requestID) {
                            turn.observations.append(.init(sourceID: receipt.id, tool: .schedule,
                                summary: "日程已执行：" + receipt.summary))
                        } else {
                            finishScheduleTurn(&turn)
                            return
                        }
                    }
                    if let toolResult = turn.toolResults.last,
                       [.pendingConfirmation, .needsInformation, .blocked, .conflict, .failed, .cancelled]
                        .contains(toolResult.state) {
                        finishTurn(&turn, text: toolResult.state == .pendingConfirmation ? "已整理好，确认后执行。" : toolResult.summary, at: now())
                        return
                    }
                }
                if let message = result.continuationMessage, nativeResults.count == actions.count {
                    turn.toolExchanges.append(.init(assistantMessage: message, results: nativeResults))
                }
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
                        duration: now().timeIntervalSince(turn.activeToolStartedAt ?? turn.startedAt),
                        error: Self.traceError(for: error, tool: tool)
                    )
                )
            }
            failTurn(&turn, error: error, at: now())
        }
    }

    func execute(_ action: V2AgentAction, turn: inout TurnState) async throws {
        let startedAt = now()
        // Mark web work before validating its module ticket. If the user
        // disabled the web module while a turn was running, the failure must
        // remain attributed to the web step rather than to the preceding
        // model step.
        switch action {
        case .webSearch:
            beginStep(.webSearch, turn: &turn, at: startedAt)
        case .webRead:
            beginStep(.webRead, turn: &turn, at: startedAt)
        default:
            break
        }
        try V2PluginStore.shared.validate(turn.moduleTicket)
        switch action {
        case .answer:
            return
        case let .webSearch(query):
            let toolTicket = try V2PluginStore.shared.ticket(["web"])
            guard let safeQuery = V2AgentSafeSearchQuery(query) else {
                throw V2AgentClientError.invalidOutput("搜索词不符合安全约束")
            }
            let results = try await dependencies.webSearch(query, 8)
            try V2PluginStore.shared.validate(toolTicket)
            try Task.checkCancellation()
                try V2PluginStore.shared.validate(turn.moduleTicket)
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
            if observedIDs.isEmpty {
                turn.observations.append(
                    V2AgentObservation(
                        sourceID: "",
                        tool: .webSearch,
                        summary: "网页搜索未找到可用来源，请调整关键词后重试。"
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
            let toolTicket = try V2PluginStore.shared.ticket(["web"])
            guard let safeURL = V2AgentTraceWebURL(url),
                  let normalizedKey = Self.normalizedURLKey(url) else {
                throw V2WebToolError.unsupportedURL
            }
            let text = try await dependencies.webRead(url, 8_000)
            try V2PluginStore.shared.validate(toolTicket)
            try Task.checkCancellation()
                try V2PluginStore.shared.validate(turn.moduleTicket)
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
            let observationSummary: String
            if bounded.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                observationSummary = "来源：\(url.absoluteString)\n网页正文为空，未提取到可引用内容。请打开来源或稍后重试。"
            } else {
                observationSummary = "来源：\(url.absoluteString)\n\(bounded)"
            }
            turn.observations.append(
                V2AgentObservation(
                    sourceID: source.id,
                    tool: .webRead,
                    summary: String(observationSummary.prefix(8_000))
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
            beginStep(.localSearch, turn: &turn, at: startedAt)
            let summary = try await dependencies.localSearch(query)
            try Task.checkCancellation()
                try V2PluginStore.shared.validate(turn.moduleTicket)
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
        case let .schedule(query):
            try await executeSchedule(query, turn: &turn)
        case let .plan(query):
            let toolTicket = try V2PluginStore.shared.ticket(["tasks"])
            guard let session = workspace.session(id: turn.sessionID) else {
                throw V2AssistantTurnError.sessionUnavailable
            }
            beginStep(.plan, turn: &turn, at: startedAt)
            let outcome = try await turn.modelSnapshot.generatePlan(session, query, startedAt)
            try V2PluginStore.shared.validate(toolTicket)
            try Task.checkCancellation()
                try V2PluginStore.shared.validate(turn.moduleTicket)
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
        case let .toolCall(call):
            try await executeDynamicTool(call, turn: &turn, at: startedAt)
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
        V2UsageTrace.shared.record(.init(kind: .assistantFinished, source: .assistant,
            sessionID: turn.sessionID, operationID: turn.userMessageID,
            duration: date.timeIntervalSince(turn.startedAt), at: date))
        operationErrorMessage = nil
    }

    func failTurn(_ turn: inout TurnState, error: Error, at date: Date) {
        V2UsageTrace.shared.record(.init(kind: .assistantFailed, source: .assistant,
            sessionID: turn.sessionID, operationID: turn.userMessageID,
            duration: date.timeIntervalSince(turn.startedAt), at: date))
        let failedTool = turn.activeTool
        turn.activeTool = nil
        let message = Self.userFacingMessage(for: error, tool: failedTool)
        operationErrorMessage = message
        if mayMutate {
            let saved = commitWorkspace {
                Self.updateTurn(in: &$0, turn: turn, messageStatus: .failed,
                                traceStatus: .failed, error: .retryable(message),
                                endedAt: date, at: date)
            }
            if !saved {
                markTurnFailedInMemory(turn, error: error, at: date, userFacingMessage: message)
            }
        } else {
            markTurnFailedInMemory(turn, error: error, at: date, userFacingMessage: message)
        }
    }

    func cancelTurn(_ turn: inout TurnState, at date: Date) {
        V2UsageTrace.shared.record(.init(kind: .assistantCancelled, source: .assistant,
            sessionID: turn.sessionID, operationID: turn.userMessageID,
            duration: date.timeIntervalSince(turn.startedAt), at: date))
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

    func beginStep(_ tool: V2AgentTool, turn: inout TurnState, at date: Date) {
        turn.activeTool = tool
        turn.activeToolStartedAt = date
        activity = Activity(messageID: turn.agentMessageID, tool: tool)
    }

    func recordCancelledStep(in turn: inout TurnState) {
        guard let tool = turn.activeTool else { return }
        turn.steps.append(
            V2AgentTraceStep(
                tool: tool,
                status: .cancelled,
                duration: now().timeIntervalSince(turn.activeToolStartedAt ?? turn.startedAt),
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
        if let schedule = turn.schedule { parts.append(.schedule(schedule)) }
        parts.append(contentsOf: turn.toolResults.filter { turn.schedule == nil || $0.toolID != "core.tasks.schedule" }.map(V2AgentMessagePart.tool))
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

    func conversation(from session: V2AgentSession, before userMessageID: String, context: V2AssistantContext? = nil) -> [V2AgentConversationMessage] {
        guard let userIndex = session.messages.firstIndex(where: { $0.id == userMessageID }) else { return [] }
        return V2AssistantHistory.conversation(Array(session.messages[..<userIndex]), coveredIDs: context?.coveredMessageIDs ?? [])
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
        case .plan, .schedule: category = .planning
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
        } else if let error = error as? URLError {
            switch error.code {
            case .timedOut: code = .timeout
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost,
                 .cannotFindHost, .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff,
                 .secureConnectionFailed, .cannotLoadFromNetwork, .resourceUnavailable:
                code = .unavailable
            default: code = .unknown
            }
        } else if let error = error as? V2ModuleRuntimeError {
            switch error {
            case .unavailable, .stale: code = .unavailable
            default: code = .unknown
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

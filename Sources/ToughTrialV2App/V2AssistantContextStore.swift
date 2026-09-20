import Foundation
import ToughTrialV2Core

extension V2AssistantStore {
    func syncContextArchive() {
        guard storageState == .healthy else { return }
        do {
            try contextArchive.sync(workspace)
            if V2PluginStore.shared.enabled("notes") { try contextArchive.syncMemory(dependencies.allMemoryRecords()) }
            contextIssueMessage = nil
        } catch {
            contextIssueMessage = "会话已保存在本机，但日志投影暂不可用；原文不会因压缩被丢弃。"
        }
    }

    func requestContext(for session: V2AgentSession, before messageID: String? = nil, at date: Date) -> V2AssistantContext {
        var source = session.sourceTask
        var referenceState: V2AssistantContext.ReferenceState = .none
        if let selected = source {
            if V2PluginStore.shared.enabled("tasks"), let task = dependencies.scheduleSnapshot().tasks.first(where: { $0.id == selected.id }) {
                source = .init(id: task.id, title: task.title, note: task.note, contextID: task.contextID, parentID: task.parentID)
                referenceState = .available
            } else { referenceState = .missing }
        }
        var history = session
        if let messageID, let index = history.messages.firstIndex(where: { $0.id == messageID }) {
            history.messages = Array(history.messages[..<index])
        }
        let currentMessage = messageID.flatMap { id in session.messages.first(where: { $0.id == id }) } ?? (messageID == nil ? session.messages.last(where: { $0.role == .user }) : nil)
        let quotedMessages = currentMessage?.references ?? []
        let attachmentSources = currentMessage?.attachments ?? []
        var compact: V2AssistantCompaction?
        if contextIssueMessage == nil {
            do {
                // Historical retries never replace the current session's summary.
                let isHistoricalRetry = messageID != nil && messageID != session.messages.last(where: { $0.role == .user })?.id
                if !isHistoricalRetry && history.messages.count > 12 {
                    let candidate = try contextArchive.compact(history, at: date)
                    compact = candidate.didReduce ? candidate : nil
                } else if !isHistoricalRetry {
                    let candidate = try contextArchive.loadCompaction(sessionID: session.id)
                    let earlierIDs = Set(history.messages.map(\.id))
                    if let candidate, candidate.didReduce, Set(candidate.coveredMessageIDs).isSubset(of: earlierIDs) {
                        compact = candidate
                    }
                }
            } catch { contextIssueMessage = "上下文摘要暂不可用，本轮继续使用近期原文。" }
        }
        return .init(attachmentSources: attachmentSources, quotedMessages: quotedMessages,
                     sourceTask: source, referenceState: referenceState,
                     memories: dependencies.contextMemories(source, date), compactSummary: compact?.summary ?? "",
                     compactRevision: compact?.revision, coveredMessageIDs: compact?.coveredMessageIDs ?? [],
                     at: date, timeZoneIdentifier: dependencies.timeZoneIdentifier())
    }

    func recordRequestContext(_ context: V2AssistantContext, conversation: [V2AgentConversationMessage], kind: String, turn: TurnState) {
        guard V2PluginStore.shared.enabled("trace"), V2UsageTrace.shared.isEnabled else { return }
        let manifest = V2AssistantContextManifest(kind: kind, context: context, conversation: conversation)
        V2UsageTrace.shared.record(.init(kind: .contextPrepared, source: .assistant, sessionID: turn.sessionID,
            operationID: turn.userMessageID, traceID: turn.traceID, context: manifest))
        do {
            try contextArchive.record(sessionID: turn.sessionID, kind: "turn_context", requestID: turn.userMessageID,
                metadata: ["traceID": turn.traceID, "requestKind": kind,
                    "toolCatalogRevision": turn.toolCatalog.revision,
                    "toolIDs": turn.toolCatalog.tools.map(\.id).joined(separator: ","),
                    "workflowIDs": V2AssistantWorkflows.available(in: turn.toolCatalog).map(\.id).joined(separator: ","),
                    "referenceID": manifest.referenceID ?? "", "referenceState": manifest.referenceState.rawValue,
                    "memoryIDs": manifest.memoryIDs.joined(separator: ","),
                    "compactRevision": manifest.compactRevision.map(String.init) ?? "none",
                    "conversationMessageCount": String(manifest.conversationMessageCount),
                    "contextCharacterCount": String(manifest.contextCharacterCount),
                    "nativeToolExchangeCount": String(turn.toolExchanges.count),
                    "nativeToolResultCount": String(turn.toolExchanges.reduce(0) { $0 + $1.results.count })], at: now())
        } catch { contextIssueMessage = "请求已继续，但本次上下文诊断记录未能保存。" }
    }

    func authorizedToWrite(_ turn: TurnState) -> Bool {
        guard let session = workspace.session(id: turn.sessionID),
              let index = session.messages.firstIndex(where: { $0.id == turn.userMessageID }) else { return false }
        return V2AssistantWriteIntent.authorize(turn.userText,
            priorMessages: Array(session.messages[..<index]), hasTaskReference: session.sourceTask != nil)
    }

    @discardableResult
    func compactSelectedSession() -> Bool {
        compactSelectedSessionResult()?.didReduce == true
    }

    @discardableResult
    func compactSelectedSessionResult() -> V2AssistantCompaction? {
        guard !isRunningTurn, let session = selectedSession, V2PluginStore.shared.enabled("assistant") else { return nil }
        do {
            try contextArchive.sync(workspace)
            let previous = try contextArchive.loadCompaction(sessionID: session.id)
            let result = try contextArchive.compact(session, at: now())
            if previous == result, result.didReduce {
                return .init(revision: result.revision, summary: result.summary, coveredMessageIDs: result.coveredMessageIDs,
                    createdAt: result.createdAt, preservedReferenceIDs: result.preservedReferenceIDs,
                    metrics: .init(beforeCharacterCount: result.metrics.afterCharacterCount, afterCharacterCount: result.metrics.afterCharacterCount,
                        beforeTokenEstimate: result.metrics.afterTokenEstimate, afterTokenEstimate: result.metrics.afterTokenEstimate,
                        coveredMessageCount: result.metrics.coveredMessageCount, retainedMessageCount: result.metrics.retainedMessageCount,
                        noBenefitReason: "alreadyCompacted"))
            }
            contextIssueMessage = nil
            objectWillChange.send()
            return result
        } catch { contextIssueMessage = "上下文尚未整理，原始会话仍保留。"; return nil }
    }

    func priorMessages(sessionID: String, before messageID: String) -> [V2AgentMessage] {
        guard let session = workspace.session(id: sessionID),
              let index = session.messages.firstIndex(where: { $0.id == messageID }) else { return [] }
        return Array(session.messages[..<index])
    }

    func executeContextTool(_ call: V2AgentToolCall, context: V2ToolExecutionContext, turn: TurnState) throws -> V2ToolExecutionResult {
        let catalog = try dependencies.toolCatalog()
        let (descriptor, args) = try catalog.validate(call)
        try V2PluginStore.shared.require(descriptor.requiredModules)
        try contextArchive.sync(workspace)
        let query = args.string("query") ?? ""
        func sessionID() throws -> String {
            guard let reference = args.string("sessionReference") else { return turn.sessionID }
            let matches = workspace.sessions.filter { $0.id == reference || $0.title == reference }
            guard matches.count == 1, let id = matches.first?.id else { throw V2RegisteredToolError.reference(reference) }
            return id
        }
        let summary: String
        switch call.toolID {
        case "core.notes.searchMemory":
            let records = dependencies.contextMemories(context.assistantContext?.sourceTask, now())
                .filter { query.isEmpty || $0.statement.localizedCaseInsensitiveContains(query) }.prefix(20)
            summary = records.isEmpty ? "没有匹配的记忆。" : records.map { "\($0.id)：\($0.statement)" }.joined(separator: "\n")
        case "core.assistant.searchSessions":
            let sessions = try contextArchive.sessions(query: query, limit: 12)
            summary = sessions.isEmpty ? "没有匹配的会话。" : sessions.map { "\($0.id) · \($0.title) · \($0.messageCount) 条消息" }.joined(separator: "\n")
        case "core.assistant.readSession":
            let messages = try contextArchive.readSession(id: sessionID(), query: query, limit: 16)
            summary = messages.isEmpty ? "没有匹配的消息。" : messages.map { "[\($0.id)] \($0.role)：\($0.text)" }.joined(separator: "\n")
        case "core.assistant.readTrace":
            let id = try sessionID()
            let events = try contextArchive.trace(sessionID: id, limit: 12)
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]
            let records = V2UsageTrace.shared.events.filter { $0.sessionID == id }.suffix(12)
            summary = "上下文日志：\n" + String(decoding: try encoder.encode(events), as: UTF8.self)
                + "\n使用记录：\n" + String(decoding: try encoder.encode(Array(records)), as: UTF8.self)
        case "core.assistant.compact":
            guard var session = workspace.session(id: turn.sessionID) else { throw V2AssistantTurnError.sessionUnavailable }
            if let index = session.messages.firstIndex(where: { $0.id == turn.userMessageID }) { session.messages = Array(session.messages[..<index]) }
            let previous = try contextArchive.loadCompaction(sessionID: session.id)
            let compact = try contextArchive.compact(session, at: now())
            summary = previous == compact && compact.didReduce ? "当前摘要已是最新，无需重复整理；原文仍保留。" : compact.didReduce
                ? "上下文已整理为版本 \(compact.revision)，有效字符 \(compact.metrics.beforeCharacterCount) → \(compact.metrics.afterCharacterCount)，估算 token \(compact.metrics.beforeTokenEstimate) → \(compact.metrics.afterTokenEstimate)，覆盖 \(compact.coveredMessageIDs.count) 条旧消息；原文仍可回看。"
                : (compact.noBenefitMessage ?? "本次整理没有减少有效上下文，继续使用原文。")
        default: throw V2ToolExecutionError.unsupported(call.toolID)
        }
        return V2ToolExecutionResult(toolID: call.toolID, state: .applied, operationID: context.operationID,
            idempotencyKey: context.idempotencyKey,
            summary: call.toolID == "core.assistant.compact" ? summary : "已读取\(descriptor.title)资料，可按来源继续核对。",
            observation: String(Self.redactCredentials(in: summary).prefix(8_000)))
            .bound(to: call, context: context)
    }
}

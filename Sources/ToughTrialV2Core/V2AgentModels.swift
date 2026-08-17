import Foundation

public struct V2AgentSourceTask: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var note: String
    public var contextID: String?
    public var parentID: String?

    public init(
        id: String,
        title: String,
        note: String = "",
        contextID: String? = nil,
        parentID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.note = note
        self.contextID = contextID
        self.parentID = parentID
    }

    public init(
        taskID: String,
        title: String,
        note: String = "",
        contextID: String? = nil,
        parentID: String? = nil
    ) {
        self.init(
            id: taskID,
            title: title,
            note: note,
            contextID: contextID,
            parentID: parentID
        )
    }

    public var taskID: String { id }
}

public enum V2AgentMessageError: Codable, Equatable, Sendable {
    case message(String)
    case retryable(String)
    case cancelled

    public var message: String {
        switch self {
        case let .message(message), let .retryable(message):
            return message
        case .cancelled:
            return "操作已取消。"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case message
    }

    private enum Tag: String, Codable {
        case message
        case retryable
        case cancelled
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .message(message):
            try container.encode(Tag.message, forKey: .type)
            try container.encode(message, forKey: .message)
        case let .retryable(message):
            try container.encode(Tag.retryable, forKey: .type)
            try container.encode(message, forKey: .message)
        case .cancelled:
            try container.encode(Tag.cancelled, forKey: .type)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Tag.self, forKey: .type) {
        case .message:
            self = .message(try container.decode(String.self, forKey: .message))
        case .retryable:
            self = .retryable(try container.decode(String.self, forKey: .message))
        case .cancelled:
            self = .cancelled
        }
    }
}

public struct V2AgentProviderState: Codable, Equatable, Sendable {
    public var providerLabel: String
    public var model: String
    public var remoteConversationID: String?
    public var remoteResponseID: String?
    public var updatedAt: Date

    public init(
        providerLabel: String,
        model: String,
        remoteConversationID: String? = nil,
        remoteResponseID: String? = nil,
        updatedAt: Date
    ) {
        self.providerLabel = providerLabel
        self.model = model
        self.remoteConversationID = remoteConversationID
        self.remoteResponseID = remoteResponseID
        self.updatedAt = updatedAt
    }
}

public enum V2AgentTraceStatus: String, Codable, Equatable, Sendable {
    case running
    case succeeded
    case failed
    case cancelled
}

public enum V2AgentTraceTool: String, Codable, Equatable, Sendable {
    case model
    case webSearch
    case webRead
    case localSearch
    case plan
    case other

    public init(label: String) {
        switch label.lowercased() {
        case "model", "assistant":
            self = .model
        case "web_search", "web search", "search":
            self = .webSearch
        case "web_read", "web read", "read":
            self = .webRead
        case "local_search", "local search":
            self = .localSearch
        case "plan", "planning":
            self = .plan
        default:
            self = .other
        }
    }
}

public enum V2AgentTraceSanitizer {
    public static func redact(_ text: String) -> String {
        let patterns: [(String, String)] = [
            (#"(?i)(authorization|proxy-authorization)\s*[:=]\s*(?:bearer\s+)?[^\s,;]+"#, "$1: [REDACTED]"),
            (#"(?i)\bbearer\s+[A-Za-z0-9._~+/=-]+"#, "Bearer [REDACTED]"),
            (#"(?i)\b(?:x-)?api[-_ ]?key\s*[:=]\s*[^\s,;]+"#, "api-key=[REDACTED]"),
            (#"(?i)\b(?:cookie|set-cookie)\s*[:=]\s*[^\r\n]+"#, "Cookie: [REDACTED]"),
            (#"(?i)\b(?:access[-_ ]?token|refresh[-_ ]?token|id[-_ ]?token|auth[-_ ]?token|session[-_ ]?token|client[-_ ]?secret|token|secret|password)\s*[:=]\s*[^\s,;]+"#, "token=[REDACTED]"),
            (#"\beyJ[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+){2}\b"#, "[REDACTED]"),
            (#"(?i)\b(?:sk|pk|rk|key)[-_][A-Za-z0-9]{16,}\b"#, "[REDACTED]")
        ]

        return patterns.reduce(text) { value, pattern in
            replacing(value, pattern: pattern.0, with: pattern.1)
        }
    }

    public static func redact(_ values: [String: String]) -> [String: String] {
        values.reduce(into: [:]) { result, entry in
            let key = redact(entry.key)
            result[key] = isCredentialKey(entry.key) ? "[REDACTED]" : redact(entry.value)
        }
    }

    private static func replacing(_ value: String, pattern: String, with replacement: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return value }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return expression.stringByReplacingMatches(
            in: value,
            options: [],
            range: range,
            withTemplate: replacement
        )
    }

    private static func isCredentialKey(_ key: String) -> Bool {
        let normalized = key.lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        return normalized.contains("authorization")
            || normalized.contains("api_key")
            || normalized.contains("apikey")
            || normalized.contains("cookie")
            || normalized == "token"
            || normalized.hasSuffix("_token")
            || normalized.contains("secret")
            || normalized.contains("password")
    }
}

public struct V2AgentTraceSummary: Codable, Equatable, Sendable {
    public private(set) var summary: String
    public private(set) var status: V2AgentTraceStatus
    public private(set) var toolLabels: [V2AgentTraceTool]
    public private(set) var duration: TimeInterval?

    public init(
        summary: String,
        status: V2AgentTraceStatus,
        toolLabels: [V2AgentTraceTool],
        duration: TimeInterval?
    ) {
        self.summary = V2AgentTraceSanitizer.redact(summary)
        self.status = status
        self.toolLabels = toolLabels
        self.duration = duration.map { max(0, $0) }
    }

    public init(_ trace: V2AgentTrace) {
        self.init(
            summary: trace.summary,
            status: trace.status,
            toolLabels: trace.steps.map(\.tool),
            duration: trace.duration
        )
    }

    private enum CodingKeys: String, CodingKey {
        case summary
        case status
        case toolLabels
        case duration
        case steps
        case startedAt
        case endedAt
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(summary, forKey: .summary)
        try container.encode(status, forKey: .status)
        try container.encode(toolLabels, forKey: .toolLabels)
        try container.encodeIfPresent(duration, forKey: .duration)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacySteps = try container.decodeIfPresent([V2AgentTraceStep].self, forKey: .steps) ?? []
        let startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        let endedAt = try container.decodeIfPresent(Date.self, forKey: .endedAt)
        let legacyDuration: TimeInterval? = {
            guard let startedAt, let endedAt else { return nil }
            return max(0, endedAt.timeIntervalSince(startedAt))
        }()
        let duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration) ?? legacyDuration
        self.init(
            summary: try container.decodeIfPresent(String.self, forKey: .summary) ?? "",
            status: try container.decodeIfPresent(V2AgentTraceStatus.self, forKey: .status) ?? .succeeded,
            toolLabels: try container.decodeIfPresent([V2AgentTraceTool].self, forKey: .toolLabels)
                ?? legacySteps.map(\.tool),
            duration: duration
        )
    }
}

public struct V2AgentTraceStep: Identifiable, Codable, Equatable, Sendable {
    public typealias Status = V2AgentTraceStatus

    public private(set) var id: String
    public private(set) var tool: V2AgentTraceTool
    public private(set) var summary: String
    public private(set) var status: V2AgentTraceStatus
    public private(set) var startedAt: Date
    public private(set) var endedAt: Date?
    public private(set) var metadata: [String: String]
    public private(set) var parameters: [String: String]
    public private(set) var resultSummary: String?

    public init(
        id: String = UUID().uuidString,
        tool: V2AgentTraceTool,
        summary: String = "",
        status: V2AgentTraceStatus = .succeeded,
        startedAt: Date,
        endedAt: Date? = nil,
        metadata: [String: String] = [:],
        parameters: [String: String] = [:],
        resultSummary: String? = nil
    ) {
        self.id = V2AgentTraceSanitizer.redact(id)
        self.tool = tool
        self.summary = V2AgentTraceSanitizer.redact(summary)
        self.status = status
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.metadata = V2AgentTraceSanitizer.redact(metadata)
        self.parameters = V2AgentTraceSanitizer.redact(parameters)
        self.resultSummary = resultSummary.map(V2AgentTraceSanitizer.redact)
    }

    public init(
        id: String = UUID().uuidString,
        label: String,
        detail: String = "",
        status: V2AgentTraceStatus = .succeeded,
        startedAt: Date,
        endedAt: Date? = nil,
        metadata: [String: String] = [:],
        parameters: [String: String] = [:],
        resultSummary: String? = nil
    ) {
        self.init(
            id: id,
            tool: V2AgentTraceTool(label: label),
            summary: detail,
            status: status,
            startedAt: startedAt,
            endedAt: endedAt,
            metadata: metadata,
            parameters: parameters,
            resultSummary: resultSummary
        )
    }

    public var label: String { tool.rawValue }

    public var detail: String { summary }

    public var duration: TimeInterval? {
        guard let endedAt else { return nil }
        return max(0, endedAt.timeIntervalSince(startedAt))
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case tool
        case name
        case summary
        case status
        case startedAt
        case endedAt
        case metadata
        case parameters
        case resultSummary
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(tool, forKey: .tool)
        try container.encode(summary, forKey: .summary)
        try container.encode(status, forKey: .status)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encodeIfPresent(endedAt, forKey: .endedAt)
        try container.encode(metadata, forKey: .metadata)
        try container.encode(parameters, forKey: .parameters)
        try container.encodeIfPresent(resultSummary, forKey: .resultSummary)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            tool: try container.decodeIfPresent(V2AgentTraceTool.self, forKey: .tool)
                ?? V2AgentTraceTool(label: try container.decodeIfPresent(String.self, forKey: .name) ?? "other"),
            summary: try container.decodeIfPresent(String.self, forKey: .summary) ?? "",
            status: try container.decodeIfPresent(V2AgentTraceStatus.self, forKey: .status) ?? .succeeded,
            startedAt: try container.decode(Date.self, forKey: .startedAt),
            endedAt: try container.decodeIfPresent(Date.self, forKey: .endedAt),
            metadata: try container.decodeIfPresent([String: String].self, forKey: .metadata) ?? [:],
            parameters: try container.decodeIfPresent([String: String].self, forKey: .parameters) ?? [:],
            resultSummary: try container.decodeIfPresent(String.self, forKey: .resultSummary)
        )
    }
}

public struct V2AgentTrace: Identifiable, Codable, Equatable, Sendable {
    public typealias Status = V2AgentTraceStatus

    public private(set) var id: String
    public private(set) var summary: String
    public private(set) var status: V2AgentTraceStatus
    public private(set) var steps: [V2AgentTraceStep]
    public private(set) var startedAt: Date
    public private(set) var endedAt: Date?
    public private(set) var providerLabel: String?
    public private(set) var model: String?
    public private(set) var requestID: String?
    public private(set) var responseID: String?
    public private(set) var providerSessionID: String?
    public private(set) var metadata: [String: String]
    public private(set) var promptTokens: Int?
    public private(set) var completionTokens: Int?
    public private(set) var totalTokens: Int?

    public init(
        id: String = UUID().uuidString,
        summary: String = "",
        status: V2AgentTraceStatus = .succeeded,
        steps: [V2AgentTraceStep] = [],
        startedAt: Date,
        endedAt: Date? = nil,
        providerLabel: String? = nil,
        model: String? = nil,
        requestID: String? = nil,
        responseID: String? = nil,
        providerSessionID: String? = nil,
        metadata: [String: String] = [:],
        promptTokens: Int? = nil,
        completionTokens: Int? = nil,
        totalTokens: Int? = nil
    ) {
        self.id = V2AgentTraceSanitizer.redact(id)
        self.summary = V2AgentTraceSanitizer.redact(summary)
        self.status = status
        self.steps = steps
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.providerLabel = providerLabel.map(V2AgentTraceSanitizer.redact)
        self.model = model.map(V2AgentTraceSanitizer.redact)
        self.requestID = requestID.map(V2AgentTraceSanitizer.redact)
        self.responseID = responseID.map(V2AgentTraceSanitizer.redact)
        self.providerSessionID = providerSessionID.map(V2AgentTraceSanitizer.redact)
        self.metadata = V2AgentTraceSanitizer.redact(metadata)
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
    }

    public var duration: TimeInterval? {
        guard let endedAt else { return nil }
        return max(0, endedAt.timeIntervalSince(startedAt))
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case summary
        case status
        case steps
        case startedAt
        case endedAt
        case providerLabel
        case model
        case requestID
        case responseID
        case providerSessionID
        case metadata
        case promptTokens
        case completionTokens
        case totalTokens
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(summary, forKey: .summary)
        try container.encode(status, forKey: .status)
        try container.encode(steps, forKey: .steps)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encodeIfPresent(endedAt, forKey: .endedAt)
        try container.encodeIfPresent(providerLabel, forKey: .providerLabel)
        try container.encodeIfPresent(model, forKey: .model)
        try container.encodeIfPresent(requestID, forKey: .requestID)
        try container.encodeIfPresent(responseID, forKey: .responseID)
        try container.encodeIfPresent(providerSessionID, forKey: .providerSessionID)
        try container.encode(metadata, forKey: .metadata)
        try container.encodeIfPresent(promptTokens, forKey: .promptTokens)
        try container.encodeIfPresent(completionTokens, forKey: .completionTokens)
        try container.encodeIfPresent(totalTokens, forKey: .totalTokens)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            summary: try container.decodeIfPresent(String.self, forKey: .summary) ?? "",
            status: try container.decodeIfPresent(V2AgentTraceStatus.self, forKey: .status) ?? .succeeded,
            steps: try container.decodeIfPresent([V2AgentTraceStep].self, forKey: .steps) ?? [],
            startedAt: try container.decode(Date.self, forKey: .startedAt),
            endedAt: try container.decodeIfPresent(Date.self, forKey: .endedAt),
            providerLabel: try container.decodeIfPresent(String.self, forKey: .providerLabel),
            model: try container.decodeIfPresent(String.self, forKey: .model),
            requestID: try container.decodeIfPresent(String.self, forKey: .requestID),
            responseID: try container.decodeIfPresent(String.self, forKey: .responseID),
            providerSessionID: try container.decodeIfPresent(String.self, forKey: .providerSessionID),
            metadata: try container.decodeIfPresent([String: String].self, forKey: .metadata) ?? [:],
            promptTokens: try container.decodeIfPresent(Int.self, forKey: .promptTokens),
            completionTokens: try container.decodeIfPresent(Int.self, forKey: .completionTokens),
            totalTokens: try container.decodeIfPresent(Int.self, forKey: .totalTokens)
        )
    }
}

public struct V2WebSource: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var url: URL
    public var snippet: String
    public var siteName: String?

    public init(
        id: String,
        title: String,
        url: URL,
        snippet: String = "",
        siteName: String? = nil
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.snippet = snippet
        self.siteName = siteName
    }

    public init?(
        id: String,
        title: String,
        url: String,
        snippet: String = "",
        siteName: String? = nil
    ) {
        guard let url = URL(string: url),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            return nil
        }
        self.init(
            id: id,
            title: title,
            url: url,
            snippet: snippet,
            siteName: siteName
        )
    }
}

public struct V2BrowserSessionState: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var sourceID: String
    public var lastURL: URL
    public var isExpanded: Bool
    public var isFullscreen: Bool
    public var scrollOffsetY: Double
    public var navigationHistory: [URL]
    public var updatedAt: Date

    public init(
        id: String,
        sourceID: String,
        lastURL: URL,
        isExpanded: Bool = false,
        isFullscreen: Bool = false,
        scrollOffsetY: Double = 0,
        navigationHistory: [URL] = [],
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.sourceID = sourceID
        self.lastURL = lastURL
        self.isExpanded = isExpanded
        self.isFullscreen = isFullscreen
        self.scrollOffsetY = scrollOffsetY
        self.navigationHistory = navigationHistory
        self.updatedAt = updatedAt
    }

    public var isFullScreen: Bool {
        get { isFullscreen }
        set { isFullscreen = newValue }
    }
}

public enum V2AgentMessagePart: Codable, Equatable, Sendable {
    case text(String)
    case trace(V2AgentTraceSummary)
    case sources([V2WebSource])
    case plan(V2PlanDraft)
    case error(V2AgentMessageError)

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case trace
        case sources
        case plan
        case error
    }

    private enum Tag: String, Codable {
        case text
        case trace
        case sources
        case plan
        case error
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(text):
            try container.encode(Tag.text, forKey: .type)
            try container.encode(text, forKey: .text)
        case let .trace(trace):
            try container.encode(Tag.trace, forKey: .type)
            try container.encode(trace, forKey: .trace)
        case let .sources(sources):
            try container.encode(Tag.sources, forKey: .type)
            try container.encode(sources, forKey: .sources)
        case let .plan(plan):
            try container.encode(Tag.plan, forKey: .type)
            try container.encode(plan, forKey: .plan)
        case let .error(error):
            try container.encode(Tag.error, forKey: .type)
            try container.encode(error, forKey: .error)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Tag.self, forKey: .type) {
        case .text:
            self = .text(try container.decode(String.self, forKey: .text))
        case .trace:
            self = .trace(try container.decode(V2AgentTraceSummary.self, forKey: .trace))
        case .sources:
            self = .sources(try container.decode([V2WebSource].self, forKey: .sources))
        case .plan:
            self = .plan(try container.decode(V2PlanDraft.self, forKey: .plan))
        case .error:
            self = .error(try container.decode(V2AgentMessageError.self, forKey: .error))
        }
    }
}

public struct V2AgentMessage: Identifiable, Codable, Equatable, Sendable {
    public enum Role: String, Codable, Equatable, Sendable {
        case user
        case agent

        public static var assistant: Self { .agent }
    }

    public enum Status: String, Codable, Equatable, Sendable {
        case pending
        case streaming
        case complete
        case failed
        case cancelled

        public static var completed: Self { .complete }
    }

    public var id: String
    public var role: Role
    public var parts: [V2AgentMessagePart]
    public var createdAt: Date
    public var updatedAt: Date
    public var status: Status

    public init(
        id: String = UUID().uuidString,
        role: Role,
        parts: [V2AgentMessagePart],
        createdAt: Date,
        updatedAt: Date? = nil,
        status: Status = .complete
    ) {
        self.id = id
        self.role = role
        self.parts = parts
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.status = status
    }

    public static func userText(
        _ text: String,
        at date: Date = Date()
    ) -> Self {
        Self(role: .user, parts: [.text(text)], createdAt: date)
    }

    public static func agentText(
        _ text: String,
        at date: Date = Date()
    ) -> Self {
        Self(role: .agent, parts: [.text(text)], createdAt: date)
    }

    public var plainText: String {
        parts.compactMap { part in
            guard case let .text(text) = part else { return nil }
            return text
        }
        .joined()
    }
}

public struct V2AgentSession: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var createdAt: Date
    public var updatedAt: Date
    public var messages: [V2AgentMessage]
    public var browserSessions: [V2BrowserSessionState]
    public var sourceTask: V2AgentSourceTask?
    public var providerState: V2AgentProviderState?
    public var pendingPlanPrompt: String?
    public var pendingPlan: V2PlanDraft?
    public var traces: [V2AgentTrace]

    public init(
        id: String = UUID().uuidString,
        title: String = "新会话",
        createdAt: Date,
        updatedAt: Date? = nil,
        messages: [V2AgentMessage] = [],
        browserSessions: [V2BrowserSessionState] = [],
        sourceTask: V2AgentSourceTask? = nil,
        providerState: V2AgentProviderState? = nil,
        pendingPlanPrompt: String? = nil,
        pendingPlan: V2PlanDraft? = nil,
        traces: [V2AgentTrace] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.messages = messages
        self.browserSessions = browserSessions
        self.sourceTask = sourceTask
        self.providerState = providerState
        self.pendingPlanPrompt = pendingPlanPrompt
        self.pendingPlan = pendingPlan
        self.traces = traces
    }
}

public struct V2AgentWorkspace: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public static let empty = V2AgentWorkspace()

    public var schemaVersion: Int
    public var sessions: [V2AgentSession]
    public var selectedSessionID: String?

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        sessions: [V2AgentSession] = [],
        selectedSessionID: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.sessions = sessions
        self.selectedSessionID = selectedSessionID
    }

    public var selectedSession: V2AgentSession? {
        guard let selectedSessionID else { return nil }
        return session(id: selectedSessionID)
    }

    @discardableResult
    public mutating func createSession(
        at date: Date = Date(),
        sourceTask: V2AgentSourceTask? = nil
    ) -> V2AgentSession {
        let session = V2AgentSession(createdAt: date, sourceTask: sourceTask)
        sessions.append(session)
        selectedSessionID = session.id
        return session
    }

    @discardableResult
    public mutating func selectSession(id: String) -> Bool {
        guard sessions.contains(where: { $0.id == id }) else { return false }
        selectedSessionID = id
        return true
    }

    public func session(id: String) -> V2AgentSession? {
        sessions.first { $0.id == id }
    }

    @discardableResult
    public mutating func appendMessage(
        _ message: V2AgentMessage,
        to sessionID: String
    ) -> Bool {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else {
            return false
        }

        sessions[index].messages.append(message)
        updateSessionTitleIfNeeded(at: index)
        sessions[index].updatedAt = max(sessions[index].updatedAt, message.updatedAt)
        return true
    }

    @discardableResult
    public mutating func replaceMessage(
        _ message: V2AgentMessage,
        in sessionID: String
    ) -> Bool {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }),
              let messageIndex = sessions[sessionIndex].messages.firstIndex(where: { $0.id == message.id }) else {
            return false
        }

        let oldMessage = sessions[sessionIndex].messages[messageIndex]
        let oldTitleMessageID = firstMeaningfulUserMessage(in: sessions[sessionIndex].messages)?.id
        sessions[sessionIndex].messages[messageIndex] = message

        if oldMessage.id == oldTitleMessageID {
            sessions[sessionIndex].title = firstMeaningfulUserMessage(in: sessions[sessionIndex].messages)
                .map { Self.sessionTitle(from: $0.plainText) }
                ?? Self.defaultSessionTitle
        } else if sessions[sessionIndex].title == Self.defaultSessionTitle {
            updateSessionTitleIfNeeded(at: sessionIndex)
        }
        sessions[sessionIndex].updatedAt = max(sessions[sessionIndex].updatedAt, message.updatedAt)
        return true
    }

    @discardableResult
    public mutating func updateBrowserState(
        _ state: V2BrowserSessionState,
        in sessionID: String
    ) -> Bool {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }) else {
            return false
        }

        if let browserIndex = sessions[sessionIndex].browserSessions.firstIndex(where: { $0.id == state.id }) {
            sessions[sessionIndex].browserSessions[browserIndex] = state
        } else {
            sessions[sessionIndex].browserSessions.append(state)
        }
        sessions[sessionIndex].updatedAt = max(sessions[sessionIndex].updatedAt, state.updatedAt)
        return true
    }

    @discardableResult
    public mutating func updateProviderState(
        _ state: V2AgentProviderState?,
        in sessionID: String
    ) -> Bool {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }) else {
            return false
        }

        sessions[sessionIndex].providerState = state
        if let state {
            sessions[sessionIndex].updatedAt = max(sessions[sessionIndex].updatedAt, state.updatedAt)
        }
        return true
    }

    @discardableResult
    public mutating func deleteSession(id: String) -> Bool {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else {
            return false
        }

        let wasSelected = selectedSessionID == id
        sessions.remove(at: index)

        let selectionIsInvalid = selectedSessionID.map { selectedID in
            !sessions.contains { $0.id == selectedID }
        } ?? false
        if wasSelected || selectionIsInvalid {
            selectedSessionID = mostRecentlyUpdatedSessionID()
        }
        return true
    }
}

private extension V2AgentWorkspace {
    static let defaultSessionTitle = "新会话"

    mutating func updateSessionTitleIfNeeded(at index: Int) {
        guard let firstMeaningfulUserMessage = firstMeaningfulUserMessage(in: sessions[index].messages) else {
            if sessions[index].title.isEmpty {
                sessions[index].title = Self.defaultSessionTitle
            }
            return
        }

        if sessions[index].title == Self.defaultSessionTitle || sessions[index].title.isEmpty {
            sessions[index].title = Self.sessionTitle(from: firstMeaningfulUserMessage.plainText)
        }
    }

    func firstMeaningfulUserMessage(in messages: [V2AgentMessage]) -> V2AgentMessage? {
        messages.first { message in
            guard message.role == .user else { return false }
            return !Self.normalizedTitleText(message.plainText).isEmpty
        }
    }

    static func normalizedTitleText(_ text: String) -> String {
        text
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    static func sessionTitle(from text: String) -> String {
        let normalized = normalizedTitleText(text)
        return String(normalized.prefix(28))
    }

    func mostRecentlyUpdatedSessionID() -> String? {
        sessions.enumerated().max { lhs, rhs in
            if lhs.element.updatedAt == rhs.element.updatedAt {
                return lhs.offset < rhs.offset
            }
            return lhs.element.updatedAt < rhs.element.updatedAt
        }?.element.id
    }
}

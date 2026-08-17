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

public enum V2AgentTool: String, Codable, Equatable, Sendable {
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

public typealias V2AgentTraceTool = V2AgentTool

public enum V2AgentTraceErrorCategory: String, Codable, Equatable, Sendable {
    case model
    case web
    case localData
    case planning
    case network
    case provider
    case cancelled
}

public enum V2AgentTraceErrorCode: String, Codable, Equatable, Sendable {
    case unauthorized
    case forbidden
    case timeout
    case rateLimited
    case invalidRequest
    case invalidResponse
    case unavailable
    case cancelled
    case unknown
}

public struct V2AgentTraceError: Codable, Equatable, Sendable {
    public var category: V2AgentTraceErrorCategory
    public var code: V2AgentTraceErrorCode

    public init(
        category: V2AgentTraceErrorCategory,
        code: V2AgentTraceErrorCode
    ) {
        self.category = category
        self.code = code
    }
}

private enum V2AgentTraceSanitizer {
    static func redact(_ text: String) -> String {
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
}

public enum V2AgentTraceSubject: Codable, Equatable, Sendable {
    case searchQuery(String)
    case sourceURL(URL)
    case sourceTitle(String)
    case localScope(String)
    case planTitle(String)

    fileprivate func sanitized() -> Self {
        switch self {
        case let .searchQuery(query):
            return .searchQuery(V2AgentTraceSanitizer.redact(query))
        case let .sourceURL(url):
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.user = nil
            components?.password = nil
            return .sourceURL(components?.url ?? url)
        case let .sourceTitle(title):
            return .sourceTitle(V2AgentTraceSanitizer.redact(title))
        case let .localScope(scope):
            return .localScope(V2AgentTraceSanitizer.redact(scope))
        case let .planTitle(title):
            return .planTitle(V2AgentTraceSanitizer.redact(title))
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case value
    }

    private enum Tag: String, Codable {
        case searchQuery
        case sourceURL
        case sourceTitle
        case localScope
        case planTitle
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .searchQuery(query):
            try container.encode(Tag.searchQuery, forKey: .type)
            try container.encode(V2AgentTraceSanitizer.redact(query), forKey: .value)
        case let .sourceURL(url):
            try container.encode(Tag.sourceURL, forKey: .type)
            try container.encode(url, forKey: .value)
        case let .sourceTitle(title):
            try container.encode(Tag.sourceTitle, forKey: .type)
            try container.encode(V2AgentTraceSanitizer.redact(title), forKey: .value)
        case let .localScope(scope):
            try container.encode(Tag.localScope, forKey: .type)
            try container.encode(V2AgentTraceSanitizer.redact(scope), forKey: .value)
        case let .planTitle(title):
            try container.encode(Tag.planTitle, forKey: .type)
            try container.encode(V2AgentTraceSanitizer.redact(title), forKey: .value)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Tag.self, forKey: .type) {
        case .searchQuery:
            self = .searchQuery(V2AgentTraceSanitizer.redact(try container.decode(String.self, forKey: .value)))
        case .sourceURL:
            self = .sourceURL(try container.decode(URL.self, forKey: .value)).sanitized()
        case .sourceTitle:
            self = .sourceTitle(V2AgentTraceSanitizer.redact(try container.decode(String.self, forKey: .value)))
        case .localScope:
            self = .localScope(V2AgentTraceSanitizer.redact(try container.decode(String.self, forKey: .value)))
        case .planTitle:
            self = .planTitle(V2AgentTraceSanitizer.redact(try container.decode(String.self, forKey: .value)))
        }
    }
}

public struct V2AgentTraceStep: Identifiable, Codable, Equatable, Sendable {
    public typealias Status = V2AgentTraceStatus

    public private(set) var id: String
    public private(set) var tool: V2AgentTool
    public private(set) var status: V2AgentTraceStatus
    public private(set) var duration: TimeInterval
    public private(set) var subject: V2AgentTraceSubject?
    public private(set) var error: V2AgentTraceError?

    public init(
        id: String = UUID().uuidString,
        tool: V2AgentTool,
        status: V2AgentTraceStatus,
        duration: TimeInterval,
        subject: V2AgentTraceSubject? = nil,
        error: V2AgentTraceError? = nil
    ) {
        self.id = V2AgentTraceSanitizer.redact(id)
        self.tool = tool
        self.status = status
        self.duration = max(0, duration)
        self.subject = subject?.sanitized()
        self.error = error
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case tool
        case status
        case duration
        case subject
        case error
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(tool, forKey: .tool)
        try container.encode(status, forKey: .status)
        try container.encode(duration, forKey: .duration)
        try container.encodeIfPresent(subject, forKey: .subject)
        try container.encodeIfPresent(error, forKey: .error)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            tool: try container.decode(V2AgentTool.self, forKey: .tool),
            status: try container.decode(V2AgentTraceStatus.self, forKey: .status),
            duration: try container.decode(TimeInterval.self, forKey: .duration),
            subject: try container.decodeIfPresent(V2AgentTraceSubject.self, forKey: .subject),
            error: try container.decodeIfPresent(V2AgentTraceError.self, forKey: .error)
        )
    }
}

public struct V2AgentTrace: Identifiable, Codable, Equatable, Sendable {
    public typealias Status = V2AgentTraceStatus

    public private(set) var id: String
    public private(set) var status: V2AgentTraceStatus
    public private(set) var steps: [V2AgentTraceStep]
    public private(set) var startedAt: Date
    public private(set) var endedAt: Date?
    public private(set) var providerLabel: String?
    public private(set) var model: String?
    public private(set) var providerSessionID: String?
    public private(set) var requestID: String?
    public private(set) var responseID: String?
    public private(set) var promptTokens: Int?
    public private(set) var completionTokens: Int?
    public private(set) var totalTokens: Int?

    public init(
        id: String = UUID().uuidString,
        status: V2AgentTraceStatus = .succeeded,
        steps: [V2AgentTraceStep] = [],
        startedAt: Date,
        endedAt: Date? = nil,
        providerLabel: String? = nil,
        model: String? = nil,
        providerSessionID: String? = nil,
        requestID: String? = nil,
        responseID: String? = nil,
        promptTokens: Int? = nil,
        completionTokens: Int? = nil,
        totalTokens: Int? = nil
    ) {
        self.id = V2AgentTraceSanitizer.redact(id)
        self.status = status
        self.steps = steps
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.providerLabel = providerLabel.map(V2AgentTraceSanitizer.redact)
        self.model = model.map(V2AgentTraceSanitizer.redact)
        self.providerSessionID = providerSessionID.map(V2AgentTraceSanitizer.redact)
        self.requestID = requestID.map(V2AgentTraceSanitizer.redact)
        self.responseID = responseID.map(V2AgentTraceSanitizer.redact)
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
        case status
        case steps
        case startedAt
        case endedAt
        case providerLabel
        case model
        case providerSessionID
        case requestID
        case responseID
        case promptTokens
        case completionTokens
        case totalTokens
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(status, forKey: .status)
        try container.encode(steps, forKey: .steps)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encodeIfPresent(endedAt, forKey: .endedAt)
        try container.encodeIfPresent(providerLabel, forKey: .providerLabel)
        try container.encodeIfPresent(model, forKey: .model)
        try container.encodeIfPresent(providerSessionID, forKey: .providerSessionID)
        try container.encodeIfPresent(requestID, forKey: .requestID)
        try container.encodeIfPresent(responseID, forKey: .responseID)
        try container.encodeIfPresent(promptTokens, forKey: .promptTokens)
        try container.encodeIfPresent(completionTokens, forKey: .completionTokens)
        try container.encodeIfPresent(totalTokens, forKey: .totalTokens)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            status: try container.decode(V2AgentTraceStatus.self, forKey: .status),
            steps: try container.decode([V2AgentTraceStep].self, forKey: .steps),
            startedAt: try container.decode(Date.self, forKey: .startedAt),
            endedAt: try container.decodeIfPresent(Date.self, forKey: .endedAt),
            providerLabel: try container.decodeIfPresent(String.self, forKey: .providerLabel),
            model: try container.decodeIfPresent(String.self, forKey: .model),
            providerSessionID: try container.decodeIfPresent(String.self, forKey: .providerSessionID),
            requestID: try container.decodeIfPresent(String.self, forKey: .requestID),
            responseID: try container.decodeIfPresent(String.self, forKey: .responseID),
            promptTokens: try container.decodeIfPresent(Int.self, forKey: .promptTokens),
            completionTokens: try container.decodeIfPresent(Int.self, forKey: .completionTokens),
            totalTokens: try container.decodeIfPresent(Int.self, forKey: .totalTokens)
        )
    }
}

public struct V2AgentTraceSummary: Codable, Equatable, Sendable {
    public private(set) var status: V2AgentTraceStatus
    public private(set) var toolCount: Int
    public private(set) var duration: TimeInterval?

    public var displayText: String {
        let statusText: String
        switch status {
        case .running:
            statusText = "进行中"
        case .succeeded:
            statusText = "完成"
        case .failed:
            statusText = "失败"
        case .cancelled:
            statusText = "已取消"
        }

        let stepText = "\(toolCount) 个步骤"
        guard let duration else {
            return "\(statusText) \(stepText)"
        }
        return "\(statusText) \(stepText) · \(String(format: "%.1f", duration)) 秒"
    }

    public init(status: V2AgentTraceStatus, toolCount: Int, duration: TimeInterval?) {
        self.status = status
        self.toolCount = max(0, toolCount)
        self.duration = duration.map { max(0, $0) }
    }

    public init(_ trace: V2AgentTrace) {
        self.init(status: trace.status, toolCount: trace.steps.count, duration: trace.duration)
    }

    private enum CodingKeys: String, CodingKey {
        case status
        case toolCount
        case duration
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(status, forKey: .status)
        try container.encode(toolCount, forKey: .toolCount)
        try container.encodeIfPresent(duration, forKey: .duration)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            status: try container.decode(V2AgentTraceStatus.self, forKey: .status),
            toolCount: try container.decode(Int.self, forKey: .toolCount),
            duration: try container.decodeIfPresent(TimeInterval.self, forKey: .duration)
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
    public static let currentSchemaVersion = 2
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

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

public struct V2AgentTraceStep: Identifiable, Codable, Equatable, Sendable {
    public enum Status: String, Codable, Equatable, Sendable {
        case running
        case succeeded
        case failed
        case cancelled
    }

    public var id: String
    public var name: String
    public var summary: String
    public var status: Status
    public var startedAt: Date
    public var endedAt: Date?

    public init(
        id: String = UUID().uuidString,
        name: String,
        summary: String = "",
        status: Status = .succeeded,
        startedAt: Date,
        endedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.status = status
        self.startedAt = startedAt
        self.endedAt = endedAt
    }

    public init(
        id: String = UUID().uuidString,
        label: String,
        detail: String = "",
        status: Status = .succeeded,
        startedAt: Date,
        endedAt: Date? = nil
    ) {
        self.init(
            id: id,
            name: label,
            summary: detail,
            status: status,
            startedAt: startedAt,
            endedAt: endedAt
        )
    }

    public var label: String {
        get { name }
        set { name = newValue }
    }

    public var detail: String {
        get { summary }
        set { summary = newValue }
    }

    public var duration: TimeInterval? {
        guard let endedAt else { return nil }
        return max(0, endedAt.timeIntervalSince(startedAt))
    }
}

public struct V2AgentTrace: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var summary: String
    public var steps: [V2AgentTraceStep]
    public var startedAt: Date
    public var endedAt: Date?
    public var providerLabel: String?
    public var model: String?
    public var requestID: String?
    public var responseID: String?
    public var providerSessionID: String?
    public var promptTokens: Int?
    public var completionTokens: Int?
    public var totalTokens: Int?

    public init(
        id: String = UUID().uuidString,
        summary: String = "",
        steps: [V2AgentTraceStep] = [],
        startedAt: Date,
        endedAt: Date? = nil,
        providerLabel: String? = nil,
        model: String? = nil,
        requestID: String? = nil,
        responseID: String? = nil,
        providerSessionID: String? = nil,
        promptTokens: Int? = nil,
        completionTokens: Int? = nil,
        totalTokens: Int? = nil
    ) {
        self.id = id
        self.summary = summary
        self.steps = steps
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.providerLabel = providerLabel
        self.model = model
        self.requestID = requestID
        self.responseID = responseID
        self.providerSessionID = providerSessionID
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
    }

    public var duration: TimeInterval? {
        guard let endedAt else { return nil }
        return max(0, endedAt.timeIntervalSince(startedAt))
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

    public init(
        id: String,
        title: String,
        url: String,
        snippet: String = "",
        siteName: String? = nil
    ) {
        self.init(
            id: id,
            title: title,
            url: URL(string: url) ?? URL(string: "about:blank")!,
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
    case trace(V2AgentTrace)
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
            self = .trace(try container.decode(V2AgentTrace.self, forKey: .trace))
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

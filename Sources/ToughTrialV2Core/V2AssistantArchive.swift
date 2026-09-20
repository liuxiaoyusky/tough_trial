import Foundation

/// A bounded, source-linked projection of an assistant session.
public struct V2ArchiveSessionSummary: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let updatedAt: Date
    public let messageCount: Int

    public init(id: String, title: String, updatedAt: Date, messageCount: Int) {
        self.id = id
        self.title = title
        self.updatedAt = updatedAt
        self.messageCount = max(0, messageCount)
    }
}

/// The public text projection intentionally omits binary and large structured payloads.
public struct V2ArchiveMessage: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let role: V2AgentMessage.Role
    public let text: String
    public let createdAt: Date

    public init(id: String, role: V2AgentMessage.Role, text: String, createdAt: Date) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
    }
}

/// Effective request-size measurements for a deterministic local compaction.
/// Token values are estimates; provider usage reported by a completed request
/// remains the authoritative token count.
public struct V2AssistantCompactionMetrics: Codable, Equatable, Sendable {
    public let beforeCharacterCount: Int
    public let afterCharacterCount: Int
    public let beforeTokenEstimate: Int
    public let afterTokenEstimate: Int
    public let coveredMessageCount: Int
    public let retainedMessageCount: Int
    public let noBenefitReason: String?
    public let tokenEstimateIsHeuristic: Bool

    public init(
        beforeCharacterCount: Int = 0,
        afterCharacterCount: Int = 0,
        beforeTokenEstimate: Int = 0,
        afterTokenEstimate: Int = 0,
        coveredMessageCount: Int = 0,
        retainedMessageCount: Int = 0,
        noBenefitReason: String? = nil,
        tokenEstimateIsHeuristic: Bool = true
    ) {
        self.beforeCharacterCount = max(0, beforeCharacterCount)
        self.afterCharacterCount = max(0, afterCharacterCount)
        self.beforeTokenEstimate = max(0, beforeTokenEstimate)
        self.afterTokenEstimate = max(0, afterTokenEstimate)
        self.coveredMessageCount = max(0, coveredMessageCount)
        self.retainedMessageCount = max(0, retainedMessageCount)
        self.noBenefitReason = noBenefitReason
        self.tokenEstimateIsHeuristic = tokenEstimateIsHeuristic
    }

    public static let empty = Self()

    public var didReduce: Bool {
        noBenefitReason == nil
            && beforeCharacterCount > afterCharacterCount
            && beforeTokenEstimate >= afterTokenEstimate
    }

    public var savedCharacterCount: Int { max(0, beforeCharacterCount - afterCharacterCount) }
    public var savedTokenEstimate: Int { max(0, beforeTokenEstimate - afterTokenEstimate) }

    public var reductionPercentage: Double {
        guard beforeCharacterCount > 0 else { return 0 }
        return Double(savedCharacterCount) / Double(beforeCharacterCount)
    }

    // Short aliases keep the contract convenient for context/turn-loop code.
    public var beforeCharacters: Int { beforeCharacterCount }
    public var afterCharacters: Int { afterCharacterCount }
    public var beforeTokens: Int { beforeTokenEstimate }
    public var afterTokens: Int { afterTokenEstimate }
    public var beforeEffectiveCharacterCount: Int { beforeCharacterCount }
    public var afterEffectiveCharacterCount: Int { afterCharacterCount }
    public var estimatedBeforeTokenCount: Int { beforeTokenEstimate }
    public var estimatedAfterTokenCount: Int { afterTokenEstimate }

    public var feedback: String {
        if didReduce {
            return "已缩减有效上下文：字符 " + String(beforeCharacterCount) + " → " + String(afterCharacterCount)
                + "，估算 token " + String(beforeTokenEstimate) + " → " + String(afterTokenEstimate) + "。"
        }
        switch noBenefitReason {
        case "alreadyCompacted":
            return "当前摘要已是最新，无需重复整理；原文仍保留。"
        case "shortSession":
            return "会话较短，无需整理；继续使用原文。"
        case "noCoveredMessages":
            return "没有可整理的旧消息；继续使用原文。"
        case "noReduction":
            return "摘要没有减少有效上下文；继续使用原文。"
        default:
            return "本次整理没有减少有效上下文；继续使用原文。"
        }
    }
}

/// The effective size of the material sent to a provider for one request.
/// This deliberately reports a local estimate separately from provider usage.
public struct V2AssistantContextMetrics: Codable, Equatable, Sendable {
    public let characterCount: Int
    public let tokenEstimate: Int
    public let messageCount: Int
    public let compactSummaryCharacterCount: Int
    public let tokenEstimateIsHeuristic: Bool

    public init(
        characterCount: Int,
        tokenEstimate: Int,
        messageCount: Int,
        compactSummaryCharacterCount: Int = 0,
        tokenEstimateIsHeuristic: Bool = true
    ) {
        self.characterCount = max(0, characterCount)
        self.tokenEstimate = max(0, tokenEstimate)
        self.messageCount = max(0, messageCount)
        self.compactSummaryCharacterCount = max(0, compactSummaryCharacterCount)
        self.tokenEstimateIsHeuristic = tokenEstimateIsHeuristic
    }

    public var effectiveCharacterCount: Int { characterCount }
    public var estimatedTokenCount: Int { tokenEstimate }
}

public struct V2AssistantCompaction: Codable, Equatable, Sendable {
    public let revision: Int
    public let summary: String
    public let coveredMessageIDs: [String]
    public let preservedReferenceIDs: [String]
    public let createdAt: Date
    public let metrics: V2AssistantCompactionMetrics

    public init(
        revision: Int,
        summary: String,
        coveredMessageIDs: [String],
        createdAt: Date,
        preservedReferenceIDs: [String] = [],
        metrics: V2AssistantCompactionMetrics = .empty
    ) {
        self.revision = max(1, revision)
        self.summary = summary
        self.coveredMessageIDs = coveredMessageIDs
        self.preservedReferenceIDs = Array(preservedReferenceIDs.prefix(24))
        self.createdAt = createdAt
        self.metrics = metrics
    }

    private enum CodingKeys: String, CodingKey {
        case revision
        case summary
        case coveredMessageIDs
        case preservedReferenceIDs
        case createdAt
        case metrics
    }

    /// Keep public compaction values readable when an older caller persisted
    /// the original revision/summary/source-ID shape before metrics and
    /// preserved references were added.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            revision: try container.decode(Int.self, forKey: .revision),
            summary: try container.decode(String.self, forKey: .summary),
            coveredMessageIDs: try container.decode([String].self, forKey: .coveredMessageIDs),
            createdAt: try container.decode(Date.self, forKey: .createdAt),
            preservedReferenceIDs: try container.decodeIfPresent([String].self, forKey: .preservedReferenceIDs) ?? [],
            metrics: try container.decodeIfPresent(V2AssistantCompactionMetrics.self, forKey: .metrics) ?? .empty
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(revision, forKey: .revision)
        try container.encode(summary, forKey: .summary)
        try container.encode(coveredMessageIDs, forKey: .coveredMessageIDs)
        try container.encode(preservedReferenceIDs, forKey: .preservedReferenceIDs)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(metrics, forKey: .metrics)
    }

    public var referencedIDs: [String] { preservedReferenceIDs }
    public var didReduce: Bool { metrics.didReduce }
    public var noBenefitMessage: String? { didReduce ? nil : metrics.feedback }
}

public struct V2ArchiveEvent: Codable, Equatable, Sendable {
    public let kind: String
    public let requestID: String?
    public let metadata: [String: String]
    public let at: Date

    public init(
        kind: String,
        requestID: String? = nil,
        metadata: [String: String] = [:],
        at: Date
    ) {
        self.kind = kind
        self.requestID = requestID
        self.metadata = metadata
        self.at = at
    }
}

public enum V2AssistantArchiveError: Error, Equatable, LocalizedError, Sendable {
    case invalidSessionID(String)
    case invalidValue(String)
    case unsupportedSchema(Int)
    case corruptFile(URL)
    case fileNotFound(URL)

    public var errorDescription: String? {
        switch self {
        case let .invalidSessionID(id):
            return "助手会话 ID 无效：\(id)"
        case let .invalidValue(value):
            return "助手归档字段无效：\(value)"
        case let .unsupportedSchema(version):
            return "助手归档版本不受支持：\(version)"
        case let .corruptFile(url):
            return "助手归档文件损坏：\(url.lastPathComponent)"
        case let .fileNotFound(url):
            return "助手归档文件不存在：\(url.lastPathComponent)"
        }
    }
}

/// Durable local history for the assistant. Passing no root keeps the archive in memory.
/// The class is synchronised because the host may archive a completed turn while the UI reads it.
public final class V2AssistantArchive: @unchecked Sendable {
    public let rootURL: URL?

    private static let schemaVersion = 1
    private static let maxQueryCharacters = 512
    private static let maxLimit = 100
    private static let maxSessionIDCharacters = 96
    private static let maxMessageIDCharacters = 256
    private static let maxTextCharacters = 16_000
    private static let maxTitleCharacters = 256
    private static let maxKindCharacters = 128
    private static let maxRequestIDCharacters = 256
    private static let maxMetadataKeyCharacters = 64
    private static let maxMetadataValueCharacters = 512
    private static let maxMemoryStatementCharacters = 2_000
    private static let maxArchiveBytes = 32 * 1024 * 1024
    private static let maxArchiveLines = 100_000
    private static let minimumCompactionMessageCount = 13

    private let lock = NSRecursiveLock()
    private let fileManager: FileManager

    private var memoryLines: [String: [StoredLine]] = [:]
    private var memoryIndex: [String: ArchiveIndexEntry] = [:]
    private var memoryCompactions: [String: V2AssistantCompaction] = [:]
    private var memoryCompactionFingerprints: [String: [String]] = [:]
    private var memoryRecords: [V2UserMemoryRecord] = []

    public init(rootURL: URL? = nil) {
        self.rootURL = rootURL?.standardizedFileURL
        self.fileManager = .default
    }

    /// Estimates provider tokens without claiming to reproduce a provider
    /// tokenizer. CJK/emoji scalars count individually; ASCII runs are grouped
    /// in small chunks so the estimate remains stable and bounded locally.
    public static func estimatedTokenCount(for text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        var tokenCount = 0
        var asciiRunLength = 0
        func flushASCII() {
            if asciiRunLength > 0 {
                tokenCount += (asciiRunLength + 3) / 4
                asciiRunLength = 0
            }
        }
        for scalar in text.unicodeScalars {
            let value = scalar.value
            if value < 128 {
                if (9...13).contains(value) || value == 32 {
                    flushASCII()
                    tokenCount += 1
                } else {
                    asciiRunLength += 1
                }
            } else {
                flushASCII()
                tokenCount += 1
            }
        }
        flushASCII()
        return tokenCount
    }

    public static func effectiveCharacterCount(for messages: [V2ArchiveMessage]) -> Int {
        messages.reduce(0) { $0 + $1.text.count }
    }

    public static func estimatedTokenCount(for messages: [V2ArchiveMessage]) -> Int {
        messages.reduce(0) { $0 + estimatedTokenCount(for: $1.text) }
    }

    /// Measures the actual context materials that the host assembled for a
    /// request. The source task and memory are retained facts, while the
    /// compact summary is counted as sent text rather than archive bytes.
    public static func effectiveContextMetrics(
        conversation: [V2AgentConversationMessage],
        compactSummary: String = "",
        sourceTask: V2AgentSourceTask? = nil,
        memories: [V2UserMemoryRecord] = []
    ) -> V2AssistantContextMetrics {
        var text = compactSummary
        text += conversation.map(\.text).joined()
        if let sourceTask {
            text += sourceTask.id + sourceTask.title + sourceTask.note
        }
        text += memories.map(\.statement).joined()
        return V2AssistantContextMetrics(
            characterCount: text.count,
            tokenEstimate: estimatedTokenCount(for: text),
            messageCount: conversation.count,
            compactSummaryCharacterCount: compactSummary.count
        )
    }

    public func sync(_ workspace: V2AgentWorkspace) throws {
        lock.lock()
        defer { lock.unlock() }

        guard workspace.schemaVersion == V2AgentWorkspace.currentSchemaVersion else {
            throw V2AssistantArchiveError.unsupportedSchema(workspace.schemaVersion)
        }

        var incomingIDs = Set<String>()
        var nextIndex: [String: ArchiveIndexEntry] = [:]
        let existingIndex = try loadIndex()

        for session in workspace.sessions {
            try validateSessionID(session.id)
            guard incomingIDs.insert(session.id).inserted else {
                throw V2AssistantArchiveError.invalidValue("重复会话 ID")
            }
            let entry = try syncSession(session)
            nextIndex[session.id] = entry
        }

        let oldIDs = Set(existingIndex.sessions.map(\.id)).union(try storedSessionIDs())
        try persistIndex(ArchiveIndex(sessions: nextIndex.values.sorted(by: Self.indexSort)))

        for id in oldIDs where !incomingIDs.contains(id) {
            try removeSessionFiles(id)
        }

        // `persistIndex` updates the in-memory projection as well.
    }

    public func sessions(query: String = "", limit: Int = 20) throws -> [V2ArchiveSessionSummary] {
        lock.lock()
        defer { lock.unlock() }

        let normalizedLimit = Self.normalizedLimit(limit)
        guard normalizedLimit > 0 else { return [] }
        let normalizedQuery = Self.normalizedQuery(query)
        let index = try loadIndex()
        var matches: [V2ArchiveSessionSummary] = []

        for entry in index.sessions {
            let summary = V2ArchiveSessionSummary(
                id: entry.id,
                title: entry.title,
                updatedAt: entry.updatedAt,
                messageCount: entry.messageCount
            )
            if normalizedQuery.isEmpty || summary.title.localizedCaseInsensitiveContains(normalizedQuery) {
                matches.append(summary)
                continue
            }

            let lines = try loadLines(for: entry.id)
            if latestMessages(from: lines).contains(where: { $0.message.text.localizedCaseInsensitiveContains(normalizedQuery) }) {
                matches.append(summary)
            }
        }

        return Array(matches.sorted(by: Self.summarySort).prefix(normalizedLimit))
    }

    public func readSession(
        id: String,
        query: String = "",
        limit: Int = 20
    ) throws -> [V2ArchiveMessage] {
        lock.lock()
        defer { lock.unlock() }

        try validateSessionID(id)
        let normalizedLimit = Self.normalizedLimit(limit)
        guard normalizedLimit > 0 else { return [] }
        let normalizedQuery = Self.normalizedQuery(query)
        let messages = latestMessages(from: try loadLines(for: id))
            .map(\.message)
            .filter { normalizedQuery.isEmpty || $0.text.localizedCaseInsensitiveContains(normalizedQuery) }
            .sorted(by: Self.messageSort)
        return Array(messages.suffix(normalizedLimit))
    }

    public func compact(
        _ session: V2AgentSession,
        at date: Date = Date(),
        recentMessageLimit: Int = 12,
        summaryCharacterLimit: Int = 6_000
    ) throws -> V2AssistantCompaction {
        lock.lock()
        defer { lock.unlock() }

        try validateSessionID(session.id)
        let archiveMessages = try normalizedMessages(from: session)
        try appendMissingMessages(archiveMessages, sessionID: session.id)

        let currentLines = try loadLines(for: session.id)
        let currentMessages = latestMessages(from: currentLines)
        let requestedTitle = bounded(Self.redact(session.title.trimmingCharacters(in: .whitespacesAndNewlines)), to: Self.maxTitleCharacters)
        let title = requestedTitle.isEmpty
            ? (currentMessages.first(where: { $0.message.role == .user })?.message.text.prefix(28).description ?? "新会话")
            : requestedTitle
        var index = try loadIndex()
        index.sessions.removeAll { $0.id == session.id }
        index.sessions.append(.init(
            id: session.id,
            title: title,
            updatedAt: max(session.updatedAt, currentMessages.map { max($0.message.createdAt, $0.revision) }.max() ?? session.updatedAt),
            messageCount: currentMessages.count
        ))
        try persistIndex(index)

        let recentLimit = min(max(0, recentMessageLimit), Self.maxLimit)
        let sortedMessages = archiveMessages // Canonical conversation order, including equal-time user/assistant pairs.
        let coveredCount = max(0, sortedMessages.count - recentLimit)
        let previous = try loadStoredCompactionUnlocked(sessionID: session.id)

        let enoughMessages = sortedMessages.count >= Self.minimumCompactionMessageCount
        let canCoverMessages = enoughMessages && coveredCount > 0
        let coveredProjected = canCoverMessages ? Array(sortedMessages.prefix(coveredCount)) : []
        let covered = coveredProjected.map(\.message)
        let retained: [V2ArchiveMessage] = canCoverMessages
            ? Array(sortedMessages.suffix(sortedMessages.count - coveredCount)).map(\.message)
            : sortedMessages.map(\.message)
        let coveredIDs = canCoverMessages ? covered.map(\.id) : []
        let summary = canCoverMessages
            ? makeCompactionSummary(for: covered, characterLimit: min(summaryCharacterLimit, covered.reduce(0) { $0 + $1.text.count } / 3))
            : ""
        let beforeText = V2AssistantHistory.conversation(session.messages).map(\.text).joined()
        let afterText = canCoverMessages
            ? summary + V2AssistantHistory.conversation(session.messages, coveredIDs: coveredIDs).map(\.text).joined()
            : beforeText
        let beforeCharacterCount = beforeText.count
        let afterCharacterCount = afterText.count
        let beforeTokenEstimate = Self.estimatedTokenCount(for: beforeText)
        let afterTokenEstimate = Self.estimatedTokenCount(for: afterText)
        let noBenefitReason: String?
        if !enoughMessages {
            noBenefitReason = "shortSession"
        } else if coveredCount == 0 {
            noBenefitReason = "noCoveredMessages"
        } else if afterCharacterCount >= beforeCharacterCount || afterTokenEstimate > beforeTokenEstimate {
            noBenefitReason = "noReduction"
        } else {
            noBenefitReason = nil
        }
        let metrics = V2AssistantCompactionMetrics(
            beforeCharacterCount: beforeCharacterCount,
            afterCharacterCount: noBenefitReason == nil ? afterCharacterCount : beforeCharacterCount,
            beforeTokenEstimate: beforeTokenEstimate,
            afterTokenEstimate: noBenefitReason == nil ? afterTokenEstimate : beforeTokenEstimate,
            coveredMessageCount: noBenefitReason == nil ? covered.count : 0,
            retainedMessageCount: noBenefitReason == nil ? retained.count : sortedMessages.count,
            noBenefitReason: noBenefitReason
        )
        let referenceIDs = preservedReferenceIDs(for: session)

        if let previous,
           previous.value.summary == summary,
           previous.value.coveredMessageIDs == coveredIDs,
           previous.value.preservedReferenceIDs == referenceIDs,
           previous.value.metrics == metrics,
           previous.messageFingerprints == (metrics.didReduce ? coveredProjected.map { fingerprint(for: $0.message, revision: $0.revision) } : []) {
            return previous.value
        }

        if !metrics.didReduce {
            let noOp = V2AssistantCompaction(
                revision: previous?.value.revision ?? 1,
                summary: "",
                coveredMessageIDs: [],
                createdAt: date,
                preservedReferenceIDs: referenceIDs,
                metrics: metrics
            )
            // Persisting a no-op clears a previous stale summary after a
            // session is shortened, while callers can still show the reason.
            try persistCompaction(noOp, sessionID: session.id, messageFingerprints: [])
            return noOp
        }

        let fingerprints = coveredProjected.map { fingerprint(for: $0.message, revision: $0.revision) }
        let compaction = V2AssistantCompaction(
            revision: (previous?.value.revision ?? 0) + 1,
            summary: summary,
            coveredMessageIDs: coveredIDs,
            createdAt: date,
            preservedReferenceIDs: referenceIDs,
            metrics: metrics
        )
        try persistCompaction(compaction, sessionID: session.id, messageFingerprints: fingerprints)
        return compaction
    }

    public func loadCompaction(sessionID: String) throws -> V2AssistantCompaction? {
        lock.lock()
        defer { lock.unlock() }
        try validateSessionID(sessionID)
        return try loadCompactionUnlocked(sessionID: sessionID)
    }

    public func syncMemory(_ records: [V2UserMemoryRecord]) throws {
        lock.lock()
        defer { lock.unlock() }

        let normalized = try records.map(normalizedMemoryRecord).sorted(by: Self.memorySort)
        let markdown = memoryMarkdown(for: normalized)
        let summary = memorySummaryMarkdown(for: normalized)

        if let rootURL {
            let directory = rootURL.appendingPathComponent("memory", isDirectory: true)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try markdown.data(using: .utf8)!.write(
                to: directory.appendingPathComponent("MEMORY.md"),
                options: .atomic
            )
            try summary.data(using: .utf8)!.write(
                to: directory.appendingPathComponent("memory_summary.md"),
                options: .atomic
            )
        }
        memoryRecords = normalized
    }

    public func record(
        sessionID: String,
        kind: String,
        requestID: String? = nil,
        metadata: [String: String] = [:],
        at date: Date = Date()
    ) throws {
        lock.lock()
        defer { lock.unlock() }

        try validateSessionID(sessionID)
        let event = V2ArchiveEvent(
            kind: bounded(Self.redact(kind), to: Self.maxKindCharacters),
            requestID: requestID.map { bounded(Self.redact($0), to: Self.maxRequestIDCharacters) },
            metadata: normalizedMetadata(metadata),
            at: date
        )
        guard !event.kind.isEmpty else {
            throw V2AssistantArchiveError.invalidValue("kind")
        }
        let line = StoredLine(
            schemaVersion: Self.schemaVersion,
            type: .trace,
            messageID: nil,
            revision: nil,
            message: nil,
            eventID: UUID().uuidString,
            event: event
        )
        try appendLines([line], sessionID: sessionID)

        var index = try loadIndex()
        if let current = index.sessions.first(where: { $0.id == sessionID }) {
            let updated = ArchiveIndexEntry(
                id: current.id,
                title: current.title,
                updatedAt: max(current.updatedAt, date),
                messageCount: current.messageCount
            )
            index.sessions.removeAll { $0.id == sessionID }
            index.sessions.append(updated)
        } else {
            index.sessions.append(.init(id: sessionID, title: "新会话", updatedAt: date, messageCount: 0))
        }
        try persistIndex(index)
        if rootURL == nil {
            memoryIndex = Dictionary(uniqueKeysWithValues: index.sessions.map { ($0.id, $0) })
        }
    }

    public func trace(sessionID: String, limit: Int = 20) throws -> [V2ArchiveEvent] {
        lock.lock()
        defer { lock.unlock() }

        try validateSessionID(sessionID)
        let normalizedLimit = Self.normalizedLimit(limit)
        guard normalizedLimit > 0 else { return [] }
        let events = try loadLines(for: sessionID).compactMap(\.event)
        return Array(events.suffix(normalizedLimit))
    }
}

private extension V2AssistantArchive {
    enum StoredLineType: String, Codable {
        case message
        case trace
    }

    struct StoredLine: Codable {
        let schemaVersion: Int
        let type: StoredLineType
        let messageID: String?
        let revision: Date?
        let message: V2ArchiveMessage?
        let eventID: String?
        let event: V2ArchiveEvent?
    }

    struct ArchiveIndex: Codable {
        let schemaVersion: Int
        var sessions: [ArchiveIndexEntry]

        init(schemaVersion: Int = V2AssistantArchive.schemaVersion, sessions: [ArchiveIndexEntry] = []) {
            self.schemaVersion = schemaVersion
            self.sessions = sessions
        }
    }

    struct ArchiveIndexEntry: Codable {
        let id: String
        let title: String
        let updatedAt: Date
        let messageCount: Int
    }

    struct StoredCompaction: Codable {
        let schemaVersion: Int
        let revision: Int
        let summary: String
        let coveredMessageIDs: [String]
        let preservedReferenceIDs: [String]
        let createdAt: Date
        let messageFingerprints: [String]
        let metrics: V2AssistantCompactionMetrics

        init(_ value: V2AssistantCompaction, messageFingerprints: [String] = []) {
            schemaVersion = V2AssistantArchive.schemaVersion
            revision = value.revision
            summary = value.summary
            coveredMessageIDs = value.coveredMessageIDs
            preservedReferenceIDs = value.preservedReferenceIDs
            createdAt = value.createdAt
            self.messageFingerprints = messageFingerprints
            metrics = value.metrics
        }

        private enum CodingKeys: String, CodingKey {
            case schemaVersion
            case revision
            case summary
            case coveredMessageIDs
            case preservedReferenceIDs
            case createdAt
            case messageFingerprints
            case metrics
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
            revision = try container.decode(Int.self, forKey: .revision)
            summary = try container.decode(String.self, forKey: .summary)
            coveredMessageIDs = try container.decode([String].self, forKey: .coveredMessageIDs)
            preservedReferenceIDs = try container.decodeIfPresent([String].self, forKey: .preservedReferenceIDs) ?? []
            createdAt = try container.decode(Date.self, forKey: .createdAt)
            // Fingerprints were added after the first persisted format. An absent
            // field forces one deterministic recomputation on the next compact.
            messageFingerprints = try container.decodeIfPresent([String].self, forKey: .messageFingerprints) ?? []
            metrics = try container.decodeIfPresent(V2AssistantCompactionMetrics.self, forKey: .metrics) ?? .empty
        }

        var value: V2AssistantCompaction {
            V2AssistantCompaction(
                revision: revision,
                summary: summary,
                coveredMessageIDs: coveredMessageIDs,
                createdAt: createdAt,
                preservedReferenceIDs: preservedReferenceIDs,
                metrics: metrics
            )
        }
    }

    struct LatestMessage {
        let message: V2ArchiveMessage
        let revision: Date
        let lineIndex: Int
    }

    struct ProjectedMessage {
        let message: V2ArchiveMessage
        let revision: Date
    }

    struct LoadedCompaction {
        let value: V2AssistantCompaction
        let messageFingerprints: [String]
    }

    var indexURL: URL? {
        rootURL?.appendingPathComponent("session-index.json", isDirectory: false)
    }

    func sessionURL(_ id: String) -> URL? {
        rootURL?.appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("\(id).jsonl", isDirectory: false)
    }

    func compactionURL(_ id: String) -> URL? {
        rootURL?.appendingPathComponent("compact", isDirectory: true)
            .appendingPathComponent("\(id).json", isDirectory: false)
    }

    func jsonEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    func jsonDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }

    func validateSessionID(_ id: String) throws {
        guard !id.isEmpty,
              id.count <= Self.maxSessionIDCharacters,
              id != ".",
              id != "..",
              id.unicodeScalars.allSatisfy({ scalar in
                  let value = scalar.value
                  return (value >= 48 && value <= 57)
                      || (value >= 65 && value <= 90)
                      || (value >= 97 && value <= 122)
                      || value == 45
                      || value == 46
                      || value == 95
              }) else {
            throw V2AssistantArchiveError.invalidSessionID(id)
        }
    }

    func validateMessageID(_ id: String) throws {
        guard !id.isEmpty,
              id.count <= Self.maxMessageIDCharacters,
              !id.contains(where: { $0.isNewline || $0.isWhitespace }) else {
            throw V2AssistantArchiveError.invalidValue("messageID")
        }
    }

    func normalizedMessages(from session: V2AgentSession) throws -> [ProjectedMessage] {
        var byID: [String: ProjectedMessage] = [:]
        for message in session.messages {
            try validateMessageID(message.id)
            let projected = V2ArchiveMessage(
                id: message.id,
                role: message.role,
                text: bounded(Self.redact(publicText(for: message)), to: Self.maxTextCharacters),
                createdAt: message.createdAt
            )
            let candidate = ProjectedMessage(message: projected, revision: message.updatedAt)
            if let existing = byID[message.id], existing.revision > candidate.revision {
                continue
            }
            byID[message.id] = candidate
        }
        return byID.values.sorted { Self.messageSort($0.message, $1.message) }
    }

    func syncSession(_ session: V2AgentSession) throws -> ArchiveIndexEntry {
        let messages = try normalizedMessages(from: session)
        let lines = try loadLines(for: session.id)
        var latest = latestMessages(from: lines)
        var additions: [StoredLine] = []

        for projected in messages {
            let message = projected.message
            if let existing = latest.first(where: { $0.message.id == message.id }),
               existing.message == message,
               existing.revision >= projected.revision {
                continue
            }
            if let existing = latest.first(where: { $0.message.id == message.id }),
               existing.revision > projected.revision {
                continue
            }
            additions.append(StoredLine(
                schemaVersion: Self.schemaVersion,
                type: .message,
                messageID: message.id,
                revision: projected.revision,
                message: message,
                eventID: nil,
                event: nil
            ))
            latest.removeAll { $0.message.id == message.id }
            latest.append(LatestMessage(message: message, revision: projected.revision, lineIndex: .max))
        }

        let traceLines = try traceLines(from: session.traces, existing: lines)
        additions.append(contentsOf: traceLines)
        try appendLines(additions, sessionID: session.id)
        latest = latestMessages(from: latest.map { StoredLine(
            schemaVersion: Self.schemaVersion,
            type: .message,
            messageID: $0.message.id,
            revision: $0.revision,
            message: $0.message,
            eventID: nil,
            event: nil
        ) })

        let title = bounded(Self.redact(session.title.trimmingCharacters(in: .whitespacesAndNewlines)), to: Self.maxTitleCharacters)
        let resolvedTitle = title.isEmpty ? (latest.first(where: { $0.message.role == .user })?.message.text.prefix(28).description ?? "新会话") : title
        let messageUpdatedAt = latest.map { max($0.message.createdAt, $0.revision) }.max() ?? session.updatedAt
        return ArchiveIndexEntry(
            id: session.id,
            title: resolvedTitle,
            updatedAt: max(session.updatedAt, messageUpdatedAt),
            messageCount: latest.count
        )
    }

    func appendMissingMessages(_ messages: [ProjectedMessage], sessionID: String) throws {
        let existing = try loadLines(for: sessionID)
        let latest = latestMessages(from: existing)
        var additions: [StoredLine] = []
        for projected in messages {
            let message = projected.message
            guard let old = latest.first(where: { $0.message.id == message.id }) else {
                additions.append(StoredLine(
                    schemaVersion: Self.schemaVersion,
                    type: .message,
                    messageID: message.id,
                    revision: projected.revision,
                    message: message,
                    eventID: nil,
                    event: nil
                ))
                continue
            }
            if old.revision < projected.revision || old.message != message {
                additions.append(StoredLine(
                    schemaVersion: Self.schemaVersion,
                    type: .message,
                    messageID: message.id,
                    revision: projected.revision,
                    message: message,
                    eventID: nil,
                    event: nil
                ))
            }
        }
        try appendLines(additions, sessionID: sessionID)
    }

    func traceLines(from traces: [V2AgentTrace], existing: [StoredLine]) throws -> [StoredLine] {
        let existingIDs = Set(existing.compactMap { $0.eventID })
        return traces.compactMap { trace in
            let eventID = "agent-trace-\(trace.id)"
            guard !existingIDs.contains(eventID) else { return nil }
            var metadata: [String: String] = [
                "status": trace.status.rawValue,
                "toolCount": String(trace.steps.count)
            ]
            if let model = trace.model { metadata["model"] = model }
            if let provider = trace.providerLabel { metadata["provider"] = provider }
            return StoredLine(
                schemaVersion: Self.schemaVersion,
                type: .trace,
                messageID: nil,
                revision: nil,
                message: nil,
                eventID: eventID,
                event: V2ArchiveEvent(
                    kind: "agent.trace",
                    requestID: trace.requestID,
                    metadata: normalizedMetadata(metadata),
                    at: trace.endedAt ?? trace.startedAt
                )
            )
        }
    }

    func loadIndex() throws -> ArchiveIndex {
        if rootURL == nil {
            return ArchiveIndex(sessions: memoryIndex.values.sorted(by: Self.indexSort))
        }
        guard let indexURL else { return ArchiveIndex() }
        guard fileManager.fileExists(atPath: indexURL.path) else {
            let entries = try rebuildIndexFromLogs()
            return ArchiveIndex(sessions: entries.sorted(by: Self.indexSort))
        }
        let data = try Data(contentsOf: indexURL)
        do {
            let index = try jsonDecoder().decode(ArchiveIndex.self, from: data)
            guard index.schemaVersion == Self.schemaVersion else {
                throw V2AssistantArchiveError.unsupportedSchema(index.schemaVersion)
            }
            var seen = Set<String>()
            for entry in index.sessions {
                try validateSessionID(entry.id)
                guard entry.title.count <= Self.maxTitleCharacters,
                      (0...Self.maxArchiveLines).contains(entry.messageCount) else {
                    throw V2AssistantArchiveError.corruptFile(indexURL)
                }
                guard seen.insert(entry.id).inserted else {
                    throw V2AssistantArchiveError.corruptFile(indexURL)
                }
            }
            return ArchiveIndex(sessions: index.sessions.sorted(by: Self.indexSort))
        } catch let error as V2AssistantArchiveError {
            throw error
        } catch {
            throw V2AssistantArchiveError.corruptFile(indexURL)
        }
    }

    func rebuildIndexFromLogs() throws -> [ArchiveIndexEntry] {
        guard let rootURL else { return [] }
        let directory = rootURL.appendingPathComponent("sessions", isDirectory: true)
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        let urls = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        return try urls.compactMap { url in
            guard url.pathExtension == "jsonl" else { return nil }
            let id = url.deletingPathExtension().lastPathComponent
            try validateSessionID(id)
            let latest = latestMessages(from: try readLines(at: url))
            let title = latest.first(where: { $0.message.role == .user })?.message.text.prefix(28).description ?? "新会话"
            let updatedAt = latest.map { max($0.message.createdAt, $0.revision) }.max() ?? Date(timeIntervalSince1970: 0)
            return ArchiveIndexEntry(id: id, title: title, updatedAt: updatedAt, messageCount: latest.count)
        }
    }

    func storedSessionIDs() throws -> Set<String> {
        if rootURL == nil { return Set(memoryLines.keys) }
        guard let rootURL else { return [] }
        let directory = rootURL.appendingPathComponent("sessions", isDirectory: true)
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        var ids = Set<String>(try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).compactMap { (url: URL) -> String? in
            guard url.pathExtension == "jsonl" else { return nil }
            let id = url.deletingPathExtension().lastPathComponent
            guard (try? validateSessionID(id)) != nil else { return nil }
            return id
        })
        let compactDirectory = rootURL.appendingPathComponent("compact", isDirectory: true)
        if fileManager.fileExists(atPath: compactDirectory.path) {
            ids.formUnion(try fileManager.contentsOfDirectory(at: compactDirectory, includingPropertiesForKeys: nil).compactMap { (url: URL) -> String? in
                guard url.pathExtension == "json" else { return nil }
                let id = url.deletingPathExtension().lastPathComponent
                guard (try? validateSessionID(id)) != nil else { return nil }
                return id
            })
        }
        return ids
    }

    func loadLines(for id: String) throws -> [StoredLine] {
        try validateSessionID(id)
        if rootURL == nil { return memoryLines[id] ?? [] }
        guard let url = sessionURL(id) else { return [] }
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        return try readLines(at: url)
    }

    func readLines(at url: URL) throws -> [StoredLine] {
        let data = try Data(contentsOf: url)
        guard data.count <= Self.maxArchiveBytes else {
            throw V2AssistantArchiveError.corruptFile(url)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw V2AssistantArchiveError.corruptFile(url)
        }
        let rawLines = text.split(separator: "\n", omittingEmptySubsequences: true)
        guard rawLines.count <= Self.maxArchiveLines else {
            throw V2AssistantArchiveError.corruptFile(url)
        }
        var lines: [StoredLine] = []
        for rawLine in rawLines {
            do {
                let line = try jsonDecoder().decode(StoredLine.self, from: Data(rawLine.utf8))
                try validateStoredLine(line, url: url)
                lines.append(line)
            } catch let error as V2AssistantArchiveError {
                throw error
            } catch {
                // A malformed final line is deliberately not discarded. Callers can retry
                // after restoring the file and no prior valid bytes are rewritten.
                throw V2AssistantArchiveError.corruptFile(url)
            }
        }
        return lines
    }

    func validateStoredLine(_ line: StoredLine, url: URL) throws {
        guard line.schemaVersion == Self.schemaVersion else {
            throw V2AssistantArchiveError.unsupportedSchema(line.schemaVersion)
        }
        switch line.type {
        case .message:
            guard let messageID = line.messageID,
                  let revision = line.revision,
                  let message = line.message,
                  line.event == nil,
                  line.eventID == nil,
                  messageID == message.id else {
                throw V2AssistantArchiveError.corruptFile(url)
            }
            try validateMessageID(messageID)
            guard message.text.count <= Self.maxTextCharacters else {
                throw V2AssistantArchiveError.corruptFile(url)
            }
            _ = revision
        case .trace:
            guard line.messageID == nil,
                  line.revision == nil,
                  line.message == nil,
                  line.eventID != nil,
                  let event = line.event,
                  !event.kind.isEmpty,
                  event.kind.count <= Self.maxKindCharacters,
                  (event.requestID?.count ?? 0) <= Self.maxRequestIDCharacters,
                  event.metadata.count <= 64,
                  event.metadata.keys.allSatisfy({ $0.count <= Self.maxMetadataKeyCharacters }),
                  event.metadata.values.allSatisfy({ $0.count <= Self.maxMetadataValueCharacters }) else {
                throw V2AssistantArchiveError.corruptFile(url)
            }
        }
    }

    func latestMessages(from lines: [StoredLine]) -> [LatestMessage] {
        var latest: [String: LatestMessage] = [:]
        for (index, line) in lines.enumerated() where line.type == .message {
            guard let id = line.messageID, let revision = line.revision, let message = line.message else { continue }
            let candidate = LatestMessage(message: message, revision: revision, lineIndex: index)
            guard let old = latest[id] else {
                latest[id] = candidate
                continue
            }
            if revision > old.revision || (revision == old.revision && index > old.lineIndex) {
                latest[id] = candidate
            }
        }
        return latest.values.sorted {
            if $0.message.createdAt == $1.message.createdAt { return $0.lineIndex < $1.lineIndex }
            return $0.message.createdAt < $1.message.createdAt
        }
    }

    func appendLines(_ lines: [StoredLine], sessionID: String) throws {
        guard !lines.isEmpty else {
            if rootURL == nil, memoryLines[sessionID] == nil { memoryLines[sessionID] = [] }
            return
        }
        if rootURL == nil {
            memoryLines[sessionID, default: []].append(contentsOf: lines)
            return
        }
        guard let url = sessionURL(sessionID), let rootURL else { return }
        let directory = rootURL.appendingPathComponent("sessions", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        if !fileManager.fileExists(atPath: url.path) {
            fileManager.createFile(atPath: url.path, contents: nil)
        }
        let encoder = jsonEncoder()
        var data = Data()
        for line in lines {
            data.append(try encoder.encode(line))
            data.append(0x0A)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try handle.synchronize()
    }

    func persistIndex(_ index: ArchiveIndex) throws {
        let normalized = ArchiveIndex(sessions: index.sessions.sorted(by: Self.indexSort))
        if rootURL == nil {
            memoryIndex = Dictionary(uniqueKeysWithValues: normalized.sessions.map { ($0.id, $0) })
            return
        }
        guard let indexURL, let rootURL else { return }
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try jsonEncoder().encode(normalized).write(to: indexURL, options: .atomic)
    }

    func removeSessionFiles(_ id: String) throws {
        try validateSessionID(id)
        if rootURL == nil {
            memoryLines.removeValue(forKey: id)
            memoryCompactions.removeValue(forKey: id)
            memoryCompactionFingerprints.removeValue(forKey: id)
            memoryIndex.removeValue(forKey: id)
            return
        }
        if let url = sessionURL(id), fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        if let url = compactionURL(id), fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    func persistCompaction(
        _ compaction: V2AssistantCompaction,
        sessionID: String,
        messageFingerprints: [String] = []
    ) throws {
        if rootURL == nil {
            memoryCompactions[sessionID] = compaction
            memoryCompactionFingerprints[sessionID] = messageFingerprints
            return
        }
        guard let url = compactionURL(sessionID), let rootURL else { return }
        let directory = rootURL.appendingPathComponent("compact", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try jsonEncoder().encode(StoredCompaction(compaction, messageFingerprints: messageFingerprints)).write(to: url, options: .atomic)
    }

    func loadCompactionUnlocked(sessionID: String) throws -> V2AssistantCompaction? {
        try loadStoredCompactionUnlocked(sessionID: sessionID)?.value
    }

    func loadStoredCompactionUnlocked(sessionID: String) throws -> LoadedCompaction? {
        if rootURL == nil {
            guard let value = memoryCompactions[sessionID] else { return nil }
            return LoadedCompaction(
                value: value,
                messageFingerprints: memoryCompactionFingerprints[sessionID] ?? []
            )
        }
        guard let url = compactionURL(sessionID), fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        do {
            let stored = try jsonDecoder().decode(StoredCompaction.self, from: data)
            guard stored.schemaVersion == Self.schemaVersion else {
                throw V2AssistantArchiveError.unsupportedSchema(stored.schemaVersion)
            }
            guard stored.revision > 0,
                  stored.summary.count <= Self.maxTextCharacters,
                  stored.coveredMessageIDs.count <= Self.maxArchiveLines,
                  stored.preservedReferenceIDs.count <= 24,
                  stored.preservedReferenceIDs.allSatisfy({ $0.count <= Self.maxMessageIDCharacters }) else {
                throw V2AssistantArchiveError.corruptFile(url)
            }
            for id in stored.coveredMessageIDs {
                try validateMessageID(id)
            }
            guard stored.messageFingerprints.isEmpty || stored.messageFingerprints.count == stored.coveredMessageIDs.count else {
                throw V2AssistantArchiveError.corruptFile(url)
            }
            return LoadedCompaction(value: stored.value, messageFingerprints: stored.messageFingerprints)
        } catch let error as V2AssistantArchiveError {
            throw error
        } catch {
            throw V2AssistantArchiveError.corruptFile(url)
        }
    }

    func publicText(for message: V2AgentMessage) -> String {
        message.parts.compactMap { part -> String? in
            switch part {
            case let .text(text):
                return text
            case let .trace(trace):
                return trace.displayText
            case let .sources(sources):
                return sources.prefix(24).map { source in
                    let site = source.siteName.map { " (\($0))" } ?? ""
                    return "来源：\(source.title)\(site) \(source.url.absoluteString)"
                }.joined(separator: "\n")
            case let .plan(plan):
                let decisions = plan.decisions.prefix(12).joined(separator: "；")
                return [plan.title, plan.summary, decisions].filter { !$0.isEmpty }.joined(separator: "：")
            case let .schedule(card):
                // The baseline may contain a complete task database. Only the proposal is public.
                let operationTitles = card.proposal.operations.prefix(24).compactMap(\.title).joined(separator: "、")
                let operations = operationTitles.isEmpty ? "\(card.proposal.operations.count) 个操作" : operationTitles
                return "日程建议：\(card.proposal.summary)（\(operations)，状态：\(card.status.rawValue)）"
            case let .tool(result):
                let references = result.entityReferences.prefix(24).joined(separator: ", ")
                let suffix = references.isEmpty ? "" : "；引用：\(references)"
                return "工具 \(result.toolID)（\(result.state.rawValue)）：\(result.summary)\(suffix)"
            case let .error(error):
                return "错误：\(error.message)"
            }
        }.joined(separator: "\n")
    }

    func preservedReferenceIDs(for session: V2AgentSession) -> [String] {
        var ids: [String] = []
        if let source = session.sourceTask {
            ids.append(source.id)
            if let contextID = source.contextID { ids.append(contextID) }
            if let parentID = source.parentID { ids.append(parentID) }
        }
        ids += session.messages.reversed().flatMap { message in
            (message.references ?? []).map(\.id) + (message.attachments ?? []).map(\.assetID)
        }
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }.prefix(24).map { $0 }
    }

    func compactionExcerpt(_ text: String, limit: Int) -> String {
        guard text.count > limit, limit > 40 else { return String(text.prefix(max(0, limit))) }
        let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
        let markers = ["必须", "不要", "不能", "最多", "至少", "决定", "目标", "待办", "未完成", "明天", "截止", "未决", "问题", "?", "？", "question", "must", "never", "deadline"]
        let important = lines.filter { line in markers.contains { line.localizedCaseInsensitiveContains($0) } }
        let head = String(text.prefix(limit / 3))
        let tail = String(text.suffix(limit / 3))
        let constraints = important.joined(separator: " / ")
        let middle = constraints.isEmpty ? "" : String(constraints.prefix(max(0, limit - head.count - tail.count - 6)))
        return String((head + " … " + middle + " … " + tail).prefix(limit))
    }

    func makeCompactionSummary(for messages: [V2ArchiveMessage], characterLimit: Int) -> String {
        let limit = min(max(0, characterLimit), Self.maxTextCharacters)
        guard limit > 0, !messages.isEmpty else { return "" }

        let header = "旧消息摘要（详情可通过 readSession 获取）："
        let omittedDetails = "… 其余旧消息细节已省略，可通过 readSession 获取。"
        let minimumExcerptCharacters = 12
        let linePrefix: (V2ArchiveMessage) -> String = {
            "- [\($0.id)] \($0.role.rawValue)："
        }
        let minimumBodyLength: (ArraySlice<V2ArchiveMessage>) -> Int = { slice in
            slice.reduce(0) { total, message in
                total + linePrefix(message).count + min(minimumExcerptCharacters, message.text.count)
            } + max(0, slice.count - 1)
        }

        guard limit > header.count + 1 else {
            return String(header.prefix(limit))
        }

        // Keep all covered messages when their small excerpts fit. If they do
        // not, choose the largest suffix that fits so the latest decisions stay
        // visible while every omitted message remains source-linked below.
        let allMessages = Array(messages)
        let fullBodyLength = minimumBodyLength(allMessages[...])
        let headerLength = header.count + 1
        var selectedStart = 0
        var includeOmissionLabel = false
        if headerLength + fullBodyLength > limit {
            includeOmissionLabel = true
            let bodyLimit = limit - headerLength - omittedDetails.count - 1
            selectedStart = allMessages.count
            if bodyLimit > 0 {
                for candidateStart in 0..<allMessages.count {
                    if minimumBodyLength(allMessages[candidateStart...]) <= bodyLimit {
                        selectedStart = candidateStart
                        break
                    }
                }
            }
        }

        let selected = Array(allMessages.dropFirst(selectedStart))
        let bodyLimit = max(
            0,
            limit - headerLength - (includeOmissionLabel ? omittedDetails.count + 1 : 0)
        )
        var lines: [String] = []
        var remaining = bodyLimit
        for (index, message) in selected.enumerated() {
            let prefix = linePrefix(message)
            let remainingMessages = selected.count - index
            let separatorReserve = max(0, remainingMessages - 1)
            let fairShare = max(0, (remaining - separatorReserve) / max(1, remainingMessages))
            let textLimit = min(
                message.text.count,
                max(0, min(fairShare - prefix.count, remaining - separatorReserve - prefix.count))
            )
            let line = prefix + compactionExcerpt(message.text, limit: textLimit)
            lines.append(line)
            remaining -= line.count
            if index < selected.count - 1 {
                remaining -= 1
            }
        }

        var result = header
        if !lines.isEmpty {
            result += "\n" + lines.joined(separator: "\n")
        }
        if includeOmissionLabel {
            result += "\n" + omittedDetails
        }
        return String(result.prefix(limit))
    }

    func fingerprint(for message: V2ArchiveMessage, revision: Date) -> String {
        // A small deterministic content fingerprint is persisted beside the
        // compaction. It detects same-ID edits even when a caller forgets to
        // advance the source message's update date.
        let value = "\(message.id)|\(message.role.rawValue)|\(message.createdAt.timeIntervalSince1970)|\(revision.timeIntervalSince1970)|\(message.text)"
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    func normalizedMemoryRecord(_ record: V2UserMemoryRecord) throws -> V2UserMemoryRecord {
        guard !record.id.isEmpty, record.id.count <= Self.maxMessageIDCharacters else {
            throw V2AssistantArchiveError.invalidValue("memoryID")
        }
        let statement = bounded(Self.redact(record.statement.trimmingCharacters(in: .whitespacesAndNewlines)), to: Self.maxMemoryStatementCharacters)
        guard !statement.isEmpty else { throw V2AssistantArchiveError.invalidValue("memory statement") }
        return V2UserMemoryRecord(
            id: record.id,
            kind: record.kind,
            scope: record.scope,
            scopeID: record.scopeID.map { bounded(Self.redact($0), to: Self.maxMessageIDCharacters) },
            statement: statement,
            origin: record.origin,
            evidenceIDs: Array(record.evidenceIDs.prefix(48)).map { bounded(Self.redact($0), to: Self.maxMessageIDCharacters) },
            supersedesID: record.supersedesID.map { bounded(Self.redact($0), to: Self.maxMessageIDCharacters) },
            createdAt: record.createdAt,
            updatedAt: record.updatedAt,
            expiresAt: record.expiresAt,
            availability: record.availability
        )
    }

    func memoryMarkdown(for records: [V2UserMemoryRecord]) -> String {
        var output = "# Tough Trial Memory\n\nGenerated from typed user memory records.\n"
        let grouped = Dictionary(grouping: records, by: { $0.kind.rawValue })
        for kind in V2UserMemoryRecord.Kind.allCases.map(\.rawValue) where grouped[kind] != nil {
            output += "\n## \(kind)\n"
            for record in grouped[kind, default: []] {
                output += "- `\(record.id)` \(record.statement.replacingOccurrences(of: "\n", with: " "))\n"
                output += "  - scope: \(record.scope.rawValue)\n"
                output += "  - origin: \(record.origin.rawValue)\n"
                if !record.evidenceIDs.isEmpty {
                    output += "  - evidence: \(record.evidenceIDs.joined(separator: ", "))\n"
                }
            }
        }
        return output
    }

    func memorySummaryMarkdown(for records: [V2UserMemoryRecord]) -> String {
        var output = "# Memory summary\n\nGenerated from \(records.count) typed user memory record(s).\n"
        let counts = Dictionary(grouping: records, by: { $0.kind.rawValue }).mapValues(\.count)
        for kind in V2UserMemoryRecord.Kind.allCases.map(\.rawValue) where counts[kind] != nil {
            output += "- \(kind): \(counts[kind]!)\n"
        }
        return output
    }

    func normalizedMetadata(_ metadata: [String: String]) -> [String: String] {
        metadata.keys.sorted().reduce(into: [String: String]()) { result, key in
            let normalizedKey = bounded(Self.redact(key), to: Self.maxMetadataKeyCharacters)
            let isSensitiveKey = ["token", "api_key", "apikey", "password", "secret", "authorization"].contains {
                normalizedKey.lowercased().replacingOccurrences(of: "-", with: "_") == $0
            }
            let normalizedValue = isSensitiveKey
                ? "[REDACTED]"
                : bounded(Self.redact(metadata[key] ?? ""), to: Self.maxMetadataValueCharacters)
            guard !normalizedKey.isEmpty, !normalizedValue.isEmpty else { return }
            result[normalizedKey] = normalizedValue
        }
    }

    static func normalizedLimit(_ value: Int) -> Int {
        min(max(0, value), maxLimit)
    }

    static func normalizedQuery(_ value: String) -> String {
        bounded(value.trimmingCharacters(in: .whitespacesAndNewlines), to: maxQueryCharacters)
    }

    static func bounded(_ value: String, to limit: Int) -> String {
        String(value.prefix(max(0, limit)))
    }

    func bounded(_ value: String, to limit: Int) -> String {
        Self.bounded(value, to: limit)
    }

    static func redact(_ value: String) -> String {
        var result = value
        let replacements: [(String, String)] = [
            (#"(?i)\b(sk-[A-Za-z0-9_-]{8,}|ghp_[A-Za-z0-9]{8,}|xox[baprs]-[A-Za-z0-9-]{8,})\b"#, "[REDACTED]"),
            (#"(?i)\bBearer\s+[A-Za-z0-9._~+/=-]{8,}"#, "Bearer [REDACTED]"),
            (#"(?i)\b(api[_-]?key|token|password|secret|authorization)\s*[:=]\s*[^\s,;；]+"#, "$1=[REDACTED]")
        ]
        for (pattern, replacement) in replacements {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: replacement)
        }
        return result
    }

    static func messageSort(_ lhs: V2ArchiveMessage, _ rhs: V2ArchiveMessage) -> Bool {
        if lhs.createdAt == rhs.createdAt { return lhs.id < rhs.id }
        return lhs.createdAt < rhs.createdAt
    }

    static func summarySort(_ lhs: V2ArchiveSessionSummary, _ rhs: V2ArchiveSessionSummary) -> Bool {
        if lhs.updatedAt == rhs.updatedAt { return lhs.id < rhs.id }
        return lhs.updatedAt > rhs.updatedAt
    }

    static func indexSort(_ lhs: ArchiveIndexEntry, _ rhs: ArchiveIndexEntry) -> Bool {
        if lhs.updatedAt == rhs.updatedAt { return lhs.id < rhs.id }
        return lhs.updatedAt > rhs.updatedAt
    }

    static func memorySort(_ lhs: V2UserMemoryRecord, _ rhs: V2UserMemoryRecord) -> Bool {
        if lhs.updatedAt == rhs.updatedAt { return lhs.id < rhs.id }
        return lhs.updatedAt < rhs.updatedAt
    }
}

import Foundation

/// Deliberately has no free-text payload: user content and provider errors stay out of usage logs.
public struct V2UsageEvent: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case inputSubmitted, speechStarted, speechFinished, speechCancelled, speechFailed
        case transcriptEdited, assistantFinished, assistantFailed, assistantCancelled
        case scheduleProposed, scheduleApplied, scheduleConfirmed, scheduleUndone
        case manualEdit, syncFinished, syncFailed, conflictResolved
        case captureStage, categoryMerged, categoryUndone
        case importRecognized, importRecognitionFailed
        case financeChanged, financeFailed
        case moduleChanged, jobFinished, jobDeferred, commandApplied, commandBlocked, commandProposed, commandUndone, migrationFinished, contextPrepared
    }
    public enum Source: String, Codable, Sendable { case keyboard, apple, funASR, assistant, manual, sync }
    public let id: String
    public let kind: Kind
    public let source: Source?
    public let sessionID: String?
    public let operationID: String?
    public let moduleID: String?
    public let commandID: String?
    public let traceID: String?
    public let duration: TimeInterval?
    public let characterCount: Int?
    public let capture: V2CaptureTraceContext?
    public let at: Date
    public let context: V2AssistantContextManifest?

    public init(
        kind: Kind, source: Source? = nil, sessionID: String? = nil,
        operationID: String? = nil, duration: TimeInterval? = nil,
        characterCount: Int? = nil, at: Date = Date(), capture: V2CaptureTraceContext? = nil,
        moduleID: String? = nil, commandID: String? = nil, traceID: String? = nil,
        context: V2AssistantContextManifest? = nil
    ) {
        self.moduleID = moduleID
        self.context = context
        self.commandID = commandID
        self.traceID = traceID
        self.capture = capture
        self.id = UUID().uuidString
        self.kind = kind
        self.source = source
        self.sessionID = sessionID
        self.operationID = operationID
        self.duration = duration.flatMap { $0.isFinite ? max(0, $0) : nil }
        self.characterCount = characterCount.map { max(0, $0) }
        self.at = at
    }
}

@MainActor
public final class V2UsageTraceStore {
    public private(set) var events: [V2UsageEvent] = []
    public private(set) var hasStorageError = false
    public var isEnabled: Bool
    private let fileURL: URL
    private let limit: Int
    private let retention: TimeInterval = 30 * 86400

    public init(fileURL: URL, isEnabled: Bool = true, limit: Int = 2000, now: Date = Date()) {
        self.fileURL = fileURL
        self.isEnabled = isEnabled
        self.limit = max(1, limit)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            events = try JSONDecoder().decode([V2UsageEvent].self, from: data)
            let retained = filtered(events, now: now)
            if retained != events { try save(retained) }
            events = retained
        } catch { hasStorageError = true }
    }

    public func record(_ event: V2UsageEvent, now: Date = Date()) throws {
        guard isEnabled else { return }
        guard !hasStorageError else { throw TraceError.storageUnavailable }
        let next = filtered(events + [event], now: now)
        try save(next)
        events = next
    }

    public func exportJSON(now: Date = Date()) throws -> String {
        guard !hasStorageError else { throw TraceError.storageUnavailable }
        return String(decoding: try encode(filtered(events, now: now)), as: UTF8.self)
    }

    public func clear() throws {
        try save([])
        events = []
        hasStorageError = false
    }

    private func filtered(_ values: [V2UsageEvent], now: Date) -> [V2UsageEvent] {
        Array(values.filter { $0.at >= now.addingTimeInterval(-retention) }.suffix(limit))
    }

    private func encode(_ values: [V2UsageEvent]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(values)
    }

    private func save(_ values: [V2UsageEvent]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encode(values).write(to: fileURL, options: .atomic)
    }

    private enum TraceError: Error { case storageUnavailable }
}

/// Deliberately bounded metadata, never source content or provider response bodies.
public struct V2CaptureTraceContext: Codable, Equatable, Sendable {
    public enum Stage: String, Codable, Sendable {
        case sourceSaved, extractionStarted, extractionFinished, validationFailed, proposalSaved
        case itemCommitted, itemPresented, categoryConfirmed, categoryMerged, undone, failed, cancelled
    }
    public var traceID: String
    public var spanID: String
    public var parentSpanID: String?
    public var captureID: String
    public var sourceRevision: Int
    public var batchID: String?
    public var candidateID: String?
    public var receiptID: String?
    public var model: String?
    public var schemaVersion: Int = 1
    public var promptVersion: Int = 1
    public var taxonomyRevision: Int
    public var stage: Stage
    public var errorCode: V2CaptureError?
    public init(traceID: String, captureID: String, sourceRevision: Int, batchID: String? = nil,
                candidateID: String? = nil, receiptID: String? = nil, model: String? = nil,
                taxonomyRevision: Int, stage: Stage, errorCode: V2CaptureError? = nil) {
        self.traceID = traceID; self.spanID = stage == .sourceSaved && sourceRevision == 1 ? traceID : UUID().uuidString
        self.parentSpanID = stage == .sourceSaved && sourceRevision == 1 ? nil : traceID
        self.captureID = captureID; self.sourceRevision = sourceRevision; self.batchID = batchID
        self.candidateID = candidateID; self.receiptID = receiptID; self.model = model
        self.taxonomyRevision = taxonomyRevision; self.stage = stage; self.errorCode = errorCode
    }
}

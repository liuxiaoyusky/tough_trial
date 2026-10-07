import Foundation

public struct V2TranscriptionSegment: Codable, Equatable, Sendable {
    public var start: Double
    public var end: Double
    public var text: String

    public init(start: Double, end: Double, text: String) {
        self.start = start; self.end = end; self.text = text
    }
}

public struct V2TranscriptionRecord: Identifiable, Codable, Equatable, Sendable {
    public enum Source: String, Codable, Sendable { case audio, video }
    public enum Provider: String, Codable, Sendable { case apple, funASR }
    public enum Status: String, Codable, Sendable { case draft, processing, failed, complete }

    public var id: UUID
    public var title: String
    public var createdAt: Date
    public var source: Source
    public var provider: Provider?
    public var status: Status
    public var mediaFileName: String
    public var duration: Double?
    public var segments: [V2TranscriptionSegment]
    public var transcript: String
    public var summary: String?
    public var errorMessage: String?

    public init(id: UUID = UUID(), title: String, createdAt: Date = .now, source: Source,
                mediaFileName: String, provider: Provider? = nil, status: Status = .draft,
                duration: Double? = nil, segments: [V2TranscriptionSegment] = [],
                transcript: String = "", summary: String? = nil, errorMessage: String? = nil) {
        self.id = id; self.title = title; self.createdAt = createdAt; self.source = source
        self.mediaFileName = mediaFileName; self.provider = provider; self.status = status
        self.duration = duration; self.segments = segments; self.transcript = transcript
        self.summary = summary; self.errorMessage = errorMessage
    }

    public func matches(_ query: String) -> Bool {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty || [title, summary ?? "", transcript].contains {
            $0.localizedStandardContains(value)
        }
    }

    public var preview: String {
        let value = summary?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value, !value.isEmpty { return value }
        return transcript
    }
}

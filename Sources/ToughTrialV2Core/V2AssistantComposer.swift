import Foundation

/// A selected excerpt remains reference data, never new write authorization.
public struct V2AssistantMessageReference: Codable, Equatable, Sendable, Identifiable {
    public var sessionID: String
    public var messageID: String
    public var excerpt: String
    public var id: String { "\(sessionID)/\(messageID)" }
    public init(sessionID: String, messageID: String, excerpt: String) {
        self.sessionID = sessionID; self.messageID = messageID
        self.excerpt = String(excerpt.prefix(4_000))
    }
}

public struct V2AssistantDraft: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var text: String
    public var references: [V2AssistantMessageReference]
    public var attachments: [V2AssistantAttachment]?
    public init(id: String = UUID().uuidString, text: String = "", references: [V2AssistantMessageReference] = [], attachments: [V2AssistantAttachment]? = nil) {
        self.id = id; self.text = text; self.references = Array(references.prefix(4)); self.attachments = attachments
    }
}

public struct V2AssistantAttachment: Codable, Equatable, Sendable, Identifiable {
    public var assetID: String
    public var fileName: String
    public var extractedText: String?
    public var id: String { assetID }
    public init(assetID: String, fileName: String, extractedText: String? = nil) {
        self.assetID = assetID; self.fileName = String(fileName.prefix(255))
        self.extractedText = extractedText.map { String($0.prefix(8_000)) }
    }
}

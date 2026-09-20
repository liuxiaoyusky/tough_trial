import Foundation

/// The shared projection used both by actual requests and Compact measurements.
public enum V2AssistantHistory {
    public static func conversation(_ messages: [V2AgentMessage], coveredIDs: [String] = []) -> [V2AgentConversationMessage] {
        let covered = Set(coveredIDs)
        let history = messages.suffix(40).compactMap { message -> V2AgentConversationMessage? in
            guard message.status == .complete, !covered.contains(message.id) else { return nil }
            let text = message.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return .init(role: message.role == .user ? .user : .assistant, text: String(text.prefix(4_000)))
        }
        var remaining = 16_000
        var selected: [V2AgentConversationMessage] = []
        for message in history.reversed() where remaining > 0 {
            let text = String(message.text.prefix(remaining))
            selected.append(.init(role: message.role, text: text)); remaining -= text.count
        }
        return selected.reversed()
    }
}

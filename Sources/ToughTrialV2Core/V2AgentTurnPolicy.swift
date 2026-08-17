public enum V2AgentAutomaticTool: String, CaseIterable, Equatable, Sendable {
    case webSearch
    case webRead
    case localSearch
    case planDraft
}

public struct V2AgentTurnPolicy: Equatable, Sendable {
    public let maximumToolCalls: Int
    public private(set) var toolCallCount: Int

    public init(maximumToolCalls: Int = 3) {
        self.maximumToolCalls = max(0, maximumToolCalls)
        self.toolCallCount = 0
    }

    public static func tool(for action: V2AgentAction) -> V2AgentAutomaticTool? {
        switch action {
        case .answer:
            nil
        case .webSearch:
            .webSearch
        case .webRead:
            .webRead
        case .localSearch:
            .localSearch
        case .plan:
            .planDraft
        }
    }

    @discardableResult
    public mutating func registerToolCall(_ action: V2AgentAction) -> Bool {
        guard Self.tool(for: action) != nil else { return true }
        guard toolCallCount < maximumToolCalls else { return false }
        toolCallCount += 1
        return true
    }
}

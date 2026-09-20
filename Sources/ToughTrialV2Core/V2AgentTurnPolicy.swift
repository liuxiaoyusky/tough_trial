import Foundation

public enum V2AgentAutomaticTool: String, CaseIterable, Equatable, Sendable {
    case webSearch
    case webRead
    case localSearch
    case planDraft
    case schedule
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
        case .schedule:
            .schedule
        case .plan:
            .planDraft
        case .toolCall:
            nil
        }
    }

    /// Routing only: the schedule client still validates intent and every operation.
    public static func canDirectlyParseCreation(_ text: String) -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count <= 180,
              !["?", "？", "吗", "么", "是否", "如果", "假如", "不要", "别", "不想", "先不", "暂不", "讨论", "举例", "例如"].contains(where: text.contains)
        else { return false }
        return text.range(of: #"^(?:请)?(?:帮我)?(?:新增|创建|添加)(?:一个|一条|个)?(?:任务|待办)[：:，,\s]+\S"#,
                          options: .regularExpression) != nil
    }

    @discardableResult
    public mutating func registerToolCall(_ action: V2AgentAction) -> Bool {
        if case .toolCall = action {
            guard toolCallCount < maximumToolCalls else { return false }
            toolCallCount += 1
            return true
        }
        guard Self.tool(for: action) != nil else { return true }
        guard toolCallCount < maximumToolCalls else { return false }
        toolCallCount += 1
        return true
    }
}

import Foundation

/// The thinking choices exposed by the host. The host never presents a
/// choice unless the selected provider/model capability includes it.
public enum V2AIThinking: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case automatic = "auto"
    case disabled
    case low
    case medium
    case high
    case max

    public var title: String {
        switch self {
        case .automatic:
            "自动"
        case .disabled:
            "关闭"
        case .low:
            "低"
        case .medium:
            "中"
        case .high:
            "高"
        case .max:
            "最大"
        }
    }
}

public enum V2AIThinkingCapabilityKind: String, Codable, Equatable, Sendable {
    case glm
    case kimiK3
    case kimiK2
    case kimiK27Code
    case miniMax
    case unknown
}

public struct V2AIThinkingCapability: Codable, Equatable, Sendable {
    public let kind: V2AIThinkingCapabilityKind
    public let options: [V2AIThinking]
    public let note: String

    public init(
        kind: V2AIThinkingCapabilityKind,
        options: [V2AIThinking],
        note: String
    ) {
        self.kind = kind
        self.options = options
        self.note = note
    }

    public func supports(_ selection: V2AIThinking) -> Bool {
        options.contains(selection)
    }
}

/// A session-level model choice that can be stored independently of the
/// persistent provider profile. The App layer may use this as an optional
/// override; an absent override means the persisted default applies.
public struct V2AIProviderSelection: Codable, Equatable, Sendable {
    public var providerID: String
    public var model: String
    public var thinking: V2AIThinking

    public init(providerID: String, model: String, thinking: V2AIThinking) {
        self.providerID = providerID
        self.model = model
        self.thinking = thinking
    }

    /// Applies a session override to a configuration snapshot while keeping
    /// the provider endpoint, credentials, and cache policy from that profile.
    public func applying(
        to configuration: V2OpenAICompatibleAgentConfiguration
    ) -> V2OpenAICompatibleAgentConfiguration {
        var result = configuration
        result.model = model
        result.thinking = thinking
        return result
    }

    public func applying(
        to configuration: V2OpenAICompatiblePlanningConfiguration
    ) -> V2OpenAICompatiblePlanningConfiguration {
        var result = configuration
        result.model = model
        result.thinking = thinking
        return result
    }
}

public enum V2AIThinkingError: Error, Equatable, LocalizedError, Sendable {
    case unsupported(selection: V2AIThinking, model: String)

    public var errorDescription: String? {
        switch self {
        case let .unsupported(selection, model):
            "模型 \(model) 不支持思考设置“\(selection.title)”"
        }
    }
}

public extension V2AIThinking {
    /// Returns only options verified for the provider endpoint and model.
    static func capability(for endpoint: URL, model: String) -> V2AIThinkingCapability {
        let normalizedModel = normalizedModel(model)
        let host = endpoint.host?.lowercased() ?? ""
        let path = endpoint.path.lowercased()

        if isGLMHost(host),
           path.contains("/api/paas/v4") || path.contains("/api/coding/paas/v4") {
            switch normalizedModel {
            case "glm-5.3", "glm-5.3-flash":
                // These models force thinking on. The effort values are the
                // only supported controls documented for this generation.
                return V2AIThinkingCapability(
                    kind: .glm,
                    options: [.automatic, .low, .high, .max],
                    note: "GLM-5.3 强制思考，支持 low / high / max。"
                )
            case "glm-5.2":
                // GLM-5.2 documents low and medium as aliases of high. Do
                // not present aliases as separate user choices.
                return V2AIThinkingCapability(
                    kind: .glm,
                    options: [.automatic, .disabled, .high, .max],
                    note: "GLM-5.2 支持 thinking 开关和 high / max。"
                )
            case "glm-5.1", "glm-5-turbo", "glm-4.7":
                return V2AIThinkingCapability(
                    kind: .glm,
                    options: [.automatic, .disabled],
                    note: "该 GLM 模型只支持 thinking 开关。"
                )
            default:
                // A GLM host may serve models outside this allowlist. Host
                // identity alone is not evidence that a model accepts these
                // fields.
                return unknownCapability(note: "当前 GLM 模型未声明可用的思考参数。")
            }
        }

        if isKimiHost(host) {
            if isKimiPublicHost(host), isKimiK3(normalizedModel) {
                return V2AIThinkingCapability(
                    kind: .kimiK3,
                    options: [.automatic, .low, .high, .max],
                    note: "Kimi K3 始终思考，支持 low / high / max。"
                )
            }
            if isKimiPublicHost(host), normalizedModel == "kimi-k2.7-code" {
                return V2AIThinkingCapability(
                    kind: .kimiK27Code,
                    options: [.automatic],
                    note: "Kimi K2.7 Code 始终开启思考。"
                )
            }
            if isKimiPublicHost(host), normalizedModel == "kimi-k2.6" {
                return V2AIThinkingCapability(
                    kind: .kimiK2,
                    options: [.automatic, .disabled],
                    note: "Kimi K2.6 支持开启或关闭思考。"
                )
            }
            return V2AIThinkingCapability(
                kind: .unknown,
                options: [.automatic],
                note: "当前 Kimi 模型未声明可用的思考参数。"
            )
        }

        if isMiniMaxHost(host) {
            return V2AIThinkingCapability(
                kind: .miniMax,
                options: [.automatic],
                note: "MiniMax OpenAI 兼容接口由模型决定思考；可分离思考内容。"
            )
        }

        return V2AIThinkingCapability(
            kind: .unknown,
            options: [.automatic],
            note: "此服务未声明可用的思考参数。"
        )
    }

    /// Returns the safe default for a persisted profile or a newly pinned
    /// session selection. Forced-thinking GLM-5.3 models use low effort;
    /// known older GLM models keep the existing disabled default. Every
    /// unverified provider/model pair remains automatic.
    static func defaultSelection(endpoint: URL, model: String) -> V2AIThinking {
        let capability = capability(for: endpoint, model: model)
        let normalizedModel = normalizedModel(model)

        if capability.kind == .glm {
            if normalizedModel == "glm-5.3" || normalizedModel == "glm-5.3-flash" {
                return .low
            }
            if capability.supports(.disabled) {
                return .disabled
            }
        }
        return .automatic
    }

    /// Produces the exact provider fields for one pinned model selection.
    /// Unsupported choices fail before a request is sent.
    static func wireFields(
        for endpoint: URL,
        model: String,
        selection: V2AIThinking
    ) throws -> [String: Any] {
        let capability = capability(for: endpoint, model: model)
        guard capability.supports(selection) else {
            throw V2AIThinkingError.unsupported(selection: selection, model: model)
        }

        switch capability.kind {
        case .glm:
            switch selection {
            case .automatic:
                return ["thinking": ["type": "enabled"]]
            case .disabled:
                return ["thinking": ["type": "disabled"]]
            case .low, .medium, .high, .max:
                return [
                    "thinking": ["type": "enabled"],
                    "reasoning_effort": selection.rawValue
                ]
            }
        case .kimiK3:
            switch selection {
            case .automatic:
                return [:]
            case .low, .high, .max:
                return ["reasoning_effort": selection.rawValue]
            case .disabled, .medium:
                throw V2AIThinkingError.unsupported(selection: selection, model: model)
            }
        case .kimiK2:
            switch selection {
            case .automatic:
                return [:]
            case .disabled:
                return ["thinking": ["type": "disabled"]]
            case .low, .medium, .high, .max:
                throw V2AIThinkingError.unsupported(selection: selection, model: model)
            }
        case .kimiK27Code, .unknown:
            return [:]
        case .miniMax:
            // MiniMax documents reasoning_split as the OpenAI-compatible way
            // to separate reasoning_details from the final content.
            return ["reasoning_split": true]
        }
    }

    private static func normalizedModel(_ model: String) -> String {
        model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func isGLMHost(_ host: String) -> Bool {
        ["open.bigmodel.cn", "api.z.ai"].contains(host)
    }

    private static func isKimiHost(_ host: String) -> Bool {
        ["api.kimi.com", "api.moonshot.cn", "api.kimi.ai"].contains(host)
    }

    private static func isKimiPublicHost(_ host: String) -> Bool {
        ["api.moonshot.cn", "api.kimi.ai"].contains(host)
    }

    private static func isMiniMaxHost(_ host: String) -> Bool {
        ["api.minimax.cn", "api.minimaxi.com", "api.minimax.io"].contains(host)
    }

    private static func isKimiK3(_ model: String) -> Bool {
        model == "kimi-k3"
    }

    private static func unknownCapability(note: String) -> V2AIThinkingCapability {
        V2AIThinkingCapability(
            kind: .unknown,
            options: [.automatic],
            note: note
        )
    }
}

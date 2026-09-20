import Foundation

/// Applies provider-specific fields to an OpenAI-compatible request.
///
/// The no-selection `body` overload remains for older model clients. New
/// callers should use `makeBody` with the pinned per-turn selection so an
/// unsupported setting cannot disappear silently.
enum V2OpenAIRequestCompatibility {
    static func body(
        _ body: [String: Any],
        endpoint: URL,
        model: String
    ) -> [String: Any] {
        // Keep the historical low-latency default for legacy callers. New
        // clients pass their explicit per-turn selection through makeBody.
        let defaultSelection = V2AIThinking.defaultSelection(endpoint: endpoint, model: model)
        return (try? makeBody(
            body,
            endpoint: endpoint,
            model: model,
            thinking: defaultSelection
        )) ?? body
    }

    static func makeBody(
        _ body: [String: Any],
        endpoint: URL,
        model: String,
        thinking: V2AIThinking?
    ) throws -> [String: Any] {
        let selection = thinking ?? .automatic
        let fields = try V2AIThinking.wireFields(
            for: endpoint,
            model: model,
            selection: selection
        )
        var result = body
        let capability = V2AIThinking.capability(for: endpoint, model: model)
        if capability.kind != .unknown && selection != .disabled {
            // Reasoning and answer share the provider's completion budget.
            // A tiny legacy answer-only budget can consume everything before JSON is emitted.
            let budget = [V2AIThinking.high, .max, .medium].contains(selection) ? 32_768 : 8_192
            result["max_tokens"] = max(result["max_tokens"] as? Int ?? 0, budget)
        }
        for (key, value) in fields {
            result[key] = value
        }
        return result
    }
}

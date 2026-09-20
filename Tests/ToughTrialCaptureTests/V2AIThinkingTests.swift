import Foundation
import XCTest
@testable import ToughTrialV2Core

final class V2AIThinkingTests: XCTestCase {
    func testGLM53FlashForcesThinkingAndExposesVerifiedEffortValues() throws {
        let endpoint = URL(string: "https://open.bigmodel.cn/api/coding/paas/v4/chat/completions")!
        let capability = V2AIThinking.capability(for: endpoint, model: "glm-5.3-flash")

        XCTAssertEqual(capability.options, [.automatic, .low, .high, .max])
        XCTAssertEqual(
            try V2AIThinking.wireFields(for: endpoint, model: "glm-5.3-flash", selection: .automatic)["thinking"] as? [String: String],
            ["type": "enabled"]
        )
        XCTAssertEqual(
            try V2AIThinking.wireFields(for: endpoint, model: "glm-5.3-flash", selection: .low)["reasoning_effort"] as? String,
            "low"
        )
        XCTAssertThrowsError(
            try V2AIThinking.wireFields(for: endpoint, model: "glm-5.3-flash", selection: .disabled)
        )
    }

    func testGLM52ExposesOnlySupportedReasoningEffortValues() throws {
        let endpoint = URL(string: "https://api.z.ai/api/coding/paas/v4/chat/completions")!
        let capability = V2AIThinking.capability(for: endpoint, model: "glm-5.2")

        XCTAssertEqual(capability.options, [.automatic, .disabled, .high, .max])
        XCTAssertFalse(capability.supports(.low))
        XCTAssertFalse(capability.supports(.medium))

        let fields = try V2AIThinking.wireFields(for: endpoint, model: "glm-5.2", selection: .high)

        XCTAssertEqual(fields["thinking"] as? [String: String], ["type": "enabled"])
        XCTAssertEqual(fields["reasoning_effort"] as? String, "high")
    }

    func testKnownOlderGLMModelsOnlyExposeThinkingSwitch() throws {
        let endpoint = URL(string: "https://open.bigmodel.cn/api/paas/v4/chat/completions")!
        let capability = V2AIThinking.capability(for: endpoint, model: "glm-5.1")

        XCTAssertEqual(capability.options, [.automatic, .disabled])
        XCTAssertEqual(
            try V2AIThinking.wireFields(for: endpoint, model: "glm-5.1", selection: .disabled)["thinking"] as? [String: String],
            ["type": "disabled"]
        )
        XCTAssertThrowsError(
            try V2AIThinking.wireFields(for: endpoint, model: "glm-5.1", selection: .high)
        )
    }

    func testUnknownGLMModelDoesNotInheritHostCapability() throws {
        let endpoint = URL(string: "https://open.bigmodel.cn/api/coding/paas/v4/chat/completions")!
        let capability = V2AIThinking.capability(for: endpoint, model: "glm-5.3-preview")

        XCTAssertEqual(capability.kind, .unknown)
        XCTAssertEqual(capability.options, [.automatic])
        XCTAssertTrue(
            try V2AIThinking.wireFields(for: endpoint, model: "glm-5.3-preview", selection: .automatic).isEmpty
        )
        XCTAssertThrowsError(
            try V2AIThinking.wireFields(for: endpoint, model: "glm-5.3-preview", selection: .high)
        )
    }

    func testDefaultSelectionIsModelAndCapabilityAware() {
        let glmEndpoint = URL(string: "https://open.bigmodel.cn/api/coding/paas/v4/chat/completions")!
        let otherGLMEndpoint = URL(string: "https://open.bigmodel.cn/api/paas/v4/chat/completions")!
        let kimiEndpoint = URL(string: "https://api.moonshot.cn/v1/chat/completions")!

        XCTAssertEqual(
            V2AIThinking.defaultSelection(endpoint: glmEndpoint, model: "glm-5.3-flash"),
            .low
        )
        XCTAssertEqual(
            V2AIThinking.defaultSelection(endpoint: glmEndpoint, model: "glm-5.3"),
            .low
        )
        XCTAssertEqual(
            V2AIThinking.defaultSelection(endpoint: otherGLMEndpoint, model: "glm-5.2"),
            .disabled
        )
        XCTAssertEqual(
            V2AIThinking.defaultSelection(endpoint: kimiEndpoint, model: "kimi-k3"),
            .automatic
        )
        XCTAssertEqual(
            V2AIThinking.defaultSelection(endpoint: glmEndpoint, model: "glm-5.3-preview"),
            .automatic
        )
    }

    func testKimiK3UsesOnlyVerifiedModelNameAndReasoningEffortValues() throws {
        let endpoint = URL(string: "https://api.moonshot.cn/v1/chat/completions")!
        let capability = V2AIThinking.capability(for: endpoint, model: "kimi-k3")

        XCTAssertEqual(capability.options, [.automatic, .low, .high, .max])
        XCTAssertEqual(
            try V2AIThinking.wireFields(for: endpoint, model: "kimi-k3", selection: .low)["reasoning_effort"] as? String,
            "low"
        )
        XCTAssertThrowsError(
            try V2AIThinking.wireFields(for: endpoint, model: "kimi-k3", selection: .disabled)
        )

        let alternateEndpoint = URL(string: "https://api.kimi.ai/v1/chat/completions")!
        XCTAssertEqual(
            V2AIThinking.capability(for: alternateEndpoint, model: "kimi-k3").kind,
            .kimiK3
        )
        XCTAssertEqual(
            V2AIThinking.capability(for: alternateEndpoint, model: "k3").options,
            [.automatic]
        )
    }

    func testUnverifiedKimiCodingAliasRemainsAutomaticOnly() throws {
        let endpoint = URL(string: "https://api.kimi.com/coding/v1/chat/completions")!
        let capability = V2AIThinking.capability(for: endpoint, model: "k3-256k")

        XCTAssertEqual(capability.kind, .unknown)
        XCTAssertEqual(capability.options, [.automatic])
        XCTAssertTrue(
            try V2AIThinking.wireFields(for: endpoint, model: "k3-256k", selection: .automatic).isEmpty
        )
        XCTAssertThrowsError(
            try V2AIThinking.wireFields(for: endpoint, model: "k3-256k", selection: .high)
        )
    }

    func testKimiK2AndCodeModelsExposeDifferentCapabilities() throws {
        let endpoint = URL(string: "https://api.moonshot.cn/v1/chat/completions")!
        let k2 = V2AIThinking.capability(for: endpoint, model: "kimi-k2.6")
        XCTAssertEqual(k2.options, [.automatic, .disabled])
        XCTAssertEqual(
            try V2AIThinking.wireFields(for: endpoint, model: "kimi-k2.6", selection: .disabled)["thinking"] as? [String: String],
            ["type": "disabled"]
        )

        let code = V2AIThinking.capability(for: endpoint, model: "kimi-k2.7-code")
        XCTAssertEqual(code.options, [.automatic])
        XCTAssertThrowsError(
            try V2AIThinking.wireFields(for: endpoint, model: "kimi-k2.7-code", selection: .disabled)
        )
    }

    func testMiniMaxSeparatesReasoningButDoesNotPretendToOfferEffort() throws {
        let endpoint = URL(string: "https://api.minimaxi.com/v1/chat/completions")!
        let capability = V2AIThinking.capability(for: endpoint, model: "MiniMax-M2.7-highspeed")

        XCTAssertEqual(capability.options, [.automatic])
        XCTAssertEqual(
            try V2AIThinking.wireFields(for: endpoint, model: "MiniMax-M2.7-highspeed", selection: .automatic)["reasoning_split"] as? Bool,
            true
        )
        XCTAssertThrowsError(
            try V2AIThinking.wireFields(for: endpoint, model: "MiniMax-M2.7-highspeed", selection: .high)
        )
    }

    func testUnknownOpenAICompatibleServiceOnlyUsesAutomaticWithoutExtraFields() throws {
        let endpoint = URL(string: "https://example.com/v1/chat/completions")!
        let capability = V2AIThinking.capability(for: endpoint, model: "custom-model")

        XCTAssertEqual(capability.options, [.automatic])
        XCTAssertTrue(try V2AIThinking.wireFields(for: endpoint, model: "custom-model", selection: .automatic).isEmpty)
    }

    func testAgentRequestUsesPinnedThinkingForTheWholeTurn() throws {
        let endpoint = URL(string: "https://open.bigmodel.cn/api/coding/paas/v4/chat/completions")!
        let configuration = V2OpenAICompatibleAgentConfiguration(
            endpoint: endpoint,
            apiKey: "fixture-key",
            model: "glm-5.2",
            thinking: .max
        )
        let client = V2OpenAICompatibleAgentClient(
            configuration: configuration,
            transport: V2URLSessionPlanningTransport()
        )
        let request = try client.makeURLRequest(
            for: V2AgentRequest(userText: "复杂问题", conversation: [], observations: [])
        )
        let body = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any]
        )

        XCTAssertEqual(body["model"] as? String, "glm-5.2")
        XCTAssertEqual(body["reasoning_effort"] as? String, "max")
        XCTAssertEqual(body["thinking"] as? [String: String], ["type": "enabled"])
    }

    func testSelectionRoundTripsForSessionOverride() throws {
        let selection = V2AIProviderSelection(providerID: "glm-coding", model: "glm-5.2", thinking: .high)
        let restored = try JSONDecoder().decode(
            V2AIProviderSelection.self,
            from: JSONEncoder().encode(selection)
        )

        XCTAssertEqual(restored, selection)
    }

    func testSessionSelectionAppliesOnlyModelAndThinkingToPinnedProfiles() {
        let selection = V2AIProviderSelection(providerID: "glm-coding", model: "glm-5.2", thinking: .high)
        let configuration = V2OpenAICompatibleAgentConfiguration(
            endpoint: URL(string: "https://open.bigmodel.cn/api/coding/paas/v4/chat/completions")!,
            apiKey: "fixture-key",
            model: "glm-5.3-flash",
            providerLabel: "GLM",
            usesPromptCacheKey: false,
            thinking: .disabled
        )

        let overridden = selection.applying(to: configuration)
        XCTAssertEqual(overridden.endpoint, configuration.endpoint)
        XCTAssertEqual(overridden.apiKey, configuration.apiKey)
        XCTAssertEqual(overridden.providerLabel, configuration.providerLabel)
        XCTAssertEqual(overridden.model, "glm-5.2")
        XCTAssertEqual(overridden.thinking, .high)
    }
}

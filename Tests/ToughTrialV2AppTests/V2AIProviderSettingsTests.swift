import XCTest
import ToughTrialV2Core
@testable import ToughTrial

final class V2AIProviderSettingsTests: XCTestCase {
    func testExistingAndLegacyProfilesKeepTheirProviderAndModel() throws {
        let suite = "model-tests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("silicon-flow", forKey: "ai.provider.active")
        defaults.set("https://api.siliconflow.cn/v1", forKey: "ai.provider.silicon-flow.base-url")
        defaults.set("saved-custom-model", forKey: "ai.provider.silicon-flow.model")
        XCTAssertEqual(V2AIProviderSettingsStore.load(defaults: defaults).model, "saved-custom-model")
        defaults.removePersistentDomain(forName: suite)
        defaults.set("https://api.siliconflow.cn/v1", forKey: "ai.openai-compatible.base-url")
        let legacy = V2AIProviderSettingsStore.load(defaults: defaults)
        XCTAssertEqual(legacy.provider, .siliconFlow)
        XCTAssertEqual(legacy.model, V2AIProviderPreset.siliconFlow.defaultModel)
    }
    func testFastDefaultAndMiniMaxPreset() throws {
        XCTAssertEqual(V2AIProviderSettings.defaults.provider, .glmCoding)
        XCTAssertEqual(V2AIProviderSettings.defaults.model, "glm-5.3-flash")
        var settings = V2AIProviderPreset.miniMax.defaultSettings()
        settings.apiKey = "fixture-key"
        XCTAssertEqual(settings.model, "MiniMax-M2.7-highspeed")
        XCTAssertEqual(try settings.agentConfiguration().endpoint.absoluteString, "https://api.minimax.io/v1/chat/completions")
        XCTAssertEqual(V2AIProviderPreset.inferred(from: settings.baseURL), .miniMax)
    }
    func testMiniMaxRejectsPastedConfigurationInsteadOfSendingIt() throws {
        var settings = V2AIProviderPreset.miniMax.defaultSettings()
        settings.apiKey = "Authorization: Bearer fixture-key"
        XCTAssertThrowsError(try settings.agentConfiguration())
        settings.apiKey = "fixture\nkey"
        XCTAssertThrowsError(try settings.agentConfiguration())
        settings.apiKey = "  fixture-key\n"
        XCTAssertEqual(try settings.agentConfiguration().apiKey, "fixture-key")
    }

    func testSavedMiniMaxRegionIsPreserved() throws {
        let suite = "minimax-region-tests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("minimax", forKey: "ai.provider.active")
        defaults.set(true, forKey: "ai.provider.minimax.enabled")
        for endpoint in ["https://api.minimax.cn/v1", "https://api.minimax.io/v1"] {
            defaults.set(endpoint, forKey: "ai.provider.minimax.base-url")
            let profile = V2AIProviderSettingsStore.loadProfile(for: .miniMax, defaults: defaults)
            XCTAssertEqual(profile.baseURL, endpoint, "Existing accounts must not be silently moved to another region")
        }
    }

    func testGLMCodingPresetAndEndpointResolution() throws {
        var settings = V2AIProviderPreset.glmCoding.defaultSettings()
        XCTAssertEqual(settings.model, "glm-5.3-flash")
        XCTAssertTrue(V2AIProviderPreset.glmCoding.models.contains("glm-5.3-flash"))
        settings.apiKey = "fixture-key"
        XCTAssertEqual(try settings.agentConfiguration().endpoint.absoluteString,
                       "https://open.bigmodel.cn/api/coding/paas/v4/chat/completions")
        settings.baseURL = "https://api.z.ai/api/coding/paas/v4"
        XCTAssertEqual(V2AIProviderPreset.inferred(from: settings.baseURL), .glmCoding)
        XCTAssertEqual(try settings.agentConfiguration().endpoint.absoluteString,
                       "https://api.z.ai/api/coding/paas/v4/chat/completions")
        XCTAssertEqual(V2AIProviderPreset.inferred(from: "https://open.bigmodel.cn/api/paas/v4"), .custom)
    }

    func testThinkingDefaultAndLegacyProfileLoadIndependently() throws {
        let suite = "thinking-tests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(V2AIProviderPreset.glmCoding.defaultSettings().thinking, .low)
        XCTAssertEqual(V2AIProviderPreset.kimiCoding.defaultSettings().thinking, .automatic)

        // Seed preference metadata only; a test must never change the user's Keychain profile.
        defaults.set("glm-coding", forKey: "ai.provider.active")
        defaults.set(true, forKey: "ai.provider.glm-coding.enabled")
        defaults.set(V2AIThinking.automatic.rawValue, forKey: "ai.provider.glm-coding.thinking")
        XCTAssertEqual(
            V2AIProviderSettingsStore.load(defaults: defaults).thinking,
            .automatic
        )

        defaults.removePersistentDomain(forName: suite)
        defaults.set("glm-coding", forKey: "ai.provider.active")
        defaults.set(true, forKey: "ai.provider.glm-coding.enabled")
        defaults.set("https://open.bigmodel.cn/api/coding/paas/v4", forKey: "ai.provider.glm-coding.base-url")
        defaults.set("glm-5.3-flash", forKey: "ai.provider.glm-coding.model")
        XCTAssertEqual(
            V2AIProviderSettingsStore.load(defaults: defaults).thinking,
            .low,
            "Profiles written before thinking existed use the valid fast default"
        )
    }
}

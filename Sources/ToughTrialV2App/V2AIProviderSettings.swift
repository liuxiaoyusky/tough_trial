import Foundation
import Security
import ToughTrialV2Core

enum V2AIProviderPreset: String, CaseIterable, Identifiable {
    case siliconFlow = "silicon-flow"
    case kimiCoding = "kimi-coding"
    case glmCoding = "glm-coding"
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .siliconFlow:
            "SiliconFlow"
        case .kimiCoding:
            "Kimi Coding Plan"
        case .glmCoding:
            "GLM Coding Plan"
        case .custom:
            "其他兼容服务"
        }
    }

    var baseURL: String {
        switch self {
        case .siliconFlow:
            "https://api.siliconflow.cn/v1"
        case .kimiCoding:
            "https://api.kimi.com/coding/v1"
        case .glmCoding:
            "https://open.bigmodel.cn/api/coding/paas/v4"
        case .custom:
            "https://api.openai.com/v1"
        }
    }

    var defaultModel: String {
        switch self {
        case .siliconFlow:
            "Qwen/Qwen3.5-35B-A3B"
        case .kimiCoding:
            "k3-256k"
        case .glmCoding:
            "glm-5.2"
        case .custom:
            ""
        }
    }

    var models: [String] {
        switch self {
        case .kimiCoding:
            ["k3-256k", "k3", "kimi-for-coding", "kimi-for-coding-highspeed"]
        case .glmCoding:
            ["glm-5.2", "glm-5-turbo", "glm-4.7"]
        case .siliconFlow, .custom:
            []
        }
    }

    var keychainAccount: String {
        "openai-compatible-api-key.\(rawValue)"
    }

    func defaultSettings() -> V2AIProviderSettings {
        V2AIProviderSettings(
            provider: self,
            isEnabled: false,
            baseURL: baseURL,
            model: defaultModel,
            apiKey: ""
        )
    }

    static func inferred(from baseURL: String) -> Self {
        let host = URL(string: baseURL)?.host?.lowercased() ?? ""
        if host.contains("siliconflow") {
            return .siliconFlow
        }
        if host == "api.kimi.com" {
            return .kimiCoding
        }
        if host == "open.bigmodel.cn" {
            return .glmCoding
        }
        return .custom
    }
}

struct V2AIProviderSettings: Equatable {
    static let siliconFlowBaseURL = V2AIProviderPreset.siliconFlow.baseURL
    static let suggestedModel = V2AIProviderPreset.siliconFlow.defaultModel

    var provider: V2AIProviderPreset
    var isEnabled: Bool
    var baseURL: String
    var model: String
    var apiKey: String

    static var defaults: Self {
        V2AIProviderPreset.siliconFlow.defaultSettings()
    }

    func planningConfiguration() throws -> V2OpenAICompatiblePlanningConfiguration {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw V2AIProviderSettingsError.invalidValue("请输入 API Key")
        }
        guard !model.isEmpty else {
            throw V2AIProviderSettingsError.invalidValue("请输入模型名称")
        }

        let rawURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let baseURL = URL(string: rawURL),
            baseURL.scheme?.lowercased() == "https",
            baseURL.host != nil
        else {
            throw V2AIProviderSettingsError.invalidValue("服务地址必须是有效的 HTTPS URL")
        }

        let endpoint: URL
        let normalizedPath = baseURL.path.trimmingCharacters(
            in: CharacterSet(charactersIn: "/")
        )
        if normalizedPath.hasSuffix("chat/completions") {
            endpoint = baseURL
        } else {
            endpoint = baseURL
                .appendingPathComponent("chat")
                .appendingPathComponent("completions")
        }

        return V2OpenAICompatiblePlanningConfiguration(
            endpoint: endpoint,
            apiKey: key,
            model: model,
            providerLabel: providerLabel(for: baseURL),
            usesPromptCacheKey: provider == .kimiCoding
        )
    }

    private func providerLabel(for url: URL) -> String {
        switch provider {
        case .siliconFlow:
            return "硅基流动"
        case .kimiCoding:
            return "Kimi Coding Plan"
        case .glmCoding:
            return "GLM Coding Plan"
        case .custom:
            break
        }

        let host = url.host?.lowercased() ?? ""
        if host.contains("openai") {
            return "OpenAI"
        }
        if host == "localhost" || host == "127.0.0.1" {
            return "本地模型"
        }
        return "在线 AI"
    }
}

enum V2AIProviderSettingsStore {
    private static let activeProviderKey = "ai.provider.active"
    private static let legacyEnabledKey = "ai.openai-compatible.enabled"
    private static let legacyBaseURLKey = "ai.openai-compatible.base-url"
    private static let legacyModelKey = "ai.openai-compatible.model"
    private static let legacyKeychainAccount = "openai-compatible-api-key"

    static func load(defaults: UserDefaults = .standard) -> V2AIProviderSettings {
        guard
            let rawProvider = defaults.string(forKey: activeProviderKey),
            let provider = V2AIProviderPreset(rawValue: rawProvider)
        else {
            return loadLegacy(defaults: defaults)
        }
        return loadProfile(for: provider, defaults: defaults)
    }

    static func loadProfile(
        for provider: V2AIProviderPreset,
        defaults: UserDefaults = .standard
    ) -> V2AIProviderSettings {
        guard hasStoredProfile(for: provider, defaults: defaults) else {
            if defaults.string(forKey: activeProviderKey) == nil {
                let legacy = loadLegacy(defaults: defaults)
                if legacy.provider == provider {
                    return legacy
                }
            }
            return provider.defaultSettings()
        }

        let initial = provider.defaultSettings()
        return V2AIProviderSettings(
            provider: provider,
            isEnabled: defaults.bool(forKey: profileKey("enabled", provider: provider)),
            baseURL: defaults.string(forKey: profileKey("base-url", provider: provider))
                ?? initial.baseURL,
            model: defaults.string(forKey: profileKey("model", provider: provider))
                ?? initial.model,
            apiKey: (try? V2AIProviderKeychain.load(account: provider.keychainAccount)) ?? ""
        )
    }

    static func save(
        _ settings: V2AIProviderSettings,
        defaults: UserDefaults = .standard
    ) throws {
        try migrateLegacyProfileIfNeeded(defaults: defaults)
        try saveProfile(settings, defaults: defaults)
        defaults.set(settings.provider.rawValue, forKey: activeProviderKey)

        // Keep the previous single-provider format current for a reversible app downgrade.
        try V2AIProviderKeychain.save(settings.apiKey, account: legacyKeychainAccount)
        defaults.set(settings.isEnabled, forKey: legacyEnabledKey)
        defaults.set(settings.baseURL, forKey: legacyBaseURLKey)
        defaults.set(settings.model, forKey: legacyModelKey)
    }

    private static func loadLegacy(defaults: UserDefaults) -> V2AIProviderSettings {
        let initial = V2AIProviderSettings.defaults
        let baseURL = defaults.string(forKey: legacyBaseURLKey) ?? initial.baseURL
        return V2AIProviderSettings(
            provider: V2AIProviderPreset.inferred(from: baseURL),
            isEnabled: defaults.bool(forKey: legacyEnabledKey),
            baseURL: baseURL,
            model: defaults.string(forKey: legacyModelKey) ?? initial.model,
            apiKey: (try? V2AIProviderKeychain.load(account: legacyKeychainAccount)) ?? ""
        )
    }

    private static func migrateLegacyProfileIfNeeded(defaults: UserDefaults) throws {
        guard defaults.string(forKey: activeProviderKey) == nil else { return }
        try saveProfile(loadLegacy(defaults: defaults), defaults: defaults)
    }

    private static func saveProfile(
        _ settings: V2AIProviderSettings,
        defaults: UserDefaults
    ) throws {
        try V2AIProviderKeychain.save(
            settings.apiKey,
            account: settings.provider.keychainAccount
        )
        defaults.set(
            settings.isEnabled,
            forKey: profileKey("enabled", provider: settings.provider)
        )
        defaults.set(
            settings.baseURL,
            forKey: profileKey("base-url", provider: settings.provider)
        )
        defaults.set(
            settings.model,
            forKey: profileKey("model", provider: settings.provider)
        )
    }

    private static func hasStoredProfile(
        for provider: V2AIProviderPreset,
        defaults: UserDefaults
    ) -> Bool {
        defaults.object(forKey: profileKey("enabled", provider: provider)) != nil
            || defaults.object(forKey: profileKey("base-url", provider: provider)) != nil
            || defaults.object(forKey: profileKey("model", provider: provider)) != nil
    }

    private static func profileKey(
        _ component: String,
        provider: V2AIProviderPreset
    ) -> String {
        "ai.provider.\(provider.rawValue).\(component)"
    }
}

enum V2AIModelCatalogStore {
    private static let catalogKey = "ai.siliconflow.model-catalog"

    static func load(defaults: UserDefaults = .standard) -> V2AIModelCatalogState {
        guard
            let data = defaults.data(forKey: catalogKey),
            let state = try? JSONDecoder().decode(V2AIModelCatalogState.self, from: data)
        else {
            return V2AIModelCatalogState()
        }
        return state
    }

    static func save(
        _ state: V2AIModelCatalogState,
        defaults: UserDefaults = .standard
    ) throws {
        defaults.set(try JSONEncoder().encode(state), forKey: catalogKey)
    }
}

private enum V2AIProviderKeychain {
    private static var service: String {
        "\(Bundle.main.bundleIdentifier ?? "com.skyliu.toughtrial").ai-provider"
    }

    static func load(account: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return ""
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw V2AIProviderSettingsError.keychain(status)
        }
        return String(decoding: data, as: UTF8.self)
    }

    static func save(_ value: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw V2AIProviderSettingsError.keychain(status)
            }
            return
        }

        let attributes: [String: Any] = [
            kSecValueData as String: Data(trimmed.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw V2AIProviderSettingsError.keychain(updateStatus)
        }

        var item = query
        attributes.forEach { item[$0.key] = $0.value }
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw V2AIProviderSettingsError.keychain(addStatus)
        }
    }
}

enum V2AIProviderSettingsError: LocalizedError {
    case invalidValue(String)
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidValue(let message):
            message
        case .keychain(let status):
            "无法安全保存 API Key（错误代码 \(status)）"
        }
    }
}

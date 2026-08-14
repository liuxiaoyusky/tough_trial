import Foundation
import Security
import ToughTrialV2Core

struct V2AIProviderSettings: Equatable {
    static let siliconFlowBaseURL = "https://api.siliconflow.cn/v1"
    static let suggestedModel = "Qwen/Qwen3.5-35B-A3B"

    var isEnabled: Bool
    var baseURL: String
    var model: String
    var apiKey: String

    static var defaults: Self {
        V2AIProviderSettings(
            isEnabled: false,
            baseURL: siliconFlowBaseURL,
            model: suggestedModel,
            apiKey: ""
        )
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
            providerLabel: providerLabel(for: baseURL)
        )
    }

    private func providerLabel(for url: URL) -> String {
        let host = url.host?.lowercased() ?? ""
        if host.contains("siliconflow") {
            return "硅基流动"
        }
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
    private static let enabledKey = "ai.openai-compatible.enabled"
    private static let baseURLKey = "ai.openai-compatible.base-url"
    private static let modelKey = "ai.openai-compatible.model"

    static func load(defaults: UserDefaults = .standard) -> V2AIProviderSettings {
        let initial = V2AIProviderSettings.defaults
        return V2AIProviderSettings(
            isEnabled: defaults.bool(forKey: enabledKey),
            baseURL: defaults.string(forKey: baseURLKey) ?? initial.baseURL,
            model: defaults.string(forKey: modelKey) ?? initial.model,
            apiKey: (try? V2AIProviderKeychain.load()) ?? ""
        )
    }

    static func save(
        _ settings: V2AIProviderSettings,
        defaults: UserDefaults = .standard
    ) throws {
        try V2AIProviderKeychain.save(settings.apiKey)
        defaults.set(settings.isEnabled, forKey: enabledKey)
        defaults.set(settings.baseURL, forKey: baseURLKey)
        defaults.set(settings.model, forKey: modelKey)
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
    private static let account = "openai-compatible-api-key"
    private static var service: String {
        "\(Bundle.main.bundleIdentifier ?? "com.skyliu.toughtrial").ai-provider"
    }

    static func load() throws -> String {
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

    static func save(_ value: String) throws {
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
            "无法保存 API Key（Keychain \(status)）"
        }
    }
}

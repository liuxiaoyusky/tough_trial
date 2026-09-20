import Foundation
import Combine
import ToughTrialV2Core

/// A connection probe has no persistence or access to the person's workspace.
@MainActor
final class V2AIConnectionTest: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var message: String?
    @Published private(set) var succeeded = false
    private var verifiedSettings: V2AIProviderSettings?
    private var generation = UUID()
    private let probe: (V2AIProviderSettings) async throws -> Void

    init(probe: @escaping (V2AIProviderSettings) async throws -> Void = V2AIConnectionTest.liveProbe) {
        self.probe = probe
    }

    func canSave(_ settings: V2AIProviderSettings) -> Bool {
        !isRunning && succeeded && verifiedSettings == settings
    }

    func invalidate() {
        generation = UUID()
        verifiedSettings = nil
        isRunning = false
        succeeded = false
        message = nil
    }

    func run(_ settings: V2AIProviderSettings) async {
        invalidate()
        let requestGeneration = generation
        isRunning = true
        let started = Date()
        do {
            _ = try settings.agentConfiguration()
            try await probe(settings)
            try Task.checkCancellation()
            guard generation == requestGeneration else { return }
            verifiedSettings = settings
            succeeded = true
            message = String(format: "连接成功 · %.1f 秒 · 可以保存配置", Date().timeIntervalSince(started))
        } catch {
            guard generation == requestGeneration else { return }
            message = Self.failureMessage(error, settings: settings)
        }
        guard generation == requestGeneration else { return }
        isRunning = false
    }

    static let request = V2AgentRequest(
        userText: "请完成连接测试，并按系统要求返回 JSON 对象：action 为 answer，text 为连接成功，query 和 url 为空字符串。不要调用工具。",
        conversation: [], observations: [], toolCatalog: .empty, context: .init()
    )

    static func liveProbe(_ settings: V2AIProviderSettings) async throws {
        let client = V2OpenAICompatibleAgentClient(configuration: try settings.agentConfiguration())
        let result = try await client.respond(Self.request)
        guard case .answer(let text) = result.action, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw V2AgentClientError.invalidOutput("连接测试没有返回有效回答")
        }
    }

    private static func failureMessage(_ error: Error, settings: V2AIProviderSettings) -> String {
        if error is CancellationError { return "测试已取消，配置未保存。" }
        if let error = error as? URLError {
            return error.code == .timedOut ? "连接超时，请稍后重试。配置未保存。" : "网络连接失败，请检查网络后重试。配置未保存。"
        }
        if let error = error as? V2AgentClientError {
            switch error {
            case .requestFailed(let code, _):
                switch code {
                case 401: return "鉴权失败（401）：请检查完整 Key 与账号地区，Coding Plan 请使用订阅专用 Key。配置未保存。"
                case 403: return "访问被拒绝（403）：请检查账号或套餐是否允许调用此模型。配置未保存。"
                case 429: return "请求受限（429）：请检查套餐额度，或稍后重试。配置未保存。"
                default: return "服务请求失败（HTTP \(code)）。请检查模型与服务地址，配置未保存。"
                }
            case .invalidOutput, .missingOutput:
                return "已收到服务响应，但回复格式不兼容。请尝试其他模型，配置未保存。"
            case .refused:
                return "服务拒绝了连接测试，配置未保存。"
            case .invalidConfiguration:
                break
            }
        }
        let description = (error as? LocalizedError)?.errorDescription ?? "测试失败，请检查配置。"
        let key = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? description : description.replacingOccurrences(of: key, with: "[已隐藏]")
    }
}

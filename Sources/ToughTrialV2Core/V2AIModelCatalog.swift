import Foundation

public struct V2AIModel: Codable, Equatable, Hashable, Sendable {
    public var id: String

    public init(id: String) {
        self.id = id
    }
}

public struct V2AIModelCatalogState: Codable, Equatable, Sendable {
    public private(set) var models: [V2AIModel]
    public private(set) var hiddenModelIDs: Set<String>
    public private(set) var selectedModelID: String?
    public private(set) var lastSuccessfulSyncAt: Date?

    public init(
        models: [V2AIModel] = [],
        hiddenModelIDs: Set<String> = [],
        selectedModelID: String? = nil,
        lastSuccessfulSyncAt: Date? = nil
    ) {
        self.models = Self.normalized(models)
        self.hiddenModelIDs = hiddenModelIDs
        self.selectedModelID = selectedModelID
        self.lastSuccessfulSyncAt = lastSuccessfulSyncAt
    }

    public var visibleModels: [V2AIModel] {
        models.filter { !hiddenModelIDs.contains($0.id) }
    }

    public var isSelectedModelAvailable: Bool {
        guard let selectedModelID else { return false }
        return models.contains { $0.id == selectedModelID }
            && !hiddenModelIDs.contains(selectedModelID)
    }

    public mutating func applySuccessfulSync(models: [V2AIModel], at date: Date) {
        self.models = Self.normalized(models)
        lastSuccessfulSyncAt = date
    }

    public mutating func selectModel(id: String) throws {
        guard models.contains(where: { $0.id == id }) else {
            throw V2AIModelCatalogStateError.modelUnavailable
        }
        guard !hiddenModelIDs.contains(id) else {
            throw V2AIModelCatalogStateError.modelHidden
        }
        selectedModelID = id
    }

    public mutating func setModelHidden(id: String, isHidden: Bool) throws {
        guard models.contains(where: { $0.id == id }) else {
            throw V2AIModelCatalogStateError.modelUnavailable
        }
        if isHidden, selectedModelID == id {
            throw V2AIModelCatalogStateError.cannotHideSelectedModel
        }
        if isHidden {
            hiddenModelIDs.insert(id)
        } else {
            hiddenModelIDs.remove(id)
        }
    }

    private static func normalized(_ models: [V2AIModel]) -> [V2AIModel] {
        let ids = Set(
            models.compactMap { model -> String? in
                let id = model.id.trimmingCharacters(in: .whitespacesAndNewlines)
                return id.isEmpty ? nil : id
            }
        )
        return ids
            .map(V2AIModel.init(id:))
            .sorted {
                $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending
            }
    }
}

public enum V2AIModelCatalogStateError: Error, Equatable, LocalizedError, Sendable {
    case modelUnavailable
    case modelHidden
    case cannotHideSelectedModel

    public var errorDescription: String? {
        switch self {
        case .modelUnavailable:
            "这个模型目前不可用，请先更新模型列表。"
        case .modelHidden:
            "请先恢复显示这个模型。"
        case .cannotHideSelectedModel:
            "当前模型不能隐藏，请先选择另一个模型。"
        }
    }
}

public protocol V2AIModelCatalogClient: Sendable {
    func fetchModels(apiKey: String) async throws -> [V2AIModel]
}

public struct V2SiliconFlowModelCatalogClient<Transport: V2PlanningHTTPTransport>:
    V2AIModelCatalogClient
{
    private let transport: Transport

    public init(transport: Transport) {
        self.transport = transport
    }

    public func fetchModels(apiKey: String) async throws -> [V2AIModel] {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw V2AIModelCatalogClientError.missingAPIKey
        }

        var components = URLComponents(
            url: URL(string: "https://api.siliconflow.cn/v1/models")!,
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "sub_type", value: "chat")]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await transport.data(for: request)
        switch response.statusCode {
        case 200..<300:
            break
        case 401, 403:
            throw V2AIModelCatalogClientError.authenticationFailed
        case 429:
            throw V2AIModelCatalogClientError.rateLimited
        default:
            throw V2AIModelCatalogClientError.requestFailed(statusCode: response.statusCode)
        }

        let envelope: ResponseEnvelope
        do {
            envelope = try JSONDecoder().decode(ResponseEnvelope.self, from: data)
        } catch {
            throw V2AIModelCatalogClientError.invalidResponse
        }
        let models = V2AIModelCatalogState(models: envelope.data).models
        guard !models.isEmpty else {
            throw V2AIModelCatalogClientError.emptyCatalog
        }
        return models
    }
}

public extension V2SiliconFlowModelCatalogClient where Transport == V2URLSessionPlanningTransport {
    init() {
        self.init(transport: V2URLSessionPlanningTransport())
    }
}

private extension V2SiliconFlowModelCatalogClient {
    struct ResponseEnvelope: Decodable {
        var data: [V2AIModel]
    }
}

public enum V2AIModelCatalogClientError: Error, Equatable, LocalizedError, Sendable {
    case missingAPIKey
    case authenticationFailed
    case rateLimited
    case requestFailed(statusCode: Int)
    case invalidResponse
    case emptyCatalog

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "请粘贴 API Key。"
        case .authenticationFailed:
            "API Key 无效或没有访问权限，请检查后重试。"
        case .rateLimited:
            "请求过于频繁，请稍后再更新模型。"
        case .requestFailed(let statusCode):
            "SiliconFlow 暂时无法更新模型（HTTP \(statusCode)）。"
        case .invalidResponse:
            "SiliconFlow 返回了无法识别的模型列表。"
        case .emptyCatalog:
            "没有找到可用的聊天模型。"
        }
    }
}

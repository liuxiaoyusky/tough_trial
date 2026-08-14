import Foundation
import ToughTrialV2Core

func checkAIModelCatalog() async throws {
    let firstSync = Date(timeIntervalSince1970: 1_800_000_000)
    let secondSync = firstSync.addingTimeInterval(60)
    let thirdSync = secondSync.addingTimeInterval(60)

    var state = V2AIModelCatalogState()
    state.applySuccessfulSync(
        models: [
            V2AIModel(id: "Qwen/Qwen3-32B"),
            V2AIModel(id: "deepseek-ai/DeepSeek-V3"),
        ],
        at: firstSync
    )
    require(
        state.visibleModels.map(\.id) == ["deepseek-ai/DeepSeek-V3", "Qwen/Qwen3-32B"],
        "A first model sync should show every returned chat model"
    )
    require(
        state.lastSuccessfulSyncAt == firstSync,
        "A successful model sync should record its actual completion time"
    )

    try state.selectModel(id: "Qwen/Qwen3-32B")
    do {
        try state.setModelHidden(id: "Qwen/Qwen3-32B", isHidden: true)
        fatalError("The selected model must not be hidden")
    } catch V2AIModelCatalogStateError.cannotHideSelectedModel {
        // Expected: selecting another model is an explicit user decision.
    }

    try state.setModelHidden(id: "deepseek-ai/DeepSeek-V3", isHidden: true)
    state.applySuccessfulSync(
        models: [
            V2AIModel(id: "Qwen/Qwen3-32B"),
            V2AIModel(id: "moonshotai/Kimi-K2"),
        ],
        at: secondSync
    )
    require(
        state.visibleModels.map(\.id) == ["moonshotai/Kimi-K2", "Qwen/Qwen3-32B"],
        "A newly discovered model should be visible by default"
    )
    require(
        state.hiddenModelIDs == ["deepseek-ai/DeepSeek-V3"],
        "A temporarily missing model must keep its manual hidden preference"
    )

    state.applySuccessfulSync(
        models: [
            V2AIModel(id: "deepseek-ai/DeepSeek-V3"),
            V2AIModel(id: "moonshotai/Kimi-K2"),
        ],
        at: thirdSync
    )
    require(
        state.selectedModelID == "Qwen/Qwen3-32B",
        "A removed current model must not be silently replaced"
    )
    require(
        !state.isSelectedModelAvailable,
        "A removed current model should require an explicit replacement"
    )
    require(
        state.visibleModels.map(\.id) == ["moonshotai/Kimi-K2"],
        "A hidden model should stay hidden when it returns to the service catalog"
    )

    let responseData = try JSONSerialization.data(
        withJSONObject: [
            "object": "list",
            "data": [
                [
                    "id": "Qwen/Qwen3-32B",
                    "object": "model",
                    "created": 0,
                    "owned_by": "Qwen",
                ],
                [
                    "id": "deepseek-ai/DeepSeek-V3",
                    "object": "model",
                    "created": 0,
                    "owned_by": "deepseek-ai",
                ],
            ],
        ],
        options: [.sortedKeys]
    )
    let transport = V2FakeModelCatalogTransport(
        result: .response(statusCode: 200, data: responseData)
    )
    let client = V2SiliconFlowModelCatalogClient(transport: transport)
    let models = try await client.fetchModels(apiKey: "fake-key-never-sent")
    require(
        models.map(\.id) == ["deepseek-ai/DeepSeek-V3", "Qwen/Qwen3-32B"],
        "The SiliconFlow client should decode and stably sort chat models"
    )

    let requests = await transport.recordedRequests()
    require(requests.count == 1, "A model refresh should make exactly one request")
    let request = requests[0]
    require(request.httpMethod == "GET", "The model catalog request should use GET")
    require(
        request.value(forHTTPHeaderField: "Authorization") == "Bearer fake-key-never-sent",
        "The model catalog request should use the supplied bearer credential"
    )
    let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
    require(
        components?.scheme == "https"
            && components?.host == "api.siliconflow.cn"
            && components?.path == "/v1/models",
        "The model catalog request should use SiliconFlow's official endpoint"
    )
    require(
        components?.queryItems == [URLQueryItem(name: "sub_type", value: "chat")],
        "The model catalog request should ask SiliconFlow for chat models only"
    )

    let rejectedKey = "fake-rejected-key-never-log"
    let rejectedClient = V2SiliconFlowModelCatalogClient(
        transport: V2FakeModelCatalogTransport(
            result: .response(
                statusCode: 401,
                data: Data("{\"message\":\"unauthorized\"}".utf8)
            )
        )
    )
    do {
        _ = try await rejectedClient.fetchModels(apiKey: rejectedKey)
        fatalError("A rejected API key should fail model refresh")
    } catch V2AIModelCatalogClientError.authenticationFailed {
        require(
            !V2AIModelCatalogClientError.authenticationFailed.localizedDescription.contains(rejectedKey),
            "A model refresh error must never contain the API key"
        )
    }
}

private actor V2FakeModelCatalogTransport: V2PlanningHTTPTransport {
    enum Result: Sendable {
        case response(statusCode: Int, data: Data)
    }

    private let result: Result
    private var requests: [URLRequest] = []

    init(result: Result) {
        self.result = result
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        switch result {
        case .response(let statusCode, let data):
            guard let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            ) else {
                fatalError("Unable to build fake model catalog response")
            }
            return (data, response)
        }
    }

    func recordedRequests() -> [URLRequest] {
        requests
    }
}

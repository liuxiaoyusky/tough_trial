import XCTest
import ToughTrialV2Core
@testable import ToughTrial

@MainActor
final class V2AIConnectionTestTests: XCTestCase {
    private func settings() -> V2AIProviderSettings {
        var settings = V2AIProviderPreset.miniMax.defaultSettings()
        settings.apiKey = "fixture-key"
        return settings
    }

    func testProbePromptRequestsWireJSONWithoutPrivateContext() {
        let request = V2AIConnectionTest.request
        XCTAssertTrue(request.userText.contains("JSON"))
        XCTAssertTrue(request.conversation.isEmpty)
        XCTAssertTrue(request.observations.isEmpty)
        XCTAssertTrue(request.toolCatalog.tools.isEmpty)
        XCTAssertEqual(request.context, V2AssistantContext())
    }

    func testSuccessOnlyAuthorizesExactTestedConfiguration() async {
        let original = settings()
        var received: V2AIProviderSettings?
        let test = V2AIConnectionTest(probe: { received = $0 })
        XCTAssertFalse(test.canSave(original))
        await test.run(original)
        XCTAssertEqual(received, original)
        XCTAssertTrue(test.canSave(original))
        for changed in ["model", "key", "endpoint", "thinking"] {
            var edited = original
            switch changed {
            case "model": edited.model = "another-model"
            case "key": edited.apiKey = "another-key"
            case "endpoint": edited.baseURL = "https://api.minimax.cn/v1"
            default: edited.thinking = .low
            }
            XCTAssertFalse(test.canSave(edited))
        }
        test.invalidate()
        XCTAssertFalse(test.canSave(original))
    }

    func testAuthenticationFailureDoesNotExposeServerEchoOrAllowSave() async {
        let settings = settings()
        let test = V2AIConnectionTest(probe: { _ in
            throw V2AgentClientError.requestFailed(statusCode: 401, message: settings.apiKey)
        })
        await test.run(settings)
        XCTAssertFalse(test.canSave(settings))
        XCTAssertTrue(test.message?.contains("401") == true)
        XCTAssertFalse(test.message?.contains(settings.apiKey) == true)
    }

    func testEditedConfigurationDiscardsLateSuccess() async {
        var finish: CheckedContinuation<Void, Never>?
        let test = V2AIConnectionTest(probe: { _ in
            await withCheckedContinuation { finish = $0 }
        })
        let settings = settings()
        let task = Task { await test.run(settings) }
        while finish == nil { await Task.yield() }
        test.invalidate()
        finish?.resume()
        await task.value
        XCTAssertFalse(test.canSave(settings))
        XCTAssertNil(test.message)
    }

    func testInvalidKeyIsRejectedBeforeNetwork() async {
        var settings = settings()
        settings.apiKey = "not a key"
        var called = false
        let test = V2AIConnectionTest(probe: { _ in called = true })
        await test.run(settings)
        XCTAssertFalse(called)
        XCTAssertFalse(test.canSave(settings))
        XCTAssertTrue(test.message?.contains("空白") == true)
    }

    func testResponseFormatFailureIsDistinctFromNetworkFailure() async {
        let settings = settings()
        let test = V2AIConnectionTest(probe: { _ in throw V2AgentClientError.invalidOutput("fixture") })
        await test.run(settings)
        XCTAssertTrue(test.message?.contains("已收到服务响应") == true)
        XCTAssertFalse(test.canSave(settings))
    }
}

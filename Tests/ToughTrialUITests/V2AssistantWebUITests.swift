import XCTest

@MainActor
final class V2AssistantWebUITests: XCTestCase {
    private func launch(failure: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TOUGH_TRIAL_UI_TESTING"] = "1"
        app.launchEnvironment["TOUGH_TRIAL_UI_TEST_EMPTY"] = "1"
        app.launchEnvironment["TOUGH_TRIAL_UI_TEST_BROWSER_FIXTURE"] = "1"
        if failure { app.launchEnvironment["TOUGH_TRIAL_UI_WEB_FAIL_ONCE"] = "1" }
        app.launch()
        XCTAssertTrue(app.textViews["assistant.composer"].waitForExistence(timeout: 10))
        return app
    }
    private func query(_ app: XCUIApplication) {
        let input = app.textViews["assistant.composer"]
        input.tap(); input.typeText("搜索网页")
        app.buttons["assistant.send"].tap()
    }
    private func screenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testTimeoutKeepsQuestionAndRetryShowsSources() {
        let app = launch(failure: true)
        query(app)
        let retry = app.buttons["assistant.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "超时")).firstMatch.exists)
        XCTAssertFalse(app.buttons["Tough Trial 测试来源"].exists)
        screenshot(app, "web-timeout-retry")
        retry.tap()
        XCTAssertTrue(app.buttons["Tough Trial 测试来源"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["测试回复已根据工具结果生成。"].exists)
        screenshot(app, "web-retry-sources")
        app.tabBars.buttons["任务"].tap()
        XCTAssertFalse(app.buttons["搜索网页"].exists)
    }
    func testDisabledSearchGivesSettingsPathThenCanRetryAfterEnabling() {
        let app = launch()
        toggleWeb(app)
        query(app)
        let retry = app.buttons["assistant.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 8))
        let explanation = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "功能与插件", "网页搜索")).firstMatch
        XCTAssertTrue(explanation.exists)
        XCTAssertTrue(explanation.label.contains("网页搜索"))
        XCTAssertFalse(app.buttons["Tough Trial 测试来源"].exists)
        screenshot(app, "web-disabled-settings")
        toggleWeb(app)
        XCTAssertTrue(retry.waitForExistence(timeout: 5)); retry.tap()
        XCTAssertTrue(app.buttons["Tough Trial 测试来源"].waitForExistence(timeout: 8))
    }
    func testUnconfiguredServiceOpensSettingsAndCancelPreservesGuidance() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TOUGH_TRIAL_UI_TESTING"] = "1"
        app.launchEnvironment["TOUGH_TRIAL_UI_TEST_EMPTY"] = "1"
        app.launchEnvironment["TOUGH_TRIAL_UI_TEST_REQUIRE_AI_CONFIGURATION"] = "1"
        app.launch()
        let configure = app.buttons["assistant.configureAI"]
        XCTAssertTrue(configure.waitForExistence(timeout: 8))
        XCTAssertFalse(app.textViews["assistant.composer"].exists)
        configure.tap()
        XCTAssertTrue(app.navigationBars["AI 服务"].waitForExistence(timeout: 5))
        app.navigationBars["AI 服务"].buttons["完成"].tap()
        XCTAssertTrue(configure.waitForExistence(timeout: 5))
        XCTAssertFalse(app.textViews["assistant.composer"].exists)
        screenshot(app, "web-ai-configuration-needed")
    }
    private func toggleWeb(_ app: XCUIApplication) {
        app.buttons["plugins.manage"].tap()
        let control = app.switches["plugin.toggle.web"]
        for _ in 0..<10 where !control.isHittable { app.swipeUp() }
        XCTAssertTrue(control.isHittable)
        control.switches.firstMatch.exists ? control.switches.firstMatch.tap()
            : control.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        app.buttons["plugins.done"].tap()
    }
}

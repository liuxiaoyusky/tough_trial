import XCTest

final class V2DynamicToolsUITests: XCTestCase {
    @MainActor private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TOUGH_TRIAL_UI_TESTING"] = "1"
        app.launchEnvironment["TOUGH_TRIAL_UI_TEST_EMPTY"] = "1"
        app.launchEnvironment["TOUGH_TRIAL_UI_TEST_DYNAMIC_TOOLS"] = "1"
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["助手"].waitForExistence(timeout: 15))
        app.tabBars.buttons["助手"].tap()
        return app
    }
    @MainActor private func send(_ text: String, app: XCUIApplication) {
        let composer = app.textViews["assistant.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        composer.tap(); composer.typeText(text)
        app.buttons["assistant.send"].tap()
    }
    @MainActor private func button(_ prefix: String, tool: String, app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier CONTAINS %@", prefix, tool)).firstMatch
    }
    @MainActor private func screenshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name
        attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor func testDynamicTaskHasReceiptAndUndo() {
        let app = launch()
        send("请记录待办 Tool Test Task，回家路上", app: app)
        let undo = button("assistant.tool.undo.", tool: "core.tasks.create", app: app)
        XCTAssertTrue(undo.waitForExistence(timeout: 10))
        screenshot("dynamic-task-applied", app: app)
        undo.tap()
        XCTAssertTrue(app.staticTexts["已撤销"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(undo.exists)
        screenshot("dynamic-task-undone", app: app)
    }
    @MainActor func testSubscriptionAndExplicitPaymentConfirmation() {
        let app = launch()
        send("创建订阅 Test Subscription，每月20美元，2026-10-10到期", app: app)
        let createUndo = button("assistant.tool.undo.", tool: "core.finance.createPlan", app: app)
        XCTAssertTrue(createUndo.waitForExistence(timeout: 10))
        send("Test Subscription 2026-10-10 已付款，请记录", app: app)
        let confirm = button("assistant.tool.confirm.", tool: "core.finance.markPaid", app: app)
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        screenshot("dynamic-payment-confirmation", app: app)
        confirm.tap()
        let undo = button("assistant.tool.undo.", tool: "core.finance.markPaid", app: app)
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        screenshot("dynamic-payment-applied", app: app)
        undo.tap()
        XCTAssertFalse(confirm.exists)
        XCTAssertTrue(app.staticTexts["已撤销"].firstMatch.waitForExistence(timeout: 5))
    }
}

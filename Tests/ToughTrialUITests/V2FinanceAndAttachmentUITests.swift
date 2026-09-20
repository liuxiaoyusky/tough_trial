import XCTest

final class V2FinanceAndAttachmentUITests: XCTestCase {
    @MainActor private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TOUGH_TRIAL_UI_TESTING"] = "1"
        app.launchEnvironment["TOUGH_TRIAL_UI_TEST_EMPTY"] = "1"
        app.launchEnvironment["TOUGH_TRIAL_UI_TEST_FINANCE"] = "1"
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["随手记"].waitForExistence(timeout: 10))
        app.tabBars.buttons["随手记"].tap()
        return app
    }
    @MainActor func testFilesShownInCaptureAndSubscriptionWithPaymentUndo() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["receipt.png"].waitForExistence(timeout: 5))
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["invoice.pdf"].exists)
        XCTAssertTrue(app.staticTexts["backup.custom"].exists)
        keep(app, "capture-attachments")
        app.swipeDown()
        app.segmentedControls.buttons["记账"].tap()
        app.buttons["finance.open"].tap()
        XCTAssertTrue(app.buttons["finance.plan.ChatGPT Test"].waitForExistence(timeout: 5))
        app.buttons["finance.plan.ChatGPT Test"].tap()
        XCTAssertTrue(app.buttons["finance.pay"].waitForExistence(timeout: 5))
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["invoice.pdf"].exists)
        XCTAssertTrue(app.staticTexts["backup.custom"].exists)
        keep(app, "subscription-attachments")
        app.swipeDown()
        app.buttons["finance.pay"].tap()
        app.buttons["已支付，记入流水"].tap()
        app.swipeUp()
        XCTAssertTrue(app.buttons["finance.undo"].waitForExistence(timeout: 5))
        app.buttons["finance.undo"].tap()
        XCTAssertTrue(app.staticTexts["已撤销"].waitForExistence(timeout: 5))
        app.buttons["完成"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["budget.progress"].label.contains("已花 0"))
    }
    @MainActor func testCreateSubscriptionAndDisableRestoreModule() {
        let app = launch()
        app.segmentedControls.buttons["记账"].tap()
        app.buttons["finance.open"].tap()
        app.buttons["finance.add"].tap()
        let title = app.textFields["finance.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap(); title.typeText("Rent Test")
        let amount = app.textFields["finance.amount"]
        amount.tap(); amount.typeText("1200")
        app.buttons["finance.save"].tap()
        XCTAssertTrue(app.buttons["finance.plan.Rent Test"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["plugins.manage"].tap()
        let toggle = app.switches["plugin.toggle.ledger"]
        for _ in 0..<5 where !toggle.isHittable { app.swipeUp() }
        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        app.buttons["完成"].firstMatch.tap()
        XCTAssertFalse(app.segmentedControls.buttons["记账"].exists)
        app.buttons["plugins.manage"].tap()
        for _ in 0..<5 where !toggle.isHittable { app.swipeUp() }
        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        app.buttons["完成"].firstMatch.tap()
        app.segmentedControls.buttons["记账"].tap()
        app.buttons["finance.open"].tap()
        XCTAssertTrue(app.buttons["finance.plan.Rent Test"].waitForExistence(timeout: 5))
    }
    @MainActor private func keep(_ app: XCUIApplication, _ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = name; screenshot.lifetime = .keepAlways; add(screenshot)
    }
}

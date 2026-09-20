import XCTest

final class ToughTrialUsageTraceTests: XCTestCase {
    @MainActor
    func testUsageTraceCanBeViewedDisabledAndCleared() {
        let app = XCUIApplication()
        app.launchEnvironment["TOUGH_TRIAL_UI_TESTING"] = "1"
        app.launch()
        app.tabBars.firstMatch.buttons["助手"].tap()
        let composer = app.textViews["assistant.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        composer.tap()
        composer.typeText("hello")
        app.buttons["assistant.send"].tap()
        XCTAssertTrue(app.staticTexts["hello"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["assistant.more"].tap()
        app.buttons["assistant.trace"].tap()
        XCTAssertTrue(app.navigationBars["使用记录"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["提交输入"].waitForExistence(timeout: 5))
        let toggle = app.switches["trace.enabled"]
        XCTAssertEqual(toggle.value as? String, "1")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String, "0")
        app.buttons["trace.export"].tap()
        XCTAssertTrue(app.navigationBars["导出预览"].waitForExistence(timeout: 3))
        app.navigationBars["导出预览"].buttons["关闭"].tap()
        app.buttons["trace.clear"].tap()
        app.buttons["trace.confirmClear"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["已保存 0 条"].waitForExistence(timeout: 3))
        app.navigationBars["使用记录"].buttons["完成"].tap()
        app.buttons["assistant.more"].tap()
        app.buttons["assistant.trace"].tap()
        XCTAssertTrue(app.switches["trace.enabled"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.switches["trace.enabled"].value as? String, "0")
    }
}

import XCTest

final class V2AssistantContextUITests: XCTestCase {
    @MainActor func testContextEntryShowsMemoryCompactAndOriginalMessage() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TOUGH_TRIAL_UI_TESTING"] = "1"
        app.launchEnvironment["TOUGH_TRIAL_UI_TEST_EMPTY"] = "1"
        app.launch()
        app.tabBars.buttons["助手"].tap()
        let composer = app.textViews["assistant.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        composer.tap(); composer.typeText("Context archive check")
        app.buttons["assistant.send"].tap()
        let entry = app.buttons["assistant.context"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5)); entry.tap()
        let compact = app.buttons["assistant.context.compact"]
        XCTAssertTrue(compact.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["管理长期记忆"].exists)
        XCTAssertTrue(app.staticTexts["Context archive check"].exists)
        compact.tap()
        XCTAssertTrue(app.staticTexts["会话较短，无需整理；继续使用原文。"].waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "assistant-memory-context-and-history"; shot.lifetime = .keepAlways; add(shot)
    }
}

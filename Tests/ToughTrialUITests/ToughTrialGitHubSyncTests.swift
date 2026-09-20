import XCTest

final class ToughTrialGitHubSyncTests: XCTestCase {
    @MainActor
    func testGitHubConfigurationRejectsInvalidRepositoryWithoutConnecting() {
        let app = XCUIApplication()
        app.launchEnvironment["TOUGH_TRIAL_UI_TESTING"] = "1"
        app.launch()
        app.tabBars.firstMatch.buttons["助手"].tap()
        XCTAssertTrue(app.buttons["assistant.more"].waitForExistence(timeout: 5))
        app.buttons["assistant.more"].tap()
        app.buttons["assistant.schedule.github"].tap()
        XCTAssertTrue(app.navigationBars["GitHub 同步"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.secureTextFields["schedule.github.credential"].exists)
        let repository = app.textFields["schedule.github.repository"]
        repository.tap()
        repository.typeText("invalid-repository")
        app.buttons["schedule.github.save"].tap()
        XCTAssertTrue(app.staticTexts["schedule.github.error"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["schedule.github.sync"].exists)
        app.navigationBars["GitHub 同步"].buttons["完成"].tap()
        XCTAssertTrue(app.buttons["assistant.more"].waitForExistence(timeout: 5))
    }
}

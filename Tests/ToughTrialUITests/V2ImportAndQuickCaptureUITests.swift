import XCTest

final class V2ImportAndQuickCaptureUITests: XCTestCase {
    @MainActor private func launch(route: String? = nil) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TOUGH_TRIAL_UI_TESTING"] = "1"
        app.launchEnvironment["TOUGH_TRIAL_UI_TEST_EMPTY"] = "1"
        app.launchEnvironment["TOUGH_TRIAL_UI_TEST_CAPTURE"] = "1"
        app.launchEnvironment["TOUGH_TRIAL_UI_TEST_IMPORT"] = "1"
        app.launchEnvironment["TOUGH_TRIAL_UI_TEST_QUICK_URL"] = route
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["随手记"].waitForExistence(timeout: 10))
        return app
    }
    @MainActor func testActualNoteURLColdLaunchOpensEditor() {
        let app = launch()
        // XCUIApplication.open relaunches the process like launch(); draft preservation is
        // checked separately against the store, while this checks the real URL handler.
        app.open(URL(string: "toughtrial://capture/note")!)
        let input = app.textViews["capture.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertEqual(input.value as? String, "")
    }
    @MainActor func testQuickTaskOpensFormAndSavesStandardTask() {
        let app = launch(route: "toughtrial://capture/task")
        let document = app.textViews["quick.task.document"]
        XCTAssertTrue(document.waitForExistence(timeout: 5))
        document.tap(); document.typeText("Buy milk")
        app.buttons["quick.task.save"].tap()
        app.tabBars.buttons["任务"].tap()
        XCTAssertTrue(app.staticTexts["Buy milk"].firstMatch.waitForExistence(timeout: 5))
    }
    @MainActor func testQuickLedgerOpensContinuousInput() {
        let app = launch(route: "toughtrial://capture/ledger")
        XCTAssertTrue(app.textViews["ledger.input"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["ledger.amount"].exists)
        XCTAssertFalse(app.buttons["ledger.organize"].isEnabled)
        XCTAssertTrue(app.buttons["ledger.manualFields"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "quick-ledger"; screenshot.lifetime = .keepAlways; add(screenshot)
    }
    @MainActor func testOrganizingFromLedgerReturnsToRecords() {
        let app = launch()
        app.tabBars.buttons["随手记"].tap()
        app.segmentedControls.buttons["记账"].tap()
        app.buttons["capture.import"].tap()
        XCTAssertTrue(app.buttons["import.organize"].waitForExistence(timeout: 5))
        app.buttons["import.organize"].tap()
        XCTAssertTrue(app.textViews["capture.input"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.segmentedControls.buttons["记录"].isSelected)
    }
    @MainActor func testImportRecognizesAndSavesSourcesWithoutOrganization() {
        let app = launch()
        app.tabBars.buttons["随手记"].tap()
        app.buttons["capture.import"].tap()
        XCTAssertTrue(app.staticTexts["测试账单.csv"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "import-preview"; screenshot.lifetime = .keepAlways; add(screenshot)
        let save = app.buttons["import.save"]
        for _ in 0..<6 where !save.isHittable { app.swipeUp() }
        XCTAssertTrue(save.isHittable); save.tap()
        XCTAssertTrue(app.staticTexts["import.saved"].waitForExistence(timeout: 5))
        app.buttons["打开第一条记录"].tap()
        XCTAssertTrue(app.textViews["capture.input"].waitForExistence(timeout: 5))
        XCTAssertTrue((app.textViews["capture.input"].value as? String ?? "").contains("午餐"))
        app.buttons["收起键盘"].firstMatch.tapIfExists()
        app.segmentedControls.buttons["记账"].tap()
        XCTAssertFalse(app.staticTexts["CNY 28"].exists)
    }
}

private extension XCUIElement {
    func tapIfExists() { if exists && isHittable { tap() } }
}

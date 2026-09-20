import XCTest

final class V2CaptureUITests: XCTestCase {
    @MainActor private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TOUGH_TRIAL_UI_TESTING"] = "1"
        app.launchEnvironment["TOUGH_TRIAL_UI_TEST_EMPTY"] = "1"
        app.launchEnvironment["TOUGH_TRIAL_UI_TEST_CAPTURE"] = "1"
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["随手记"].waitForExistence(timeout: 10))
        app.tabBars.buttons["随手记"].tap()
        return app
    }
    @MainActor private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<7 where !element.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }
    @MainActor func testMixedCaptureRoutesThroughStandardDestinations() {
        let app = launch()
        let input = app.textViews["capture.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("Lunch CNY 38. Good communication today. Film a breakfast video. Create an interview outline task.")
        app.buttons["收起键盘"].tap()
        app.buttons["capture.organize"].tap()
        let confirm = app.buttons["capture.confirmCategory"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        reveal(confirm, app: app)
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "capture-mixed-results"; attachment.lifetime = .keepAlways; add(attachment)
        confirm.tap()
        XCTAssertTrue(app.textFields["capture.categoryName"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["capture.categoryName"].value as? String, "餐饮")
        app.buttons["capture.categorySave"].tap()
        XCTAssertTrue(app.tabBars.buttons["任务"].waitForExistence(timeout: 5))
        app.tabBars.buttons["任务"].tap()
        XCTAssertTrue(app.staticTexts["整理采访提纲"].firstMatch.waitForExistence(timeout: 5))
        app.tabBars.buttons["回想"].tap()
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue((app.textViews.firstMatch.value as? String ?? "").contains("今天沟通很顺畅"))
        app.tabBars.buttons["随手记"].tap()
        app.segmentedControls.buttons["记账"].tap()
        XCTAssertTrue(app.staticTexts["支出 · CNY 38"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["餐饮"].firstMatch.exists)
        let ledger = XCTAttachment(screenshot: app.screenshot()); ledger.name = "capture-ledger-confirmed"; ledger.lifetime = .keepAlways; add(ledger)
    }
    @MainActor func testHandwritingRemainsEditableAfterSaving() {
        let app = launch()
        app.buttons["手写"].tap()
        let canvas = app.descendants(matching: .any)["recall.handwritingCanvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let start = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.25))
        let end = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.45))
        start.press(forDuration: 0.1, thenDragTo: end)
        app.buttons["保存原稿"].tap()
        XCTAssertTrue(app.buttons["继续写"].waitForExistence(timeout: 10))
        reveal(app.buttons["继续写"], app: app)
        app.buttons["继续写"].tap()
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        XCTAssertEqual(canvas.value as? String, "已有笔迹")
    }

    @MainActor func testManualBillUsesTheSameLedgerAndOthers() {
        let app = launch()
        app.segmentedControls.buttons["记账"].tap()
        app.buttons["记一笔"].tap()
        let input = app.textViews["ledger.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap(); input.typeText("Coffee")
        app.buttons["ledger.dismissKeyboard"].tap()
        app.buttons["ledger.manualFields"].tap()
        app.textFields["ledger.amount"].tap(); app.textFields["ledger.amount"].typeText("19.90")
        app.buttons["ledger.dismissKeyboard"].tap()
        app.textFields["ledger.currency"].tap(); app.textFields["ledger.currency"].typeText("CNY")
        app.buttons["ledger.dismissKeyboard"].tap()
        let save = app.buttons["ledger.save"]
        for _ in 0..<6 where !save.isHittable { app.scrollViews["ledger.scroll"].swipeUp() }
        save.tap()
        XCTAssertTrue(app.staticTexts["Coffee"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["CNY 19.90"].exists)
        XCTAssertTrue(app.staticTexts["Others"].firstMatch.exists)
        // Manual bills use the existing finance receipt; classification is available on the ledger row.
        app.buttons["确认分类"].tap()
        let category = app.textFields["capture.categoryName"]
        XCTAssertTrue(category.waitForExistence(timeout: 5))
        category.tap(); category.typeText("Coffee category")
        app.buttons["capture.categorySave"].tap()
        XCTAssertTrue(app.staticTexts["Coffee category"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["CNY 19.90"].exists)
    }
}

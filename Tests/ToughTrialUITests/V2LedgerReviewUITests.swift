import XCTest

@MainActor
final class V2LedgerReviewUITests: XCTestCase {
    private func launch(missing: Bool = false, failOnce: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TOUGH_TRIAL_UI_TESTING"] = "1"
        app.launchEnvironment["TOUGH_TRIAL_UI_TEST_EMPTY"] = "1"
        app.launchEnvironment["TOUGH_TRIAL_UI_TEST_CAPTURE"] = "1"
        app.launchEnvironment["TOUGH_TRIAL_UI_TEST_LEDGER"] = "1"
        if missing { app.launchEnvironment["TOUGH_TRIAL_UI_TEST_LEDGER_MISSING"] = "1" }
        if failOnce { app.launchEnvironment["TOUGH_TRIAL_UI_TEST_LEDGER_FAIL_ONCE"] = "1" }
        app.launch()
        app.tabBars.buttons["随手记"].tap()
        app.segmentedControls.buttons["记账"].tap()
        app.buttons["记一笔"].tap()
        XCTAssertTrue(app.textViews["ledger.input"].waitForExistence(timeout: 5))
        return app
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 where !element.isHittable { app.scrollViews["ledger.scroll"].swipeUp() }
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }

    private func dismissKeyboard(_ app: XCUIApplication) {
        let dismiss = app.buttons["ledger.dismissKeyboard"]
        if dismiss.waitForExistence(timeout: 2) { dismiss.tap() }
    }

    private func replace(_ field: XCUIElement, with value: String, app: XCUIApplication) {
        reveal(field, in: app)
        let old = field.value as? String ?? ""
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count) + value)
        XCTAssertEqual(field.value as? String, value)
        dismissKeyboard(app)
    }

    private func organize(_ raw: String, app: XCUIApplication) {
        let input = app.textViews["ledger.input"]
        input.tap(); input.typeText(raw)
        dismissKeyboard(app)
        let organize = app.buttons["ledger.organize"]
        reveal(organize, in: app); organize.tap()
        XCTAssertTrue(app.staticTexts["核对账单"].waitForExistence(timeout: 8))
    }

    func testCancelPreservesLedgerDraftWithoutChangingMixedCapture() {
        let app = launch()
        XCTAssertFalse(app.buttons["ledger.organize"].isEnabled)
        XCTAssertFalse(app.textFields["ledger.amount"].exists)
        let raw = "午饭花了三十八，不对，是三十五，昨天的"
        app.textViews["ledger.input"].tap(); app.textViews["ledger.input"].typeText(raw)
        app.buttons["ledger.cancel"].tap()
        app.segmentedControls.buttons["记录"].tap()
        XCTAssertEqual(app.textViews["capture.input"].value as? String, "")
        app.segmentedControls.buttons["记账"].tap()
        app.buttons["记一笔"].tap()
        XCTAssertEqual(app.textViews["ledger.input"].value as? String, raw)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "ledger-continuous-input"; shot.lifetime = .keepAlways; add(shot)
    }

    func testEditedReviewSavesCurrentValuesThenConfirmsCategoryAndUndoes() {
        let app = launch()
        organize("午饭 38 CNY，改成 35，昨天的", app: app)
        let prefix = "ledger.proposal.ledger-review"
        replace(app.textFields[prefix + ".amount"], with: "35", app: app)
        replace(app.textFields[prefix + ".localDate"], with: "2026-09-11", app: app)
        replace(app.textFields[prefix + ".categoryName"], with: "日常餐饮", app: app)
        let save = app.buttons[prefix + ".confirm"]
        reveal(save, in: app)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "ledger-review-before-save"; shot.lifetime = .keepAlways; add(shot)
        save.tap()
        let category = app.buttons[prefix + ".category"]
        XCTAssertTrue(category.waitForExistence(timeout: 5))
        XCTAssertFalse(save.exists)
        reveal(category, in: app); category.tap()
        XCTAssertEqual(app.textFields["capture.categoryName"].value as? String, "日常餐饮")
        app.buttons["capture.categorySave"].tap()
        app.buttons["ledger.cancel"].tap()
        XCTAssertTrue(app.staticTexts["CNY 35"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["日常餐饮"].exists)
        XCTAssertTrue(app.staticTexts["2026-09-11"].exists)
        app.buttons["记一笔"].tap()
        let undo = app.buttons[prefix + ".undo"]
        reveal(undo, in: app); undo.tap()
        XCTAssertTrue(app.staticTexts["已撤销"].waitForExistence(timeout: 5))
        let next = app.buttons["ledger.new"]
        reveal(next, in: app); next.tap()
        XCTAssertEqual(app.textViews["ledger.input"].value as? String, "")
        XCTAssertFalse(app.staticTexts["核对账单"].exists)
        app.buttons["ledger.cancel"].tap()
        XCTAssertFalse(app.staticTexts["CNY 35"].exists)
    }

    func testUnresolvedBillRequiresAmountCurrencyAndDirection() {
        let app = launch(missing: true)
        organize("午饭花了三十八，不对，是三十五，昨天的", app: app)
        let prefix = "ledger.proposal.unresolved-bill"
        let convert = app.buttons[prefix + ".convert"]
        reveal(convert, in: app); convert.tap()
        let save = app.buttons[prefix + ".confirm"]
        XCTAssertFalse(save.isEnabled)
        let amount = app.textFields[prefix + ".amount"]
        reveal(amount, in: app); amount.tap(); amount.typeText("35")
        dismissKeyboard(app)
        XCTAssertFalse(save.isEnabled)
        let currency = app.textFields[prefix + ".currency"]
        reveal(currency, in: app); currency.tap(); currency.typeText("CNY")
        dismissKeyboard(app)
        XCTAssertFalse(save.isEnabled)
        let direction = app.buttons[prefix + ".direction"]
        reveal(direction, in: app); direction.tap(); app.buttons["支出"].tap()
        reveal(save, in: app); XCTAssertTrue(save.isEnabled); save.tap()
        XCTAssertTrue(app.buttons[prefix + ".category"].waitForExistence(timeout: 5))
        app.buttons["ledger.cancel"].tap()
        XCTAssertTrue(app.staticTexts["CNY 35"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Others"].firstMatch.exists)
    }

    func testOrganizeFailureCanRetryWithoutLosingOriginal() {
        let app = launch(failOnce: true)
        let raw = "午饭 38 CNY"
        let input = app.textViews["ledger.input"]
        input.tap(); input.typeText(raw); dismissKeyboard(app)
        app.buttons["ledger.organize"].tap()
        XCTAssertTrue(app.staticTexts["ledger.error"].waitForExistence(timeout: 5))
        XCTAssertEqual(input.value as? String, raw)
        app.buttons["ledger.organize"].tap()
        XCTAssertTrue(app.staticTexts["核对账单"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["ledger.error"].exists)
        XCTAssertEqual(input.value as? String, raw)
    }
}

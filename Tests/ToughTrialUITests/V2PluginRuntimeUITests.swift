import XCTest

final class V2PluginRuntimeUITests: XCTestCase {
    @MainActor private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TOUGH_TRIAL_UI_TESTING"] = "1"
        app.launchEnvironment["TOUGH_TRIAL_UI_TEST_EMPTY"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["plugins.manage"].waitForExistence(timeout: 10))
        return app
    }
    @MainActor private func toggle(_ id: String, app: XCUIApplication) {
        let control = app.switches[id]
        for _ in 0..<6 where !control.isHittable { app.swipeUp() }
        XCTAssertTrue(control.isHittable, id)
        control.switches.firstMatch.exists ? control.switches.firstMatch.tap()
            : control.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
    }
    @MainActor func testHideAllSurfacesKeepsManagementAndTaskCapability() {
        let app = launch()
        app.buttons["plugins.manage"].tap()
        for id in ["today", "tasks", "assistant", "capture", "recall"] { toggle("plugin.surface.\(id)", app: app) }
        app.buttons["plugins.done"].tap()
        XCTAssertTrue(app.staticTexts["页面已隐藏"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["plugins.manage"].isHittable)
        XCTAssertTrue(app.buttons["plugins.assistant.fallback"].isHittable)
        app.buttons["plugins.manage"].tap()
        let taskSwitch = app.switches["plugin.toggle.tasks"]
        for _ in 0..<4 where !taskSwitch.isHittable { app.swipeUp() }
        XCTAssertTrue(taskSwitch.exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "runtime-page-and-feature-settings"; shot.lifetime = .keepAlways; add(shot)
        for _ in 0..<4 { app.swipeDown() }
        toggle("plugin.surface.tasks", app: app)
        app.buttons["plugins.done"].tap()
        XCTAssertTrue(app.tabBars.buttons["任务"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.tabBars.buttons["今天"].exists)
    }
    @MainActor func testFinanceCanOpenWhileCaptureDisabled() {
        let app = launch()
        app.buttons["plugins.manage"].tap()
        toggle("plugin.toggle.capture", app: app)
        let link = app.buttons["plugin.open.finance"]
        for _ in 0..<8 where !link.isHittable { app.swipeUp() }
        XCTAssertTrue(link.isHittable); link.tap()
        XCTAssertTrue(app.buttons["finance.add"].waitForExistence(timeout: 5))
        app.buttons["finance.add"].tap()
        let title = app.textFields["finance.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5)); title.tap(); title.typeText("Independent Finance")
        app.textFields["finance.amount"].tap(); app.textFields["finance.amount"].typeText("20")
        app.buttons["finance.save"].tap()
        XCTAssertTrue(app.buttons["finance.plan.Independent Finance"].waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "finance-with-capture-disabled"; shot.lifetime = .keepAlways; add(shot)
    }

    @MainActor func testManualLedgerWorksWithCaptureDisabled() {
        let app = launch()
        app.buttons["plugins.manage"].tap()
        toggle("plugin.toggle.capture", app: app)
        let link = app.buttons["plugin.open.ledger"]
        for _ in 0..<10 where !link.isHittable { app.swipeUp() }
        XCTAssertTrue(link.isHittable); link.tap()
        app.buttons["记一笔"].tap()
        let input = app.textViews["ledger.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap(); input.typeText("Independent lunch")
        app.buttons["ledger.dismissKeyboard"].tap()
        let amount = app.textFields["ledger.amount"]
        for _ in 0..<6 where !amount.isHittable { app.scrollViews["ledger.scroll"].swipeUp() }
        amount.tap(); amount.typeText("28")
        app.buttons["ledger.dismissKeyboard"].tap()
        let currency = app.textFields["ledger.currency"]
        for _ in 0..<6 where !currency.isHittable { app.scrollViews["ledger.scroll"].swipeUp() }
        currency.tap(); currency.typeText("CNY")
        app.buttons["ledger.dismissKeyboard"].tap()
        let save = app.buttons["ledger.save"]
        for _ in 0..<6 where !save.isHittable { app.scrollViews["ledger.scroll"].swipeUp() }
        save.tap()
        XCTAssertTrue(app.staticTexts["Independent lunch"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["确认分类"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "independent-ledger"; shot.lifetime = .keepAlways; add(shot)
    }
}

import XCTest

@MainActor
final class V2TodayQueueUITests: XCTestCase {
    func testQueuePauseCompleteRestoreAndCaptureReview() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TOUGH_TRIAL_UI_TEST_EMPTY"] = "1"
        app.launch()
        app.buttons["root.tab.today"].tap()
        XCTAssertTrue(app.buttons["today.emptyZen.startUnlinked"].waitForExistence(timeout: 5))
        capture(app, "today-empty-native")
        for name in ["页面评审", "整理素材", "同步方案"] {
            app.buttons["today.quickAdd"].tap()
            let field = app.textViews["today.quickAdd.document"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap(); field.typeText(name)
            app.buttons["today.quickAdd.submit"].tap()
        }
        start("整理素材", app)
        start("页面评审", app)
        XCTAssertTrue(app.buttons["today.queue.整理素材"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["today.plan.页面评审"].exists)
        capture(app, "today-native")
        app.buttons["today.focus.pause"].tap()
        XCTAssertTrue(app.buttons["today.plan.页面评审"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["today.queue.整理素材"].exists)
        XCTAssertTrue(app.buttons["today.focus.complete"].exists)
        capture(app, "today-paused-native")
        app.buttons["today.focus.complete"].tap()
        let restored = app.buttons["today.restore.整理素材"]
        reveal(restored, app)
        XCTAssertTrue(restored.exists)
        capture(app, "today-completed-native")
        restored.tap()
        XCTAssertFalse(app.buttons["today.restore.整理素材"].exists)
        XCTAssertFalse(app.buttons["today.focus.complete"].exists)
        start("页面评审", app)
        XCTAssertTrue(app.buttons["today.focus.pause"].waitForExistence(timeout: 5))
        app.terminate()
    }

    func testCaptureActualTaskViews() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TOUGH_TRIAL_UI_TESTING"] = "1"
        app.launch()
        app.buttons["root.tab.tasks"].tap()
        for (id, name) in [("list", "tasks-list-native"), ("structure", "tasks-structure-native"), ("time", "tasks-time-native"), ("fishbone", "tasks-fishbone-native")] {
            let button = app.buttons["tasks.lens.\(id)"]
            XCTAssertTrue(button.waitForExistence(timeout: 5), app.debugDescription)
            button.tap()
            capture(app, name)
        }
    }

    func testCaptureOtherActualModulesAndZen() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TOUGH_TRIAL_UI_TESTING"] = "1"
        app.launch()
        for (id, name) in [("assistant", "assistant-native"), ("capture", "capture-native"), ("morePlugins", "more-plugins-native")] {
            app.buttons["root.tab.\(id)"].tap()
            capture(app, name)
        }
        app.buttons["morePlugins.open.recall"].tap()
        capture(app, "recall-native")
        app.terminate(); app.launch()
        app.buttons["root.tab.morePlugins"].tap()
        app.buttons["morePlugins.open.ownProfile"].tap()
        XCTAssertTrue(app.buttons["profile.showQR"].waitForExistence(timeout: 5))
        capture(app, "my-home-native")
        app.buttons["profile.showQR"].tap()
        capture(app, "qr-share-native")
        app.terminate(); app.launch()
        app.buttons["root.tab.today"].tap()
        let direct = app.buttons["today.emptyZen.startUnlinked"]
        if direct.exists {
            direct.tap()
            XCTAssertTrue(app.buttons["zen.close"].waitForExistence(timeout: 5))
            app.buttons["zen.close"].tap()
            app.buttons["today.focus.zen"].tap()
            XCTAssertTrue(app.buttons["zen.finish"].waitForExistence(timeout: 5))
            app.buttons["zen.finish"].tap()
            XCTAssertTrue(direct.waitForExistence(timeout: 5))
        }
    }

    func testQueueFocusSwitchAndFinanceCapture() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TOUGH_TRIAL_UI_TEST_EMPTY"] = "1"
        app.launch()
        app.buttons["root.tab.today"].tap()
        for name in ["甲任务", "乙任务"] {
            app.buttons["today.quickAdd"].tap()
            let field = app.textViews["today.quickAdd.document"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["today.quickAdd.submit"].isEnabled)
            field.tap(); field.typeText(name)
            app.buttons["today.quickAdd.submit"].tap()
            start(name, app)
        }
        app.buttons["today.queue.甲任务"].tap()
        XCTAssertTrue(app.buttons["today.queue.乙任务"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["today.queue.甲任务"].exists)
        app.buttons["today.focus.zen"].tap()
        XCTAssertTrue(app.buttons["zen.close"].waitForExistence(timeout: 5))
        app.buttons["zen.close"].tap()
        app.buttons["today.focus.complete"].tap()
        XCTAssertFalse(app.buttons["today.queue.乙任务"].exists)
        let done = app.buttons["today.restore.甲任务"]
        reveal(done, app); XCTAssertTrue(done.exists)
        app.buttons["root.tab.capture"].tap()
        app.segmentedControls["capture.sections"].buttons["记账"].tap()
        let finance = app.buttons["finance.open"]
        XCTAssertTrue(finance.waitForExistence(timeout: 5)); finance.tap()
        capture(app, "finance-native")
    }

    private func start(_ name: String, _ app: XCUIApplication) {
        let row = app.buttons["today.plan.\(name)"]
        reveal(row, app); row.tap()
        let button = app.buttons["today.start.\(name)"]
        reveal(button, app); button.tap()
    }

    private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<12 {
            let frame = element.exists ? element.frame : .zero
            let viewport = scroll.frame
            if element.exists && element.isHittable && frame.minY >= viewport.minY + 4 && frame.maxY <= viewport.maxY - 100 { return }
            let down = element.exists && frame.minY < viewport.minY + 4
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: down ? 0.3 : 0.7))
            let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: down ? 0.7 : 0.3))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(element.exists && element.isHittable, app.debugDescription)
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        // SwiftUI lens transitions can outlive XCTest's idle heuristic.
        let settled = expectation(description: "Review transition settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { settled.fulfill() }
        wait(for: [settled], timeout: 3)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
    }
}

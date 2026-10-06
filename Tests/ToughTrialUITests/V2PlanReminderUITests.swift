import XCTest

@MainActor
final class V2PlanReminderUITests: XCTestCase {
    func testReminderEmptySetCancelUndoAndClear() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TOUGH_TRIAL_UI_TEST_EMPTY"] = "1"
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        app.buttons["root.tab.today"].tap()
        openReminders(app)
        XCTAssertTrue(app.staticTexts["today.reminders.empty"].waitForExistence(timeout: 5))
        capture(app, "plan-reminders-empty")
        app.buttons["today.reminders.close"].tap()

        app.buttons["today.quickAdd"].tap()
        let document = app.textViews["today.quickAdd.document"]
        XCTAssertTrue(document.waitForExistence(timeout: 5))
        document.tap(); document.typeText("吃早饭")
        XCTAssertEqual(document.value as? String, "吃早饭")
        app.buttons["today.quickAdd.submit"].tap()
        XCTAssertTrue(document.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["today.plan.吃早饭"].waitForExistence(timeout: 5), app.debugDescription)
        openReminders(app)
        let row = app.buttons["today.reminders.plan.吃早饭"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("未设提醒时间"))
        row.tap()
        XCTAssertTrue(app.buttons["today.reminders.save"].waitForExistence(timeout: 5))
        try advanceMinute(app)
        capture(app, "plan-reminder-time-editor")
        app.buttons["today.reminders.cancel"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("未设提醒时间"))

        row.tap()
        try advanceMinute(app)
        app.buttons["today.reminders.save"].tap()
        allowNotificationsIfAsked(app)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertFalse(row.label.contains("未设提醒时间"))
        XCTAssertTrue(app.staticTexts["today.reminders.feedback"].waitForExistence(timeout: 5))
        capture(app, "plan-reminder-saved")
        app.buttons["today.reminders.undo"].tap()
        XCTAssertTrue(row.label.contains("未设提醒时间"))
        XCTAssertEqual(app.staticTexts["today.reminders.feedback"].label, "已撤销时间修改。")

        row.tap()
        app.buttons["today.reminders.save"].tap()
        allowNotificationsIfAsked(app)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let plannedLabel = row.label
        let dayRange = try XCTUnwrap(plannedLabel.range(of: #"\d+月\d+日"#, options: .regularExpression))
        let plannedDay = String(plannedLabel[dayRange])
        row.tap()
        app.buttons["today.reminders.clear"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("未设提醒时间"))
        XCTAssertTrue(row.label.contains(plannedDay), "清除时间必须保留计划日期，深夜设置的提醒可能属于明天")
        app.buttons["today.reminders.close"].tap()
        XCTAssertTrue(app.buttons["today.options"].waitForExistence(timeout: 5))
        openReminders(app)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains(plannedDay))
        XCTAssertTrue(row.label.contains("未设提醒时间"))
        app.buttons["today.reminders.close"].tap()
        app.terminate()
    }

    private func openReminders(_ app: XCUIApplication) {
        app.buttons["today.options"].tap()
        let entry = app.buttons["today.reminders.open"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        XCTAssertTrue(app.buttons["today.reminders.close"].waitForExistence(timeout: 5))
    }

    private func advanceMinute(_ app: XCUIApplication) throws {
        let wheels = app.pickerWheels
        XCTAssertEqual(wheels.count, 3, app.debugDescription)
        let minute = wheels.element(boundBy: 2)
        let current = try XCTUnwrap(minute.value as? String)
        let range = try XCTUnwrap(current.range(of: #"\d+"#, options: .regularExpression))
        let number = try XCTUnwrap(Int(current[range]))
        let replacement = current[range].count == 2 ? String(format: "%02d", (number + 1) % 60) : String((number + 1) % 60)
        minute.adjust(toPickerWheelValue: replacement)
        let changed = try XCTUnwrap(minute.value as? String)
        let changedRange = try XCTUnwrap(changed.range(of: #"\d+"#, options: .regularExpression))
        XCTAssertEqual(Int(changed[changedRange]), (number + 1) % 60)
    }

    private func allowNotificationsIfAsked(_ app: XCUIApplication) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        if alert.waitForExistence(timeout: 2) {
            let allow = alert.buttons.matching(NSPredicate(format: "label == '允许' OR label == 'Allow'")).firstMatch
            if allow.exists { allow.tap() }
        }
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name; image.lifetime = .keepAlways
        add(image)
    }
}

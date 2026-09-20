import XCTest

/// Opt-in UI acceptance against the installed app's real model and persistent data.
final class ToughTrialDeviceScheduleTests: XCTestCase {
    @MainActor
    func testRealTodayLookupReturnsAnswer() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Physical device acceptance")
        #else
        guard ProcessInfo.processInfo.environment["TOUGH_TRIAL_DEVICE_SCHEDULE"] == "1" else {
            throw XCTSkip("Explicit physical schedule opt-in required")
        }
        let app = XCUIApplication()
        app.launchEnvironment["TOUGH_TRIAL_UI_TESTING"] = "0"
        app.launchEnvironment["TOUGH_TRIAL_UI_TEST_EMPTY"] = "0"
        app.launchEnvironment["TOUGH_TRIAL_DEVICE_KEEP_AWAKE"] = "1"
        app.launch()
        openAssistant(app)
        app.buttons["assistant.newSession"].tap()
        send("帮我看看我今天还有什么任务。", app: app)
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["assistant.cancel"])
        XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 90), .completed)
        XCTAssertFalse(app.staticTexts["没有收到可用回复"].exists)
        XCTAssertFalse(app.buttons["schedule.undo"].exists)
        XCTAssertFalse(app.buttons["schedule.confirm"].exists)
        capture("device-real-today-lookup", app: app)
        print("DEVICE_TODAY_LOOKUP_UI_COMPLETED")
        app.buttons["assistant.speech.settings"].tap()
        let picker = app.segmentedControls["speech.settings.provider"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        let originalApple = picker.buttons["苹果原生"].isSelected
        picker.buttons["苹果原生"].tap()
        XCTAssertTrue(app.buttons["speech.settings.prepareApple"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.secureTextFields["speech.settings.apiKey"].exists)
        capture("device-apple-speech-switch", app: app)
        if !originalApple { picker.buttons["阿里云 FunASR"].tap() }
        app.buttons["关闭"].tap()
        print("DEVICE_APPLE_SPEECH_SWITCH_AVAILABLE original_restored=true")
        #endif
    }

    @MainActor
    func testRealSchedulePersistsAcrossProcessRelaunchAndCanUndo() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Physical device acceptance")
        #else
        guard ProcessInfo.processInfo.environment["TOUGH_TRIAL_DEVICE_SCHEDULE"] == "1" else {
            throw XCTSkip("Explicit physical schedule opt-in required")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TOUGH_TRIAL_UI_TESTING"] = "0"
        app.launchEnvironment["TOUGH_TRIAL_UI_TEST_EMPTY"] = "0"
        app.launchEnvironment["TOUGH_TRIAL_DEVICE_KEEP_AWAKE"] = "1"
        app.launch()
        openAssistant(app)
        let originalStrict = setStrict(false, app: app)
        defer { _ = setStrict(originalStrict, app: app) }

        let title = "真机界面验收" + String(UUID().uuidString.prefix(8))
        app.buttons["assistant.newSession"].tap()
        send("请立即新增一个待办，标题严格为“\(title)”，备注是“保留 3 个示例，必须配图，总共最多 2 小时”。不要安排日期，不要修改其他任务。", app: app)
        XCTAssertTrue(app.buttons["schedule.undo"].waitForExistence(timeout: 90))
        XCTAssertTrue(app.staticTexts["日程已更新"].exists)
        let detail = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", title, "配图")).firstMatch
        XCTAssertTrue(detail.exists)
        XCTAssertTrue(detail.label.contains("3"))
        XCTAssertTrue(detail.label.contains("2"))
        capture("device-real-schedule-applied", app: app)

        app.tabBars.firstMatch.buttons["任务"].tap()
        XCTAssertTrue(app.staticTexts[title].firstMatch.waitForExistence(timeout: 10))
        app.terminate()
        app.launch()
        openAssistant(app)
        XCTAssertTrue(app.buttons["schedule.undo"].waitForExistence(timeout: 15), "Receipt must survive a real process restart")
        app.buttons["schedule.undo"].tap()
        XCTAssertTrue(app.staticTexts["已撤销"].waitForExistence(timeout: 10))
        app.tabBars.firstMatch.buttons["任务"].tap()
        XCTAssertFalse(app.staticTexts[title].firstMatch.exists)
        openAssistant(app)

        _ = setStrict(true, app: app)
        app.buttons["assistant.newSession"].tap()
        let strictTitle = title + "严格确认"
        send("请立即新增一个待办，标题严格为“\(strictTitle)”。不要安排日期，不要修改其他任务。", app: app)
        XCTAssertTrue(app.buttons["schedule.confirm"].waitForExistence(timeout: 90))
        XCTAssertFalse(app.staticTexts["日程已更新"].exists)
        app.tabBars.firstMatch.buttons["任务"].tap()
        XCTAssertFalse(app.staticTexts[strictTitle].firstMatch.exists)
        app.terminate()
        app.launch()
        openAssistant(app)
        XCTAssertTrue(app.buttons["schedule.confirm"].waitForExistence(timeout: 15))
        capture("device-real-schedule-pending-after-relaunch", app: app)
        app.buttons["schedule.confirm"].tap()
        XCTAssertTrue(app.buttons["schedule.undo"].waitForExistence(timeout: 10))
        app.buttons["schedule.undo"].tap()
        XCTAssertTrue(app.staticTexts["已撤销"].waitForExistence(timeout: 10))
        capture("device-real-schedule-undone", app: app)
        print("DEVICE_SCHEDULE_UI_ACCEPTANCE real_model=true process_relaunches=2 strict=true undo=true")
        #endif
    }

    @MainActor
    private func openAssistant(_ app: XCUIApplication) {
        let tab = app.tabBars.firstMatch.buttons["助手"]
        XCTAssertTrue(tab.waitForExistence(timeout: 15))
        tab.tap()
        XCTAssertTrue(app.buttons["assistant.newSession"].waitForExistence(timeout: 10))
    }

    @MainActor
    private func setStrict(_ enabled: Bool, app: XCUIApplication) -> Bool {
        app.buttons["assistant.more"].tap()
        app.buttons["assistant.schedule.settings"].tap()
        let toggle = app.switches["schedule.requiresConfirmation"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        let previous = toggle.value as? String == "1"
        if previous != enabled { toggle.tap() }
        app.navigationBars["日程修改"].buttons["完成"].tap()
        return previous
    }

    @MainActor
    private func send(_ text: String, app: XCUIApplication) {
        let composer = app.textViews["assistant.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        composer.tap()
        composer.typeText(text)
        app.buttons["assistant.send"].tap()
    }

    @MainActor
    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

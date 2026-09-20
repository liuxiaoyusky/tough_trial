import XCTest

@MainActor
final class V2UnifiedTaskInputUITests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false }

    func testTodayAddsNoteAndOffersExplicitDictationWithoutLosingDraft() {
        let app = XCUIApplication()
        app.launchEnvironment["TOUGH_TRIAL_UI_TEST_EMPTY"] = "1"
        app.launch()
        app.tabBars.buttons["今天"].tap()
        app.buttons["today.quickAdd"].tap()
        let document = app.textViews["today.quickAdd.document"]
        XCTAssertTrue(document.waitForExistence(timeout: 3))
        document.tap(); document.typeText("今日统一输入\n今日备注不会丢失")
        let mic = app.buttons["today.quickAdd.speech.start"]
        XCTAssertTrue(mic.exists, "Dictation must be discoverable in the editor")
        let editorShot = XCTAttachment(screenshot: app.screenshot())
        editorShot.name = "unified-task-editor"; editorShot.lifetime = .keepAlways; add(editorShot)
        app.buttons["today.quickAdd.cancel"].tap()
        app.buttons["继续编辑"].tap()
        XCTAssertEqual(document.value as? String, "今日统一输入\n今日备注不会丢失")
        app.buttons["today.quickAdd.submit"].tap()
        XCTAssertTrue(app.staticTexts["今日统一输入"].firstMatch.waitForExistence(timeout: 3))
        app.tabBars.buttons["任务"].tap()
        app.buttons["今日统一输入"].tap()
        XCTAssertEqual(app.buttons["tasks.detail.note"].label, "今日备注不会丢失")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "unified-today-saved-note"; screenshot.lifetime = .keepAlways; add(screenshot)
    }

    func testTimeUsesSameEditorAndPreservesSelectedSchedule() {
        let app = XCUIApplication()
        app.launchEnvironment["TOUGH_TRIAL_UI_TEST_EMPTY"] = "1"
        app.launch()
        app.tabBars.buttons["任务"].tap()
        app.buttons["tasks.lens.time"].tap()
        app.buttons["tasks.capture.open"].tap()
        let document = app.textViews["tasks.timeCapture.document"]
        XCTAssertTrue(document.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["tasks.timeCapture.submit"].isEnabled)
        document.tap(); document.typeText("时间入口统一新增\n按选中日期安排")
        app.buttons["tasks.timeCapture.submit"].tap()
        app.buttons["tasks.lens.list"].tap()
        app.buttons["时间入口统一新增"].tap()
        XCTAssertEqual(app.buttons["tasks.detail.note"].label, "按选中日期安排")
    }
    func testQuickCaptureCancelKeepsOriginalAndCanSaveLongNote() {
        let app = XCUIApplication()
        app.launchEnvironment["TOUGH_TRIAL_UI_TESTING"] = "1"
        app.launchEnvironment["TOUGH_TRIAL_UI_TEST_EMPTY"] = "1"
        app.launchEnvironment["TOUGH_TRIAL_UI_TEST_QUICK_URL"] = "toughtrial://capture/task"
        app.launch()
        let document = app.textViews["quick.task.document"]
        XCTAssertTrue(document.waitForExistence(timeout: 5))
        let content = "开头" + String(repeating: "这是一段需要完整保留的任务备注。", count: 65) + "结尾"
        let taskDocument = "快捷长备注\n" + content
        document.tap(); document.typeText(taskDocument)
        XCTAssertEqual(document.value as? String, taskDocument)
        app.buttons["quick.task.cancel"].tap()
        app.buttons["继续编辑"].tap()
        XCTAssertEqual(document.value as? String, taskDocument)
        app.buttons["quick.task.save"].tap()
        app.tabBars.buttons["任务"].tap()
        app.buttons["快捷长备注"].tap()
        XCTAssertEqual(app.buttons["tasks.detail.note"].label, content)
    }

    func testDeniedMicrophoneKeepsDraftAndAllowsManualSave() {
        let app = XCUIApplication()
        app.resetAuthorizationStatus(for: .microphone)
        app.launchEnvironment["TOUGH_TRIAL_UI_TEST_EMPTY"] = "1"
        app.launch()
        app.tabBars.buttons["任务"].tap()
        app.buttons["tasks.capture.open"].tap()
        let document = app.textViews["tasks.capture.document"]
        XCTAssertTrue(document.waitForExistence(timeout: 3))
        document.tap(); document.typeText("拒绝麦克风仍可保存\n保留键盘草稿")
        app.swipeUp()
        let settings = app.buttons["tasks.capture.speech.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 3)); settings.tap()
        app.segmentedControls.buttons["苹果原生"].tap()
        app.buttons["关闭"].tap()
        app.buttons["tasks.capture.speech.start"].tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let permission = springboard.alerts.firstMatch
        if permission.waitForExistence(timeout: 3) {
            let deny = permission.buttons.matching(NSPredicate(format: "label IN %@", ["不允许", "Don't Allow", "Don’t Allow"])).firstMatch
            XCTAssertTrue(deny.exists, springboard.debugDescription); deny.tap()
        }
        let error = app.staticTexts["tasks.capture.speech.error"]
        XCTAssertTrue(error.waitForExistence(timeout: 8))
        XCTAssertTrue(error.label.contains("麦克风"))
        XCTAssertTrue(app.buttons["tasks.capture.submit"].isEnabled)
        app.buttons["tasks.capture.submit"].tap()
        app.buttons["拒绝麦克风仍可保存"].tap()
        XCTAssertEqual(app.buttons["tasks.detail.note"].label, "保留键盘草稿")
    }

}

import XCTest

final class ToughTrialScheduleFileTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    @MainActor
    func testFileTraceLinksImportAndRecoveryWithoutContent() throws {
        let app = XCUIApplication()
        app.launchEnvironment["TOUGH_TRIAL_UI_TESTING"] = "1"
        app.launchEnvironment["TOUGH_TRIAL_UI_FILE_FIXTURE"] = UUID().uuidString
        app.launchEnvironment["TOUGH_TRIAL_UI_FILE_MODE"] = "seed"
        app.launch()
        openFiles(app)
        app.buttons["schedule.file.read"].tap()
        expectFileStatus("已读取文件中的更改。", in: app)
        let version = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'schedule.file.version.'")).firstMatch
        XCTAssertTrue(version.waitForExistence(timeout: 5))
        let operationID = String(version.identifier.dropFirst("schedule.file.version.".count))
        XCTAssertFalse(operationID.isEmpty)
        version.tap()
        app.buttons["恢复此前内容"].tap()
        expectFileStatus("已恢复此前内容，可写回文件。", in: app)
        closeFiles(app)
        app.buttons["assistant.more"].tap()
        app.buttons["assistant.trace"].tap()
        XCTAssertTrue(app.buttons["trace.export"].waitForExistence(timeout: 5))
        app.buttons["trace.export"].tap()
        let json = app.staticTexts["trace.export.json"]
        XCTAssertTrue(json.waitForExistence(timeout: 5))
        let events = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.label.utf8)) as? [[String: Any]])
        let fileEvents = events.filter { $0["source"] as? String == "manual" }
        XCTAssertEqual(fileEvents.count, 2)
        XCTAssertEqual(fileEvents.map { $0["kind"] as? String }, ["syncFinished", "scheduleUndone"])
        for event in fileEvents {
            XCTAssertEqual(event["operationID"] as? String, operationID)
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(event["duration"] as? Double), 0)
        }
        XCTAssertFalse(json.label.contains("电脑修改后的任务"))
        XCTAssertFalse(json.label.contains("文件原始任务"))
        XCTAssertFalse(json.label.contains("日程.md"))
    }

    @MainActor
    func testReadWriteRelaunchAndRecoverThroughUI() {
        let app = XCUIApplication()
        app.launchEnvironment["TOUGH_TRIAL_UI_TESTING"] = "1"
        app.launchEnvironment["TOUGH_TRIAL_UI_FILE_FIXTURE"] = UUID().uuidString
        app.launchEnvironment["TOUGH_TRIAL_UI_FILE_MODE"] = "seed"
        app.launch()
        openFiles(app)
        app.buttons["schedule.file.read"].tap()
        expectFileStatus("已读取文件中的更改。", in: app)
        closeFiles(app)
        expectTask("电脑修改后的任务", in: app)

        app.tabBars.firstMatch.buttons["助手"].tap()
        let composer = app.textViews["assistant.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        composer.tap()
        composer.typeText("新增测试任务")
        app.buttons["assistant.send"].tap()
        XCTAssertTrue(app.staticTexts["日程已更新"].waitForExistence(timeout: 8))
        openFiles(app)
        app.buttons["schedule.file.write"].tap()
        expectFileStatus("已合并并写回文件。", in: app)

        app.terminate()
        app.launchEnvironment["TOUGH_TRIAL_UI_FILE_MODE"] = "readback"
        app.launch()
        expectTask("文件原始任务", in: app)
        expectTask("日程执行测试", in: app, exists: false)
        openFiles(app)
        app.buttons["schedule.file.read"].tap()
        expectFileStatus("已读取文件中的更改。", in: app)
        closeFiles(app)
        expectTask("电脑修改后的任务", in: app)
        expectTask("日程执行测试", in: app)

        openFiles(app)
        let version = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'schedule.file.version.'")).firstMatch
        XCTAssertTrue(version.waitForExistence(timeout: 5))
        version.tap()
        app.buttons["恢复此前内容"].tap()
        expectFileStatus("已恢复此前内容，可写回文件。", in: app)
        closeFiles(app)
        expectTask("文件原始任务", in: app)
        expectTask("日程执行测试", in: app, exists: false)

        app.terminate()
        app.launchEnvironment["TOUGH_TRIAL_UI_FILE_MODE"] = "resume"
        app.launch()
        expectTask("文件原始任务", in: app)
        expectTask("电脑修改后的任务", in: app, exists: false)
        expectTask("日程执行测试", in: app, exists: false)
        openFiles(app)
        XCTAssertTrue(app.staticTexts["有本地更改待写回"].exists)
    }

    @MainActor
    private func openFiles(_ app: XCUIApplication) {
        if !app.buttons["assistant.more"].isHittable {
            app.tabBars.firstMatch.buttons["助手"].tap()
        }
        XCTAssertTrue(app.buttons["assistant.more"].waitForExistence(timeout: 5))
        app.buttons["assistant.more"].tap()
        app.buttons["assistant.schedule.files"].tap()
        XCTAssertTrue(app.navigationBars["日程文件"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func closeFiles(_ app: XCUIApplication) {
        app.navigationBars["日程文件"].buttons["完成"].tap()
    }

    @MainActor
    private func expectFileStatus(_ text: String, in app: XCUIApplication) {
        let status = app.staticTexts["schedule.file.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 8))
        XCTAssertEqual(status.label, text)
        XCTAssertFalse(app.staticTexts["schedule.file.error"].exists)
    }

    @MainActor
    private func expectTask(_ title: String, in app: XCUIApplication, exists: Bool = true) {
        if app.buttons["assistant.exit"].isHittable { app.tabBars.firstMatch.buttons["今天"].tap() }
        app.tabBars.firstMatch.buttons["今天"].tap()
        let picker = app.buttons["today.emptyZen.chooseTask"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()
        let search = app.textFields["today.zenTaskPicker.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.tap()
        search.typeText(title)
        if exists {
            XCTAssertTrue(app.buttons["开始 \(title) 的 Zen"].waitForExistence(timeout: 3))
        } else {
            XCTAssertTrue(app.staticTexts["没有找到任务"].waitForExistence(timeout: 3))
        }
        app.buttons["today.zenTaskPicker.cancel"].tap()
        XCTAssertTrue(search.waitForNonExistence(timeout: 3))
    }

    @MainActor
    func testFileEntryOpensSystemPickerAndCanCancel() {
        let app = XCUIApplication()
        app.launchEnvironment["TOUGH_TRIAL_UI_TESTING"] = "1"
        app.launch()
        app.tabBars.firstMatch.buttons["助手"].tap()
        XCTAssertTrue(app.buttons["assistant.more"].waitForExistence(timeout: 5))
        app.buttons["assistant.more"].tap()
        app.buttons["assistant.schedule.files"].tap()
        XCTAssertTrue(app.navigationBars["日程文件"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["schedule.file.export"].exists)
        app.buttons["schedule.file.import"].tap()
        let cancel = app.buttons.matching(NSPredicate(format: "label == '取消' OR label == 'Cancel'")).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 8))
        cancel.tap()
        XCTAssertTrue(app.buttons["schedule.file.import"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["schedule.file.error"].exists)
        app.navigationBars["日程文件"].buttons["完成"].tap()
        XCTAssertTrue(app.buttons["assistant.more"].waitForExistence(timeout: 5))
    }
}

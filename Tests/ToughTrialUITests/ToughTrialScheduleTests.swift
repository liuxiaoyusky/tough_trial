import XCTest

final class ToughTrialScheduleTests: XCTestCase {
    @MainActor
    func testSavedTaskCheckboxCompletesAndRestoresTheActualTodayTask() {
        let app = launch(strict: false)
        sendRequest(app, text: "新增任务：今天整理文件")
        let toggle = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "schedule.task.toggle.")).firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 8), "A checkbox-shaped element must be an operable control")
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "已完成")
        app.tabBars.buttons["今天"].tap()
        XCTAssertTrue(app.buttons["恢复为未完成"].firstMatch.waitForExistence(timeout: 5))
        app.tabBars.buttons["助手"].tap()
        XCTAssertEqual(toggle.value as? String, "已完成")
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "待办")
        app.buttons["schedule.undo"].tap()
        XCTAssertTrue(app.staticTexts["已撤销"].waitForExistence(timeout: 5))
        XCTAssertFalse(toggle.exists)
    }

    @MainActor
    func testCardEditorCancelDateControlsAndSavedAdjustmentAreClickable() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TOUGH_TRIAL_UI_TESTING"] = "1"
        app.launchEnvironment["TOUGH_TRIAL_UI_TEST_EMPTY"] = "1"
        app.launchEnvironment["TOUGH_TRIAL_UI_TEST_TASK_CARDS"] = "1"
        app.launch()
        sendRequest(app, text: "今天要做三件事，整理文件、学习、准备演示")
        let edit = app.buttons["schedule.task.edit.ui-task-0"]
        XCTAssertTrue(edit.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "schedule.task.toggle.")).firstMatch.exists)
        edit.tap()
        let document = app.textViews["schedule.task.document"]
        XCTAssertTrue(document.waitForExistence(timeout: 3))
        document.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.05)).tap()
        document.typeText("不保存的修改")
        app.buttons["schedule.task.cancelEditing"].tap()
        app.buttons["放弃修改"].tap()
        XCTAssertFalse(app.staticTexts["整理电脑文件不保存的修改"].exists)
        edit.tap()
        let scheduled = app.switches["schedule.task.scheduled"]
        XCTAssertTrue(scheduled.waitForExistence(timeout: 3))
        scheduled.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertTrue(scheduled.waitForValue("0", timeout: 3))
        let hiddenDate = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.datePickers["schedule.task.date"])
        wait(for: [hiddenDate], timeout: 3)
        scheduled.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertTrue(scheduled.waitForValue("1", timeout: 3))
        let date = app.datePickers["schedule.task.date"]
        XCTAssertTrue(date.waitForExistence(timeout: 3))
        date.tap()
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "task-date-picker-open"; shot.lifetime = .keepAlways; add(shot)
        // The system calendar intercepts outside touches to dismiss its popover.
        app.staticTexts["修改只更新这张待确认卡片，确认保存后才加入任务。"]
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["schedule.task.cancelEditing"].tap()
        let editorClosed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: document)
        wait(for: [editorClosed], timeout: 3)
        if !app.buttons["schedule.confirm"].isHittable { app.swipeUp() }
        app.buttons["schedule.confirm"].tap()
        XCTAssertTrue(app.staticTexts["已保存"].waitForExistence(timeout: 5))
        let adjust = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "schedule.task.edit.")).firstMatch
        if !adjust.isHittable { app.swipeDown() }
        adjust.tap()
        let instruction = app.descendants(matching: .any).matching(identifier: "schedule.task.adjustment").firstMatch
        XCTAssertTrue(instruction.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["schedule.task.save"].isEnabled)
        app.buttons["schedule.task.cancelEditing"].tap()
        adjust.tap()
        instruction.tap(); instruction.typeText("把备注改成修改后备注")
        app.buttons["schedule.task.save"].tap()
        XCTAssertTrue(app.staticTexts["待办 · 整理电脑文件\n修改后备注"].firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["修改已保存。"].firstMatch.waitForExistence(timeout: 8))
    }

    @MainActor
    func testThreeTaskCardsCanEditConfirmViewTodayAndUndo() {
        let app = XCUIApplication()
        app.launchEnvironment["TOUGH_TRIAL_UI_TESTING"] = "1"
        app.launchEnvironment["TOUGH_TRIAL_UI_TEST_EMPTY"] = "1"
        app.launchEnvironment["TOUGH_TRIAL_UI_TEST_TASK_CARDS"] = "1"
        app.launch()
        sendRequest(app, text: "今天要做三件事，第一整理文件，第二学习，第三准备演示")
        let edit = app.buttons["schedule.task.edit.ui-task-0"]
        XCTAssertTrue(edit.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["3 件待办"].exists)
        edit.tap()
        let document = app.textViews["schedule.task.document"]
        XCTAssertTrue(document.waitForExistence(timeout: 3))
        replaceDocument(document, with: "")
        XCTAssertFalse(app.buttons["schedule.task.save"].isEnabled)
        replaceDocument(document, with: "整理素材目录\n保留源文件和输入细节【已核对】")
        XCTAssertEqual(document.value as? String, "整理素材目录\n保留源文件和输入细节【已核对】")
        app.buttons["schedule.task.save"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "【已核对】")).firstMatch.waitForExistence(timeout: 3))
        let confirm = app.buttons["schedule.confirm"]
        if !confirm.isHittable { app.swipeUp() }
        XCTAssertTrue(confirm.waitForExistence(timeout: 3)); confirm.tap()
        XCTAssertTrue(app.staticTexts["已保存"].waitForExistence(timeout: 5))
        keepScreenshot(app, name: "three-saved-task-cards")
        app.tabBars.buttons["今天"].tap()
        XCTAssertTrue(app.staticTexts["整理素材目录"].firstMatch.waitForExistence(timeout: 5))
        app.tabBars.buttons["助手"].tap()
        let undo = app.buttons["schedule.undo"]
        let conversation = app.scrollViews["assistant.conversation"]
        // The scroll view extends behind the fixed composer; isHittable alone
        // can report controls in that covered area. Scroll within the visible conversation.
        for _ in 0..<4 {
            let bottom = app.buttons["assistant.model.selection"].firstMatch.frame.minY
            if undo.frame.maxY < bottom && undo.frame.minY > conversation.frame.minY { break }
            let origin = conversation.coordinate(withNormalizedOffset: .zero)
            let height = bottom - conversation.frame.minY
            origin.withOffset(CGVector(dx: conversation.frame.width / 2, dy: height * 0.85))
                .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: conversation.frame.width / 2, dy: height * 0.2)))
        }
        undo.tap()
        app.tabBars.buttons["今天"].tap()
        XCTAssertTrue(app.staticTexts["整理素材目录"].firstMatch.waitForNonExistence(timeout: 5))
        app.tabBars.buttons["助手"].tap()
        if !app.staticTexts["已撤销"].exists { app.swipeDown() }
        XCTAssertTrue(app.staticTexts["已撤销"].waitForExistence(timeout: 5), app.debugDescription)
    }

    @MainActor
    func testScheduleShowsProgressAndCanCancelBeforeWriting() {
        let app = launch(strict: false, slow: true)
        sendRequest(app, text: "新增测试任务")
        XCTAssertTrue(app.staticTexts["正在理解你的意思…"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["进行中 0 个步骤"].exists)
        keepScreenshot(app, name: "assistant-thinking")
        XCTAssertTrue(app.staticTexts["正在整理日程…"].waitForExistence(timeout: 8))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "schedule-progress"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["assistant.cancel"].tap()
        XCTAssertTrue(app.staticTexts["操作已取消。"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["正在整理日程…"].exists)
        XCTAssertFalse(app.staticTexts["已保存"].exists)
        XCTAssertFalse(app.buttons["schedule.undo"].exists)
        keepScreenshot(app, name: "assistant-cancelled")
    }

    @MainActor
    func testRequestedScheduleAppliesAndCanUndo() {
        let app = launch(strict: false)
        sendRequest(app)
        XCTAssertTrue(app.staticTexts["已保存"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.otherElements["assistant.progress"].exists)
        XCTAssertTrue(app.staticTexts["日程执行测试"].firstMatch.exists)
        keepScreenshot(app, name: "assistant-schedule-result")
        app.buttons["schedule.undo"].tap()
        XCTAssertTrue(app.staticTexts["已撤销"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["schedule.undo"].exists)
    }

    @MainActor
    func testStrictScheduleCanCancelThenConfirm() {
        let app = launch(strict: true)
        sendRequest(app)
        XCTAssertTrue(app.buttons["schedule.confirm"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["已保存"].exists)
        keepScreenshot(app, name: "assistant-confirmation")
        app.buttons["schedule.cancel"].tap()
        XCTAssertTrue(app.staticTexts["已取消"].waitForExistence(timeout: 3))
        sendRequest(app)
        XCTAssertTrue(app.buttons["schedule.confirm"].waitForExistence(timeout: 8))
        app.buttons["schedule.confirm"].tap()
        XCTAssertTrue(app.staticTexts["已保存"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["schedule.undo"].exists)
    }

    @MainActor
    private func keepScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func launch(strict: Bool, slow: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TOUGH_TRIAL_UI_TESTING"] = "1"
        if slow { app.launchEnvironment["TOUGH_TRIAL_UI_TEST_SLOW_SCHEDULE"] = "1" }
        if strict { app.launchEnvironment["TOUGH_TRIAL_UI_TEST_STRICT_SCHEDULE"] = "1" }
        app.launch()
        app.tabBars.firstMatch.buttons["助手"].tap()
        return app
    }

    @MainActor
    private func sendRequest(_ app: XCUIApplication, text: String = "新增任务：测试任务") {
        app.tabBars.firstMatch.buttons["助手"].tap()
        let composer = app.textViews["assistant.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        composer.tap()
        composer.typeText(text)
        app.buttons["assistant.send"].tap()
    }
}

@MainActor
private func replaceDocument(_ document: XCUIElement, with value: String) {
    document.tap()
    if let current = document.value as? String, !current.isEmpty {
        document.press(forDuration: 1)
        let selectAll = XCUIApplication().descendants(matching: .any).matching(NSPredicate(format: "label == '全选' OR label == 'Select All'")).firstMatch
        XCTAssertTrue(selectAll.waitForExistence(timeout: 3))
        selectAll.tap()
    }
    document.typeText(value.isEmpty ? XCUIKeyboardKey.delete.rawValue : value)
}

private extension XCUIElement {
    func waitForValue(_ expected: String, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", expected), object: self)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}

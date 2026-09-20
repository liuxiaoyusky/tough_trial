import XCTest

@MainActor
final class V2TaskDocumentUITests: XCTestCase {
    func testReturnContinuesIntoBodyAndSavesWithoutSwitchingFields() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TOUGH_TRIAL_UI_TEST_EMPTY"] = "1"
        app.launch()
        app.tabBars.buttons["今天"].tap()
        app.buttons["today.quickAdd"].tap()
        let document = app.textViews["today.quickAdd.document"]
        XCTAssertTrue(document.waitForExistence(timeout: 3))
        document.tap()
        document.typeText("整理旅行照片\n挑出十张喜欢的照片\n\n周末和家人一起看")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "document-task-with-body"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.buttons["today.quickAdd.submit"].tap()
        app.tabBars.buttons["任务"].tap()
        let task = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "整理旅行照片")).firstMatch
        XCTAssertTrue(task.waitForExistence(timeout: 3)); task.tap()
        XCTAssertEqual(app.buttons["tasks.detail.title"].label, "整理旅行照片")
        XCTAssertEqual(app.buttons["tasks.detail.note"].label, "挑出十张喜欢的照片\n\n周末和家人一起看")
    }
    func testTitleOnlyCanSaveAndDiscardedBodyDoesNotChangeTheTask() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TOUGH_TRIAL_UI_TEST_EMPTY"] = "1"
        app.launch()
        app.tabBars.buttons["任务"].tap()
        app.buttons["tasks.capture.open"].tap()
        let document = app.textViews["tasks.capture.document"]
        XCTAssertTrue(document.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["tasks.capture.submit"].isEnabled)
        document.tap(); document.typeText("买牛奶")
        app.buttons["tasks.capture.dismissKeyboard"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        app.buttons["tasks.capture.submit"].tap()
        app.buttons["买牛奶"].tap()
        XCTAssertEqual(app.buttons["tasks.detail.title"].label, "买牛奶")
        XCTAssertFalse(app.buttons["tasks.detail.note"].exists)
        app.buttons["tasks.detail.title"].tap()
        let edit = app.textViews["tasks.editor.document"]
        XCTAssertEqual(edit.value as? String, "买牛奶")
        edit.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.05)).tap()
        edit.typeText("\n只在草稿中添加的细节")
        app.buttons["tasks.editor.cancel"].tap()
        app.buttons["继续编辑"].tap()
        XCTAssertEqual(edit.value as? String, "买牛奶\n只在草稿中添加的细节")
        app.buttons["tasks.editor.cancel"].tap()
        app.buttons["放弃修改"].tap()
        XCTAssertEqual(app.buttons["tasks.detail.title"].label, "买牛奶")
        XCTAssertFalse(app.buttons["tasks.detail.note"].exists)
    }

    func testBodyWithoutTitleShowsReasonAndCanBeCorrectedInPlace() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TOUGH_TRIAL_UI_TEST_EMPTY"] = "1"
        app.launch()
        app.tabBars.buttons["任务"].tap()
        app.buttons["tasks.capture.open"].tap()
        let document = app.textViews["tasks.capture.document"]
        XCTAssertTrue(document.waitForExistence(timeout: 3))
        document.typeText("\n准备需要带的物品")
        XCTAssertFalse(app.buttons["tasks.capture.submit"].isEnabled)
        XCTAssertTrue(app.staticTexts["tasks.capture.validation"].exists)
        document.press(forDuration: 1)
        let selectAll = app.descendants(matching: .any).matching(NSPredicate(format: "label == '全选' OR label == 'Select All'")).firstMatch
        XCTAssertTrue(selectAll.waitForExistence(timeout: 3), app.debugDescription)
        selectAll.tap()
        document.typeText("准备行李\n准备需要带的物品")
        XCTAssertEqual(document.value as? String, "准备行李\n准备需要带的物品")
        XCTAssertTrue(app.buttons["tasks.capture.submit"].isEnabled)
        app.buttons["tasks.capture.submit"].tap()
        app.buttons["准备行李"].tap()
        XCTAssertEqual(app.buttons["tasks.detail.note"].label, "准备需要带的物品")
    }

}

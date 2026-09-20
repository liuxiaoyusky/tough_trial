import XCTest

@MainActor
final class V2TaskEditorUITests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false }

    func testTaskDetailsCanEditCancelSaveAndComplete() {
        let app = XCUIApplication()
        app.launchEnvironment["TOUGH_TRIAL_UI_TESTING"] = "1"
        app.launch()
        app.tabBars.firstMatch.buttons["任务"].tap()
        XCTAssertTrue(app.buttons["建立稳定创作系统"].exists)
        XCTAssertTrue(app.buttons["定位"].exists, "Child tasks must be directly available in the flat list")
        XCTAssertEqual(app.buttons["建立稳定创作系统"].frame.minX, app.buttons["定位"].frame.minX, accuracy: 1)
        app.buttons["定位"].tap()
        let edit = app.buttons["tasks.detail.title"]
        XCTAssertTrue(edit.waitForExistence(timeout: 3), "Task details must offer direct editing")
        edit.tap()
        let document = app.textViews["tasks.editor.document"]
        XCTAssertTrue(document.waitForExistence(timeout: 3))
        document.tap()
        document.typeText("取消改动")
        app.buttons["tasks.editor.cancel"].tap()
        app.buttons["继续编辑"].tap()
        XCTAssertTrue((document.value as? String)?.contains("取消改动") == true)
        app.buttons["tasks.editor.cancel"].tap()
        app.buttons["放弃修改"].tap()
        XCTAssertEqual(app.buttons["tasks.detail.title"].label, "定位")
        edit.tap()
        XCTAssertTrue(document.waitForExistence(timeout: 3))
        document.tap()
        document.press(forDuration: 1)
        let selectAll = app.descendants(matching: .any).matching(NSPredicate(format: "label == '全选' OR label == 'Select All'")).firstMatch
        XCTAssertTrue(selectAll.waitForExistence(timeout: 3), app.debugDescription)
        selectAll.tap()
        document.typeText("新标题\n保留编辑备注")
        XCTAssertEqual(document.value as? String, "新标题\n保留编辑备注")
        app.buttons["tasks.editor.submit"].tap()
        XCTAssertTrue(app.buttons["tasks.detail.title"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.buttons["tasks.detail.title"].label, "新标题")
        XCTAssertEqual(app.buttons["tasks.detail.note"].label, "保留编辑备注")
        app.buttons["tasks.detail.complete"].tap()
        XCTAssertTrue(app.buttons["恢复为未完成"].waitForExistence(timeout: 3))
        app.buttons["tasks.detail.undo"].tap()
        XCTAssertTrue(app.buttons["标记完成"].waitForExistence(timeout: 3))
        app.buttons["tasks.detail.complete"].tap()
        app.buttons["tasks.detail.complete"].tap()
        XCTAssertTrue(app.buttons["标记完成"].waitForExistence(timeout: 3))
        app.buttons["tasks.detail.close"].tap()
        XCTAssertTrue(app.scrollViews["tasks.list"].waitForExistence(timeout: 3))
    }
    func testSharedNewEditorPersistsNotesAndListCompletion() {
        let app = XCUIApplication()
        app.launchEnvironment["TOUGH_TRIAL_UI_TESTING"] = "0"
        app.launch()
        let name = "Editor-" + UUID().uuidString.prefix(6)
        app.tabBars.firstMatch.buttons["任务"].tap()
        app.buttons["tasks.capture.open"].tap()
        XCTAssertFalse(app.buttons["tasks.capture.submit"].isEnabled)
        let document = app.textViews["tasks.capture.document"]
        XCTAssertTrue(document.waitForExistence(timeout: 3))
        document.tap(); document.typeText(name + "\n保存完整备注")
        XCTAssertEqual(document.value as? String, name + "\n保存完整备注")
        app.buttons["tasks.capture.submit"].tap()
        reveal(app.buttons[name], in: app)
        app.buttons[name].tap()
        XCTAssertEqual(app.buttons["tasks.detail.note"].label, "保存完整备注")
        XCTAssertFalse(app.staticTexts["tasks.detail.path"].exists)
        app.buttons["tasks.detail.close"].tap()
        app.buttons["完成：" + name].tap()
        XCTAssertTrue(app.buttons["恢复未完成：" + name].waitForExistence(timeout: 3))
        app.buttons["tasks.action.undo"].tap()
        XCTAssertTrue(app.buttons["完成：" + name].waitForExistence(timeout: 3))
        app.buttons["关闭操作提示"].tap()
        app.terminate(); app.launch()
        app.tabBars.firstMatch.buttons["任务"].tap()
        reveal(app.buttons[name], in: app)
        app.buttons[name].tap()
        XCTAssertEqual(app.buttons["tasks.detail.note"].label, "保存完整备注")
        app.buttons["tasks.detail.title"].tap()
        app.buttons["tasks.editor.cancel"].tap()
        XCTAssertTrue(app.buttons["tasks.detail.title"].waitForExistence(timeout: 3))
    }

    func testTimeAndFishboneOpenSameEditableTask() {
        let app = XCUIApplication()
        app.launchEnvironment["TOUGH_TRIAL_UI_TEST_EMPTY"] = "1"
        app.launch()
        let name = "Views-" + UUID().uuidString.prefix(6)
        app.tabBars.firstMatch.buttons["今天"].tap()
        app.descendants(matching: .any)["today.quickAdd"].tap()
        let document = app.textViews["today.quickAdd.document"]
        XCTAssertTrue(document.waitForExistence(timeout: 3))
        document.typeText(name)
        app.buttons["today.quickAdd.submit"].tap()
        app.descendants(matching: .any)["today.quickAdd"].tap()
        let secondDocument = app.textViews["today.quickAdd.document"]
        XCTAssertTrue(secondDocument.waitForExistence(timeout: 3))
        secondDocument.typeText("另一条全天任务")
        app.buttons["today.quickAdd.submit"].tap()
        app.tabBars.firstMatch.buttons["任务"].tap()
        app.buttons["tasks.lens.time"].tap()
        app.buttons["time-scale-日"].tap()
        let allDay = app.buttons["查看当天全部任务"]
        XCTAssertTrue(allDay.waitForExistence(timeout: 3))
        allDay.tap()
        app.collectionViews.buttons[name].tap()
        app.buttons["tasks.time.details"].tap()
        XCTAssertEqual(app.buttons["tasks.detail.title"].label, name)
        app.buttons["tasks.detail.complete"].tap()
        app.buttons["tasks.detail.close"].tap()
        app.buttons["tasks.lens.fishbone"].tap()
        let fishbone = app.buttons["查看详情：" + name]
        XCTAssertTrue(fishbone.waitForExistence(timeout: 3))
        fishbone.tap()
        XCTAssertEqual(app.buttons["tasks.detail.title"].label, name)
        app.buttons["tasks.detail.title"].tap()
        let editDocument = app.textViews["tasks.editor.document"]
        XCTAssertTrue(editDocument.waitForExistence(timeout: 3))
        editDocument.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.05)).tap()
        editDocument.typeText("\n跨视图修改")
        app.buttons["tasks.editor.submit"].tap()
        XCTAssertEqual(app.buttons["tasks.detail.note"].label, "跨视图修改")
        app.buttons["tasks.detail.close"].tap()
        app.tabBars.firstMatch.buttons["今天"].tap()
        XCTAssertTrue(app.staticTexts[name].firstMatch.waitForExistence(timeout: 3))
    }

    func testLongTaskKeepsEditingAndActionsReachable() {
        checkLongTask(largeText: false)
    }

    func testLongTaskWithAccessibilityText() {
        checkLongTask(largeText: true)
    }

    private func checkLongTask(largeText: Bool) {
        let app = XCUIApplication()
        if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launchEnvironment["TOUGH_TRIAL_UI_TESTING"] = "0"
        app.launch()
        app.tabBars.firstMatch.buttons["任务"].tap()
        app.buttons["tasks.capture.open"].tap()
        let longTitle = "Long-" + UUID().uuidString.prefix(5) + String(repeating: "长任务内容需保留。", count: 20)
        let document = app.textViews["tasks.capture.document"]
        XCTAssertTrue(document.waitForExistence(timeout: 3))
        document.tap(); document.typeText(longTitle)
        XCTAssertEqual(document.value as? String, longTitle)
        app.buttons["tasks.capture.submit"].tap()
        let row = app.buttons.matching(NSPredicate(format: "label == %@", longTitle)).firstMatch
        reveal(row, in: app)
        row.tap()
        XCTAssertTrue(app.buttons["tasks.detail.title"].isHittable)
        XCTAssertTrue(app.buttons["tasks.detail.complete"].isHittable)
        app.buttons["tasks.detail.title"].tap()
        app.buttons["tasks.editor.cancel"].tap()
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = largeText ? "task-long-detail-large-text" : "task-long-detail"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["tasks.detail.complete"].tap()
        XCTAssertTrue(app.buttons["恢复为未完成"].waitForExistence(timeout: 3))
        app.buttons["tasks.detail.undo"].tap()
        app.buttons["tasks.detail.close"].tap()
    }

    func testFlatTasksCanSwitchToTreeAndEditByTappingContent() {
        let app = XCUIApplication()
        app.launchEnvironment["TOUGH_TRIAL_UI_TEST_EMPTY"] = "1"
        app.launch()
        app.tabBars.buttons["任务"].tap()
        let tabs = ["list", "structure", "time", "fishbone"].map { app.buttons["tasks.lens." + $0] }
        for tab in tabs {
            XCTAssertTrue(tab.isHittable)
            XCTAssertEqual(tab.frame.midY, tabs[0].frame.midY, accuracy: 1)
        }
        XCTAssertEqual(tabs[0].value as? String, "已选中")
        tabs[2].tap()
        XCTAssertTrue(app.buttons["time-scale-周"].exists)
        XCTAssertEqual(tabs[2].value as? String, "已选中")
        tabs[3].tap()
        XCTAssertEqual(tabs[3].value as? String, "已选中")
        let tree = app.buttons["tasks.lens.structure"]
        XCTAssertTrue(tree.waitForExistence(timeout: 3))
        tree.tap()
        XCTAssertTrue(app.staticTexts["还没有任务"].exists)
        app.buttons["tasks.lens.list"].tap()
        for title in ["独立任务甲", "独立任务乙"] {
            app.buttons["tasks.capture.open"].tap()
            let input = app.textViews["tasks.capture.document"]
            XCTAssertTrue(input.waitForExistence(timeout: 3))
            input.typeText(title)
            app.buttons["tasks.capture.submit"].tap()
        }
        tree.tap()
        XCTAssertTrue(app.staticTexts["tasks.structure.overviewTitle"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["独立任务甲"].exists)
        XCTAssertTrue(app.buttons["独立任务乙"].exists)
        app.buttons["缩小任务地图"].tap()
        app.buttons["放大任务地图"].tap()
        app.buttons["重置地图缩放"].tap()
        app.buttons["独立任务甲"].tap()
        XCTAssertFalse(app.buttons["编辑"].exists)
        app.buttons["tasks.detail.emptyBody"].tap()
        let edit = app.textViews["tasks.editor.document"]
        XCTAssertTrue(edit.waitForExistence(timeout: 3))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        edit.typeText("\n补充正文")
        app.buttons["tasks.editor.submit"].tap()
        XCTAssertEqual(app.buttons["tasks.detail.note"].label, "补充正文")
        app.buttons["tasks.detail.note"].tap()
        XCTAssertTrue(edit.waitForExistence(timeout: 3))
        edit.typeText("临时内容")
        app.buttons["tasks.editor.cancel"].tap()
        app.buttons["放弃修改"].tap()
        XCTAssertEqual(app.buttons["tasks.detail.note"].label, "补充正文")
        app.buttons["tasks.detail.undo"].tap()
        XCTAssertTrue(app.buttons["tasks.detail.emptyBody"].exists)
        app.buttons["tasks.detail.close"].tap()
        XCTAssertTrue(app.staticTexts["tasks.structure.overviewTitle"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "four-task-views-tree"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["tasks.capture.open"].tap()
        XCTAssertTrue(app.staticTexts["结构 / 新建根任务"].exists)
        app.buttons["tasks.capture.cancel"].tap()
        app.buttons["tasks.lens.list"].tap()
        XCTAssertTrue(app.buttons["独立任务甲"].exists)
        XCTAssertTrue(app.buttons["独立任务乙"].exists)
        app.buttons["独立任务甲"].tap()
        XCTAssertFalse(app.staticTexts["tasks.detail.path"].exists)
        app.buttons["tasks.detail.title"].tap()
        XCTAssertEqual(edit.value as? String, "独立任务甲")
        app.buttons["tasks.editor.cancel"].tap()
        XCTAssertEqual(app.buttons["tasks.detail.title"].label, "独立任务甲")
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<20 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable, "Saved task must be reachable in the task list")
    }

}

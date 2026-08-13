import XCTest

final class ToughTrialUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    @MainActor
    func testPrimaryNavigationAndPlanPresentation() {
        let app = launchApp()
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.buttons["今天"].waitForExistence(timeout: 5))

        tabBar.buttons["任务"].tap()
        XCTAssertTrue(app.staticTexts["任务"].firstMatch.waitForExistence(timeout: 3))

        tabBar.buttons["计划"].tap()
        XCTAssertTrue(app.staticTexts["想怎么安排？"].waitForExistence(timeout: 3))
        XCTAssertFalse(tabBar.isHittable)

        app.buttons["关闭计划"].tap()
        XCTAssertTrue(tabBar.buttons["回想"].waitForExistence(timeout: 3))

        tabBar.buttons["回想"].tap()
        XCTAssertTrue(app.staticTexts["回想"].firstMatch.waitForExistence(timeout: 3))
    }

    @MainActor
    func testPlanCanOpenAIProviderSettings() {
        let app = launchApp()
        app.tabBars.firstMatch.buttons["计划"].tap()
        XCTAssertTrue(app.buttons["计划选项"].waitForExistence(timeout: 3))

        app.buttons["计划选项"].tap()
        app.buttons["AI 服务"].tap()
        XCTAssertTrue(app.navigationBars["AI 服务"].waitForExistence(timeout: 3))

        let onlineToggle = app.switches["ai.settings.enabled"]
        XCTAssertTrue(onlineToggle.waitForExistence(timeout: 3))
        if onlineToggle.value as? String != "1" {
            onlineToggle.coordinate(
                withNormalizedOffset: CGVector(dx: 0.88, dy: 0.5)
            ).tap()
            let enabled = NSPredicate(format: "value == %@", "1")
            expectation(for: enabled, evaluatedWith: onlineToggle)
            waitForExpectations(timeout: 3)
        }
        XCTAssertTrue(
            app.descendants(matching: .any)["ai.settings.baseURL"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["ai.settings.model"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["ai.settings.apiKey"]
                .waitForExistence(timeout: 3)
        )
    }

    @MainActor
    func testQuickAddCreatesTodayTaskOnlyAfterSubmit() {
        let app = launchApp()
        let taskTitle = "UI test \(UUID().uuidString.prefix(8))"
        app.descendants(matching: .any)["today.quickAdd"].tap()

        let field = app.textFields["记一件要处理的事"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.typeText(taskTitle)
        XCTAssertFalse(app.staticTexts[taskTitle].exists)

        app.buttons["添加任务"].tap()
        XCTAssertTrue(app.staticTexts[taskTitle].waitForExistence(timeout: 3))
    }

    @MainActor
    func testTaskCaptureInStructureAndFishbonePersistsAfterRelaunch() {
        let cancelledTitle = "取消-\(UUID().uuidString.prefix(6))"
        let structureTitle = "结构-\(UUID().uuidString.prefix(6))"
        let fishboneTitle = "鱼骨-\(UUID().uuidString.prefix(6))"
        var app = launchProductionApp()

        app.tabBars.firstMatch.buttons["任务"].tap()
        XCTAssertTrue(app.buttons["tasks.lens.structure"].waitForExistence(timeout: 5))

        app.buttons["tasks.capture.open"].tap()
        let captureTitle = app.textFields["tasks.capture.title"]
        XCTAssertTrue(captureTitle.waitForExistence(timeout: 3))
        captureTitle.typeText(cancelledTitle)
        app.buttons["tasks.capture.cancel"].tap()
        XCTAssertTrue(captureTitle.waitForNonExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts[cancelledTitle].exists)

        app.buttons["tasks.capture.open"].tap()
        XCTAssertTrue(captureTitle.waitForExistence(timeout: 3))
        keepScreenshot(of: app, name: "remediation-task-capture-structure")
        captureTitle.typeText(structureTitle)
        app.buttons["tasks.capture.submit"].tap()
        XCTAssertTrue(captureTitle.waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.buttons[structureTitle].waitForExistence(timeout: 5))
        keepScreenshot(of: app, name: "remediation-task-created-structure")

        app.buttons["tasks.lens.fishbone"].tap()
        app.buttons["tasks.capture.open"].tap()
        XCTAssertTrue(captureTitle.waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["tasks.capture.location"].label, "鱼骨 / 未归类")
        keepScreenshot(of: app, name: "remediation-task-capture-fishbone")
        captureTitle.typeText(fishboneTitle)
        app.buttons["tasks.capture.submit"].tap()
        XCTAssertTrue(captureTitle.waitForNonExistence(timeout: 3))

        for _ in 0..<2 {
            app.terminate()
            app = launchProductionApp()
            assertTaskCanBeFoundForZen(structureTitle, in: app)
            assertTaskCanBeFoundForZen(fishboneTitle, in: app)
        }
    }

    @MainActor
    func testTaskDetailOpensContextualPlanAndWritesOnlyOnAccept() {
        let app = launchApp()
        app.tabBars.firstMatch.buttons["任务"].tap()

        let details = app.buttons["查看详情：定位"]
        let disclosure = app.buttons["定位"]
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        XCTAssertTrue(disclosure.exists)
        details.tap()

        XCTAssertTrue(app.staticTexts["tasks.detail.title"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["tasks.detail.title"].label, "定位")
        XCTAssertTrue(app.buttons["tasks.detail.aiPlan"].exists)
        keepScreenshot(of: app, name: "remediation-task-detail")
        app.buttons["tasks.detail.aiPlan"].tap()

        let context = app.staticTexts["plan.context.task"]
        XCTAssertTrue(context.waitForExistence(timeout: 5))
        XCTAssertEqual(context.label, "来自任务：定位")
        XCTAssertFalse(app.buttons["加入计划"].exists)
        keepScreenshot(of: app, name: "remediation-task-plan-context")

        let composer = app.textFields["plan.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 3))
        composer.tap()
        composer.typeText("这周跑 10 公里")
        app.buttons["发送"].tap()
        XCTAssertTrue(app.buttons["可以"].waitForExistence(timeout: 5))
        app.buttons["可以"].tap()
        XCTAssertTrue(app.buttons["加入计划"].waitForExistence(timeout: 5))

        app.buttons["关闭计划"].tap()
        app.tabBars.firstMatch.buttons["今天"].tap()
        assertTaskIsMissingFromZenSearch("轻松跑 3 公里", in: app)

        app.tabBars.firstMatch.buttons["任务"].tap()
        XCTAssertTrue(details.waitForExistence(timeout: 3))
        details.tap()
        app.buttons["tasks.detail.aiPlan"].tap()
        XCTAssertTrue(app.buttons["加入计划"].waitForExistence(timeout: 5))
        app.buttons["加入计划"].tap()
        XCTAssertTrue(app.buttons["加入计划"].waitForNonExistence(timeout: 5))
        app.buttons["关闭计划"].tap()

        app.tabBars.firstMatch.buttons["今天"].tap()
        assertTaskCanBeFoundForZen("轻松跑 3 公里", in: app)
    }

    @MainActor
    func testEmptyTodayZenSupportsUnlinkedAndLinkedSessions() {
        let app = launchEmptyApp()
        let directStart = app.buttons["today.emptyZen.startUnlinked"]
        XCTAssertTrue(directStart.waitForExistence(timeout: 5))
        directStart.tap()

        XCTAssertTrue(app.staticTexts["zen.title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["zen.title"].label, "自由专注")
        keepScreenshot(of: app, name: "remediation-zen-unlinked")
        app.buttons["zen.toggle"].tap()
        XCTAssertEqual(app.staticTexts["zen.status"].label, "暂停中")
        app.buttons["zen.toggle"].tap()
        XCTAssertEqual(app.staticTexts["zen.status"].label, "Zen")

        app.buttons["zen.close"].tap()
        XCTAssertTrue(app.buttons["today.focus.zen"].waitForExistence(timeout: 5))
        app.buttons["today.focus.zen"].tap()
        XCTAssertEqual(app.staticTexts["zen.title"].label, "自由专注")
        app.buttons["zen.finish"].tap()
        XCTAssertTrue(directStart.waitForExistence(timeout: 5))

        let linkedTitle = "关联-\(UUID().uuidString.prefix(6))"
        addTodayTask(linkedTitle, in: app)
        app.buttons["today.emptyZen.chooseTask"].tap()
        let search = app.textFields["today.zenTaskPicker.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.typeText(linkedTitle)
        let linkedTask = app.buttons["开始 \(linkedTitle) 的 Zen"]
        XCTAssertTrue(linkedTask.waitForExistence(timeout: 3))
        linkedTask.tap()
        XCTAssertTrue(app.staticTexts["zen.title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["zen.title"].label, linkedTitle)
        keepScreenshot(of: app, name: "remediation-zen-linked")
        app.buttons["zen.finish"].tap()
        XCTAssertTrue(app.tabBars.firstMatch.buttons["今天"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testTodayQuickAddParsesExplicitTimeAndLeavesPlainInputUntimed() {
        let app = launchEmptyApp()
        let explicitTitle = "15:00 提交-\(UUID().uuidString.prefix(6))"
        let plainTitle = "整理材料-\(UUID().uuidString.prefix(6))"

        addTodayTask(explicitTitle, in: app)
        let explicitTime = app.staticTexts["today.timeline.time.\(explicitTitle)"]
        XCTAssertTrue(explicitTime.waitForExistence(timeout: 5))
        XCTAssertEqual(explicitTime.label, "15:00")

        addTodayTask(plainTitle, in: app)
        let plainTime = app.staticTexts["today.timeline.time.\(plainTitle)"]
        XCTAssertTrue(plainTime.waitForExistence(timeout: 5))
        XCTAssertEqual(plainTime.label, "今天")
        keepScreenshot(of: app, name: "remediation-today-explicit-and-untimed")
    }

    @MainActor
    func testZenModalAccessibilityTreeExcludesTodayLayer() {
        let app = launchEmptyApp()
        XCTAssertTrue(app.buttons["today.emptyZen.startUnlinked"].waitForExistence(timeout: 5))
        app.buttons["today.emptyZen.startUnlinked"].tap()
        XCTAssertTrue(app.buttons["zen.toggle"].waitForExistence(timeout: 5))

        XCTAssertEqual(app.buttons.matching(identifier: "zen.toggle").count, 1)
        XCTAssertEqual(app.buttons.matching(identifier: "zen.finish").count, 1)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == %@", "暂停")).count, 1)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == %@", "结束时间段")).count, 1)
        XCTAssertEqual(app.tabBars.count, 0)
        XCTAssertFalse(app.descendants(matching: .any)["today.quickAdd"].exists)
        keepScreenshot(of: app, name: "remediation-zen-modal")

        app.buttons["zen.close"].tap()
        XCTAssertTrue(app.tabBars.firstMatch.buttons["今天"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["today.quickAdd"].exists)
    }

    @MainActor
    func testEndToEndSeeArrangeExecuteRecallAndRelaunch() {
        let taskTitle = "闭环-\(UUID().uuidString.prefix(6))"
        let reflection = "复盘-\(UUID().uuidString.prefix(6))"
        var app = launchProductionApp()

        addTodayTask(taskTitle, in: app)
        let timelineTask = app.staticTexts[taskTitle]
        XCTAssertTrue(timelineTask.waitForExistence(timeout: 5))
        timelineTask.tap()
        XCTAssertTrue(app.buttons["Zen"].waitForExistence(timeout: 3))
        app.buttons["Zen"].tap()
        XCTAssertTrue(app.staticTexts["zen.title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["zen.title"].label, taskTitle)
        app.buttons["zen.finish"].tap()

        app.tabBars.firstMatch.buttons["回想"].tap()
        XCTAssertTrue(app.buttons["引用"].waitForExistence(timeout: 5))
        app.buttons["引用"].tap()
        XCTAssertTrue(app.staticTexts[taskTitle].waitForExistence(timeout: 5))

        let editor = app.textViews["recall.textEditor"]
        app.buttons["recall.mode.text"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        editor.typeText("\n\(reflection)")
        app.buttons["recall.complete"].tap()
        XCTAssertTrue(app.staticTexts["已保存"].waitForExistence(timeout: 5))
        keepScreenshot(of: app, name: "remediation-recall-loop-saved")

        for _ in 0..<2 {
            app.terminate()
            app = launchProductionApp()
            app.tabBars.firstMatch.buttons["回想"].tap()
            let reloadedEditor = app.textViews["recall.textEditor"]
            XCTAssertTrue(reloadedEditor.waitForExistence(timeout: 5))
            XCTAssertTrue((reloadedEditor.value as? String)?.contains(reflection) == true)
        }
    }

    @MainActor
    func testTaskMapCollapseAndZoomControls() {
        let app = launchApp()
        app.tabBars.firstMatch.buttons["任务"].tap()

        let branch = app.buttons["定位"]
        let completedLeaf = app.descendants(matching: .any)["内容边界"]
        XCTAssertTrue(branch.waitForExistence(timeout: 3))
        XCTAssertTrue(completedLeaf.waitForExistence(timeout: 3))

        let topicBranch = app.buttons["选题库"]
        let topicChild = app.descendants(matching: .any)["建立对标账号"]
        XCTAssertTrue(topicBranch.waitForExistence(timeout: 3))
        topicBranch.tap()
        XCTAssertTrue(topicChild.waitForExistence(timeout: 3))
        XCTAssertTrue(completedLeaf.exists)
        keepScreenshot(of: app, name: "task-map-multiple-branches-expanded")

        branch.tap()
        XCTAssertTrue(completedLeaf.waitForNonExistence(timeout: 3))
        XCTAssertTrue(topicChild.exists)

        branch.tap()
        XCTAssertTrue(completedLeaf.waitForExistence(timeout: 3))

        let zoomOut = app.buttons["缩小任务地图"]
        XCTAssertTrue(zoomOut.waitForExistence(timeout: 3))
        zoomOut.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["建立稳定创作系统"].exists
        )
    }

    @MainActor
    func testRecallSwitchesTextAndHandwritingInPlace() {
        let app = launchApp()
        app.tabBars.firstMatch.buttons["回想"].tap()

        let textMode = app.buttons["recall.mode.text"]
        let handwritingMode = app.buttons["recall.mode.handwriting"]
        let textEditor = app.textViews["recall.textEditor"]

        XCTAssertTrue(textMode.waitForExistence(timeout: 3))
        XCTAssertTrue(handwritingMode.waitForExistence(timeout: 3))
        XCTAssertTrue(textEditor.waitForExistence(timeout: 3))
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        keepScreenshot(of: app, name: "recall-text-mode")

        textMode.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        textEditor.typeText("Recall draft")

        handwritingMode.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["recall.handwritingCanvas"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(textEditor.waitForNonExistence(timeout: 3))
        keepScreenshot(of: app, name: "recall-handwriting-mode")

        textMode.tap()
        XCTAssertTrue(textEditor.waitForExistence(timeout: 3))
        XCTAssertEqual(textEditor.value as? String, "Recall draft")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
    }

    @MainActor
    func testHandwritingOnlyRecallCanBeCompleted() {
        let app = launchApp()
        app.tabBars.firstMatch.buttons["回想"].tap()
        app.buttons["recall.mode.handwriting"].tap()

        let canvas = app.descendants(matching: .any)["recall.handwritingCanvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 3))

        let strokeStart = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.22, dy: 0.28))
        let strokeEnd = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.72, dy: 0.36))
        strokeStart.press(forDuration: 0.1, thenDragTo: strokeEnd)

        XCTAssertEqual(canvas.value as? String, "已有笔迹")
        XCTAssertTrue(app.staticTexts["未保存"].waitForExistence(timeout: 3))

        let complete = app.buttons["recall.complete"]
        XCTAssertTrue(complete.isEnabled)
        complete.tap()

        XCTAssertTrue(app.staticTexts["已保存"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testCapturePrimaryVisualBaselines() {
        let app = launchApp()
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.buttons["今天"].waitForExistence(timeout: 5))
        keepScreenshot(of: app, name: "01-today")

        tabBar.buttons["任务"].tap()
        XCTAssertTrue(app.staticTexts["任务"].firstMatch.waitForExistence(timeout: 3))
        keepScreenshot(of: app, name: "02-tasks")

        tabBar.buttons["计划"].tap()
        XCTAssertTrue(app.staticTexts["想怎么安排？"].waitForExistence(timeout: 3))
        keepScreenshot(of: app, name: "03-plan")

        app.buttons["关闭计划"].tap()
        tabBar.buttons["回想"].tap()
        XCTAssertTrue(app.staticTexts["回想"].firstMatch.waitForExistence(timeout: 3))
        keepScreenshot(of: app, name: "04-recall")
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TOUGH_TRIAL_AI_API_KEY"] = ""
        app.launchEnvironment["TOUGH_TRIAL_UI_TESTING"] = "1"
        app.launch()
        return app
    }

    @MainActor
    private func launchEmptyApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TOUGH_TRIAL_AI_API_KEY"] = ""
        app.launchEnvironment["TOUGH_TRIAL_UI_TESTING"] = "0"
        app.launchEnvironment["TOUGH_TRIAL_UI_TEST_EMPTY"] = "1"
        app.launch()
        return app
    }

    @MainActor
    private func launchProductionApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TOUGH_TRIAL_AI_API_KEY"] = ""
        app.launchEnvironment["TOUGH_TRIAL_UI_TESTING"] = "0"
        app.launchEnvironment["TOUGH_TRIAL_UI_TEST_EMPTY"] = "0"
        app.launch()
        return app
    }

    @MainActor
    private func addTodayTask(_ title: String, in app: XCUIApplication) {
        let quickAdd = app.descendants(matching: .any)["today.quickAdd"]
        XCTAssertTrue(quickAdd.waitForExistence(timeout: 5))
        quickAdd.tap()
        let field = app.textFields["today.quickAdd.title"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.typeText(title)
        app.buttons["添加任务"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 3))
    }

    @MainActor
    private func assertTaskCanBeFoundForZen(
        _ title: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let chooseTask = app.buttons["today.emptyZen.chooseTask"]
        XCTAssertTrue(chooseTask.waitForExistence(timeout: 5), file: file, line: line)
        chooseTask.tap()
        let search = app.textFields["today.zenTaskPicker.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 3), file: file, line: line)
        search.typeText(title)
        XCTAssertTrue(
            app.buttons["开始 \(title) 的 Zen"].waitForExistence(timeout: 3),
            file: file,
            line: line
        )
        app.buttons["today.zenTaskPicker.cancel"].tap()
        XCTAssertTrue(search.waitForNonExistence(timeout: 3), file: file, line: line)
    }

    @MainActor
    private func assertTaskIsMissingFromZenSearch(
        _ title: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let chooseTask = app.buttons["today.emptyZen.chooseTask"]
        XCTAssertTrue(chooseTask.waitForExistence(timeout: 5), file: file, line: line)
        chooseTask.tap()
        let search = app.textFields["today.zenTaskPicker.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 3), file: file, line: line)
        search.typeText(title)
        XCTAssertTrue(
            app.staticTexts["没有找到任务"].waitForExistence(timeout: 3),
            file: file,
            line: line
        )
        app.buttons["today.zenTaskPicker.cancel"].tap()
        XCTAssertTrue(search.waitForNonExistence(timeout: 3), file: file, line: line)
    }

    @MainActor
    private func keepScreenshot(of app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

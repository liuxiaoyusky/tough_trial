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
    private func keepScreenshot(of app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

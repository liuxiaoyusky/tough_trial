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

        branch.tap()
        XCTAssertTrue(completedLeaf.waitForNonExistence(timeout: 3))

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

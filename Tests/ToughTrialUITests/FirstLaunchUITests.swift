import XCTest

final class FirstLaunchUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    @MainActor
    func testFirstLaunchFromEmptySnapshot() {
        let app = launchEmptyApp()
        let tabBar = app.tabBars.firstMatch

        XCTAssertTrue(tabBar.buttons["今天"].waitForExistence(timeout: 5))

        tabBar.buttons["任务"].tap()
        XCTAssertTrue(app.staticTexts["任务"].firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["还没有任务结构"].waitForExistence(timeout: 3))

        tabBar.buttons["计划"].tap()
        XCTAssertTrue(app.textFields["plan.composer"].waitForExistence(timeout: 3))
        app.buttons["关闭计划"].tap()

        XCTAssertTrue(tabBar.buttons["回想"].waitForExistence(timeout: 3))
        tabBar.buttons["回想"].tap()
        XCTAssertTrue(app.staticTexts["回想"].firstMatch.waitForExistence(timeout: 3))

        tabBar.buttons["今天"].tap()
        let taskTitle = "第一次空数据任务"
        app.descendants(matching: .any)["today.quickAdd"].tap()

        let titleField = app.textFields["today.quickAdd.title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 3))
        titleField.typeText(taskTitle)
        app.buttons["添加任务"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)[taskTitle]
                .waitForExistence(timeout: 3)
        )

        tabBar.buttons["任务"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)[taskTitle]
                .waitForExistence(timeout: 3)
        )

        app.terminate()

        let relaunchedApp = launchEmptyApp()
        let relaunchedTabBar = relaunchedApp.tabBars.firstMatch
        XCTAssertTrue(relaunchedTabBar.buttons["任务"].waitForExistence(timeout: 5))
        relaunchedTabBar.buttons["任务"].tap()
        XCTAssertTrue(
            relaunchedApp.staticTexts["还没有任务结构"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertFalse(relaunchedApp.descendants(matching: .any)[taskTitle].exists)
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
}

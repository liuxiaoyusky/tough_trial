import XCTest

@MainActor
final class V2TaskClassificationUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testClassificationIsOptionalCollapsedAndSavesTaskType() {
        let app = makeApp()
        let name = "分类-" + UUID().uuidString.prefix(6)
        createTask(name, in: app)

        app.buttons["tasks.detail.title"].tap()
        let classification = app.descendants(matching: .any)["tasks.editor.classification"].firstMatch
        XCTAssertTrue(classification.waitForExistence(timeout: 3))
        XCTAssertTrue(classification.isHittable)
        let kindPicker = app.buttons["tasks.editor.classification.kind"]
        XCTAssertFalse(kindPicker.isHittable, "Classification choices stay collapsed until requested")

        classification.tap()
        XCTAssertTrue(kindPicker.waitForExistence(timeout: 3))
        kindPicker.tap()
        app.buttons["目标"].tap()
        app.buttons["tasks.editor.submit"].tap()

        let summary = app.descendants(matching: .any)["tasks.detail.classification"].firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 3))
        XCTAssertTrue(summary.label.contains("目标"))
        XCTAssertFalse(app.buttons["tasks.editor.classification.context"].exists)
    }

    func testClassificationCanBeClearedAndCancelDoesNotWrite() {
        let app = makeApp()
        let name = "清空分类-" + UUID().uuidString.prefix(6)
        createTask(name, in: app)

        app.buttons["tasks.detail.title"].tap()
        let classification = app.descendants(matching: .any)["tasks.editor.classification"].firstMatch
        classification.tap()
        app.buttons["tasks.editor.classification.kind"].tap()
        app.buttons["承诺"].tap()
        app.buttons["tasks.editor.submit"].tap()
        let saved = app.descendants(matching: .any)["tasks.detail.classification"].firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 3))
        XCTAssertTrue(saved.label.contains("承诺"))

        app.buttons["tasks.detail.title"].tap()
        classification.tap()
        app.buttons["tasks.editor.classification.kind"].tap()
        app.buttons["维护"].tap()
        app.buttons["tasks.editor.cancel"].tap()
        app.buttons["继续编辑"].tap()
        XCTAssertTrue(app.buttons["tasks.editor.submit"].exists)
        app.buttons["tasks.editor.cancel"].tap()
        app.buttons["放弃修改"].tap()

        let beforeClear = app.descendants(matching: .any)["tasks.detail.classification"].firstMatch
        XCTAssertTrue(beforeClear.waitForExistence(timeout: 3))
        XCTAssertTrue(beforeClear.label.contains("承诺"))

        app.buttons["tasks.detail.title"].tap()
        classification.tap()
        app.buttons["tasks.editor.classification.kind"].tap()
        app.buttons["未分类"].tap()
        app.buttons["tasks.editor.submit"].tap()
        let afterClear = app.descendants(matching: .any)["tasks.detail.classification"].firstMatch
        XCTAssertTrue(afterClear.waitForExistence(timeout: 3))
        XCTAssertTrue(afterClear.label.contains("未分类"))
        app.buttons["tasks.detail.undo"].tap()
        let afterUndo = app.descendants(matching: .any)["tasks.detail.classification"].firstMatch
        XCTAssertTrue(afterUndo.label.contains("承诺"))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "分类清空后撤销恢复"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TOUGH_TRIAL_UI_TEST_EMPTY"] = "1"
        app.launch()
        app.tabBars.buttons["任务"].tap()
        return app
    }

    private func createTask(_ name: String, in app: XCUIApplication) {
        app.buttons["tasks.capture.open"].tap()
        let document = app.textViews["tasks.capture.document"]
        XCTAssertTrue(document.waitForExistence(timeout: 3))
        document.tap()
        document.typeText(name)
        app.buttons["tasks.capture.submit"].tap()
        let task = app.buttons[name]
        XCTAssertTrue(task.waitForExistence(timeout: 3))
        task.tap()
    }
}

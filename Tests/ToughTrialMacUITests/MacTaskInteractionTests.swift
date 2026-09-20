import XCTest

final class MacTaskInteractionTests: XCTestCase {
    private var app: XCUIApplication!
    private var dataPath: String!

    override func setUpWithError() throws {
        continueAfterFailure = false
        dataPath = NSTemporaryDirectory() + "mac-task-ui-" + UUID().uuidString
        app = XCUIApplication()
        app.launchEnvironment["TOUGH_TRIAL_MAC_DATA_DIR"] = dataPath
        app.launchEnvironment["TOUGH_TRIAL_UI_TESTING"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["mac.tasks.new"].waitForExistence(timeout: 15))
    }
    override func tearDownWithError() throws {
        app?.terminate()
        if let dataPath { try? FileManager.default.removeItem(atPath: dataPath) }
    }
    private var editor: XCUIElement { app.textViews["mac.tasks.document"] }
    private func create(_ title: String) {
        app.buttons["mac.tasks.new"].click()
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.click(); editor.typeText(title)
        app.buttons["mac.tasks.save"].click()
        XCTAssertTrue(app.staticTexts[title.components(separatedBy: "\n")[0]].firstMatch.waitForExistence(timeout: 3))
    }

    func testCreateEditAutosaveRestartCompleteRestoreAndUndo() throws {
        create("Mac task\nA continuous document")
        editor.click(); editor.typeKey("a", modifierFlags: .command)
        editor.typeText("Edited task\nBody after return")
        XCTAssertTrue(app.staticTexts["Edited task"].firstMatch.waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["Edited task"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(editor.value as? String, "Edited task\nBody after return")
        app.buttons.matching(NSPredicate(format: "label == %@", "完成任务：Edited task")).firstMatch.click()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == %@", "恢复待办：Edited task")).firstMatch.exists)
        app.buttons["mac.tasks.undoSave"].click()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == %@", "完成任务：Edited task")).firstMatch.exists)
    }

    func testDraftRestartCancelAndEmptySave() {
        app.buttons["mac.tasks.new"].click()
        XCTAssertFalse(app.buttons["mac.tasks.save"].isEnabled)
        editor.click(); editor.typeText("Uncreated draft")
        app.terminate(); app.launch()
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        XCTAssertEqual(editor.value as? String, "Uncreated draft")
        app.buttons["mac.tasks.cancel"].click()
        app.buttons["放弃草稿"].click()
        XCTAssertFalse(editor.exists)
        XCTAssertTrue(app.staticTexts["给想做的事一个位置"].exists)
    }

    func testAllViewsSearchAndCompletionFeedback() {
        create("Visible task")
        for lens in ["结构", "时间", "鱼骨", "列表"] {
            app.buttons["mac.tasks.lens." + lens].click()
            if lens == "鱼骨" {
                XCTAssertTrue(app.staticTexts["还没有可见完成节点"].exists)
            } else if lens == "时间" { XCTAssertTrue(app.buttons["time-scale-月"].exists) }
            else { XCTAssertTrue(app.staticTexts["Visible task"].firstMatch.exists) }
        }
        let search = app.textFields["mac.tasks.search"]
        search.click(); search.typeText("no match")
        XCTAssertTrue(app.staticTexts["没有匹配的任务"].exists)
        search.typeKey("a", modifierFlags: .command); search.typeKey(.delete, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["Visible task"].firstMatch.exists)
    }
}

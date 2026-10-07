import XCTest
import Carbon

final class MacTaskInteractionTests: XCTestCase {
    private var app: XCUIApplication!
    private var dataPath: String!
    private var previousInputSource: TISInputSource?
    private var selectedInputSourceID: String?

    override func setUpWithError() throws {
        continueAfterFailure = false
        previousInputSource = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        dataPath = NSTemporaryDirectory() + "mac-task-ui-" + UUID().uuidString
        app = XCUIApplication()
        app.launchEnvironment["TOUGH_TRIAL_MAC_DATA_DIR"] = dataPath
        app.launchEnvironment["TOUGH_TRIAL_UI_TESTING"] = "1"
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        let available = ["com.apple.keylayout.ABC", "com.apple.keylayout.US"].compactMap { id -> (String, TISInputSource)? in
            guard let sources = TISCreateInputSourceList([kTISPropertyInputSourceID as String: id] as CFDictionary, false)?.takeRetainedValue() as? [TISInputSource],
                  let source = sources.first else { return nil }
            return (id, source)
        }
        let keyboard = try XCTUnwrap(available.first, "English automation requires an enabled English keyboard")
        selectedInputSourceID = keyboard.0
        XCTAssertEqual(TISSelectInputSource(keyboard.1), noErr)
        XCTAssertTrue(app.buttons["mac.tasks.new"].waitForExistence(timeout: 15), app.debugDescription)
    }
    override func tearDownWithError() throws {
        app?.terminate()
        let current = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        if let previousInputSource,
           let id = TISGetInputSourceProperty(current, kTISPropertyInputSourceID),
           Unmanaged<CFString>.fromOpaque(id).takeUnretainedValue() as String == selectedInputSourceID {
            XCTAssertEqual(TISSelectInputSource(previousInputSource), noErr)
        }
        if let dataPath { try? FileManager.default.removeItem(atPath: dataPath) }
    }
    private var editor: XCUIElement { app.textViews["mac.tasks.document"] }
    private func taskButton(_ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'mac.tasks.open.' AND label CONTAINS %@", title)).firstMatch
    }
    private func create(_ title: String) {
        app.buttons["mac.tasks.new"].click()
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.click(); editor.typeText(title)
        app.buttons["mac.tasks.save"].click()
        let row = taskButton(title.components(separatedBy: "\n")[0])
        XCTAssertTrue(row.waitForExistence(timeout: 3), app.debugDescription)
    }

    func testCreateEditAutosaveRestartCompleteRestoreAndUndo() throws {
        create("Mac task\nA continuous document")
        editor.click(); editor.typeKey("a", modifierFlags: .command)
        editor.typeText("Edited task\nBody after return")
        XCTAssertTrue(taskButton("Edited task").waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        XCTAssertTrue(taskButton("Edited task").waitForExistence(timeout: 10))
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
        app.windows.buttons["放弃草稿"].click()
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
            else { XCTAssertTrue(taskButton("Visible task").exists) }
        }
        let search = app.textFields["mac.tasks.search"]
        search.click(); search.typeText("no match")
        XCTAssertTrue(app.staticTexts["没有匹配的任务"].exists)
        search.typeKey("a", modifierFlags: .command); search.typeKey(.delete, modifierFlags: [])
        XCTAssertTrue(taskButton("Visible task").exists)
    }

    func testListGroupsCompletionRestoreUndoAndSearch() {
        let names = ["Review book", "Review progress", "Review files"]
        for title in names { create(title) }
        let progress = app.staticTexts["mac.tasks.group.inProgress"]
        let pending = app.staticTexts["mac.tasks.group.notStarted"]
        let done = app.staticTexts["mac.tasks.group.completed"]
        XCTAssertEqual(progress.label, "进行中 · 0")
        XCTAssertEqual(pending.label, "未开始 · 3")
        for title in names.prefix(2) {
            app.buttons["完成任务：\(title)"].click()
            XCTAssertTrue(app.buttons["恢复待办：\(title)"].waitForExistence(timeout: 5))
        }
        XCTAssertEqual(pending.label, "未开始 · 1")
        XCTAssertEqual(done.label, "已完成 · 2")
        let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        screenshot.name = "mac-tasks-three-status-lists-native"
        screenshot.lifetime = .keepAlways; add(screenshot)

        let search = app.textFields["mac.tasks.search"]
        search.click(); search.typeText("book")
        XCTAssertEqual(pending.label, "未开始 · 0")
        XCTAssertEqual(done.label, "已完成 · 1")
        XCTAssertFalse(app.buttons["完成任务：\(names[2])"].exists)
        search.typeKey("a", modifierFlags: .command); search.typeKey(.delete, modifierFlags: [])
        app.buttons["恢复待办：\(names[0])"].click()
        XCTAssertEqual(pending.label, "未开始 · 2")
        XCTAssertEqual(done.label, "已完成 · 1")
        app.buttons["mac.tasks.undoSave"].click()
        XCTAssertEqual(done.label, "已完成 · 2")
        XCTAssertTrue(app.buttons["恢复待办：\(names[0])"].exists)
        let open = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'mac.tasks.open.' AND value == '已完成'")).firstMatch
        open.click()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue(names.prefix(2).contains(editor.value as? String ?? ""))
    }
}

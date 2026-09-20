import XCTest

final class V2AssistantHomeUITests: XCTestCase {
    @MainActor
    func testConnectionMustPassBeforeSavingAndEditingInvalidatesIt() {
        let app = openMiniMaxConnectionSettings()
        let save = app.buttons["ai.settings.usePreset"]
        XCTAssertEqual(save.label, "保存配置")
        XCTAssertFalse(save.isEnabled)
        app.buttons["ai.settings.testConnection"].tap()
        XCTAssertTrue(app.staticTexts["ai.settings.testResult"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["ai.settings.testResult"].label.contains("连接成功"))
        XCTAssertTrue(save.isEnabled)
        app.swipeDown()
        let region = app.buttons["ai.settings.minimaxRegion"]
        if !region.isHittable { app.swipeDown() }
        region.tap()
        app.buttons["国内"].tap()
        if !region.waitForExistence(timeout: 2) { app.navigationBars.buttons.firstMatch.tap() }
        app.swipeUp()
        XCTAssertFalse(save.isEnabled)
        app.buttons["ai.settings.testConnection"].tap()
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(app.navigationBars["AI 服务"].waitForNonExistence(timeout: 5), app.debugDescription)
    }

    @MainActor
    func testFailedConnectionKeepsSaveDisabled() {
        let app = openMiniMaxConnectionSettings(fail: true)
        app.buttons["ai.settings.testConnection"].tap()
        let result = app.staticTexts["ai.settings.testResult"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertTrue(result.label.contains("401"))
        XCTAssertFalse(app.buttons["ai.settings.usePreset"].isEnabled)
        XCTAssertTrue(app.navigationBars["AI 服务"].exists)
    }

    @MainActor
    private func openMiniMaxConnectionSettings(fail: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TOUGH_TRIAL_UI_TESTING"] = "1"
        app.launchEnvironment["TOUGH_TRIAL_UI_TEST_EMPTY"] = "1"
        if fail { app.launchEnvironment["TOUGH_TRIAL_UI_CONNECTION_FAILURE"] = "1" }
        app.launch()
        app.buttons["assistant.model.selection"].tap()
        app.buttons["配置服务与密钥"].tap()
        app.buttons["ai.settings.provider"].tap()
        app.buttons["MiniMax"].tap()
        let key = app.secureTextFields["ai.settings.apiKey"]
        XCTAssertTrue(key.waitForExistence(timeout: 5))
        key.tap(); key.typeText("fixture-key")
        app.swipeUp()
        let test = app.buttons["ai.settings.testConnection"]
        if !test.isHittable { app.swipeUp() }
        XCTAssertTrue(test.isHittable)
        return app
    }

    @MainActor
    func testMiniMaxRegionSelection() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TOUGH_TRIAL_UI_TESTING"] = "1"
        app.launchEnvironment["TOUGH_TRIAL_UI_TEST_EMPTY"] = "1"
        app.launch()
        app.buttons["assistant.model.selection"].tap()
        app.buttons["配置服务与密钥"].tap()
        app.buttons["ai.settings.provider"].tap()
        app.buttons["MiniMax"].tap()
        let region = app.buttons["ai.settings.minimaxRegion"]
        XCTAssertTrue(region.waitForExistence(timeout: 5))
        region.tap()
        app.buttons["国内"].tap()
        if !region.waitForExistence(timeout: 2) { app.navigationBars.buttons.firstMatch.tap() }
        XCTAssertTrue(region.waitForExistence(timeout: 3))
        XCTAssertTrue((region.label + String(describing: region.value)).contains("国内"))
        region.tap()
        app.buttons["海外 · Coding Plan / API"].tap()
        if !region.waitForExistence(timeout: 2) { app.navigationBars.buttons.firstMatch.tap() }
        XCTAssertTrue(region.waitForExistence(timeout: 3))
        XCTAssertTrue((region.label + String(describing: region.value)).contains("海外"))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "minimax-account-region"; shot.lifetime = .keepAlways; add(shot)
    }

    @MainActor
    func testHomeLongDraftExpansionStaysOnAssistantPageAndPreservesSessionDraft() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TOUGH_TRIAL_UI_TESTING"] = "1"
        app.launchEnvironment["TOUGH_TRIAL_UI_TEST_EMPTY"] = "1"
        app.launch()
        let composer = app.textViews["assistant.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 8))
        XCTAssertTrue(app.tabBars.buttons["助手"].isSelected)
        XCTAssertFalse(app.buttons["assistant.exit"].exists)

        composer.tap()
        composer.typeText("先建立上下文")
        app.buttons["assistant.send"].tap()
        XCTAssertTrue(app.staticTexts["测试回复：先建立上下文"].waitForExistence(timeout: 8), app.debugDescription)
        app.buttons["assistant.message.copy"].firstMatch.tap()
        let quote = app.buttons["assistant.message.quote"].firstMatch
        XCTAssertTrue(quote.waitForExistence(timeout: 3), app.debugDescription)
        quote.tap()
        XCTAssertTrue(app.buttons["取消引用"].waitForExistence(timeout: 3), app.debugDescription)

        let draft = "开头"
            + String(repeating: "中文", count: 248)
            + "中间"
            + String(repeating: "中文", count: 249)
            + "结尾"
        XCTAssertEqual(draft.count, 1_000)
        composer.tap()
        composer.typeText(draft)
        XCTAssertEqual(composer.value as? String, draft)

        app.buttons["assistant.composer.expand"].tap()
        XCTAssertFalse(app.navigationBars["编辑消息"].exists)
        XCTAssertEqual(app.buttons["assistant.composer.expand"].label, "收起编辑")
        XCTAssertTrue(app.staticTexts["测试回复：先建立上下文"].exists)
        XCTAssertTrue(app.buttons["assistant.send"].isHittable, app.debugDescription)
        composer.typeText("尾部")
        let editedDraft = draft + "尾部"
        XCTAssertTrue((composer.value as? String)?.hasSuffix("尾部") == true)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "assistant-same-page-expanded-long-draft"; shot.lifetime = .keepAlways; add(shot)

        app.buttons["assistant.composer.expand"].tap()
        XCTAssertEqual(app.buttons["assistant.composer.expand"].label, "展开编辑")
        XCTAssertTrue(app.buttons["assistant.send"].isHittable, app.debugDescription)
        XCTAssertEqual(composer.value as? String, editedDraft)

        let dismissKeyboard = app.buttons["assistant.composer.dismissKeyboard"]
        XCTAssertTrue(dismissKeyboard.isHittable)
        dismissKeyboard.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.tabBars.buttons["今天"].isHittable, app.debugDescription)
        app.tabBars.buttons["今天"].tap()
        XCTAssertTrue(app.tabBars.buttons["今天"].isSelected)
        app.tabBars.buttons["助手"].tap()
        XCTAssertTrue(app.tabBars.buttons["助手"].isSelected)
        XCTAssertEqual(composer.value as? String, editedDraft)

        app.buttons["assistant.newSession"].tap()
        let newComposer = app.textViews["assistant.composer"]
        XCTAssertEqual(newComposer.value as? String, "")
        app.buttons["assistant.sessions"].tap()
        let oldSession = app.buttons.matching(NSPredicate(format: "label == %@", "先建立上下文")).firstMatch
        XCTAssertTrue(oldSession.waitForExistence(timeout: 3), app.debugDescription)
        oldSession.tap()
        XCTAssertEqual(app.textViews["assistant.composer"].value as? String, editedDraft)
        XCTAssertTrue(app.buttons["取消引用"].exists)
        app.buttons["assistant.composer.expand"].tap()
        composer.tap()
        XCTAssertTrue(app.buttons["assistant.send"].isHittable)
        app.buttons["assistant.send"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", "测试回复：" + editedDraft)).firstMatch.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertEqual(composer.value as? String, "")
        XCTAssertFalse(app.buttons["取消引用"].exists)
    }

    @MainActor
    func testTaskSourceOpensInHomeAndReturnsToTask() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TOUGH_TRIAL_UI_TESTING"] = "1"
        app.launch()
        app.tabBars.buttons["任务"].tap()
        let details = app.buttons["定位"]
        XCTAssertTrue(details.waitForExistence(timeout: 5)); details.tap()
        app.buttons["tasks.detail.aiPlan"].tap()
        let source = app.buttons["assistant.context.openTask"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["助手"].isSelected)
        source.tap()
        XCTAssertTrue(app.buttons["tasks.detail.title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["tasks.detail.title"].label, "定位")
    }

    @MainActor
    func testDraftSurvivesSessionSwitch() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TOUGH_TRIAL_UI_TESTING"] = "1"
        app.launchEnvironment["TOUGH_TRIAL_UI_TEST_EMPTY"] = "1"
        app.launch()
        let composer = app.textViews["assistant.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 8))
        composer.tap(); composer.typeText("First conversation")
        app.buttons["assistant.send"].tap()
        XCTAssertTrue(app.buttons["assistant.message.copy"].firstMatch.waitForExistence(timeout: 5))
        composer.tap(); composer.typeText("Unsent draft")
        app.buttons["assistant.newSession"].tap()
        XCTAssertEqual(composer.value as? String, "")
        app.buttons["assistant.sessions"].tap()
        let oldSession = app.buttons.matching(NSPredicate(format: "label == %@", "First conversation")).firstMatch
        XCTAssertTrue(oldSession.waitForExistence(timeout: 3)); oldSession.tap()
        XCTAssertEqual(composer.value as? String, "Unsent draft")
        app.buttons["assistant.model.selection"].tap()
        XCTAssertTrue(app.buttons["assistant.model.provider"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["assistant.model.thinking"].exists)
    }
}

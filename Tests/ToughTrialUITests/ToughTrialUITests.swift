import XCTest

final class ToughTrialUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    @MainActor
    func testPrimaryNavigationAndAssistantPresentation() {
        let app = launchApp()
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.buttons["今天"].waitForExistence(timeout: 5))

        tabBar.buttons["任务"].tap()
        XCTAssertTrue(app.staticTexts["任务"].firstMatch.waitForExistence(timeout: 3))

        tabBar.buttons["助手"].tap()
        XCTAssertTrue(app.staticTexts["想一起处理什么？"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["assistant.starter.chat"].exists)
        XCTAssertTrue(app.buttons["assistant.starter.web"].exists)
        XCTAssertTrue(app.buttons["assistant.starter.local"].exists)
        XCTAssertTrue(app.buttons["assistant.starter.plan"].exists)
        XCTAssertTrue(tabBar.isHittable)

        app.tabBars.firstMatch.buttons["今天"].tap()
        XCTAssertTrue(tabBar.buttons["回想"].waitForExistence(timeout: 3))

        tabBar.buttons["回想"].tap()
        XCTAssertTrue(app.staticTexts["回想"].firstMatch.waitForExistence(timeout: 3))
    }

    @MainActor
    private func testAndSaveAIConfiguration(in app: XCUIApplication) {
        let test = app.buttons["ai.settings.testConnection"]
        for _ in 0..<3 where !test.isHittable { app.swipeUp() }
        test.tap()
        XCTAssertTrue(app.staticTexts["ai.settings.testResult"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["ai.settings.testResult"].label.contains("连接成功"))
        app.buttons["ai.settings.usePreset"].tap()
        XCTAssertTrue(app.navigationBars["AI 服务"].waitForNonExistence(timeout: 5))
    }

    @MainActor
    func testAssistantCanConnectAndManageSiliconFlowModels() {
        let app = launchApp()
        app.tabBars.firstMatch.buttons["助手"].tap()
        app.buttons["assistant.more"].tap()
        app.buttons["assistant.settings"].tap()
        XCTAssertTrue(app.navigationBars["AI 服务"].waitForExistence(timeout: 3))

        selectAIProvider("SiliconFlow", in: app)

        let apiKey = app.secureTextFields["ai.settings.apiKey"]
        XCTAssertTrue(apiKey.waitForExistence(timeout: 3))
        XCTAssertFalse(app.textFields["ai.settings.baseURL"].exists)
        XCTAssertFalse(app.textFields["ai.settings.model"].exists)

        apiKey.tap()
        apiKey.typeText("fake-ui-key")
        app.buttons["ai.settings.connect"].tap()
        XCTAssertTrue(
            app.staticTexts["ai.settings.catalogLoaded"].waitForExistence(timeout: 5)
        )

        app.collectionViews.firstMatch.swipeUp()
        let currentModel = app.buttons["ai.settings.currentModel"]
        XCTAssertTrue(currentModel.waitForExistence(timeout: 3))
        currentModel.tap()
        let qwenModel = app.buttons["ai.settings.modelOption.Qwen/Qwen3-32B"]
        XCTAssertTrue(qwenModel.waitForExistence(timeout: 3))
        qwenModel.tap()
        XCTAssertTrue(app.buttons["ai.settings.currentModel"].label.contains("Qwen/Qwen3-32B"))

        app.collectionViews.firstMatch.swipeUp()
        let manageModels = app.buttons["ai.settings.manageModels"]
        XCTAssertTrue(manageModels.waitForExistence(timeout: 3))
        manageModels.tap()
        XCTAssertTrue(app.navigationBars["管理模型"].waitForExistence(timeout: 3))
        let selectedModelToggle = app.switches["ai.model.visible.Qwen/Qwen3-32B"]
        XCTAssertTrue(selectedModelToggle.waitForExistence(timeout: 3))
        XCTAssertFalse(selectedModelToggle.isEnabled)

        let hiddenModelToggle = app.switches["ai.model.visible.deepseek-ai/DeepSeek-V3"]
        XCTAssertTrue(hiddenModelToggle.waitForExistence(timeout: 3))
        XCTAssertTrue(hiddenModelToggle.isEnabled)
        hiddenModelToggle.coordinate(
            withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)
        ).tap()
        let hidden = NSPredicate(format: "value == %@", "0")
        expectation(for: hidden, evaluatedWith: hiddenModelToggle)
        waitForExpectations(timeout: 3)
        app.navigationBars["管理模型"].buttons["AI 服务"].tap()

        testAndSaveAIConfiguration(in: app)
        XCTAssertTrue(app.buttons["assistant.sessions"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["assistant.more"].exists)
    }

    @MainActor
    func testAssistantRequiresAIConfigurationBeforeAcceptingPrompts() {
        let app = XCUIApplication()
        app.launchEnvironment["TOUGH_TRIAL_UI_TESTING"] = "1"
        app.launchEnvironment["TOUGH_TRIAL_UI_TEST_REQUIRE_AI_CONFIGURATION"] = "1"
        app.launch()

        app.tabBars.firstMatch.buttons["助手"].tap()

        XCTAssertTrue(app.staticTexts["先连接 AI"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.textViews["assistant.composer"].exists)
        XCTAssertFalse(app.buttons["assistant.starter.plan"].exists)
        keepScreenshot(of: app, name: "assistant-ai-configuration-required")

        let configure = app.buttons["assistant.configureAI"]
        XCTAssertTrue(configure.exists)
        configure.tap()
        XCTAssertTrue(app.navigationBars["AI 服务"].waitForExistence(timeout: 3))

        selectAIProvider("SiliconFlow", in: app)

        let apiKey = app.secureTextFields["ai.settings.apiKey"]
        apiKey.tap()
        apiKey.typeText("fake-ui-key")
        app.buttons["ai.settings.connect"].tap()
        XCTAssertTrue(app.staticTexts["ai.settings.catalogLoaded"].waitForExistence(timeout: 5))

        app.collectionViews.firstMatch.swipeUp()
        let currentModel = app.buttons["ai.settings.currentModel"]
        XCTAssertTrue(currentModel.waitForExistence(timeout: 3))
        currentModel.tap()
        let qwenModel = app.buttons["ai.settings.modelOption.Qwen/Qwen3-32B"]
        XCTAssertTrue(qwenModel.waitForExistence(timeout: 3))
        qwenModel.tap()
        XCTAssertTrue(app.buttons["ai.settings.currentModel"].label.contains("Qwen/Qwen3-32B"))
        testAndSaveAIConfiguration(in: app)

        XCTAssertTrue(app.textViews["assistant.composer"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["先连接 AI"].exists)
    }

    @MainActor
    func testAssistantCanConfigureKimiAndGLMCodingPlanPresets() {
        let app = XCUIApplication()
        app.launchEnvironment["TOUGH_TRIAL_UI_TESTING"] = "1"
        app.launchEnvironment["TOUGH_TRIAL_UI_TEST_REQUIRE_AI_CONFIGURATION"] = "1"
        app.launch()

        app.tabBars.firstMatch.buttons["助手"].tap()
        app.buttons["assistant.configureAI"].tap()
        XCTAssertTrue(app.navigationBars["AI 服务"].waitForExistence(timeout: 3))

        selectAIProvider("Kimi Coding Plan", in: app)

        let presetModel = app.buttons["ai.settings.presetModel"]
        XCTAssertTrue(presetModel.waitForExistence(timeout: 3))
        XCTAssertTrue(presetModel.label.contains("k3-256k"))

        let kimiKey = app.secureTextFields["ai.settings.apiKey"]
        kimiKey.tap()
        kimiKey.typeText("fake-kimi-key")
        testAndSaveAIConfiguration(in: app)
        XCTAssertTrue(app.textViews["assistant.composer"].waitForExistence(timeout: 3))

        app.buttons["assistant.more"].tap()
        app.buttons["assistant.settings"].tap()
        XCTAssertTrue(app.navigationBars["AI 服务"].waitForExistence(timeout: 3))

        selectAIProvider("GLM Coding Plan", in: app)
        let glmPresetModel = app.buttons["ai.settings.presetModel"]
        XCTAssertTrue(glmPresetModel.waitForExistence(timeout: 3))
        XCTAssertTrue(glmPresetModel.label.contains("glm-5.3-flash"))

        let glmKey = app.secureTextFields["ai.settings.apiKey"]
        XCTAssertEqual(glmKey.value as? String, "粘贴 API Key")
        glmKey.tap()
        glmKey.typeText("fake-glm-key")
        testAndSaveAIConfiguration(in: app)
        XCTAssertTrue(app.textViews["assistant.composer"].waitForExistence(timeout: 3))

        app.buttons["assistant.more"].tap()
        app.buttons["assistant.settings"].tap()
        selectAIProvider("Kimi Coding Plan", in: app)
        let restoredKimiKey = app.secureTextFields["ai.settings.apiKey"]
        XCTAssertTrue(restoredKimiKey.waitForExistence(timeout: 3))
        XCTAssertNotEqual(restoredKimiKey.value as? String, "粘贴 API Key")
    }

    @MainActor
    func testAssistantPlanDraftAutoSavesAndAllowsDirectEditing() {
        let app = launchApp()
        app.tabBars.firstMatch.buttons["助手"].tap()

        let composer = app.textViews["assistant.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 3))
        keepScreenshot(of: app, name: "assistant-empty")
        composer.tap()
        composer.typeText("帮我安排计划")
        app.buttons["assistant.send"].tap()
        XCTAssertTrue(
            app.staticTexts["我可以先给一个轻量安排，只确定最重要的推进点，其余时间保留弹性。这样可以吗？"]
                .waitForExistence(timeout: 5)
        )
        composer.tap()
        composer.typeText("帮我安排计划，可以")
        app.buttons["assistant.send"].tap()

        XCTAssertTrue(app.buttons["assistant.plan.accept"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["计划草稿 · 自动保存"].exists)
        keepScreenshot(of: app, name: "assistant-plan-artifact")

        let editableItem = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "编辑安排：")
        ).firstMatch
        XCTAssertTrue(editableItem.waitForExistence(timeout: 3))
        editableItem.tap()

        let title = app.textFields["assistant.plan.editor.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        keepScreenshot(of: app, name: "plan-v2-editor")
        title.tap()
        title.typeText("（调整）")
        app.buttons["assistant.plan.editor.save"].tap()
        XCTAssertTrue(
            app.buttons.matching(
                NSPredicate(format: "label CONTAINS %@", "（调整）")
            ).firstMatch.waitForExistence(timeout: 3)
        )
    }

    @MainActor
    func testAssistantRequestFailureStaysVisibleInConversation() {
        let app = XCUIApplication()
        app.launchEnvironment["TOUGH_TRIAL_UI_TESTING"] = "1"
        app.launchEnvironment["TOUGH_TRIAL_UI_TEST_PLANNING_FAILURE"] = "1"
        app.launch()

        app.tabBars.firstMatch.buttons["助手"].tap()
        let composer = app.textViews["assistant.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 3))
        composer.tap()
        composer.typeText("帮我安排明天")
        app.buttons["assistant.send"].tap()

        XCTAssertTrue(app.staticTexts["没有收到可用回复"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["assistant.retry"].exists)
        keepScreenshot(of: app, name: "assistant-error")
    }

    @MainActor
    func testAssistantComposerKeepsEnteredTextVisible() {
        let app = XCUIApplication()
        app.launchEnvironment["TOUGH_TRIAL_UI_TESTING"] = "1"
        app.launch()

        app.tabBars.firstMatch.buttons["助手"].tap()
        let composer = app.textViews["assistant.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 3))
        composer.tap()
        composer.typeText("这周想跑十公里")
        XCTAssertEqual(composer.value as? String, "这周想跑十公里")
        keepScreenshot(of: app, name: "assistant-composer")
    }

    @MainActor
    func testAssistantSessionsKeepConversationIsolatedAndSearchable() {
        let app = launchApp()
        app.tabBars.firstMatch.buttons["助手"].tap()
        let composer = app.textViews["assistant.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 3))

        composer.tap()
        composer.typeText("第一段独立对话")
        app.buttons["assistant.send"].tap()
        XCTAssertTrue(app.staticTexts["测试回复：第一段独立对话"].waitForExistence(timeout: 5))

        composer.tap()
        composer.typeText("先做最重要的一件事，剩下的晚点再看")
        app.buttons["assistant.send"].tap()
        XCTAssertTrue(app.staticTexts["测试回复：先做最重要的一件事，剩下的晚点再看"].waitForExistence(timeout: 5))
        keepScreenshot(of: app, name: "assistant-multiturn")

        app.buttons["assistant.newSession"].tap()
        XCTAssertTrue(app.staticTexts["想一起处理什么？"].waitForExistence(timeout: 3))
        composer.tap()
        composer.typeText("第二段独立对话")
        app.buttons["assistant.send"].tap()
        XCTAssertTrue(app.staticTexts["测试回复：第二段独立对话"].waitForExistence(timeout: 5))

        app.buttons["assistant.sessions"].tap()
        let search = app.textFields["assistant.sessions.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        keepScreenshot(of: app, name: "assistant-session-list")
        search.tap()
        search.typeText("第一段")
        XCTAssertTrue(app.buttons["第一段独立对话"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["第二段独立对话"].exists)
        app.buttons["第一段独立对话"].tap()

        XCTAssertTrue(app.staticTexts["第一段独立对话"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["测试回复：第一段独立对话"].exists)
        XCTAssertFalse(app.staticTexts["第二段独立对话"].exists)
    }

    @MainActor
    func testAssistantRendersTraceSourcesAndFullSessionDetails() {
        let app = launchApp()
        app.tabBars.firstMatch.buttons["助手"].tap()
        let composer = app.textViews["assistant.composer"]
        composer.tap()
        composer.typeText("搜索网页")
        app.buttons["assistant.send"].tap()

        XCTAssertTrue(app.staticTexts["测试回复已根据工具结果生成。"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Tough Trial 测试来源"].exists)
        let trace = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "完成 3 个步骤")
        ).firstMatch
        XCTAssertTrue(trace.waitForExistence(timeout: 3))
        keepScreenshot(of: app, name: "assistant-sources")
        trace.tap()
        XCTAssertTrue(app.staticTexts["搜索网页"].waitForExistence(timeout: 3))
        keepScreenshot(of: app, name: "assistant-conversation-trace")

        app.buttons["assistant.more"].tap()
        app.buttons["assistant.details"].tap()
        XCTAssertTrue(app.navigationBars["会话详情"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["UI 测试 Agent"].exists)
        XCTAssertTrue(app.staticTexts["deterministic-ui-test"].exists)
    }

    @MainActor
    func testAssistantSupportsMultipleInlineBrowsers() {
        let app = XCUIApplication()
        app.launchEnvironment["TOUGH_TRIAL_AI_API_KEY"] = ""
        app.launchEnvironment["TOUGH_TRIAL_UI_TESTING"] = "1"
        app.launchEnvironment["TOUGH_TRIAL_UI_TEST_BROWSER_FIXTURE"] = "1"
        app.launch()

        app.tabBars.firstMatch.buttons["助手"].tap()
        let composer = app.textViews["assistant.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 3))
        composer.tap()
        composer.typeText("搜索网页")
        app.buttons["assistant.send"].tap()

        XCTAssertTrue(app.staticTexts["测试回复已根据工具结果生成。"].waitForExistence(timeout: 5))
        let sources = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "assistant.source.")
        )
        let firstSource = sources.element(boundBy: 0)
        let secondSource = sources.element(boundBy: 1)
        XCTAssertTrue(firstSource.waitForExistence(timeout: 3))
        XCTAssertTrue(secondSource.waitForExistence(timeout: 3))

        firstSource.tap()
        let inlineBrowsers = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "assistant.browser.inline.")
        )
        let firstInlineBrowser = inlineBrowsers.element(boundBy: 0)
        XCTAssertTrue(firstInlineBrowser.waitForExistence(timeout: 3))

        // Expanded content can place the next source behind the fixed composer on small screens.
        let conversation = app.scrollViews["assistant.conversation"]
        conversation.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.60))
            .press(forDuration: 0.05, thenDragTo: conversation.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.12)))
        secondSource.tap()
        let secondInlineBrowser = inlineBrowsers.element(boundBy: 1)
        XCTAssertTrue(secondInlineBrowser.waitForExistence(timeout: 3))
        XCTAssertTrue(composer.exists)
        keepScreenshot(of: app, name: "assistant-two-inline-browsers")

        conversation.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.60))
            .press(forDuration: 0.05, thenDragTo: conversation.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.12)))
        let fullscreenButton = app.buttons.matching(identifier: "assistant.browser.fullscreen").allElementsBoundByIndex.last!
        XCTAssertTrue(fullscreenButton.waitForExistence(timeout: 3))
        fullscreenButton.tap()

        let fullscreenBrowser = app.descendants(matching: .any)["assistant.browser.fullscreen"]
        XCTAssertTrue(fullscreenBrowser.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["assistant.browser.minimize"].exists)
        XCTAssertTrue(app.buttons["assistant.browser.back"].exists)
        XCTAssertTrue(app.buttons["assistant.browser.openExternal"].exists)
        keepScreenshot(of: app, name: "assistant-fullscreen-browser")

        app.buttons["assistant.browser.minimize"].tap()
        XCTAssertTrue(firstInlineBrowser.waitForExistence(timeout: 3))
        XCTAssertTrue(secondInlineBrowser.waitForExistence(timeout: 3))
    }

    @MainActor
    func testQuickAddCreatesTodayTaskOnlyAfterSubmit() {
        let app = launchApp()
        let taskTitle = "UI test \(UUID().uuidString.prefix(8))"
        app.descendants(matching: .any)["today.quickAdd"].tap()

        let document = app.textViews["today.quickAdd.document"]
        XCTAssertTrue(document.waitForExistence(timeout: 3))
        document.typeText(taskTitle)
        XCTAssertFalse(app.staticTexts[taskTitle].exists)

        app.buttons["today.quickAdd.submit"].tap()
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
        let document = app.textViews["tasks.capture.document"]
        XCTAssertTrue(document.waitForExistence(timeout: 3))
        document.typeText(cancelledTitle)
        app.buttons["tasks.capture.cancel"].tap()
        app.buttons["放弃修改"].tap()
        XCTAssertTrue(document.waitForNonExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts[cancelledTitle].exists)

        app.buttons["tasks.capture.open"].tap()
        XCTAssertTrue(document.waitForExistence(timeout: 3))
        keepScreenshot(of: app, name: "remediation-task-capture-structure")
        document.typeText(structureTitle)
        app.buttons["tasks.capture.submit"].tap()
        XCTAssertTrue(document.waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.buttons[structureTitle].waitForExistence(timeout: 5))
        keepScreenshot(of: app, name: "remediation-task-created-structure")

        app.buttons["tasks.lens.fishbone"].tap()
        app.buttons["tasks.capture.open"].tap()
        XCTAssertTrue(document.waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["tasks.capture.location"].label, "鱼骨 / 未归类")
        keepScreenshot(of: app, name: "remediation-task-capture-fishbone")
        document.typeText(fishboneTitle)
        app.buttons["tasks.capture.submit"].tap()
        XCTAssertTrue(document.waitForNonExistence(timeout: 3))

        for _ in 0..<2 {
            app.terminate()
            app = launchProductionApp()
            assertTaskCanBeFoundForZen(structureTitle, in: app)
            assertTaskCanBeFoundForZen(fishboneTitle, in: app)
        }
    }

    @MainActor
    func testTaskDetailOpensContextualAssistantAndWritesOnlyOnAccept() {
        let app = launchApp()
        app.tabBars.firstMatch.buttons["任务"].tap()
        app.buttons["tasks.lens.structure"].tap()

        let details = app.buttons["查看详情：定位"]
        let disclosure = app.buttons["定位"]
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        XCTAssertTrue(disclosure.exists)
        details.tap()

        XCTAssertTrue(app.buttons["tasks.detail.title"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.buttons["tasks.detail.title"].label, "定位")
        XCTAssertTrue(app.buttons["tasks.detail.aiPlan"].exists)
        keepScreenshot(of: app, name: "remediation-task-detail")
        app.buttons["tasks.detail.aiPlan"].tap()

        let context = app.staticTexts["assistant.context.task"]
        XCTAssertTrue(context.waitForExistence(timeout: 5))
        XCTAssertEqual(context.label, "来自任务：定位")
        XCTAssertFalse(app.buttons["加入计划"].exists)
        keepScreenshot(of: app, name: "remediation-task-assistant-context")

        let composer = app.textViews["assistant.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 3))
        composer.tap()
        composer.typeText("帮我安排这周跑 10 公里")
        app.buttons["assistant.send"].tap()
        XCTAssertTrue(
            app.staticTexts["分三次会比较轻松：3 + 3 + 4 公里，最长的一次放在周末。这样安排可以吗？"]
                .waitForExistence(timeout: 5)
        )
        composer.tap()
        composer.typeText("可以，继续安排")
        app.buttons["assistant.send"].tap()
        XCTAssertTrue(app.buttons["assistant.plan.accept"].waitForExistence(timeout: 5))

        app.tabBars.firstMatch.buttons["今天"].tap()
        app.tabBars.firstMatch.buttons["今天"].tap()
        assertTaskIsMissingFromZenSearch("轻松跑 3 公里", in: app)

        app.tabBars.firstMatch.buttons["任务"].tap()
        XCTAssertTrue(details.waitForExistence(timeout: 3))
        details.tap()
        app.buttons["tasks.detail.aiPlan"].tap()
        XCTAssertTrue(app.buttons["assistant.plan.accept"].waitForExistence(timeout: 5))
        app.buttons["assistant.plan.accept"].tap()
        XCTAssertTrue(app.staticTexts["已加入计划"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["assistant.plan.accept"].exists)
        app.tabBars.firstMatch.buttons["今天"].tap()

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
        app.buttons["tasks.lens.structure"].tap()

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
        app.buttons["tasks.lens.list"].tap()
        XCTAssertTrue(app.buttons["建立稳定创作系统"].waitForExistence(timeout: 3))
        keepScreenshot(of: app, name: "tasks-root-list")
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
    func testLooseTasksShareOneListAndOpenDetails() {
        let app = launchEmptyApp()
        app.tabBars.firstMatch.buttons["任务"].tap()
        for title in ["买牛奶", "取快递"] {
            app.buttons["tasks.capture.open"].tap()
            let input = app.textViews["tasks.capture.document"]
            XCTAssertTrue(input.waitForExistence(timeout: 3))
            XCTAssertEqual(app.staticTexts["tasks.capture.location"].label, "结构 / 新建根任务")
            input.tap()
            input.typeText(title)
            app.buttons["tasks.capture.submit"].tap()
        }
        XCTAssertTrue(app.buttons["买牛奶"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["取快递"].exists)
        keepScreenshot(of: app, name: "tasks-shared-list")
        app.buttons["买牛奶"].tap()
        XCTAssertTrue(app.staticTexts["买牛奶"].firstMatch.waitForExistence(timeout: 3))
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

        tabBar.buttons["助手"].tap()
        XCTAssertTrue(app.staticTexts["想一起处理什么？"].waitForExistence(timeout: 3))
        keepScreenshot(of: app, name: "03-assistant")

        app.tabBars.firstMatch.buttons["今天"].tap()
        tabBar.buttons["回想"].tap()
        XCTAssertTrue(app.staticTexts["回想"].firstMatch.waitForExistence(timeout: 3))
        keepScreenshot(of: app, name: "04-recall")
    }

    @MainActor
    func testAssistantOffersRealtimeSpeechAndIndependentSettings() {
        let app = launchApp()
        app.tabBars.firstMatch.buttons["助手"].tap()
        XCTAssertTrue(app.buttons["assistant.speech.start"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["assistant.speech.finish"].exists)
        keepScreenshot(of: app, name: "assistant-realtime-speech-entry")
        let selector = app.buttons["assistant.speech.provider"]
        XCTAssertTrue(selector.exists)
        selector.tap()
        app.buttons["苹果原生"].tap()
        XCTAssertTrue(selector.label.contains("苹果原生"))
        selector.tap()
        app.buttons["阿里云 FunASR"].tap()
        XCTAssertTrue(selector.label.contains("FunASR"))
        app.buttons["assistant.more"].tap()
        app.buttons["assistant.settings"].tap()
        app.buttons["ai.settings.speech"].tap()
        app.segmentedControls["speech.settings.provider"].buttons["阿里云 FunASR"].tap()
        XCTAssertTrue(app.secureTextFields["speech.settings.apiKey"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["speech.settings.save"].exists)
        XCTAssertFalse(app.staticTexts["无法读取语音配置，请稍后重试。"].exists)
        keepScreenshot(of: app, name: "assistant-realtime-speech-settings")
        app.segmentedControls["speech.settings.provider"].buttons["苹果原生"].tap()
        XCTAssertTrue(app.buttons["speech.settings.prepareApple"].exists)
        XCTAssertFalse(app.secureTextFields["speech.settings.apiKey"].exists)
        keepScreenshot(of: app, name: "assistant-apple-speech-settings")
        app.terminate()
        app.launch()
        app.tabBars.firstMatch.buttons["助手"].tap()
        app.buttons["assistant.speech.settings"].tap()
        XCTAssertTrue(app.buttons["speech.settings.prepareApple"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.segmentedControls["speech.settings.provider"].buttons["苹果原生"].isSelected)
        app.segmentedControls["speech.settings.provider"].buttons["阿里云 FunASR"].tap()
        XCTAssertTrue(app.secureTextFields["speech.settings.apiKey"].exists)

    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TOUGH_TRIAL_AI_API_KEY"] = ""
        app.launchEnvironment["TOUGH_TRIAL_UI_TESTING"] = "1"
        app.launch()
        app.tabBars.firstMatch.buttons["今天"].tap()
        return app
    }

    @MainActor
    private func launchEmptyApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TOUGH_TRIAL_AI_API_KEY"] = ""
        app.launchEnvironment["TOUGH_TRIAL_UI_TESTING"] = "0"
        app.launchEnvironment["TOUGH_TRIAL_UI_TEST_EMPTY"] = "1"
        app.launch()
        app.tabBars.firstMatch.buttons["今天"].tap()
        return app
    }

    @MainActor
    private func launchProductionApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TOUGH_TRIAL_AI_API_KEY"] = ""
        app.launchEnvironment["TOUGH_TRIAL_UI_TESTING"] = "0"
        app.launchEnvironment["TOUGH_TRIAL_UI_TEST_EMPTY"] = "0"
        app.launch()
        app.tabBars.firstMatch.buttons["今天"].tap()
        return app
    }

    @MainActor
    private func addTodayTask(_ title: String, in app: XCUIApplication) {
        let quickAdd = app.descendants(matching: .any)["today.quickAdd"]
        XCTAssertTrue(quickAdd.waitForExistence(timeout: 5))
        quickAdd.tap()
        let document = app.textViews["today.quickAdd.document"]
        XCTAssertTrue(document.waitForExistence(timeout: 3))
        document.typeText(title)
        app.buttons["today.quickAdd.submit"].tap()
        XCTAssertTrue(document.waitForNonExistence(timeout: 3))
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
    private func selectAIProvider(
        _ name: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let provider = app.buttons["ai.settings.provider"]
        XCTAssertTrue(provider.waitForExistence(timeout: 3), file: file, line: line)
        if (provider.label + String(describing: provider.value)).contains(name) { return }
        provider.tap()
        let option = app.buttons[name]
        XCTAssertTrue(option.waitForExistence(timeout: 3), file: file, line: line)
        option.tap()
        if !provider.waitForExistence(timeout: 2) { app.navigationBars.buttons.firstMatch.tap() }
        XCTAssertTrue(provider.waitForExistence(timeout: 3), file: file, line: line)
        XCTAssertTrue((provider.label + String(describing: provider.value)).contains(name), file: file, line: line)
    }

    @MainActor
    private func keepScreenshot(of app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

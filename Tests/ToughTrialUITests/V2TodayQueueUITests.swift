import XCTest

@MainActor
final class V2TodayQueueUITests: XCTestCase {
    func testTodayScrollsHeroAndKeepsQuietCompletedTimeline() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TOUGH_TRIAL_UI_TEST_EMPTY"] = "1"
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.terminate(); app.launch()
        app.buttons["root.tab.today"].tap()
        let names = ["阅读一页", "整理资料", "写作练习", "买早餐", "回访计划", "预备邮件", "整理笔记", "晚上散步", "记录想法", "备份资料", "核对清单", "准备明天"]
        for name in names {
            app.buttons["today.quickAdd"].tap()
            let document = app.textViews["today.quickAdd.document"]
            XCTAssertTrue(document.waitForExistence(timeout: 5))
            document.tap(); document.typeText(name)
            app.buttons["today.quickAdd.submit"].tap()
        }
        start(names[0], app)
        let pause = app.buttons["today.focus.pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 5))
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<3 { scroll.swipeUp() }
        capture(app, "today-scrolls-to-details-native")
        XCTAssertLessThanOrEqual(pause.frame.maxY, app.frame.minY,
                                 "主卡片必须随页面滚出视口，给下方内容让出空间")
        XCTAssertTrue(app.buttons["today.quickAdd"].isHittable)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '执行中'")).firstMatch.exists)
        app.buttons["today.quickAdd"].tap()
        XCTAssertFalse(app.buttons["today.quickAdd.submit"].isEnabled)
        let draft = app.textViews["today.quickAdd.document"]
        XCTAssertTrue(draft.waitForExistence(timeout: 5))
        draft.tap(); draft.typeText("未保存草稿")
        app.buttons["today.quickAdd.cancel"].tap()
        let discard = app.alerts["放弃未保存的修改？"]
        XCTAssertTrue(discard.waitForExistence(timeout: 5))
        discard.buttons["继续编辑"].tap()
        XCTAssertEqual(draft.value as? String, "未保存草稿")
        app.buttons["today.quickAdd.cancel"].tap()
        discard.buttons["放弃修改"].tap()
        XCTAssertTrue(draft.waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.buttons["today.plan.未保存草稿"].exists)

        let lastRow = app.buttons["today.plan.\(names.last!)"]
        reveal(lastRow, app)
        let time = app.staticTexts["today.timeline.time.\(names.last!)"]
        XCTAssertTrue(time.exists)
        XCTAssertEqual(time.label, "今天")
        XCTAssertLessThan(time.frame.maxX, lastRow.frame.minX)

        let complete = app.buttons["today.focus.complete"]
        reveal(complete, app); complete.tap()
        let done = app.buttons["today.plan.\(names[0])"]
        reveal(done, app)
        XCTAssertEqual(done.value as? String, "已完成")
        XCTAssertTrue(done.label.contains("已完成"))
        XCTAssertFalse(app.buttons["today.restore.\(names[0])"].exists,
                       "完成条目的恢复操作应默认收起")
        let pending = app.buttons["today.plan.\(names[1])"]
        XCTAssertLessThan(done.frame.height, pending.frame.height)
        XCTAssertGreaterThanOrEqual(done.frame.height, 44)
        capture(app, "today-quiet-completed-timeline-native")
        done.tap()
        let restore = app.buttons["today.restore.\(names[0])"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5)); restore.tap()
        XCTAssertEqual(done.value as? String, "未完成")
        XCTAssertFalse(app.buttons["today.focus.pause"].exists)
        app.terminate()
    }

    func testQueuePauseCompleteRestoreAndCaptureReview() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TOUGH_TRIAL_UI_TEST_EMPTY"] = "1"
        app.terminate(); app.launch()
        app.buttons["root.tab.today"].tap()
        XCTAssertTrue(app.buttons["today.emptyZen.startUnlinked"].waitForExistence(timeout: 5))
        capture(app, "today-empty-native")
        for name in ["页面评审", "整理素材", "同步方案"] {
            app.buttons["today.quickAdd"].tap()
            let field = app.textViews["today.quickAdd.document"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap(); field.typeText(name)
            app.buttons["today.quickAdd.submit"].tap()
        }
        start("整理素材", app)
        start("页面评审", app)
        XCTAssertTrue(app.buttons["today.queue.整理素材"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["today.plan.页面评审"].exists)
        reveal(app.buttons["today.focus.pause"], app)
        capture(app, "today-native")
        app.buttons["today.focus.pause"].tap()
        XCTAssertTrue(app.buttons["today.plan.页面评审"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["today.queue.整理素材"].exists)
        XCTAssertTrue(app.buttons["today.focus.complete"].exists)
        capture(app, "today-paused-native")
        reveal(app.buttons["today.focus.complete"], app)
        app.buttons["today.focus.complete"].tap()
        let done = app.buttons["today.plan.整理素材"]
        reveal(done, app)
        XCTAssertEqual(done.value as? String, "已完成")
        XCTAssertTrue(done.label.contains("已完成"))
        let restored = app.buttons["today.restore.整理素材"]
        XCTAssertFalse(restored.exists)
        let pending = app.buttons["today.plan.同步方案"]
        XCTAssertLessThan(done.frame.height, pending.frame.height)
        XCTAssertGreaterThanOrEqual(done.frame.height, 44)
        capture(app, "today-completed-native")
        done.tap()
        reveal(restored, app)
        restored.tap()
        XCTAssertFalse(app.buttons["today.restore.整理素材"].exists)
        XCTAssertFalse(app.buttons["today.focus.complete"].exists)
        start("页面评审", app)
        XCTAssertTrue(app.buttons["today.focus.pause"].waitForExistence(timeout: 5))
        app.terminate()
    }

    func testInvertedTreeModesFocusAndControls() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TOUGH_TRIAL_UI_TESTING"] = "1"
        app.launch()
        app.buttons["root.tab.tasks"].tap()
        XCTAssertGreaterThanOrEqual(app.buttons["tasks.lens.structure"].frame.height, 44)
        app.buttons["tasks.lens.structure"].tap()
        let overview = app.staticTexts["tasks.inverted.overviewRoot"]
        XCTAssertTrue(overview.waitForExistence(timeout: 3))
        XCTAssertTrue(overview.isHittable)
        XCTAssertEqual(overview.label, "未分类")
        XCTAssertEqual(app.staticTexts.matching(identifier: "tasks.inverted.overviewRoot").count, 1)
        XCTAssertFalse(app.buttons["tasks.structure.mode.directory"].exists)
        XCTAssertFalse(app.buttons["tasks.structure.mode.inverted"].exists)
        overview.tap()
        XCTAssertFalse(app.buttons["tasks.inverted.details"].exists)
        let root = app.buttons["选择任务：建立稳定创作系统"]
        let branch = app.buttons["选择任务：定位"]
        let other = app.buttons["选择任务：选题库"]
        XCTAssertTrue(branch.waitForExistence(timeout: 3))
        XCTAssertGreaterThan(branch.frame.minY, root.frame.maxY)
        XCTAssertGreaterThan(other.frame.minX, branch.frame.maxX)
        XCTAssertGreaterThanOrEqual(branch.frame.height, 44)
        let disclosure = app.buttons["收起子任务：定位"]
        XCTAssertGreaterThanOrEqual(disclosure.frame.width, 44)
        XCTAssertGreaterThanOrEqual(disclosure.frame.height, 44)
        XCTAssertLessThanOrEqual(branch.frame.maxX, disclosure.frame.minX,
                                 "选择与展开点击区应彼此独立")
        capture(app, "inverted-tree-native-overview")
        revealTree(branch, app)
        branch.tap()
        capture(app, "inverted-tree-native-selection")
        app.buttons["tasks.inverted.details"].tap()
        XCTAssertEqual(app.buttons["tasks.detail.title"].label, "定位")
        app.buttons["tasks.detail.close"].tap()
        app.buttons["tasks.inverted.focus"].tap()
        XCTAssertFalse(other.exists)
        XCTAssertTrue(app.buttons["tasks.inverted.back"].exists)
        capture(app, "inverted-tree-native-focus")
        let toggle = app.buttons["收起子任务：定位"]
        toggle.tap()
        XCTAssertFalse(app.buttons["选择任务：内容边界"].exists)
        app.buttons["展开子任务：定位"].tap()
        XCTAssertTrue(app.buttons["选择任务：内容边界"].exists)
        app.buttons["tasks.inverted.back"].tap()
        XCTAssertTrue(other.exists)
        XCTAssertFalse(overview.exists, "返回父任务后仍处于该真实分支")
        app.buttons["tasks.inverted.back"].tap()
        XCTAssertTrue(overview.waitForExistence(timeout: 3))
        app.buttons["tasks.inverted.zoomOut"].tap()
        app.buttons["tasks.inverted.zoomOut"].tap()
        XCTAssertFalse(app.buttons["tasks.inverted.zoomOut"].isEnabled)
        app.buttons["tasks.inverted.reset"].tap()
        let width = root.frame.width
        app.buttons["tasks.inverted.zoomIn"].tap()
        XCTAssertGreaterThan(root.frame.width, width)
        app.buttons["tasks.inverted.reset"].tap()
        app.scrollViews["tasks.inverted.canvas"].pinch(withScale: 1.2, velocity: 1)
        XCTAssertGreaterThan(root.frame.width, width)
        app.buttons["tasks.inverted.reset"].tap()
        app.buttons["tasks.capture.open"].tap()
        XCTAssertFalse(app.buttons["tasks.capture.submit"].isEnabled)
        app.buttons["tasks.capture.cancel"].tap()
        XCTAssertTrue(root.exists)
        XCTAssertTrue(overview.isHittable)
        app.buttons["tasks.lens.list"].tap()
        XCTAssertTrue(app.buttons["建立稳定创作系统"].exists)
        app.buttons["tasks.lens.structure"].tap()
        XCTAssertTrue(overview.waitForExistence(timeout: 3))
        app.terminate()
    }

    func testInvertedSixLevelsAndEmptyModes() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TOUGH_TRIAL_UI_TESTING"] = "1"
        app.launchEnvironment["TOUGH_TRIAL_UI_TEST_SIX_LEVELS"] = "1"
        app.launch()
        app.buttons["root.tab.tasks"].tap()
        app.buttons["tasks.lens.structure"].tap()
        XCTAssertFalse(app.buttons["tasks.structure.mode.directory"].exists)
        capture(app, "structure-common-root-forest-native")
        let secondRoot = app.buttons["选择任务：另一棵树：健康计划"]
        revealTree(secondRoot, app)
        XCTAssertTrue(secondRoot.isHittable)
        XCTAssertLessThanOrEqual(secondRoot.frame.maxX, app.frame.maxX + 1)
        app.buttons["tasks.inverted.reset"].tap()
        for title in ["知识分享系列", "写作方法专题", "文章结构训练"] {
            let control = app.buttons["展开子任务：\(title)"]
            revealTree(control, app)
            XCTAssertTrue(control.isHittable)
            control.tap()
        }
        let leaf = app.buttons["选择任务：整理三个真实案例并写出各自的开头与结尾"]
        revealTree(leaf, app)
        XCTAssertTrue(leaf.isHittable)
        capture(app, "inverted-tree-native-six-levels")
        leaf.tap()
        app.buttons["tasks.inverted.details"].tap()
        XCTAssertEqual(app.buttons["tasks.detail.title"].label, "整理三个真实案例并写出各自的开头与结尾")
        app.buttons["tasks.detail.close"].tap()
        app.buttons["tasks.inverted.focus"].tap()
        XCTAssertTrue(app.buttons["选择任务：文章结构训练"].isHittable)
        XCTAssertTrue(leaf.isHittable)
        leaf.tap()
        XCTAssertFalse(app.buttons["tasks.inverted.focus"].isEnabled)
        app.buttons["tasks.inverted.dismissSelection"].tap()
        XCTAssertFalse(app.buttons["tasks.inverted.details"].exists)
        app.buttons["tasks.inverted.back"].tap()
        XCTAssertTrue(app.buttons["选择任务：写作方法专题"].isHittable)
        for _ in 0..<4 { app.buttons["tasks.inverted.zoomIn"].tap() }
        XCTAssertFalse(app.buttons["tasks.inverted.zoomIn"].isEnabled)
        app.buttons["tasks.inverted.reset"].tap()
        app.terminate()
        app.launchEnvironment = ["TOUGH_TRIAL_UI_TEST_EMPTY": "1"]
        app.launch()
        app.buttons["root.tab.tasks"].tap()
        app.buttons["tasks.lens.structure"].tap()
        XCTAssertTrue(app.staticTexts["还没有任务"].exists)
        XCTAssertFalse(app.staticTexts["tasks.inverted.overviewRoot"].exists)
        XCTAssertFalse(app.buttons["tasks.structure.mode.directory"].exists)
        capture(app, "structure-empty-native")
        app.terminate()
    }

    func testStructureCompletedNodesRestoreAndUndo() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TOUGH_TRIAL_UI_TESTING"] = "1"
        app.launch()
        app.buttons["root.tab.tasks"].tap()
        app.buttons["tasks.lens.structure"].tap()
        let leaf = app.buttons["选择任务：内容边界"]
        revealTree(leaf, app)
        XCTAssertEqual(leaf.value as? String, "已完成")
        capture(app, "structure-completed-leaf-native")
        leaf.tap()
        app.buttons["tasks.inverted.details"].tap()
        XCTAssertEqual(app.staticTexts["tasks.detail.status"].label, "已完成")
        app.buttons["tasks.detail.complete"].tap()
        XCTAssertEqual(app.staticTexts["tasks.detail.status"].label, "未开始")
        app.buttons["tasks.detail.undo"].tap()
        XCTAssertEqual(app.staticTexts["tasks.detail.status"].label, "已完成")
        app.buttons["tasks.detail.close"].tap()
        XCTAssertEqual(leaf.value as? String, "已完成")
        app.buttons["tasks.inverted.dismissSelection"].tap()
        app.buttons["tasks.inverted.reset"].tap()
        let parent = app.buttons["选择任务：建立稳定创作系统"]
        revealTree(parent, app)
        parent.tap()
        app.buttons["tasks.inverted.details"].tap()
        app.buttons["tasks.detail.complete"].tap()
        XCTAssertEqual(app.staticTexts["tasks.detail.status"].label, "已完成")
        app.buttons["tasks.detail.close"].tap()
        XCTAssertEqual(parent.value as? String, "已完成")
        app.buttons["tasks.inverted.dismissSelection"].tap()
        app.buttons["tasks.inverted.reset"].tap()
        capture(app, "structure-completed-parent-native")
        app.terminate()
    }

    func testMorePluginsUsesPaperThemeAndEditsNavigation() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TOUGH_TRIAL_UI_TESTING"] = "1"
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        app.buttons["root.tab.morePlugins"].tap()
        XCTAssertTrue(app.navigationBars["更多插件"].exists)
        app.buttons["morePlugins.editNavigation"].tap()
        XCTAssertTrue(app.navigationBars["编辑底部导航"].exists)
        revealList(app.buttons["navigation.add.recall"], app)
        XCTAssertFalse(app.buttons["navigation.add.recall"].isEnabled)
        revealList(app.buttons["navigation.remove.assistant"], app)
        app.buttons["navigation.remove.assistant"].tap()
        app.buttons["navigation.remove.capture"].tap()
        revealList(app.buttons["navigation.add.transcription"], app)
        app.buttons["navigation.add.transcription"].tap()
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'root.tab.'")).count, 4)
        XCTAssertTrue(app.buttons["root.tab.transcription"].exists)
        XCTAssertFalse(app.buttons["root.tab.capture"].exists)
        capture(app, "navigation-editor-four-tabs-native")
        app.navigationBars["编辑底部导航"].buttons.firstMatch.tap()
        let taskTab = app.buttons["root.tab.tasks"]
        let moreTab = app.buttons["root.tab.morePlugins"]
        taskTab.press(forDuration: 1, thenDragTo: moreTab)
        moreTab.press(forDuration: 1, thenDragTo: taskTab)
        XCTAssertLessThan(app.buttons["root.tab.transcription"].frame.midX, moreTab.frame.midX)
        XCTAssertLessThan(moreTab.frame.midX, taskTab.frame.midX)
        capture(app, "more-plugins-paper-four-tabs-native")
        app.buttons["morePlugins.open.ownProfile"].tap()
        XCTAssertTrue(app.buttons["profile.showQR"].waitForExistence(timeout: 5))
        app.navigationBars["我的资料"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)))
        XCTAssertTrue(app.buttons["profile.showQR"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["morePlugins.editNavigation"].isHittable)
        revealList(app.buttons["morePlugins.settings"], app)
        app.buttons["morePlugins.settings"].tap()
        XCTAssertTrue(app.switches["plugin.toggle.tasks"].waitForExistence(timeout: 5))
        app.navigationBars.firstMatch.buttons.firstMatch.tap()
        revealList(app.buttons["morePlugins.editNavigation"], app)
        app.buttons["morePlugins.editNavigation"].tap()
        app.buttons["navigation.remove.tasks"].tap()
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'root.tab.'")).count, 3)
        app.buttons["navigation.remove.transcription"].tap()
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'root.tab.'")).count, 2)
        XCTAssertFalse(app.buttons["navigation.remove.today"].isEnabled)
        XCTAssertFalse(app.buttons["navigation.remove.morePlugins"].exists)
        capture(app, "navigation-editor-two-tabs-native")
        for id in ["tasks", "transcription", "capture"] {
            let add = app.buttons["navigation.add.\(id)"]
            revealList(add, app); add.tap()
        }
        revealList(app.buttons["navigation.add.recall"], app)
        XCTAssertFalse(app.buttons["navigation.add.recall"].isEnabled)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'root.tab.'")).count, 5)
        revealList(app.staticTexts["navigation.constraints"], app)
        XCTAssertTrue(app.staticTexts["navigation.constraints"].label.contains("2–5"))
        app.navigationBars["编辑底部导航"].buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["root.tab.capture"].exists)
        app.buttons["root.tab.today"].tap()
        XCTAssertTrue(app.buttons["root.tab.today"].isSelected)
        app.terminate()
    }

    func testCaptureActualTaskViews() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TOUGH_TRIAL_UI_TESTING"] = "1"
        app.launch()
        app.buttons["root.tab.tasks"].tap()
        for (id, name) in [("list", "tasks-list-native"), ("structure", "tasks-structure-native"), ("time", "tasks-time-native"), ("fishbone", "tasks-fishbone-native")] {
            let button = app.buttons["tasks.lens.\(id)"]
            XCTAssertTrue(button.waitForExistence(timeout: 5), app.debugDescription)
            button.tap()
            capture(app, name)
        }
    }

    func testCaptureOtherActualModulesAndZen() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TOUGH_TRIAL_UI_TESTING"] = "1"
        app.launch()
        for (id, name) in [("assistant", "assistant-native"), ("capture", "capture-native"), ("morePlugins", "more-plugins-native")] {
            app.buttons["root.tab.\(id)"].tap()
            capture(app, name)
        }
        app.buttons["morePlugins.open.recall"].tap()
        capture(app, "recall-native")
        app.terminate(); app.launch()
        app.buttons["root.tab.morePlugins"].tap()
        app.buttons["morePlugins.open.ownProfile"].tap()
        XCTAssertTrue(app.buttons["profile.showQR"].waitForExistence(timeout: 5))
        capture(app, "my-home-native")
        app.buttons["profile.showQR"].tap()
        capture(app, "qr-share-native")
        app.terminate(); app.launch()
        app.buttons["root.tab.today"].tap()
        let direct = app.buttons["today.emptyZen.startUnlinked"]
        if direct.exists {
            direct.tap()
            XCTAssertTrue(app.buttons["zen.close"].waitForExistence(timeout: 5))
            app.buttons["zen.close"].tap()
            app.buttons["today.focus.zen"].tap()
            XCTAssertTrue(app.buttons["zen.finish"].waitForExistence(timeout: 5))
            app.buttons["zen.finish"].tap()
            XCTAssertTrue(direct.waitForExistence(timeout: 5))
        }
    }

    func testQueueFocusSwitchAndFinanceCapture() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TOUGH_TRIAL_UI_TEST_EMPTY"] = "1"
        app.terminate(); app.launch()
        app.buttons["root.tab.today"].tap()
        for name in ["甲任务", "乙任务"] {
            app.buttons["today.quickAdd"].tap()
            let field = app.textViews["today.quickAdd.document"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["today.quickAdd.submit"].isEnabled)
            field.tap(); field.typeText(name)
            app.buttons["today.quickAdd.submit"].tap()
            start(name, app)
        }
        let queued = app.buttons["today.queue.甲任务"]
        reveal(queued, app); queued.tap()
        XCTAssertTrue(app.buttons["today.queue.乙任务"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["today.queue.甲任务"].exists)
        reveal(app.buttons["today.focus.zen"], app)
        app.buttons["today.focus.zen"].tap()
        XCTAssertTrue(app.buttons["zen.close"].waitForExistence(timeout: 5))
        app.buttons["zen.close"].tap()
        reveal(app.buttons["today.focus.complete"], app)
        app.buttons["today.focus.complete"].tap()
        XCTAssertFalse(app.buttons["today.queue.乙任务"].exists)
        let done = app.buttons["today.plan.甲任务"]
        reveal(done, app)
        XCTAssertEqual(done.value as? String, "已完成")
        XCTAssertFalse(app.buttons["today.restore.甲任务"].exists)
        app.buttons["root.tab.capture"].tap()
        app.segmentedControls["capture.sections"].buttons["记账"].tap()
        let finance = app.buttons["finance.open"]
        XCTAssertTrue(finance.waitForExistence(timeout: 5)); finance.tap()
        capture(app, "finance-native")
    }

    private func revealList(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<8 {
            if element.exists && element.isHittable && element.frame.maxY < app.buttons["root.tab.morePlugins"].frame.minY { return }
            if element.exists && element.frame.minY < 100 { app.swipeDown() }
            else { app.swipeUp() }
        }
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }

    private func revealTree(_ element: XCUIElement, _ app: XCUIApplication) {
        let canvas = app.scrollViews["tasks.inverted.canvas"]
        for _ in 0..<12 {
            guard element.waitForExistence(timeout: 2) else { break }
            let frame = element.frame
            let viewport = canvas.frame
            if element.isHittable && frame.midX > viewport.minX + 15 && frame.midX < viewport.maxX - 15 &&
                frame.midY > viewport.minY + 15 && frame.midY < viewport.maxY - 85 { return }
            if frame.midX <= viewport.minX + 15 { canvas.swipeRight() }
            else if frame.midX >= viewport.maxX - 15 { canvas.swipeLeft() }
            else if frame.midY < viewport.minY + 15 { canvas.swipeDown() }
            else { canvas.swipeUp() }
        }
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }

    private func start(_ name: String, _ app: XCUIApplication) {
        let row = app.buttons["today.plan.\(name)"]
        reveal(row, app); row.tap()
        let button = app.buttons["today.start.\(name)"]
        reveal(button, app); button.tap()
    }

    private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        let scroll = app.scrollViews["today.scroll"]
        for _ in 0..<12 {
            let frame = element.exists ? element.frame : .zero
            let viewport = scroll.frame
            if element.exists && element.isHittable && frame.minY >= viewport.minY + 4 && frame.maxY <= viewport.maxY - 100 { return }
            let down = element.exists && frame.minY < viewport.minY + 4
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: down ? 0.3 : 0.7))
            let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: down ? 0.7 : 0.3))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(element.exists && element.isHittable, app.debugDescription)
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        // SwiftUI lens transitions can outlive XCTest's idle heuristic.
        let settled = expectation(description: "Review transition settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { settled.fulfill() }
        wait(for: [settled], timeout: 3)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
    }
}

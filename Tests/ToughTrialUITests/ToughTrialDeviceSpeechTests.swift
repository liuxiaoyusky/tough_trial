import XCTest

/// Runs against the installed device configuration, without deterministic AI fixtures.
final class ToughTrialDeviceSpeechTests: XCTestCase {
    @MainActor
    func testPhysicalDeviceSpeechToAssistant() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Physical microphone required")
        #else
        guard ProcessInfo.processInfo.environment["TOUGH_TRIAL_DEVICE_SPEECH"] == "1" else {
            throw XCTSkip("Explicit physical recording opt-in required")
        }
        let schedule = ProcessInfo.processInfo.environment["TOUGH_TRIAL_DEVICE_SPEECH_SCHEDULE"] == "1"
        let terminalPhrase = schedule ? "其他任务" : "测试成功"
        let app = XCUIApplication()
        app.launchEnvironment["TOUGH_TRIAL_UI_TESTING"] = "0"
        app.launchEnvironment["TOUGH_TRIAL_UI_TEST_EMPTY"] = "0"
        app.launchEnvironment["TOUGH_TRIAL_DEVICE_KEEP_AWAKE"] = "1"
        app.launch()
        app.tabBars.firstMatch.buttons["助手"].tap()
        XCTAssertTrue(app.buttons["assistant.speech.start"].waitForExistence(timeout: 10))
        if let provider = ProcessInfo.processInfo.environment["TOUGH_TRIAL_DEVICE_SPEECH_PROVIDER"] {
            app.buttons["assistant.speech.settings"].tap()
            app.segmentedControls["speech.settings.provider"].buttons[provider == "apple" ? "苹果原生" : "阿里云 FunASR"].tap()
            app.buttons["关闭"].tap()
        }
        app.buttons["assistant.newSession"].tap()
        let recorded = app.buttons["assistant.speech.provider"].label.contains("FunASR")
        let start = Date()
        app.buttons["assistant.speech.start"].tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let permission = springboard.alerts.firstMatch
        if permission.waitForExistence(timeout: 3),
           permission.staticTexts.allElementsBoundByIndex.contains(where: { $0.label.contains("麦克风") || $0.label.localizedCaseInsensitiveContains("microphone") }) {
            let allow = permission.buttons.matching(NSPredicate(format: "label IN %@", ["允许", "Allow", "OK", "好"])).firstMatch
            if allow.exists { allow.tap() }
        }
        let finish = app.buttons["assistant.speech.finish"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (finish.exists && finish.isEnabled) || app.alerts.firstMatch.exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 180), .completed)
        guard finish.exists, finish.isEnabled else {
            let diagnostic = XCTAttachment(screenshot: app.screenshot())
            diagnostic.name = "physical-speech-unavailable"; diagnostic.lifetime = .keepAlways; add(diagnostic)
            XCTFail("Speech not ready: " + app.alerts.firstMatch.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " | "))
            return
        }
        print("DEVICE_MIC_RECORDING_READY \(Date().timeIntervalSince1970)")
        let composer = app.descendants(matching: .any).matching(identifier: "assistant.composer").firstMatch
        var firstTextAt: Date?
        var lastText = ""
        var lastChange = Date()
        let deadline = Date().addingTimeInterval(recorded ? (schedule ? 30 : 15) : 45)
        while Date() < deadline {
            let text = composer.value as? String ?? ""
            if !text.isEmpty, text != "问点什么...", text != lastText {
                if firstTextAt == nil { firstTextAt = Date() }
                lastText = text
                lastChange = Date()
            }
            if lastText.contains(terminalPhrase), Date().timeIntervalSince(lastChange) > 2 { break }
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertFalse(app.buttons["assistant.cancel"].exists, "Speech must not submit before Finish")
        XCTAssertFalse(app.buttons["schedule.undo"].exists, "Recording must not write a schedule before Finish")
        if recorded { XCTAssertTrue(lastText.isEmpty, "FunASR must not emit live text") }
        let before = XCTAttachment(screenshot: app.screenshot())
        before.name = "physical-speech-before-finish"; before.lifetime = .keepAlways; add(before)
        guard recorded || lastText.contains(terminalPhrase) else {
            if app.buttons["assistant.speech.cancel"].exists { app.buttons["assistant.speech.cancel"].tap() }
            XCTFail("Test phrase not captured; cancelled without submission")
            return
        }
        print("DEVICE_SPEECH_TRANSCRIPT \(lastText)")
        let finishAt = Date()
        finish.tap()
        let returned = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: finish)
        XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: recorded ? 130 : 25), .completed)
        let finalizedAt = Date()
        let reply = schedule ? app.buttons["schedule.undo"] : app.staticTexts.matching(NSPredicate(format: "label == %@ OR label == %@", "测试成功", "测试成功。")).firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout: 45), "Real AI reply required")
        let replyAt = Date()
        let after = XCTAttachment(screenshot: app.screenshot())
        after.name = "physical-speech-assistant-reply"; after.lifetime = .keepAlways; add(after)
        print("DEVICE_SPEECH_TIMING first_text_from_tap=\(firstTextAt?.timeIntervalSince(start) ?? -1) finish_to_ui_idle=\(finalizedAt.timeIntervalSince(finishAt)) finish_to_reply=\(replyAt.timeIntervalSince(finishAt))")
        if schedule {
            let detail = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "语音链路验收", "配图")).firstMatch
            XCTAssertTrue(detail.exists)
            XCTAssertTrue(detail.label.contains("3") || detail.label.contains("三"))
            XCTAssertTrue(detail.label.contains("2") || detail.label.contains("两"))
            guard reply.exists else { return }
            reply.tap()
            XCTAssertTrue(app.staticTexts["已撤销"].waitForExistence(timeout: 10))
            print("DEVICE_SPEECH_SCHEDULE_ACCEPTANCE retained_constraints=true undo=true")
        }
        #endif
    }

    @MainActor
    func testPhysicalDeviceSpeechConfiguration() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Requires the user's physical iPhone and its existing configuration")
        #else
        let app = XCUIApplication()
        app.launchEnvironment["TOUGH_TRIAL_UI_TESTING"] = "0"
        app.launchEnvironment["TOUGH_TRIAL_UI_TEST_EMPTY"] = "0"
        app.launch()
        let assistant = app.tabBars.firstMatch.buttons["助手"]
        XCTAssertTrue(assistant.waitForExistence(timeout: 15))
        assistant.tap()
        let mic = app.buttons["assistant.speech.start"]
        let configured = mic.waitForExistence(timeout: 5)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "physical-device-assistant-readiness"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        guard configured else {
            throw XCTSkip("DEVICE_SETUP_REQUIRED: Chat AI is not configured on the iPhone")
        }
        app.buttons["assistant.more"].tap()
        app.buttons["assistant.settings"].tap()
        app.buttons["ai.settings.speech"].tap()
        let key = app.secureTextFields["speech.settings.apiKey"]
        XCTAssertTrue(key.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["无法读取语音配置，请稍后重试。"].exists)
        let keyPresent = (key.value as? String).map { !$0.isEmpty && $0 != "粘贴百炼 API Key" } ?? false
        guard keyPresent else {
            throw XCTSkip("DEVICE_SETUP_REQUIRED: Speech API Key is not configured on the iPhone")
        }
        print("DEVICE_CONFIGURATION_READY")
        #endif
    }
}

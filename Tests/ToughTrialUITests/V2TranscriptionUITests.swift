import XCTest

final class V2TranscriptionUITests: XCTestCase {
    @MainActor private func open(_ fixture: String) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TOUGH_TRIAL_UI_TESTING"] = "1"
        app.launchEnvironment["TOUGH_TRIAL_UI_TEST_TRANSCRIPTION"] = fixture
        app.terminate()
        app.launch()
        let more = app.buttons["root.tab.morePlugins"]
        XCTAssertTrue(more.waitForExistence(timeout: 10)); more.tap()
        let module = app.buttons["morePlugins.open.transcription"]
        XCTAssertTrue(module.waitForExistence(timeout: 5)); module.tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'transcription.open.'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        XCTAssertTrue(app.staticTexts["转录测试录音"].waitForExistence(timeout: 5))
        return app
    }

    @MainActor func testAppleEmptyOrUnavailableFailureRetainsFileAndReadableFeedback() {
        let app = open("draft")
        let provider = app.segmentedControls["transcription.provider"]
        provider.buttons["苹果原生"].tap()
        app.buttons["transcription.start"].tap()
        let issue = app.descendants(matching: .any)["transcription.issue"].firstMatch
        XCTAssertTrue(issue.waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["transcription.start"].exists)
        let feedback = XCTAttachment(screenshot: app.screenshot())
        feedback.name = "transcription-readable-retry"; feedback.lifetime = .keepAlways; add(feedback)
        app.buttons["transcription.transcript.open"].tap()
        XCTAssertTrue(app.buttons["transcription.audio.play"].waitForExistence(timeout: 5))
        app.buttons["transcription.audio.play"].tap()
        XCTAssertEqual(app.buttons["transcription.audio.play"].label, "暂停原录音")
        app.buttons["transcription.audio.play"].tap()
        XCTAssertEqual(app.buttons["transcription.audio.play"].label, "播放原录音")
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "transcription-original-retained"; image.lifetime = .keepAlways; add(image)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(provider.waitForExistence(timeout: 5))
        XCTAssertTrue(provider.buttons["苹果原生"].isSelected,
                      "查看原文件返回后必须保留所选的本地识别方式")
    }

    @MainActor func testProcessingKeepsSavedContentReadableAndPreventsEditing() {
        let app = open("processing")
        XCTAssertFalse(app.buttons["transcription.summary.edit"].isEnabled)
        XCTAssertFalse(app.buttons["transcription.summary.retry"].isEnabled)
        XCTAssertTrue(app.staticTexts["测试摘要"].exists)
        XCTAssertTrue(app.staticTexts["转录中暂时无法编辑；暂停后可以修改已保存的内容。"].exists)
        app.buttons["transcription.transcript.open"].tap()
        XCTAssertTrue(app.buttons["transcription.audio.play"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["transcription.transcript.edit"].isEnabled)
        app.buttons["transcription.audio.play"].tap()
        XCTAssertEqual(app.buttons["transcription.audio.play"].label, "暂停原录音")
        app.buttons["transcription.audio.play"].tap()
        XCTAssertEqual(app.buttons["transcription.audio.play"].label, "播放原录音")
    }

    @MainActor func testEditCancelSaveAndDeleteConfirmation() {
        let app = open("complete")
        app.buttons["transcription.summary.edit"].tap()
        let summary = app.textViews["transcription.summary.input"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5)); summary.tap(); summary.typeText(" cancelled")
        app.buttons["取消"].tap()
        XCTAssertTrue(app.staticTexts["测试摘要"].exists)
        app.buttons["transcription.summary.edit"].tap()
        XCTAssertTrue(summary.waitForExistence(timeout: 5)); summary.tap(); summary.typeText(" saved")
        let savedSummary = (summary.value as! String).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertTrue(savedSummary.contains("saved"))
        app.buttons["保存"].tap()
        XCTAssertTrue(app.staticTexts[savedSummary].waitForExistence(timeout: 5))
        app.buttons["transcription.transcript.open"].tap()
        app.buttons["transcription.transcript.edit"].tap()
        let transcript = app.textViews["transcription.transcript.input"]
        XCTAssertTrue(transcript.waitForExistence(timeout: 5)); transcript.tap(); transcript.typeText(" saved")
        let savedTranscript = transcript.value as! String
        XCTAssertTrue(savedTranscript.contains("saved"))
        app.buttons["保存"].tap()
        XCTAssertTrue(app.staticTexts[savedTranscript].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["transcription.record.menu"].tap()
        app.buttons["删除记录与原文件"].tap()
        if app.buttons["取消"].exists { app.buttons["取消"].tap() }
        else { app.otherElements["PopoverDismissRegion"].tap() }
        XCTAssertTrue(app.staticTexts["转录测试录音"].exists)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "transcription-readable-detail"; image.lifetime = .keepAlways; add(image)
        app.buttons["transcription.record.menu"].tap()
        app.buttons["删除记录与原文件"].tap()
        app.buttons["删除"].tap()
        XCTAssertTrue(app.staticTexts["把声音留成可查的文字"].waitForExistence(timeout: 5))
    }
}

import XCTest
import ToughTrialV2Core
@testable import ToughTrial

@MainActor
final class V2DictationControlTests: XCTestCase {
    func testAppleRevisionsReplaceOneDictationSegmentAndFinishOnce() async {
        let fixture = DictationAppleFixture()
        let model = fixture.makeModel()

        model.start(preRecordingText: "先保留", provider: .apple)
        await wait { model.state == .recording }

        fixture.emit(.text(start: 0, end: 1, text: "明天三点", final: false))
        await wait { model.transcript == "明天三点" }
        XCTAssertEqual(model.renderedText, "先保留\n明天三点")

        // The provider revision replaces the temporary segment instead of
        // appending another copy to the bound draft.
        fixture.emit(.text(start: 0, end: 1, text: "明天四点", final: false))
        await wait { model.transcript == "明天四点" }
        XCTAssertEqual(model.renderedText, "先保留\n明天四点")

        model.finish()
        await wait { fixture.finishCount == 1 }
        fixture.emit(.text(start: 0, end: 1, text: "明天四点。", final: true))
        fixture.end()
        await wait { !model.isActive }

        XCTAssertEqual(model.renderedText, "先保留\n明天四点。")
        XCTAssertEqual(fixture.finishCount, 1)
    }

    func testRepeatedFinishAndLateAppleCompletionApplyOnlyOnce() async {
        let fixture = DictationAppleFixture()
        let model = fixture.makeModel()

        model.start(preRecordingText: "原有内容", provider: .apple)
        await wait { model.state == .recording }
        fixture.emit(.text(start: 0, end: 1, text: "第一次结果", final: false))
        await wait { model.transcript == "第一次结果" }

        model.finish()
        model.finish()
        await wait { fixture.finishCount == 1 }

        fixture.emit(.text(start: 0, end: 1, text: "最终结果", final: true))
        fixture.end()
        await wait { !model.isActive }
        XCTAssertEqual(model.renderedText, "原有内容\n最终结果")

        // A provider callback after completion belongs to the invalidated
        // session and must not rewrite the bound field.
        fixture.emit(.text(start: 0, end: 1, text: "迟到结果", final: true))
        await Task.yield()
        XCTAssertEqual(model.renderedText, "原有内容\n最终结果")
        XCTAssertEqual(fixture.finishCount, 1)
    }

    func testCancelRestoresPreRecordingDraftAndIgnoresLateRevision() async {
        let fixture = DictationAppleFixture()
        let model = fixture.makeModel()

        model.start(preRecordingText: "原有标题", provider: .apple)
        await wait { model.state == .recording }
        fixture.emit(.text(start: 0, end: 1, text: "临时听写", final: false))
        await wait { model.transcript == "临时听写" }

        model.cancel()
        XCTAssertFalse(model.isActive)
        XCTAssertEqual(model.renderedText, "原有标题")
        XCTAssertEqual(model.pendingText, "原有标题", "Cancel must restore the bound field, not only internal state")

        fixture.emit(.text(start: 0, end: 1, text: "迟到结果", final: true))
        await Task.yield()
        XCTAssertEqual(model.renderedText, "原有标题")
    }

    func testAppleFailureKeepsRecognizedDraftForEditing() async {
        let fixture = DictationAppleFixture()
        let model = fixture.makeModel()

        model.start(preRecordingText: "会议", provider: .apple)
        await wait { model.state == .recording }
        fixture.emit(.text(start: 0, end: 1, text: "会议改到周五", final: false))
        await wait { model.transcript == "会议改到周五" }

        model.finish()
        await wait { fixture.finishCount == 1 }
        fixture.end(error: DictationFixtureError.backend)
        await wait { !model.isActive }

        XCTAssertEqual(model.renderedText, "会议\n会议改到周五")
        XCTAssertNotNil(model.errorMessage)
    }

    func testFunASRFailureRetainsAudioForOrchestratorRetry() async throws {
        let fixture = DictationCloudFixture()
        let previousKey = try? V2SpeechSettings.loadKey()
        try V2SpeechSettings.saveKey("dictation-test-key")
        defer { try? V2SpeechSettings.saveKey(previousKey ?? "") }

        let cloud = fixture.makeTranscriber()
        let apple = V2AppleSpeechTranscriber(permission: { false }, makeSession: {
            throw DictationFixtureError.unexpected
        })
        let speech = V2AssistantSpeechTranscriber(cloud: cloud, apple: apple)
        let model = V2DictationControlModel(ownerModuleID: "core.tasks", speech: speech)

        model.start(preRecordingText: "稍后整理", provider: .funASR)
        await wait { model.state == .recording }
        fixture.audio.yield(Data([1, 2, 3, 4]))
        model.finish()
        await wait { model.canRetry }

        XCTAssertEqual(model.renderedText, "稍后整理")
        XCTAssertEqual(fixture.requests, [Data([1, 2, 3, 4])])

        model.finish()
        await wait { !model.isActive }
        XCTAssertEqual(model.renderedText, "稍后整理\n云端完成")
        XCTAssertEqual(model.pendingText, "稍后整理\n云端完成", "Finish must emit text to the bound field")
        XCTAssertEqual(fixture.requests, [Data([1, 2, 3, 4]), Data([1, 2, 3, 4])])
    }

    func testUnavailableOwnerDoesNotStartBackendOrChangeDraft() {
        let fixture = DictationAppleFixture()
        let model = fixture.makeModel(ownerModuleID: "core.noSuchModule")

        model.start(preRecordingText: "保留这句", provider: .apple)

        XCTAssertFalse(model.isActive)
        XCTAssertEqual(model.renderedText, "保留这句")
        XCTAssertNotNil(model.errorMessage)
        XCTAssertNil(fixture.update)
    }

    func testCancelWithoutSessionDoesNotEraseCurrentDraft() {
        let fixture = DictationAppleFixture()
        let model = fixture.makeModel()
        model.adoptIdleText("用户正在编辑")

        model.cancel()

        XCTAssertEqual(model.renderedText, "用户正在编辑")
    }

    func testManualEditAfterCompletionSurvivesBackgroundCancellation() async {
        let fixture = DictationAppleFixture()
        let model = fixture.makeModel()

        model.start(preRecordingText: "原有内容", provider: .apple)
        await wait { model.state == .recording }
        fixture.emit(.text(start: 0, end: 1, text: "听写结果", final: true))
        model.finish()
        await wait { fixture.finishCount == 1 }
        fixture.end()
        await wait { !model.isActive }

        // This mirrors the control's `onChange(of: text)` path after the
        // parent field was edited by hand following a completed dictation.
        model.adoptIdleText("用户后来手动修改")
        XCTAssertNil(model.pendingText, "idle parent edits must not enqueue a binding write")
        model.cancel() // scenePhase leaving active / background

        XCTAssertFalse(model.isActive)
        XCTAssertEqual(model.state, .idle)
        XCTAssertEqual(model.renderedText, "用户后来手动修改")
    }

    func testIdleParentEditDoesNotEchoBackThroughSpeechOutput() {
        let fixture = DictationAppleFixture()
        let model = fixture.makeModel()

        model.adoptIdleText("手动编辑后的标题")

        XCTAssertEqual(model.renderedText, "手动编辑后的标题")
        XCTAssertNil(model.pendingText)
    }

    func testDeniedMicrophoneKeepsDraftAndReturnsIdle() async {
        let fixture = DictationAppleFixture()
        let model = fixture.makeModel(permissionGranted: false)

        model.start(preRecordingText: "保留这份草稿", provider: .apple)
        await wait { model.errorMessage != nil && !model.isActive }

        XCTAssertEqual(model.state, .idle)
        XCTAssertEqual(model.renderedText, "保留这份草稿")
        XCTAssertFalse(model.canRetry)
        XCTAssertNil(fixture.update)
    }

    func testDictationRevisesSelectedDocumentTextAndCancelRestoresIt() async {
        let fixture = DictationAppleFixture()
        let model = fixture.makeModel()
        let original = "准备🧳\n出发前确认车票，带好雨伞"
        let selected = (original as NSString).range(of: "车票")
        model.start(preRecordingText: original, provider: .apple, selection: selected)
        await wait { model.state == .recording }
        fixture.emit(.text(start: 0, end: 1, text: "酒店", final: false))
        await wait { model.transcript == "酒店" }
        XCTAssertEqual(model.renderedText, "准备🧳\n出发前确认酒店，带好雨伞")
        fixture.emit(.text(start: 0, end: 1, text: "酒店和路线", final: false))
        await wait { model.transcript == "酒店和路线" }
        XCTAssertEqual(model.renderedText, "准备🧳\n出发前确认酒店和路线，带好雨伞")
        model.cancel()
        XCTAssertEqual(model.pendingText, original)
        XCTAssertEqual(model.pendingSelection, selected)
    }

    func testDictationAtTitleCaretDoesNotForceANewParagraph() async {
        let fixture = DictationAppleFixture()
        let model = fixture.makeModel()
        model.start(preRecordingText: "整理照片\n周末完成", provider: .apple,
                    selection: NSRange(location: 2, length: 0))
        await wait { model.state == .recording }
        fixture.emit(.text(start: 0, end: 1, text: "旅行", final: false))
        await wait { model.transcript == "旅行" }
        model.finish()
        await wait { fixture.finishCount == 1 }
        fixture.end()
        await wait { !model.isActive }
        XCTAssertEqual(model.pendingText, "整理旅行照片\n周末完成")
        XCTAssertEqual(model.pendingSelection, NSRange(location: 4, length: 0))
    }

    func testDictationCanReplaceEmojiAndParagraphBoundaryWithoutDamagingSuffix() async {
        let fixture = DictationAppleFixture()
        let model = fixture.makeModel()
        let original = "准备🧳\n检查护照，明天出发"
        let selection = (original as NSString).range(of: "🧳\n检查")
        model.start(preRecordingText: original, provider: .apple, selection: selection)
        await wait { model.state == .recording }
        fixture.emit(.text(start: 0, end: 1, text: "行李\n确认", final: false))
        await wait { model.transcript == "行李\n确认" }
        model.finish()
        await wait { fixture.finishCount == 1 }
        fixture.end()
        await wait { !model.isActive }
        XCTAssertEqual(model.pendingText, "准备行李\n确认护照，明天出发")
        XCTAssertEqual(model.pendingSelection, NSRange(location: 7, length: 0))
    }

    private func wait(
        _ condition: @escaping () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Timed out waiting for dictation state", file: file, line: line)
    }
}

@MainActor
private final class DictationAppleFixture {
    var update: (@MainActor (V2AppleSpeechEvent) -> Void)?
    var finishCount = 0
    private var endContinuation: CheckedContinuation<Void, Error>?

    func makeModel(
        ownerModuleID: String = "core.tasks",
        permissionGranted: Bool = true
    ) -> V2DictationControlModel {
        let speech = V2AssistantSpeechTranscriber(
            cloud: V2RecordedSpeechTranscriber(
                permission: { false },
                startAudio: { AsyncThrowingStream { $0.finish() } },
                stopAudio: {},
                transcribe: { _, _ in throw DictationFixtureError.unexpected }
            ),
            apple: makeSpeech(permissionGranted: permissionGranted)
        )
        return V2DictationControlModel(ownerModuleID: ownerModuleID, speech: speech)
    }

    func makeSpeech(permissionGranted: Bool = true) -> V2AppleSpeechTranscriber {
        V2AppleSpeechTranscriber(permission: { permissionGranted }, makeSession: { [weak self] in
            guard let self else { throw DictationFixtureError.unexpected }
            return V2AppleSpeechSession(
                run: { update in
                    self.update = update
                    update(.ready)
                    try await withCheckedThrowingContinuation { continuation in
                        self.endContinuation = continuation
                    }
                },
                finish: { self.finishCount += 1 },
                cancel: { self.end() }
            )
        })
    }

    func emit(_ event: V2AppleSpeechEvent) {
        update?(event)
    }

    func end(error: Error? = nil) {
        guard let continuation = endContinuation else { return }
        endContinuation = nil
        if let error { continuation.resume(throwing: error) }
        else { continuation.resume() }
    }
}

@MainActor
private final class DictationCloudFixture {
    let stream: AsyncThrowingStream<Data, Error>
    let audio: AsyncThrowingStream<Data, Error>.Continuation
    var requests: [Data] = []
    private var failNext = true

    init() {
        let pair = AsyncThrowingStream<Data, Error>.makeStream()
        stream = pair.stream
        audio = pair.continuation
    }

    func makeTranscriber() -> V2RecordedSpeechTranscriber {
        V2RecordedSpeechTranscriber(
            permission: { true },
            startAudio: { self.stream },
            stopAudio: { self.audio.finish() },
            transcribe: { pcm, _ in
                self.requests.append(pcm)
                if self.failNext {
                    self.failNext = false
                    throw DictationFixtureError.backend
                }
                return "云端完成"
            }
        )
    }
}

private enum DictationFixtureError: Error {
    case backend
    case unexpected
}

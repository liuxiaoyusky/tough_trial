import AVFoundation
import XCTest
@testable import ToughTrial

@MainActor
final class V2AppleSpeechTests: XCTestCase {
    func testFinalRevisionSubmitsExactlyOnceAfterFinish() async {
        let fixture = AppleSpeechFixture()
        let speech = fixture.makeSpeech()
        speech.start()
        await waitUntil { speech.state == .recording }
        fixture.update?(.text(start: 0, end: 2, text: "明天三点", final: false))
        XCTAssertEqual(speech.transcript, "明天三点")
        var submissions: [String] = []
        speech.finish { submissions.append($0) }
        speech.finish { _ in XCTFail("Duplicate finish") }
        await waitUntil { fixture.finishCount == 1 }
        XCTAssertTrue(submissions.isEmpty)
        fixture.update?(.text(start: 0, end: 2, text: "明天四点，不要取消。", final: true))
        fixture.end()
        await waitUntil { speech.state == .idle }
        XCTAssertEqual(submissions, ["明天四点，不要取消。"])
        XCTAssertEqual(fixture.finishCount, 1)
    }

    func testResultsEndingBeforeFailedDrainNeverSubmits() async {
        let fixture = AppleSpeechFixture()
        var drain: CheckedContinuation<Void, Error>?
        fixture.finishAction = { try await withCheckedThrowingContinuation { drain = $0 } }
        let speech = fixture.makeSpeech()
        speech.start()
        await waitUntil { speech.state == .recording }
        fixture.update?(.text(start: 0, end: 2, text: "不要删除", final: true))
        speech.finish { _ in XCTFail("Drain failure submitted") }
        await waitUntil { drain != nil }
        fixture.end()
        await Task.yield()
        XCTAssertEqual(speech.state, .finishing)
        drain?.resume(throwing: V2SpeechAudioError.conversion)
        await waitUntil { speech.state == .idle }
        XCTAssertNotNil(speech.errorMessage)
    }

    func testCancelKeepsDraftAndIgnoresLateFinal() async {
        let fixture = AppleSpeechFixture()
        let speech = fixture.makeSpeech()
        speech.start()
        await waitUntil { speech.state == .recording }
        fixture.update?(.text(start: 0, end: 2, text: "不要删除", final: false))
        speech.finish { _ in XCTFail("Cancelled recording submitted") }
        speech.cancel()
        fixture.update?(.text(start: 0, end: 2, text: "迟到文字", final: true))
        await Task.yield()
        XCTAssertEqual(speech.transcript, "不要删除")
        XCTAssertEqual(speech.state, .idle)
    }

    func testPartialOrUnexpectedEndNeverSubmits() async {
        for finishing in [false, true] {
            let fixture = AppleSpeechFixture()
            let speech = fixture.makeSpeech()
            speech.start()
            await waitUntil { speech.state == .recording }
            fixture.update?(.text(start: 0, end: 2, text: "还没说完", final: false))
            if finishing { speech.finish { _ in XCTFail("Partial submitted") } }
            fixture.end()
            await waitUntil { speech.state == .idle }
            XCTAssertNotNil(speech.errorMessage)
            XCTAssertEqual(speech.transcript, "还没说完")
        }
    }

    func testDeniedAndCancelledPermissionNeverStartBackend() async {
        let denied = AppleSpeechFixture()
        let speech = denied.makeSpeech(permission: { false })
        speech.start()
        await waitUntil { speech.errorMessage != nil }
        XCTAssertNil(denied.update)
        var reply: CheckedContinuation<Bool, Never>?
        let cancelled = AppleSpeechFixture()
        let pending = cancelled.makeSpeech(permission: { await withCheckedContinuation { reply = $0 } })
        pending.start()
        await waitUntil { reply != nil }
        pending.cancel()
        reply?.resume(returning: true)
        await Task.yield()
        XCTAssertNil(cancelled.update)
    }

    func testPreparationAndBackendFailurePreserveDraft() async {
        let fixture = AppleSpeechFixture()
        let speech = fixture.makeSpeech()
        speech.start()
        await waitUntil { speech.state == .recording }
        fixture.update?(.text(start: 0, end: 2, text: "周五开会", final: true))
        speech.finish { _ in XCTFail("Failure submitted") }
        fixture.end(error: V2SpeechAudioError.conversion)
        await waitUntil { speech.state == .idle }
        XCTAssertEqual(speech.transcript, "周五开会")
        XCTAssertNotNil(speech.errorMessage)
    }

    func testAppleSelectionNeverOpensCloudConnectionAndCannotSwitchWhileRecording() async {
        var cloudOpened = false
        let cloud = V2RecordedSpeechTranscriber(permission: { true }, startAudio: {
            cloudOpened = true
            return AsyncThrowingStream { $0.finish() }
        }, stopAudio: {}, transcribe: { _, _ in XCTFail("Must not upload before Finish"); return "" })
        let fixture = AppleSpeechFixture()
        let speech = V2AssistantSpeechTranscriber(cloud: cloud, apple: fixture.makeSpeech())
        speech.start(provider: .apple)
        await waitUntil { speech.state == .recording }
        speech.start(provider: .funASR, key: "test")
        XCTAssertEqual(speech.provider, .apple)
        XCTAssertFalse(cloudOpened)
        speech.cancel()
        speech.start(provider: .funASR, key: "test")
        await waitUntil { cloudOpened }
        speech.cancel()
    }

    func testTranscriptRevisionsAndLatePartialProtection() {
        var result = V2AppleSpeechTranscript()
        result.apply(start: 0, end: 1, text: "三点", final: false)
        result.apply(start: 0, end: 1, text: "四点。", final: true)
        result.apply(start: 0, end: 1, text: "三点", final: false)
        result.apply(start: 1, end: 2, text: "不要取消。", final: true)
        XCTAssertEqual(result.text, "四点。不要取消。")
        XCTAssertFalse(result.hasUnfinishedText)
    }

    func testAudioConversionDrainsAndCopiesBuffers() throws {
        for (sourceRate, targetRate) in [(48000.0, 16000.0), (44100.0, 16000.0), (48000.0, 48000.0)] {
            let inputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sourceRate, channels: 1, interleaved: false)!
            let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: targetRate, channels: 1, interleaved: false)!
            let converter = try V2AppleAudioConverter(input: inputFormat, output: outputFormat)
            let input = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(sourceRate / 10))!
            input.frameLength = input.frameCapacity
            for index in 0..<Int(input.frameLength) { input.floatChannelData![0][index] = 0.1 }
            var buffers: [AVAudioPCMBuffer] = []
            for _ in 0..<10 { buffers += try converter.convert(input) }
            buffers += try converter.convert(nil)
            XCTAssertLessThan(abs(Double(buffers.reduce(0) { $0 + Int($1.frameLength) }) - targetRate), 2)
            XCTAssertFalse(buffers.contains { $0 === input })
            XCTAssertTrue(try converter.convert(nil).isEmpty)
        }
    }

    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Timed out", file: file, line: line)
    }
}

@MainActor
private final class AppleSpeechFixture {
    var update: (@MainActor (V2AppleSpeechEvent) -> Void)?
    var continuation: CheckedContinuation<Void, Error>?
    var finishCount = 0
    var finishAction: (@MainActor () async throws -> Void)?
    func makeSpeech(permission: @escaping () async -> Bool = { true }) -> V2AppleSpeechTranscriber {
        V2AppleSpeechTranscriber(permission: permission, makeSession: {
            V2AppleSpeechSession(run: { update in
                self.update = update
                update(.preparing("正在准备模型"))
                try await withCheckedThrowingContinuation { continuation in
                    self.continuation = continuation
                    update(.ready)
                }
            }, finish: { self.finishCount += 1; try await self.finishAction?() }, cancel: { self.end(error: CancellationError()) })
        })
    }
    func end(error: Error? = nil) {
        let pending = continuation
        continuation = nil
        if let error { pending?.resume(throwing: error) } else { pending?.resume() }
    }
}

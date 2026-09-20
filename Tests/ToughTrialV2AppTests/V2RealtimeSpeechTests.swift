import AVFoundation
import XCTest
@testable import ToughTrial

@MainActor
final class V2RealtimeSpeechTests: XCTestCase {
    func testFinishDrainsAudioAndSubmitsFinalRevisionExactlyOnce() async throws {
        let fixture = SpeechFixture()
        let speech = fixture.makeSpeech()
        speech.start(key: "test")
        await waitUntil { speech.state == .recording }
        fixture.audio.yield(Data([1, 2]))
        fixture.emitText("明天三点", final: false)
        await waitUntil { speech.transcript == "明天三点" }
        var submissions: [String] = []
        XCTAssertTrue(submissions.isEmpty)
        speech.finish { submissions.append($0) }
        speech.finish { _ in XCTFail("Duplicate finish must be ignored") }
        await waitUntil { fixture.sentActions.contains("finish-task") }
        XCTAssertEqual(fixture.sentActions, ["run-task", "audio", "finish-task"])
        XCTAssertEqual(speech.state, .finishing)
        XCTAssertTrue(submissions.isEmpty)
        fixture.emitText("明天四点，不要取消。", final: true)
        fixture.emit("task-finished")
        await waitUntil { speech.state == .idle }
        XCTAssertEqual(submissions, ["明天四点，不要取消。"])
        XCTAssertEqual(fixture.closeCount, 1)
    }

    func testCancelDuringFinishKeepsDraftAndNeverSubmitsLateResult() async {
        let fixture = SpeechFixture()
        let speech = fixture.makeSpeech()
        speech.start(key: "test")
        await waitUntil { speech.state == .recording }
        fixture.emitText("不要删掉", final: false)
        await waitUntil { speech.transcript == "不要删掉" }
        speech.finish { _ in XCTFail("Cancelled recording must not submit") }
        speech.cancel()
        fixture.emitText("迟到的结果", final: true)
        fixture.emit("task-finished")
        await Task.yield()
        XCTAssertEqual(speech.state, .idle)
        XCTAssertEqual(speech.transcript, "不要删掉")
    }

    func testFailureKeepsDraftWithoutAutomaticSubmission() async {
        let fixture = SpeechFixture()
        let speech = fixture.makeSpeech()
        speech.start(key: "test")
        await waitUntil { speech.state == .recording }
        fixture.emitText("周五开会", final: false)
        await waitUntil { speech.transcript == "周五开会" }
        speech.finish { _ in XCTFail("Failed recording must not submit") }
        fixture.emit("task-failed")
        await waitUntil { speech.state == .idle }
        XCTAssertEqual(speech.transcript, "周五开会")
        XCTAssertNotNil(speech.errorMessage)
    }

    func testUnexpectedFinishAndUnfinalizedDraftDoNotSubmit() async {
        for finishRequested in [false, true] {
            let fixture = SpeechFixture()
            let speech = fixture.makeSpeech()
            speech.start(key: "test")
            await waitUntil { speech.state == .recording }
            fixture.emitText("尚未定稿", final: false)
            await waitUntil { speech.transcript == "尚未定稿" }
            if finishRequested { speech.finish { _ in XCTFail("Partial text must not auto-submit") } }
            fixture.emit("task-finished")
            await waitUntil { speech.state == .idle }
            XCTAssertNotNil(speech.errorMessage)
        }
    }

    func testCancelWhilePermissionPendingNeverOpensConnection() async {
        let fixture = SpeechFixture()
        var permissionReply: CheckedContinuation<Bool, Never>?
        let speech = fixture.makeSpeech(permission: {
            await withCheckedContinuation { permissionReply = $0 }
        })
        speech.start(key: "test")
        await waitUntil { permissionReply != nil }
        speech.cancel()
        permissionReply?.resume(returning: true)
        await Task.yield()
        XCTAssertTrue(fixture.sentActions.isEmpty)
        XCTAssertEqual(speech.state, .idle)
    }

    func testDeniedPermissionNeverOpensConnection() async {
        let fixture = SpeechFixture()
        let speech = fixture.makeSpeech(permission: { false })
        speech.start(key: "test")
        await waitUntil { speech.errorMessage != nil }
        XCTAssertTrue(fixture.sentActions.isEmpty)
        XCTAssertEqual(speech.state, .idle)
    }

    func testPCMConversionDrainsCommonMicrophoneFormats() throws {
        for (rate, channels) in [(48000.0, 2), (44100.0, 1), (16000.0, 1)] {
            let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: AVAudioChannelCount(channels), interleaved: false)!
            let converter = try V2SpeechPCMConverter(input: format)
            let frames = Int(rate / 10)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
            buffer.frameLength = AVAudioFrameCount(frames)
            for channel in 0..<channels {
                for sample in 0..<frames {
                    buffer.floatChannelData![channel][sample] = sin(Float(sample) * 2 * .pi * 440 / Float(rate)) * 0.2
                }
            }
            var data = Data()
            for _ in 0..<10 { data.append(try converter.convert(buffer)) }
            data.append(try converter.finish())
            XCTAssertLessThan(abs(data.count - 32000), 4, "One second must contain 16000 mono Int16 samples")
            XCTAssertTrue(data.contains { $0 != 0 })
            XCTAssertTrue(try converter.finish().isEmpty)
        }
    }

    func testSpeechCredentialCanBeSavedReadAndRemoved() throws {
        let account = "speech-test-" + UUID().uuidString
        defer { try? V2AIProviderKeychain.save("", account: account) }
        XCTAssertEqual(try V2AIProviderKeychain.load(account: account), "")
        try V2AIProviderKeychain.save("test-credential", account: account)
        XCTAssertEqual(try V2AIProviderKeychain.load(account: account), "test-credential")
        try V2AIProviderKeychain.save("updated-test-credential", account: account)
        XCTAssertEqual(try V2AIProviderKeychain.load(account: account), "updated-test-credential")
        try V2AIProviderKeychain.save("", account: account)
        XCTAssertEqual(try V2AIProviderKeychain.load(account: account), "")
    }

    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Timed out waiting for speech state", file: file, line: line)
    }
}

@MainActor
private final class SpeechFixture {
    let audio: AsyncThrowingStream<Data, Error>.Continuation
    private var messages: [URLSessionWebSocketTask.Message] = []
    private var reply: CheckedContinuation<URLSessionWebSocketTask.Message, Error>?
    private let audioStream: AsyncThrowingStream<Data, Error>
    private var taskID = ""
    var sentActions: [String] = []
    var closeCount = 0

    init() {
        let audio = AsyncThrowingStream<Data, Error>.makeStream()
        self.audio = audio.continuation
        audioStream = audio.stream
    }

    func makeSpeech(permission: @escaping () async -> Bool = { true }) -> V2RealtimeSpeechTranscriber {
        V2RealtimeSpeechTranscriber(permission: permission, open: { _ in
            V2SpeechConnection(send: { message in
                switch message {
                case let .string(text):
                    let object = try JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
                    let header = object["header"] as! [String: String]
                    self.sentActions.append(header["action"]!)
                    if header["action"] == "run-task" {
                        self.taskID = header["task_id"]!
                        self.emit("task-started")
                    }
                case .data: self.sentActions.append("audio")
                @unknown default: break
                }
            }, receive: {
                if !self.messages.isEmpty { return self.messages.removeFirst() }
                return try await withCheckedThrowingContinuation { self.reply = $0 }
            }, close: {
                self.closeCount += 1
                self.reply?.resume(throwing: CancellationError())
                self.reply = nil
            })
        }, startAudio: { self.audioStream }, stopAudio: { self.audio.finish() })
    }

    func emit(_ event: String, sentence: [String: Any]? = nil) {
        var payload: [String: Any] = [:]
        if let sentence { payload["output"] = ["sentence": sentence] }
        let data = try! JSONSerialization.data(withJSONObject: [
            "header": ["event": event, "task_id": taskID], "payload": payload
        ])
        if let reply {
            self.reply = nil
            reply.resume(returning: .data(data))
        } else { messages.append(.data(data)) }
    }

    func emitText(_ text: String, final: Bool) {
        emit("result-generated", sentence: ["sentence_id": 1, "text": text, "sentence_end": final])
    }
}

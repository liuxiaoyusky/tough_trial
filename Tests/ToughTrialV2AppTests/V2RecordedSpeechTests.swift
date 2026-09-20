import XCTest
@testable import ToughTrial

@MainActor
final class V2RecordedSpeechLifecycleTests: XCTestCase {
    func testNoUploadUntilFinishAndOnlyOneComplete() async {
        let f = RecordedSpeechFixture()
        let speech = f.make()
        speech.start(key: "test")
        await wait { speech.state == .recording }
        f.audio.yield(Data([1, 2, 3, 4]))
        await Task.yield()
        XCTAssertEqual(f.requests.count, 0)
        XCTAssertEqual(speech.transcript, "")
        var results: [String] = []
        speech.finish { results.append($0) }
        speech.finish { _ in XCTFail("Duplicate finish") }
        await wait { f.reply != nil }
        XCTAssertEqual(f.requests, [Data([1, 2, 3, 4])])
        f.reply?.resume(returning: "完整文字")
        await wait { speech.state == .idle }
        XCTAssertEqual(results, ["完整文字"])
        XCTAssertFalse(speech.canRetry)
    }

    func testFailureRetainsAudioAndCancelRejectsLateRetry() async {
        let f = RecordedSpeechFixture()
        let speech = f.make()
        speech.start(key: "test")
        await wait { speech.state == .recording }
        f.audio.yield(Data([1, 2]))
        speech.finish { _ in XCTFail("Failed or cancelled must not submit") }
        await wait { f.reply != nil }
        f.reply?.resume(throwing: URLError(.notConnectedToInternet))
        f.reply = nil
        await wait { speech.canRetry }
        speech.finish { _ in XCTFail("Cancelled retry") }
        await wait { f.reply != nil }
        XCTAssertEqual(f.requests, [Data([1, 2]), Data([1, 2])])
        speech.cancel()
        f.reply?.resume(returning: "迟到文字")
        await Task.yield()
        XCTAssertEqual(speech.state, .idle)
        XCTAssertFalse(speech.canRetry)
        XCTAssertEqual(speech.transcript, "")
    }

    func testRecordingLimitStopsCaptureWithoutSubmitting() async {
        let f = RecordedSpeechFixture()
        let speech = f.make(maximumBytes: 4)
        speech.start(key: "test")
        await wait { speech.state == .recording }
        f.audio.yield(Data([1, 2, 3, 4, 5, 6]))
        await wait { speech.reachedLimit }
        XCTAssertEqual(f.requests.count, 0)
        XCTAssertGreaterThan(f.stops, 0)
        speech.finish { _ in }
        await wait { f.reply != nil }
        XCTAssertEqual(f.requests, [Data([1, 2, 3, 4])])
        f.reply?.resume(returning: "完整文字")
        await wait { speech.state == .idle }
    }

    private func wait(_ condition: () -> Bool) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("State transition timed out")
    }
}

@MainActor
private final class RecordedSpeechFixture {
    let stream: AsyncThrowingStream<Data, Error>
    let audio: AsyncThrowingStream<Data, Error>.Continuation
    var requests: [Data] = []
    var reply: CheckedContinuation<String, Error>?
    var stops = 0
    init() { (stream, audio) = AsyncThrowingStream.makeStream() }
    func make(maximumBytes: Int = 9_600_000) -> V2RecordedSpeechTranscriber {
        V2RecordedSpeechTranscriber(permission: { true }, startAudio: { self.stream },
            stopAudio: { self.stops += 1; self.audio.finish() },
            transcribe: { pcm, _ in
                self.requests.append(pcm)
                return try await withCheckedThrowingContinuation { self.reply = $0 }
            }, maximumBytes: maximumBytes)
    }
}

import XCTest
import ToughTrialV2Core
@testable import ToughTrial

@MainActor
final class V2CaptureSpeechPersistenceTests: XCTestCase {
    func testSuccessfulFinishSavesWAVBeforeUploadingAndOnlyOnce() async throws {
        let fixture = CaptureSpeechPersistenceFixture()
        let speech = fixture.make()
        var saved: [Data] = []
        speech.onRecordingCaptured = { wav in
            fixture.events.append("save")
            saved.append(wav)
        }

        speech.start(key: "test")
        await wait { speech.state == .recording }
        let pcm = Data([1, 2, 3, 4])
        fixture.audio.yield(pcm)
        speech.finish { _ in }
        await wait { speech.state == .idle }

        XCTAssertEqual(fixture.events, ["save", "upload"])
        XCTAssertEqual(fixture.requests, [pcm])
        XCTAssertEqual(saved, [try V2RecordedSpeechClient.wavData(pcm: pcm)])
    }

    func testASRRetryDoesNotSaveTheSameRecordingTwice() async {
        let fixture = CaptureSpeechPersistenceFixture()
        fixture.failFirstUpload = true
        let speech = fixture.make()
        var saved: [Data] = []
        speech.onRecordingCaptured = { saved.append($0) }

        speech.start(key: "test")
        await wait { speech.state == .recording }
        fixture.audio.yield(Data([5, 6]))
        speech.finish { _ in XCTFail("The first upload is expected to fail") }
        await wait { speech.canRetry }
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(fixture.requests.count, 1)

        speech.finish { _ in }
        await wait { speech.state == .idle }
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(fixture.requests.count, 2)
    }

    func testFailedWAVSaveSkipsUploadAndKeepsPCMForRetry() async {
        let fixture = CaptureSpeechPersistenceFixture()
        let speech = fixture.make()
        var attempts = 0
        var saved: [Data] = []
        speech.onRecordingCaptured = { data in
            attempts += 1
            if attempts == 1 { throw CaptureSpeechPersistenceError.saveFailed }
            saved.append(data)
        }

        speech.start(key: "test")
        await wait { speech.state == .recording }
        let pcm = Data([7, 8])
        fixture.audio.yield(pcm)
        speech.finish { _ in XCTFail("A failed save must not upload") }
        await wait { speech.canRetry }
        XCTAssertEqual(attempts, 1)
        XCTAssertTrue(saved.isEmpty)
        XCTAssertTrue(fixture.requests.isEmpty)

        speech.finish { _ in }
        await wait { speech.state == .idle }
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(saved, [try? V2RecordedSpeechClient.wavData(pcm: pcm)].compactMap { $0 })
        XCTAssertEqual(fixture.requests, [pcm])
    }

    private func wait(_ condition: @escaping () -> Bool) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("State transition timed out")
    }
}

@MainActor
private final class CaptureSpeechPersistenceFixture {
    let stream: AsyncThrowingStream<Data, Error>
    let audio: AsyncThrowingStream<Data, Error>.Continuation
    var requests: [Data] = []
    var events: [String] = []
    var failFirstUpload = false

    init() {
        (stream, audio) = AsyncThrowingStream.makeStream()
    }

    func make() -> V2RecordedSpeechTranscriber {
        V2RecordedSpeechTranscriber(
            permission: { true },
            startAudio: { self.stream },
            stopAudio: { self.audio.finish() },
            transcribe: { pcm, _ in
                self.events.append("upload")
                self.requests.append(pcm)
                if self.failFirstUpload {
                    self.failFirstUpload = false
                    throw CaptureSpeechPersistenceError.uploadFailed
                }
                return "完整文字"
            }
        )
    }
}

private enum CaptureSpeechPersistenceError: Error {
    case saveFailed
    case uploadFailed
}

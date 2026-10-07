import AVFoundation
import Foundation
import Speech
import ToughTrialV2Core
import XCTest
#if os(macOS)
@testable import ToughTrialMac
#else
@testable import ToughTrial
#endif

@MainActor
final class V2TranscriptionTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("transcription-test-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func audio(in directory: URL, seconds: Double = 2,
                       sampleRate: Double = 48_000, channels: AVAudioChannelCount = 2) throws -> URL {
        let url = directory.appendingPathComponent("test.wav")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels))
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frames = AVAudioFrameCount(seconds * sampleRate)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        let samples = try XCTUnwrap(buffer.floatChannelData)
        for channel in 0..<Int(channels) {
            for frame in 0..<Int(frames) { samples[channel][frame] = Float(sin(Double(frame) * 440 * 2 * .pi / sampleRate)) * 0.25 }
        }
        try file.write(from: buffer)
        return url
    }

    func testStereoFileProducesNonemptyMonoPCMAndResumesAtCheckpoint() async throws {
        let url = try audio(in: directory())
        let reader = try V2TranscriptionPCMReader(url: url, maximumBytes: 32_000)
        let firstData = try await reader.next()
        let secondData = try await reader.next()
        let first = try XCTUnwrap(firstData)
        let second = try XCTUnwrap(secondData)
        let remaining = try await reader.next()
        XCTAssertEqual(first.count, 32_000)
        XCTAssertEqual(second.count, 32_000)
        XCTAssertNil(remaining)
        XCTAssertTrue(first.contains { $0 != 0 })
        let resumed = try V2TranscriptionPCMReader(url: url, startingAt: 1, maximumBytes: 32_000)
        let tailData = try await resumed.next()
        let tail = try XCTUnwrap(tailData)
        XCTAssertEqual(tail.count, 32_000)
        let duration = await resumed.duration
        XCTAssertEqual(duration, 2, accuracy: 0.001)
    }

    func testCloudSecondChunkFailureKeepsFirstAndRetrySendsOnlyRemainder() async throws {
        let root = try directory()
        let store = V2TranscriptionStore(directory: root.appendingPathComponent("library"))
        let imported = try await store.importMedia(from: audio(in: root), source: .audio)
        var calls = 0
        do {
            try await V2TranscriptionProcessor.transcribeFunASR(imported, audioURL: store.mediaURL(for: imported),
                store: store, key: "synthetic-test", maximumBytes: 32_000, transcribeChunk: { _, _ in
                    calls += 1
                    if calls == 2 { throw URLError(.networkConnectionLost) }
                    return "第一段"
                })
            XCTFail("Second request must fail")
        } catch { XCTAssertTrue(error is URLError) }
        let saved = try XCTUnwrap(store.record(imported.id))
        XCTAssertEqual(saved.provider, .funASR)
        XCTAssertEqual(saved.transcript, "第一段")
        XCTAssertEqual(saved.segments.last?.end, 1)
        var retryCalls = 0
        try await V2TranscriptionProcessor.transcribeFunASR(saved, audioURL: store.mediaURL(for: saved),
            store: store, key: "synthetic-test", maximumBytes: 32_000, transcribeChunk: { pcm, _ in
                retryCalls += 1
                XCTAssertEqual(pcm.count, 32_000)
                return "第二段"
            })
        XCTAssertEqual(retryCalls, 1)
        XCTAssertEqual(store.record(imported.id)?.transcript, "第一段\n第二段")
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.mediaURL(for: imported).path))
    }

    func testChangingProviderFailurePreservesPreviousTranscriptAndSummary() async throws {
        let root = try directory()
        let store = V2TranscriptionStore(directory: root.appendingPathComponent("library"))
        var record = try await store.importMedia(from: audio(in: root), source: .audio)
        record.provider = .apple
        record.segments = [.init(start: 0, end: 1, text: "先前已保存的文字")]
        record.transcript = "先前已保存的文字"; record.summary = "先前摘要"
        try store.update(record)
        do {
            try await V2TranscriptionProcessor.transcribeFunASR(record, audioURL: store.mediaURL(for: record),
                store: store, key: "synthetic-test", transcribeChunk: { _, _ in throw URLError(.notConnectedToInternet) })
            XCTFail("Expected offline failure")
        } catch { XCTAssertTrue(error is URLError) }
        let retained = try XCTUnwrap(store.record(record.id))
        XCTAssertEqual(retained.provider, .apple)
        XCTAssertEqual(retained.transcript, record.transcript)
        XCTAssertEqual(retained.summary, record.summary)
        XCTAssertEqual(retained.segments, record.segments)
    }

    func testSilentCloudChunkDoesNotPreventFollowingSpeechOrLoseCheckpoint() async throws {
        let root = try directory()
        let store = V2TranscriptionStore(directory: root.appendingPathComponent("library"))
        let record = try await store.importMedia(from: audio(in: root), source: .audio)
        var calls = 0
        try await V2TranscriptionProcessor.transcribeFunASR(record, audioURL: store.mediaURL(for: record),
            store: store, key: "synthetic-test", maximumBytes: 32_000, transcribeChunk: { _, _ in
                calls += 1
                if calls == 1 { throw V2RecordedSpeechClient.Failure.empty }
                return "后段有人说话"
            })
        let saved = try XCTUnwrap(store.record(record.id))
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(saved.segments.count, 2)
        XCTAssertEqual(saved.segments.last?.end, 2)
        XCTAssertTrue(saved.transcript.contains("后段有人说话"))
    }

    func testSilentPrefixThenFailureDoesNotEraseOtherProviderText() async throws {
        let root = try directory()
        let store = V2TranscriptionStore(directory: root.appendingPathComponent("library"))
        var record = try await store.importMedia(from: audio(in: root), source: .audio)
        record.provider = .apple; record.transcript = "苹果已保存的文字"; record.summary = "原有摘要"
        record.segments = [.init(start: 0, end: 1, text: record.transcript)]
        try store.update(record)
        var calls = 0
        do {
            try await V2TranscriptionProcessor.transcribeFunASR(record, audioURL: store.mediaURL(for: record),
                store: store, key: "synthetic-test", maximumBytes: 32_000, transcribeChunk: { _, _ in
                    calls += 1
                    if calls == 1 { throw V2RecordedSpeechClient.Failure.empty }
                    throw URLError(.networkConnectionLost)
                })
            XCTFail("Expected second request failure")
        } catch { XCTAssertTrue(error is URLError) }
        XCTAssertEqual(store.record(record.id)?.transcript, record.transcript)
        XCTAssertEqual(store.record(record.id)?.summary, record.summary)
        XCTAssertEqual(store.record(record.id)?.provider, .apple)
    }

    func testAllEmptyCloudAttemptCanRetryFromBeginning() async throws {
        let root = try directory()
        let store = V2TranscriptionStore(directory: root.appendingPathComponent("library"))
        let record = try await store.importMedia(from: audio(in: root), source: .audio)
        do {
            try await V2TranscriptionProcessor.transcribeFunASR(record, audioURL: store.mediaURL(for: record),
                store: store, key: "synthetic-test", maximumBytes: 32_000, transcribeChunk: { _, _ in "" })
            XCTFail("Expected no speech failure")
        } catch { XCTAssertTrue(error is V2TranscriptionProcessingError) }
        let saved = try XCTUnwrap(store.record(record.id))
        var calls = 0
        try await V2TranscriptionProcessor.transcribeFunASR(saved, audioURL: store.mediaURL(for: saved),
            store: store, key: "synthetic-test", maximumBytes: 32_000, transcribeChunk: { _, _ in
                calls += 1; return "重新识别的文字"
            })
        XCTAssertEqual(calls, 2)
        XCTAssertTrue(store.record(record.id)?.transcript.contains("重新识别") == true)
    }

    func testFiveMinuteChunkLimitAndShortRemainder() async throws {
        let url = try audio(in: directory(), seconds: 301, sampleRate: 16_000, channels: 1)
        let reader = try V2TranscriptionPCMReader(url: url)
        let first = try await reader.next()
        let tail = try await reader.next()
        let end = try await reader.next()
        XCTAssertEqual(first?.count, V2RecordedSpeechClient.maximumPCMBytes)
        XCTAssertEqual(tail?.count, 32_000)
        XCTAssertNil(end)
    }

    func testCancelledRequestCannotPersistLateResponse() async throws {
        let root = try directory()
        let store = V2TranscriptionStore(directory: root.appendingPathComponent("library"))
        let record = try await store.importMedia(from: audio(in: root), source: .audio)
        let (responses, continuation) = AsyncStream<String>.makeStream()
        var requested = false
        let work = Task {
            try await V2TranscriptionProcessor.transcribeFunASR(record, audioURL: store.mediaURL(for: record),
                store: store, key: "synthetic-test", transcribeChunk: { _, _ in
                    requested = true
                    for await value in responses { return value }
                    return "迟到的结果"
                })
        }
        for _ in 0..<200 where !requested { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(requested)
        work.cancel(); continuation.yield("迟到的结果"); continuation.finish()
        do { try await work.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(store.record(record.id)?.transcript, "")
        XCTAssertEqual(store.record(record.id)?.segments, [])
    }

    func testCancelledDeletionCannotRecreateRecordOrMedia() async throws {
        let root = try directory()
        let store = V2TranscriptionStore(directory: root.appendingPathComponent("library"))
        let record = try await store.importMedia(from: audio(in: root), source: .audio)
        let mediaURL = store.mediaURL(for: record)
        let (responses, continuation) = AsyncStream<String>.makeStream()
        var requested = false
        let work = Task {
            try await V2TranscriptionProcessor.transcribeFunASR(record, audioURL: mediaURL,
                store: store, key: "synthetic-test", transcribeChunk: { _, _ in
                    requested = true
                    for await value in responses { return value }
                    return "迟到的结果"
                })
        }
        for _ in 0..<200 where !requested { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(requested)
        work.cancel(); try store.delete(record.id)
        continuation.yield("迟到的结果"); continuation.finish()
        do { try await work.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertNil(store.record(record.id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: mediaURL.path))
    }

    func testAppleInputIsConvertedToCompatibleFormatWithoutDeletingOriginal() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { throw XCTSkip("iOS/macOS 26 required") }
        let url = try audio(in: directory())
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true))
        let input = V2TranscriptionAppleInput(reader: try V2TranscriptionAppleReader(url: url, format: format))
        var frames: AVAudioFrameCount = 0
        for try await value in input {
            let buffer = value.buffer
            XCTAssertEqual(buffer.format, format)
            XCTAssertNotNil(buffer.int16ChannelData)
            frames += buffer.frameLength
        }
        XCTAssertEqual(Double(frames) / format.sampleRate, 2, accuracy: 0.005)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let resumed = V2TranscriptionAppleInput(reader: try V2TranscriptionAppleReader(url: url,
            format: format, startingAt: 1))
        var remaining: AVAudioFrameCount = 0
        for try await value in resumed { remaining += value.buffer.frameLength }
        XCTAssertEqual(Double(remaining) / format.sampleRate, 1, accuracy: 0.005)
    }

    func testInterruptedOperationDuringPauseUsesPauseMessage() {
        let interrupted = NSError(domain: AVFoundationErrorDomain, code: -11847,
            userInfo: [NSLocalizedDescriptionKey: "Operation Interrupted"])
        let message = V2TranscriptionProcessor.failureMessage(interrupted, stage: "正在提取视频音轨…", cancelled: true)
        XCTAssertTrue(message.contains("已暂停"))
        XCTAssertFalse(message.contains("Operation Interrupted"))
        let failure = V2TranscriptionProcessor.failureMessage(interrupted, stage: "正在提取视频音轨…", cancelled: false)
        XCTAssertTrue(failure.contains("音轨"))
        XCTAssertFalse(failure.contains("Operation Interrupted"))
    }

    func testPhotoImportHasReadableTitleAndInterruptedRecordSurvivesRestart() async throws {
        let root = try directory()
        let source = try audio(in: root)
        let photo = root.appendingPathComponent("picked-video-\(UUID()).wav")
        try FileManager.default.copyItem(at: source, to: photo)
        let library = root.appendingPathComponent("library")
        let store = V2TranscriptionStore(directory: library)
        var record = try await store.importMedia(from: photo, source: .video)
        XCTAssertEqual(record.title, "相册视频")
        record.status = .processing; record.transcript = "已保存的文字"
        try store.update(record)
        let restored = V2TranscriptionStore(directory: library)
        XCTAssertEqual(restored.record(record.id)?.status, .failed)
        XCTAssertEqual(restored.record(record.id)?.transcript, "已保存的文字")
        XCTAssertTrue(FileManager.default.fileExists(atPath: restored.mediaURL(for: record).path))
    }

    func testSyntheticVideoImportExtractsAndReadsCompleteAudio() async throws {
        guard let path = ProcessInfo.processInfo.environment["TOUGH_TRIAL_TRANSCRIPTION_TEST_MEDIA"] else {
            throw XCTSkip("Provide a synthetic local test video path")
        }
        let store = V2TranscriptionStore(directory: try directory())
        let record = try await store.importMedia(from: URL(fileURLWithPath: path), source: .video)
        let original = store.mediaURL(for: record)
        let extracted = try await V2TranscriptionAudioFile.prepare(original, source: .video)
        defer { try? FileManager.default.removeItem(at: extracted) }
        XCTAssertNotEqual(extracted, original)
        let file = try AVAudioFile(forReading: extracted)
        let duration = Double(file.length) / file.processingFormat.sampleRate
        XCTAssertGreaterThan(duration, 1)
        let reader = try V2TranscriptionPCMReader(url: extracted, maximumBytes: 32_000)
        var bytes = 0
        var containsAudio = false
        while let data = try await reader.next() {
            XCTAssertFalse(data.isEmpty)
            XCTAssertLessThanOrEqual(data.count, 32_000)
            bytes += data.count
            containsAudio = containsAudio || data.contains { $0 != 0 }
        }
        XCTAssertTrue(containsAudio)
        XCTAssertEqual(Double(bytes) / 32_000, duration, accuracy: 0.005)
        let afterEnd = try await reader.next()
        XCTAssertNil(afterEnd)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        XCTAssertEqual(store.record(record.id)?.status, .draft)
    }

    /// Opt-in: the saved prefix must survive retry, while later timestamps remain absolute.
    func testAppleRetryKeepsSavedPrefixAndContinuesAfterCheckpoint() async throws {
        guard let path = ProcessInfo.processInfo.environment["TOUGH_TRIAL_TRANSCRIPTION_TEST_MEDIA"] else {
            throw XCTSkip("Provide a synthetic local test recording path")
        }
        guard #available(iOS 26.0, macOS 26.0, *), SpeechTranscriber.isAvailable else {
            throw XCTSkip("Apple model unavailable; no recognition success claimed")
        }
        let library = try directory()
        let store = V2TranscriptionStore(directory: library)
        let url = URL(fileURLWithPath: path)
        var record = try await store.importMedia(from: url, source: url.pathExtension == "mp4" ? .video : .audio)
        let prefix = V2TranscriptionSegment(start: 0, end: 1, text: "已保存的首段。")
        record.provider = .apple
        record.status = .failed
        record.errorMessage = "上次转录失败"
        record.segments = [prefix]
        record.transcript = prefix.text
        try store.update(record)
        try await V2TranscriptionProcessor.transcribe(record, store: store, provider: .apple)
        let saved = try XCTUnwrap(store.record(record.id))
        XCTAssertEqual(saved.segments.first, prefix)
        XCTAssertGreaterThan(saved.segments.count, 1)
        XCTAssertTrue(saved.transcript.hasPrefix(prefix.text))
        XCTAssertTrue(saved.segments.dropFirst().allSatisfy { $0.start >= prefix.end })
        let duration = try XCTUnwrap(saved.duration)
        XCTAssertLessThanOrEqual(try XCTUnwrap(saved.segments.last).end, duration + 0.02)
        XCTAssertTrue(saved.transcript.contains("开会"))
        XCTAssertNil(saved.errorMessage)
        let reopened = V2TranscriptionStore(directory: library)
        XCTAssertEqual(reopened.record(record.id)?.transcript, saved.transcript)
        XCTAssertEqual(reopened.record(record.id)?.segments, saved.segments)
    }

    /// Opt-in: synthetic local media only. Does not load credentials or call FunASR/AI.
    func testFixedMediaThroughProductionApplePipeline() async throws {
        let fixture = Bundle.main.bundleIdentifier == "com.skyliu.toughtrial.transcriptioncheck"
            ? Bundle.main.url(forResource: "mandarin", withExtension: "mp4")?.path : nil
        guard let path = ProcessInfo.processInfo.environment["TOUGH_TRIAL_TRANSCRIPTION_TEST_MEDIA"] ?? fixture else {
            throw XCTSkip("Provide a synthetic local test audio/video path")
        }
        guard #available(iOS 26.0, macOS 26.0, *) else { throw XCTSkip("iOS/macOS 26 required") }
        guard SpeechTranscriber.isAvailable else {
            throw XCTSkip("Apple SpeechTranscriber is unavailable on this runtime; no recognition success claimed")
        }
        let library = try directory()
        let store = V2TranscriptionStore(directory: library)
        let url = URL(fileURLWithPath: path)
        let record = try await store.importMedia(from: url, source: url.pathExtension == "mp4" ? .video : .audio)
        var stages: [String] = []
        try await V2TranscriptionProcessor.transcribe(record, store: store, provider: .apple) {
            stages.append($0)
            FileHandle.standardError.write(Data(("TRANSCRIPTION_TEST_STAGE \($0)\n").utf8))
        }
        let saved = try XCTUnwrap(store.record(record.id))
        XCTAssertTrue(saved.transcript.contains("明天下午"), saved.transcript)
        XCTAssertTrue(saved.transcript.contains("开会"), saved.transcript)
        XCTAssertFalse(saved.segments.isEmpty)
        XCTAssertGreaterThan(saved.duration ?? 0, 1)
        XCTAssertTrue(stages.contains { $0.contains("本机识别") })
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.mediaURL(for: record).path))
        let reopened = V2TranscriptionStore(directory: library)
        let persisted = try XCTUnwrap(reopened.record(record.id))
        XCTAssertEqual(persisted.provider, .apple)
        XCTAssertEqual(persisted.transcript, saved.transcript)
        XCTAssertEqual(persisted.segments, saved.segments)
        XCTAssertEqual(persisted.duration, saved.duration)
        XCTAssertEqual(try Data(contentsOf: reopened.mediaURL(for: persisted)), try Data(contentsOf: url))
    }
}

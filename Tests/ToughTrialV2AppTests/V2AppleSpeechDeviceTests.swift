import AVFoundation
import Speech
import ToughTrialV2Core
import XCTest
@testable import ToughTrial

/// Opt-in model diagnostic with a locally supplied, fixed test phrase. No microphone or task writes.
@MainActor
final class V2AppleSpeechDeviceTests: XCTestCase {
    nonisolated override class func tearDown() {
        if ProcessInfo.processInfo.environment["TOUGH_TRIAL_APPLE_FILE_TEST"] == "1" {
            try? FileManager.default.removeItem(at: URL.documentsDirectory.appendingPathComponent("speech-test.aiff"))
        }
        super.tearDown()
    }

    func testFixedRecordingThroughFunASR() async throws {
        guard ProcessInfo.processInfo.environment["TOUGH_TRIAL_APPLE_FILE_TEST"] == "1" else {
            throw XCTSkip("Explicit fixed-audio device test required")
        }
        let file = try AVAudioFile(forReading: URL.documentsDirectory.appendingPathComponent("speech-test.aiff"))
        let converter = try V2SpeechPCMConverter(input: file.processingFormat)
        var pcm = Data()
        while file.framePosition < file.length {
            let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 2048)!
            try file.read(into: buffer)
            pcm.append(try converter.convert(buffer))
        }
        pcm.append(try converter.finish())
        let (audio, continuation) = AsyncThrowingStream<Data, Error>.makeStream()
        let speech = V2RealtimeSpeechTranscriber(permission: { true }, open: V2SpeechConnection.live,
            startAudio: { audio }, stopAudio: { continuation.finish() })
        defer { speech.cancel() }
        speech.start(key: try V2SpeechSettings.loadKey())
        for _ in 0..<200 {
            if speech.state == .recording || speech.errorMessage != nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertEqual(speech.state, .recording, speech.errorMessage ?? "Connection timeout")
        guard speech.state == .recording else { return }
        let start = Date()
        var firstTextAt: Date?
        for offset in stride(from: 0, to: pcm.count, by: 3200) {
            continuation.yield(pcm.subdata(in: offset..<min(offset + 3200, pcm.count)))
            if firstTextAt == nil, !speech.transcript.isEmpty { firstTextAt = Date() }
            try await Task.sleep(for: .milliseconds(100))
        }
        let finish = Date()
        var final: String?
        speech.finish { final = $0 }
        for _ in 0..<200 {
            if speech.state == .idle { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        print("FUNASR_FILE_RESULT first_text=\(firstTextAt?.timeIntervalSince(start) ?? -1) finish=\(Date().timeIntervalSince(finish)) total=\(Date().timeIntervalSince(start)) text=\(final ?? speech.transcript)")
        XCTAssertNotNil(final, speech.errorMessage ?? "Finalization timeout")
        XCTAssertTrue(final?.contains("测试成功") == true)
    }

    func testFixedRecordingThroughAppleModel() async throws {
        guard ProcessInfo.processInfo.environment["TOUGH_TRIAL_APPLE_FILE_TEST"] == "1" else {
            throw XCTSkip("Explicit fixed-audio device test required")
        }
        guard #available(iOS 26.0, *) else { throw XCTSkip("iOS 26 required") }
        XCTAssertTrue(SpeechTranscriber.isAvailable)
        try await V2AppleSpeechBackend.prepareModel { print("APPLE_MODEL_STATUS \($0)") }
        let supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "zh_CN"))
        let locale = try XCTUnwrap(supportedLocale)
        let fileURL = URL.documentsDirectory.appendingPathComponent("speech-test.aiff")
        for converted in [false, true] {
            let module = converted
                ? try await V2AppleSpeechBackend.makeTranscriber()
                : SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: [])
            let analyzer = SpeechAnalyzer(modules: [module])
            let audio = try AVAudioFile(forReading: fileURL)
            let start = Date()
            var transcript = ""
            var firstTextAt: Date?
            var finishAt: Date?
            let bestFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module])
            let format = try XCTUnwrap(bestFormat)
            print("APPLE_MODEL_FORMAT \(format) source=\(audio.processingFormat) converted=\(converted)")
            if converted {
                let converter = try V2AppleAudioConverter(input: audio.processingFormat, output: format)
                let (input, continuation) = AsyncThrowingStream<AnalyzerInput, Error>.makeStream()
                try await analyzer.start(inputSequence: input)
                let finish = Task {
                    while audio.framePosition < audio.length {
                        let buffer = AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: 2048)!
                        try audio.read(into: buffer)
                        for converted in try converter.convert(buffer) { continuation.yield(AnalyzerInput(buffer: converted)) }
                        try await Task.sleep(for: .seconds(Double(buffer.frameLength) / buffer.format.sampleRate))
                    }
                    for tail in try converter.convert(nil) { continuation.yield(AnalyzerInput(buffer: tail)) }
                    continuation.finish()
                    finishAt = Date()
                    try await analyzer.finalizeAndFinishThroughEndOfInput()
                }
                defer { finish.cancel() }
                for try await result in module.results {
                    if firstTextAt == nil { firstTextAt = Date() }
                    if result.isFinal { transcript += String(result.text.characters) }
                }
                try await finish.value
            } else {
                try await analyzer.start(inputAudioFile: audio, finishAfterFile: true)
                for try await result in module.results {
                    if result.isFinal { transcript += String(result.text.characters) }
                }
            }
            print("APPLE_FILE_RESULT converted=\(converted) seconds=\(Date().timeIntervalSince(start)) first_text=\(firstTextAt?.timeIntervalSince(start) ?? -1) finish=\(finishAt.map { Date().timeIntervalSince($0) } ?? -1) text=\(transcript)")
            XCTAssertTrue(transcript.contains("测试成功"))
            let normalized = transcript.replacingOccurrences(of: "三", with: "3").replacingOccurrences(of: "四", with: "4")
                .replacingOccurrences(of: " ", with: "")
            for detail in ["3点", "4点", "不要修改任何日程"] { XCTAssertTrue(normalized.contains(detail), detail) }
            if converted {
                XCTAssertNotNil(firstTextAt)
                XCTAssertNotNil(finishAt)
                if let firstTextAt, let finishAt { XCTAssertLessThan(firstTextAt, finishAt, "Live text must appear before Finish") }
            }
        }
    }
}

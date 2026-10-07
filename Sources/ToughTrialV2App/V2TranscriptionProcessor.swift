import AVFoundation
import Foundation
import OSLog
import Speech
import ToughTrialV2Core

enum V2TranscriptionProcessingError: LocalizedError {
    case noAudio, unsupportedApple, noSpeechKey, emptyTranscript, noAI

    var errorDescription: String? {
        switch self {
        case .noAudio: "这个文件没有可读取的音轨。"
        case .unsupportedApple: "苹果原生文件识别需要 iOS 26 / macOS 26 与可用的中文语音模型。"
        case .noSpeechKey: "请先在语音设置中保存百炼 FunASR 密钥。"
        case .emptyTranscript: "没有识别到文字；原文件已保留，可以换一种方式重试。"
        case .noAI: "尚未配置 AI 服务。逐字稿已保存，配置后可重新生成摘要。"
        }
    }
}

/// Extracts only audio from a video. The temporary audio is deleted after recognition.
enum V2TranscriptionAudioFile {
    static func prepare(_ url: URL, source: V2TranscriptionRecord.Source) async throws -> URL {
        guard source == .video else { return url }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcription-\(UUID().uuidString).m4a")
        let asset = AVURLAsset(url: url)
        guard try await !asset.loadTracks(withMediaType: .audio).isEmpty else {
            throw V2TranscriptionProcessingError.noAudio
        }
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw V2TranscriptionProcessingError.noAudio
        }
        do {
            if #available(iOS 18.0, macOS 15.0, *) {
                try await session.export(to: destination, as: .m4a)
            } else {
                session.outputURL = destination
                session.outputFileType = .m4a
                await session.export()
                guard session.status == .completed else {
                    throw session.error ?? V2TranscriptionProcessingError.noAudio
                }
            }
            try Task.checkCancellation()
            let file = try AVAudioFile(forReading: destination)
            guard file.length > 0 else { throw V2TranscriptionProcessingError.noAudio }
            return destination
        } catch {
            try? FileManager.default.removeItem(at: destination)
            if Task.isCancelled { throw CancellationError() }
            throw error
        }
    }
}

/// Pull-based input bounds memory and checks EOF before reading the last partial buffer.
@available(iOS 26.0, macOS 26.0, *)
actor V2TranscriptionAppleReader {
    let duration: Double
    private let file: AVAudioFile
    private let converter: V2AppleAudioConverter
    private var pending: [AVAudioPCMBuffer] = []
    private var finished = false

    init(url: URL, format: AVAudioFormat, startingAt seconds: Double = 0) throws {
        file = try AVAudioFile(forReading: url)
        guard file.length > 0, file.processingFormat.sampleRate > 0 else { throw V2TranscriptionProcessingError.noAudio }
        duration = Double(file.length) / file.processingFormat.sampleRate
        file.framePosition = min(file.length, max(0, AVAudioFramePosition(seconds * file.processingFormat.sampleRate)))
        converter = try V2AppleAudioConverter(input: file.processingFormat, output: format)
    }

    func next() throws -> AnalyzerInput? {
        try Task.checkCancellation()
        while pending.isEmpty && !finished {
            if file.framePosition >= file.length {
                pending = try converter.convert(nil)
                finished = true
            } else {
                let frames = AVAudioFrameCount(min(16_384, file.length - file.framePosition))
                guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames) else {
                    throw V2SpeechAudioError.conversion
                }
                try file.read(into: buffer, frameCount: frames)
                if buffer.frameLength == 0 {
                    pending = try converter.convert(nil)
                    finished = true
                } else { pending = try converter.convert(buffer) }
            }
            try Task.checkCancellation()
        }
        guard !pending.isEmpty else { return nil }
        return AnalyzerInput(buffer: pending.removeFirst())
    }
}

@available(iOS 26.0, macOS 26.0, *)
struct V2TranscriptionAppleInput: AsyncSequence, Sendable {
    typealias Element = AnalyzerInput
    let reader: V2TranscriptionAppleReader
    struct AsyncIterator: AsyncIteratorProtocol {
        let reader: V2TranscriptionAppleReader
        mutating func next() async throws -> AnalyzerInput? { try await reader.next() }
    }
    func makeAsyncIterator() -> AsyncIterator { AsyncIterator(reader: reader) }
}

actor V2TranscriptionPCMReader {
    let duration: Double
    private let file: AVAudioFile
    private let converter: V2SpeechPCMConverter
    private var pending = Data()
    private var finished = false
    private let maximumBytes: Int

    init(url: URL, startingAt seconds: Double = 0,
         maximumBytes: Int = V2RecordedSpeechClient.maximumPCMBytes) throws {
        file = try AVAudioFile(forReading: url)
        guard file.processingFormat.sampleRate > 0, file.length > 0 else { throw V2TranscriptionProcessingError.noAudio }
        duration = Double(file.length) / file.processingFormat.sampleRate
        file.framePosition = min(file.length, max(0, AVAudioFramePosition(seconds * file.processingFormat.sampleRate)))
        converter = try V2SpeechPCMConverter(input: file.processingFormat)
        self.maximumBytes = min(V2RecordedSpeechClient.maximumPCMBytes, max(2, maximumBytes / 2 * 2))
    }

    func next() throws -> Data? {
        let maximum = maximumBytes
        while pending.count < maximum && !finished {
            try Task.checkCancellation()
            if file.framePosition >= file.length {
                pending.append(try converter.finish())
                finished = true
                break
            }
            let frames = AVAudioFrameCount(min(16_384, file.length - file.framePosition))
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames) else {
                throw V2SpeechAudioError.conversion
            }
            try file.read(into: buffer, frameCount: frames)
            if buffer.frameLength == 0 {
                pending.append(try converter.finish())
                finished = true
            } else {
                pending.append(try converter.convert(buffer))
            }
        }
        guard !pending.isEmpty else { return nil }
        let count = min(maximum, pending.count)
        let chunk = pending.prefix(count)
        pending.removeFirst(count)
        return Data(chunk)
    }
}

@MainActor
enum V2TranscriptionProcessor {
    private static let logger = Logger(subsystem: "com.skyliu.toughtrial", category: "transcription")

    static func transcribe(_ record: V2TranscriptionRecord, store: V2TranscriptionStore,
                           provider: V2TranscriptionRecord.Provider,
                           progress: @escaping @MainActor (String) -> Void = { _ in }) async throws {
        try Task.checkCancellation()
        let sourceURL = store.mediaURL(for: record)
        progress(record.source == .video ? "正在提取视频音轨…" : "正在读取录音…")
        let audioURL = try await V2TranscriptionAudioFile.prepare(sourceURL, source: record.source)
        defer { if audioURL != sourceURL { try? FileManager.default.removeItem(at: audioURL) } }
        try Task.checkCancellation()
        switch provider {
        case .apple:
            guard #available(iOS 26.0, macOS 26.0, *) else { throw V2TranscriptionProcessingError.unsupportedApple }
            try await transcribeApple(record, audioURL: audioURL, store: store, progress: progress)
        case .funASR:
            progress("正在准备云端转录…")
            try await transcribeFunASR(record, audioURL: audioURL, store: store,
                key: V2SpeechSettings.loadKey(), progress: progress)
        }
    }

    @available(iOS 26.0, macOS 26.0, *)
    private static func transcribeApple(_ original: V2TranscriptionRecord, audioURL: URL,
                                        store: V2TranscriptionStore,
                                        progress: @escaping @MainActor (String) -> Void) async throws {
        let start = original.status != .complete && original.provider == .apple
            && !original.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? max(0, original.segments.map(\.end).max() ?? 0) : 0
        progress("正在准备本机中文语音模型…")
        let transcriber = try await V2AppleSpeechBackend.makeTranscriber(file: true)
        try await V2AppleSpeechBackend.install(transcriber, status: progress)
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw V2SpeechAudioError.unsupportedFormat
        }
        let opening = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            return try V2TranscriptionAppleReader(url: audioURL, format: format, startingAt: start)
        }
        let reader = try await withTaskCancellationHandler { try await opening.value } onCancel: { opening.cancel() }
        let input = V2TranscriptionAppleInput(reader: reader)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        var record = original
        record.status = .processing
        record.errorMessage = nil
        record.duration = reader.duration
        try Task.checkCancellation()
        try store.update(record)
        var hasSpeech = start > 0
        do {
            try await withTaskCancellationHandler {
                try await analyzer.prepareToAnalyze(in: format)
                try Task.checkCancellation()
                progress("正在本机识别，首段文字完成后自动保存…")
                let feeding = Task {
                    do {
                        let end = try await analyzer.analyzeSequence(input)
                        try Task.checkCancellation()
                        if let end { try await analyzer.finalizeAndFinish(through: end) }
                        else { await analyzer.cancelAndFinishNow() }
                    } catch {
                        await analyzer.cancelAndFinishNow()
                        throw error
                    }
                }
                do {
                    for try await result in transcriber.results {
                        // Keep final results already published when pausing; never recreate a deleted record.
                        guard store.record(original.id) != nil else { continue }
                        guard result.isFinal else { continue }
                        let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !text.isEmpty else { continue }
                        if !hasSpeech {
                            record.segments = []
                            record.transcript = ""
                            record.provider = .apple
                            hasSpeech = true
                        }
                        record.summary = nil
                        let segment = V2TranscriptionSegment(start: start + result.range.start.seconds,
                            end: start + result.range.end.seconds, text: text)
                        record.segments.removeAll { $0.start < segment.end && segment.start < $0.end }
                        record.segments.append(segment)
                        record.segments.sort { $0.start < $1.start }
                        record.transcript = record.segments.map(\.text).joined()
                        try store.update(record)
                        progress("正在本机识别，已保存至 \(Int(segment.end)) 秒…")
                    }
                    try await feeding.value
                } catch {
                    feeding.cancel()
                    await analyzer.cancelAndFinishNow()
                    _ = try? await feeding.value
                    throw error
                }
            } onCancel: {
                Task { await analyzer.cancelAndFinishNow() }
            }
            try Task.checkCancellation()
        } catch {
            await analyzer.cancelAndFinishNow()
            if Task.isCancelled { throw CancellationError() }
            throw error
        }
        guard hasSpeech, !record.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw V2TranscriptionProcessingError.emptyTranscript
        }
    }

    static func transcribeFunASR(_ original: V2TranscriptionRecord, audioURL: URL,
                                store: V2TranscriptionStore, key: String,
                                maximumBytes: Int = V2RecordedSpeechClient.maximumPCMBytes,
                                progress: @escaping @MainActor (String) -> Void = { _ in },
                                transcribeChunk: @MainActor (Data, String) async throws -> String = {
                                    try await V2RecordedSpeechClient.transcribe(pcm: $0, key: $1)
                                }) async throws {
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw V2TranscriptionProcessingError.noSpeechKey
        }
        var record = original
        record.status = .processing
        record.errorMessage = nil
        // A previous all-empty attempt must be retryable rather than resuming at EOF forever.
        let start = record.provider == .funASR && !record.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (record.segments.last?.end ?? 0) : 0
        let opening = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            return try V2TranscriptionPCMReader(url: audioURL, startingAt: start, maximumBytes: maximumBytes)
        }
        let reader = try await withTaskCancellationHandler { try await opening.value } onCancel: { opening.cancel() }
        record.duration = reader.duration
        try Task.checkCancellation()
        try store.update(record)
        var offset = start
        var segments = start > 0 ? record.segments : []
        var hasNewSpeech = start > 0
        while let pcm = try await reader.next() {
            try Task.checkCancellation()
            let end = min(record.duration ?? .infinity, offset + Double(pcm.count) / 32_000)
            progress("正在云端识别 \(Int(offset))–\(Int(ceil(end))) 秒音频，完成后保存…")
            let text: String
            do { text = try await transcribeChunk(pcm, key) }
            catch V2RecordedSpeechClient.Failure.empty { text = "" }
            try Task.checkCancellation()
            segments.append(.init(start: offset, end: end, text: text))
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { hasNewSpeech = true }
            offset = end
            // A silent prefix from another provider must not erase a useful existing transcript.
            if !hasNewSpeech && !original.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            record.provider = .funASR
            record.segments = segments
            if start == 0 { record.summary = nil }
            record.transcript = record.segments.map(\.text).joined(separator: "\n")
            try store.update(record)
        }
        guard hasNewSpeech, !record.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw V2TranscriptionProcessingError.emptyTranscript
        }
    }

    static func failureMessage(_ error: Error, stage: String, cancelled: Bool) -> String {
        if cancelled || error is CancellationError { return "已暂停；原文件和完成的文字已保存。" }
        let value = error as NSError
        logger.error("stage=\(stage, privacy: .public) domain=\(value.domain, privacy: .public) code=\(value.code)")
        if error is V2TranscriptionProcessingError || error is V2AppleSpeechError || error is V2RecordedSpeechClient.Failure {
            return error.localizedDescription
        }
        if value.domain == NSURLErrorDomain {
            return "云端转录连接中断，请检查网络后继续。原文件和已完成的文字已保留。"
        }
        return "\(stage.isEmpty ? "转录" : stage)未完成。原文件和已完成的文字已保留，可以继续重试。"
    }

    static func summarize(_ record: V2TranscriptionRecord, store: V2TranscriptionStore) async throws {
        let settings = V2AIProviderSettingsStore.load()
        guard settings.isEnabled else { throw V2TranscriptionProcessingError.noAI }
        let client = try settings.agentClient()
        let text = (record.segments.isEmpty ? record.transcript : record.segments.map { segment in
            let seconds = max(0, Int(segment.start))
            return String(format: "[%02d:%02d] %@", seconds / 60, seconds % 60, segment.text)
        }.joined(separator: "\n")).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw V2TranscriptionProcessingError.emptyTranscript }
        let sections = stride(from: 0, to: text.count, by: 12_000).map { start -> String in
            let a = text.index(text.startIndex, offsetBy: start)
            let b = text.index(a, offsetBy: min(12_000, text.count - start))
            return String(text[a..<b])
        }
        let instruction = "根据以下内容，输出一段简短概览和最多三条重点。只保留有依据的内容；有时间标记时在重点后注明对应时间，不要编造时间或待办。"
        let result: String
        if sections.count == 1 {
            result = try await answer(client, prompt: instruction + "\n\n" + sections[0])
        } else {
            var inputs: [String] = []
            for section in sections {
                try Task.checkCancellation()
                inputs.append(try await answer(client, prompt: "请忠实概括以下逐字稿片段，只写实际出现的事实与决定，勿虚构待办。若片段含时间标记，请保留可引用的时间。\n\n\(section)"))
            }
            result = try await answer(client, prompt: instruction + "\n\n" + inputs.joined(separator: "\n\n"))
        }
        guard var current = store.record(record.id) else { return }
        guard current.transcript == record.transcript, current.summary == record.summary else { return }
        current.summary = result
        current.errorMessage = nil
        try store.update(current)
    }

    private static func answer(_ client: any V2AgentClient, prompt: String) async throws -> String {
        let response = try await client.respond(.init(userText: prompt, conversation: [], observations: [], webAvailable: false))
        guard case let .answer(text) = response.action, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw V2AgentClientError.missingOutput
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

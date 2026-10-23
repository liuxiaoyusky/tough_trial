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

/// Carries the failing operation without exposing system descriptions or file URLs.
struct V2TranscriptionStageError: Error {
    let stage: V2TranscriptionRecord.Stage
    let underlying: Error

    static func run<T>(_ stage: V2TranscriptionRecord.Stage, _ operation: () throws -> T) throws -> T {
        do { return try operation() }
        catch {
            if error is CancellationError || error is Self { throw error }
            throw Self(stage: stage, underlying: error)
        }
    }
}

/// Extracts only audio from a video. The temporary audio is deleted after recognition.
enum V2TranscriptionAudioFile {
    static func prepare(_ url: URL, source: V2TranscriptionRecord.Source,
                        stage: @MainActor (V2TranscriptionRecord.Stage) throws -> Void = { _ in }) async throws -> URL {
        guard source == .video else { return url }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcription-\(UUID().uuidString).m4a")
        let asset = AVURLAsset(url: url)
        var operation = V2TranscriptionRecord.Stage.videoAudioInspection
        do {
            try await stage(operation)
            guard try await !asset.loadTracks(withMediaType: .audio).isEmpty else {
                throw V2TranscriptionProcessingError.noAudio
            }
            operation = .videoAudioExtraction
            try await stage(operation)
            guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
                throw V2TranscriptionProcessingError.noAudio
            }
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
            operation = .audioRead
            try await stage(operation)
            let file = try AVAudioFile(forReading: destination)
            guard file.length > 0 else { throw V2TranscriptionProcessingError.noAudio }
            return destination
        } catch {
            try? FileManager.default.removeItem(at: destination)
            if Task.isCancelled { throw CancellationError() }
            if error is V2TranscriptionStageError { throw error }
            throw V2TranscriptionStageError(stage: operation, underlying: error)
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
        file = try V2TranscriptionStageError.run(.audioRead) { try AVAudioFile(forReading: url) }
        guard file.length > 0, file.processingFormat.sampleRate > 0 else {
            throw V2TranscriptionStageError(stage: .audioRead, underlying: V2TranscriptionProcessingError.noAudio)
        }
        duration = Double(file.length) / file.processingFormat.sampleRate
        file.framePosition = min(file.length, max(0, AVAudioFramePosition(seconds * file.processingFormat.sampleRate)))
        let inputFormat = file.processingFormat
        converter = try V2TranscriptionStageError.run(.formatConversion) {
            try V2AppleAudioConverter(input: inputFormat, output: format)
        }
    }

    func next() throws -> AnalyzerInput? {
        try Task.checkCancellation()
        while pending.isEmpty && !finished {
            if file.framePosition >= file.length {
                pending = try V2TranscriptionStageError.run(.formatConversion) { try converter.convert(nil) }
                finished = true
            } else {
                let frames = AVAudioFrameCount(min(16_384, file.length - file.framePosition))
                guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames) else {
                    throw V2TranscriptionStageError(stage: .formatConversion, underlying: V2SpeechAudioError.conversion)
                }
                do { try file.read(into: buffer, frameCount: frames) }
                catch { throw V2TranscriptionStageError(stage: .audioRead, underlying: error) }
                if buffer.frameLength == 0 {
                    pending = try V2TranscriptionStageError.run(.formatConversion) { try converter.convert(nil) }
                    finished = true
                } else {
                    pending = try V2TranscriptionStageError.run(.formatConversion) { try converter.convert(buffer) }
                }
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
        file = try V2TranscriptionStageError.run(.audioRead) { try AVAudioFile(forReading: url) }
        guard file.processingFormat.sampleRate > 0, file.length > 0 else {
            throw V2TranscriptionStageError(stage: .audioRead, underlying: V2TranscriptionProcessingError.noAudio)
        }
        duration = Double(file.length) / file.processingFormat.sampleRate
        file.framePosition = min(file.length, max(0, AVAudioFramePosition(seconds * file.processingFormat.sampleRate)))
        let inputFormat = file.processingFormat
        converter = try V2TranscriptionStageError.run(.formatConversion) { try V2SpeechPCMConverter(input: inputFormat) }
        self.maximumBytes = min(V2RecordedSpeechClient.maximumPCMBytes, max(2, maximumBytes / 2 * 2))
    }

    func next() throws -> Data? {
        let maximum = maximumBytes
        while pending.count < maximum && !finished {
            try Task.checkCancellation()
            if file.framePosition >= file.length {
                pending.append(try V2TranscriptionStageError.run(.formatConversion) { try converter.finish() })
                finished = true
                break
            }
            let frames = AVAudioFrameCount(min(16_384, file.length - file.framePosition))
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames) else {
                throw V2TranscriptionStageError(stage: .formatConversion, underlying: V2SpeechAudioError.conversion)
            }
            do { try file.read(into: buffer, frameCount: frames) }
            catch { throw V2TranscriptionStageError(stage: .audioRead, underlying: error) }
            if buffer.frameLength == 0 {
                pending.append(try V2TranscriptionStageError.run(.formatConversion) { try converter.finish() })
                finished = true
            } else {
                pending.append(try V2TranscriptionStageError.run(.formatConversion) { try converter.convert(buffer) })
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
        try stage(.sourceRead, recordID: record.id, store: store, progress: progress)
        try V2TranscriptionStageError.run(.sourceRead) {
            guard try (sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) > 0 else {
                throw V2TranscriptionProcessingError.noAudio
            }
            let handle = try FileHandle(forReadingFrom: sourceURL)
            try handle.close()
        }
        let audioURL = try await V2TranscriptionAudioFile.prepare(sourceURL, source: record.source) {
            try stage($0, recordID: record.id, store: store, progress: progress)
        }
        defer { if audioURL != sourceURL { try? FileManager.default.removeItem(at: audioURL) } }
        try Task.checkCancellation()
        switch provider {
        case .apple:
            try stage(.modelPreparation, recordID: record.id, store: store, progress: progress)
            guard #available(iOS 26.0, macOS 26.0, *) else { throw V2TranscriptionProcessingError.unsupportedApple }
            try await transcribeApple(record, audioURL: audioURL, store: store, progress: progress)
        case .funASR:
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
        try stage(.modelPreparation, recordID: original.id, store: store, progress: progress)
        let transcriber = try await V2AppleSpeechBackend.makeTranscriber(file: true)
        try await V2AppleSpeechBackend.install(transcriber, status: progress)
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw V2TranscriptionStageError(stage: .formatConversion, underlying: V2SpeechAudioError.unsupportedFormat)
        }
        try stage(.audioRead, recordID: original.id, store: store, progress: progress)
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
        record.diagnosticDetails = nil
        record.duration = reader.duration
        try Task.checkCancellation()
        try save(record, store: store)
        var hasSpeech = start > 0
        do {
            try await withTaskCancellationHandler {
                try stage(.modelPreparation, recordID: original.id, store: store, progress: progress)
                try await analyzer.prepareToAnalyze(in: format)
                try Task.checkCancellation()
                try stage(.recognition, recordID: original.id, store: store, progress: progress)
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
                        try save(record, store: store)
                        try stage(.recognition, recordID: original.id, store: store, progress: progress)
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
        try stage(.recognition, recordID: original.id, store: store, progress: progress)
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw V2TranscriptionProcessingError.noSpeechKey
        }
        var record = original
        record.status = .processing
        record.errorMessage = nil
        record.diagnosticDetails = nil
        // A previous all-empty attempt must be retryable rather than resuming at EOF forever.
        let start = record.provider == .funASR && !record.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (record.segments.last?.end ?? 0) : 0
        try stage(.audioRead, recordID: original.id, store: store, progress: progress)
        let opening = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            return try V2TranscriptionPCMReader(url: audioURL, startingAt: start, maximumBytes: maximumBytes)
        }
        let reader = try await withTaskCancellationHandler { try await opening.value } onCancel: { opening.cancel() }
        record.duration = reader.duration
        try Task.checkCancellation()
        try save(record, store: store)
        var offset = start
        var segments = start > 0 ? record.segments : []
        var hasNewSpeech = start > 0
        while true {
            try stage(.formatConversion, recordID: original.id, store: store, progress: progress)
            guard let pcm = try await reader.next() else { break }
            try Task.checkCancellation()
            let end = min(record.duration ?? .infinity, offset + Double(pcm.count) / 32_000)
            try stage(.recognition, recordID: original.id, store: store, progress: progress)
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
            try save(record, store: store)
        }
        try stage(.recognition, recordID: original.id, store: store, progress: progress)
        guard hasNewSpeech, !record.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw V2TranscriptionProcessingError.emptyTranscript
        }
    }

    private static func stage(_ stage: V2TranscriptionRecord.Stage, recordID: UUID,
                              store: V2TranscriptionStore, progress: (String) -> Void) throws {
        guard var record = store.record(recordID) else { throw CancellationError() }
        record.status = .processing
        record.processingStage = stage
        record.errorMessage = nil
        record.diagnosticDetails = nil
        try V2TranscriptionStageError.run(.transcriptSave) { try store.update(record) }
        progress("正在\(stage.title)…")
    }

    private static func save(_ record: V2TranscriptionRecord, store: V2TranscriptionStore) throws {
        var saved = record
        saved.processingStage = .transcriptSave
        try V2TranscriptionStageError.run(.transcriptSave) { try store.update(saved) }
    }

    static func failureMessage(_ error: Error, stage: String, cancelled: Bool) -> String {
        if cancelled || error is CancellationError { return "已暂停；原文件和完成的文字已保存。" }
        let context = error as? V2TranscriptionStageError
        let cause = context?.underlying ?? error
        let operation = context?.stage.title ?? (stage.isEmpty ? "转录" : stage)
        let code = errorCodes(cause).first ?? "UnknownErrorDomain (0)"
        logger.error("stage=\(operation, privacy: .public) error=\(code, privacy: .public)")
        let explanation: String
        if cause is V2TranscriptionProcessingError || cause is V2AppleSpeechError || cause is V2RecordedSpeechClient.Failure {
            explanation = cause.localizedDescription
        } else if (cause as NSError).domain == NSURLErrorDomain {
            explanation = "云端连接中断，请检查网络后继续。原文件和已完成的文字已保留。"
        } else {
            explanation = "原文件和已完成的文字已保留，可以继续重试。"
        }
        return "\(operation)未完成：\(explanation)\n\(code)"
    }

    static func failedRecord(_ record: V2TranscriptionRecord, error: Error,
                             provider: V2TranscriptionRecord.Provider, cancelled: Bool) -> V2TranscriptionRecord {
        var failed = record
        let context = error as? V2TranscriptionStageError
        failed.status = .failed
        failed.processingStage = context?.stage ?? record.processingStage
        failed.errorMessage = failureMessage(error, stage: failed.processingStage?.title ?? "转录", cancelled: cancelled)
        let paused = cancelled || error is CancellationError
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        failed.diagnosticDetails = [
            "Tough Trial \(version) (\(build))", ProcessInfo.processInfo.operatingSystemVersionString,
            "方式：\(provider.rawValue) · 媒体：\(record.source.rawValue)",
            "阶段：\(failed.processingStage?.rawValue ?? "unknown") · \(failed.processingStage?.title ?? "未知")",
            paused ? "结果：已暂停 / 取消" : "结果：失败",
            paused ? "" : errorCodes(context?.underlying ?? error).joined(separator: "\n底层：")
        ].filter { !$0.isEmpty }.joined(separator: "\n")
        return failed
    }

    private static func errorCodes(_ error: Error) -> [String] {
        var values: [String] = []
        var current: NSError? = error as NSError
        var seen = Set<ObjectIdentifier>()
        while let value = current, values.count < 5, seen.insert(ObjectIdentifier(value)).inserted {
            let domain = value.domain.range(of: #"^[A-Za-z][A-Za-z0-9_.-]{0,120}$"#, options: .regularExpression) != nil
                ? value.domain : "OtherErrorDomain"
            values.append("\(domain) (\(value.code))")
            current = value.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return values
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

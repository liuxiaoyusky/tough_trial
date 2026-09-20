import AVFoundation
import Combine
import Foundation
import Speech

/// The backend emits revisions; only a successfully drained session may submit them.
enum V2AppleSpeechEvent {
    case preparing(String)
    case ready
    case text(start: Double, end: Double, text: String, final: Bool)
}

@MainActor
struct V2AppleSpeechSession {
    var run: @MainActor (@escaping @MainActor (V2AppleSpeechEvent) -> Void) async throws -> Void
    var finish: @MainActor () async throws -> Void
    var cancel: @MainActor () -> Void
}

struct V2AppleSpeechTranscript {
    struct Segment {
        var start: Double
        var end: Double
        var text: String
        var final: Bool
    }
    private var segments: [Segment] = []
    var text: String { segments.sorted { $0.start < $1.start }.map(\.text).joined() }
    var hasUnfinishedText: Bool { segments.contains { !$0.final && !$0.text.isEmpty } }

    mutating func apply(start: Double, end: Double, text: String, final: Bool) {
        // A late partial must never replace already finalized audio.
        guard !segments.contains(where: { $0.final && $0.start < end && start < $0.end }) else { return }
        segments.removeAll { !$0.final && $0.start < end && start < $0.end }
        segments.append(Segment(start: start, end: end, text: text, final: final))
    }
}

@MainActor
final class V2AppleSpeechTranscriber: ObservableObject {
    @Published private(set) var state: V2RealtimeSpeechTranscriber.State = .idle
    @Published private(set) var transcript = ""
    @Published private(set) var errorMessage: String?
    @Published private(set) var preparationStatus = "正在准备苹果语音…"
    private let makeSession: () throws -> V2AppleSpeechSession
    private let permission: () async -> Bool
    private var session: V2AppleSpeechSession?
    private var runner: Task<Void, Never>?
    private var finisher: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    private var token: UUID?
    private var reducer = V2AppleSpeechTranscript()
    private var completion: ((String) -> Void)?
    private var resultsEnded = false
    private var finishSucceeded = false

    init(permission: @escaping () async -> Bool = {
        await V2MicrophonePermission.requestAccess()
    }, makeSession: @escaping () throws -> V2AppleSpeechSession = {
        #if os(iOS)
        guard #available(iOS 26.0, *) else {
            throw V2AppleSpeechError.unavailable("苹果原生识别需要 iOS 26 或更新版本，可在语音设置中选择阿里云 FunASR。")
        }
        #elseif os(macOS)
        guard #available(macOS 26.0, *) else {
            throw V2AppleSpeechError.unavailable("苹果原生识别需要 macOS 26 或更新版本，可在语音设置中选择阿里云 FunASR。")
        }
        #else
        throw V2AppleSpeechError.unavailable("当前平台暂不支持苹果原生识别，可在语音设置中选择阿里云 FunASR。")
        #endif
        let backend = V2AppleSpeechBackend()
        return V2AppleSpeechSession(run: { try await backend.run(update: $0) },
                                    finish: { try await backend.finish() }, cancel: { backend.cancel() })
    }) {
        self.permission = permission
        self.makeSession = makeSession
    }

    func start() {
        guard state == .idle else { return }
        let id = UUID()
        token = id
        transcript = ""
        reducer = V2AppleSpeechTranscript()
        resultsEnded = false
        finishSucceeded = false
        errorMessage = nil
        preparationStatus = "正在准备苹果语音…"
        state = .connecting
        runner = Task { [weak self] in
            guard let self else { return }
            do {
                guard await permission(), token == id else {
                    if token == id { fail("麦克风权限未开启，可以在系统设置中更改。", id: id) }
                    return
                }
                let session = try makeSession()
                self.session = session
                try await session.run { [weak self] event in
                    guard let self, token == id else { return }
                    switch event {
                    case let .preparing(message): preparationStatus = message
                    case .ready: state = .recording
                    case let .text(start, end, text, final):
                        reducer.apply(start: start, end: end, text: text, final: final)
                        transcript = reducer.text
                    }
                }
                guard token == id else { return }
                guard state == .finishing, !reducer.hasUnfinishedText else {
                    fail("苹果转写提前结束，已保留文字，请检查后再发送。", id: id)
                    return
                }
                resultsEnded = true
                completeIfReady(id: id)
            } catch {
                fail(error.localizedDescription + " 已保留文字，可重试或在语音设置中切换识别方式。", id: id)
            }
        }
    }

    func finish(onComplete: @escaping (String) -> Void) {
        guard state == .recording, let id = token, let session else { return }
        state = .finishing
        completion = onComplete
        deadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(20)) } catch { return }
            self?.fail("苹果语音收尾超时，已保留文字，请检查后再发送。", id: id)
        }
        finisher = Task { [weak self] in
            do {
                try await session.finish()
                guard let self, token == id else { return }
                finishSucceeded = true
                completeIfReady(id: id)
            }
            catch { self?.fail("苹果语音收尾失败，已保留文字，请检查后再发送。", id: id) }
        }
    }

    func cancel() {
        token = nil
        completion = nil
        runner?.cancel(); runner = nil
        finisher?.cancel(); finisher = nil
        deadline?.cancel(); deadline = nil
        session?.cancel(); session = nil
        state = .idle
    }

    private func completeIfReady(id: UUID) {
        guard token == id, resultsEnded, finishSucceeded else { return }
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let callback = completion
        cancel()
        if text.isEmpty { errorMessage = "没有识别到文字，可以重新录音。" }
        else { callback?(text) }
    }

    func dismissError() { errorMessage = nil }
    private func fail(_ message: String, id: UUID) {
        guard token == id else { return }
        cancel()
        errorMessage = message
    }
}

enum V2AppleSpeechError: LocalizedError {
    case unavailable(String)
    var errorDescription: String? {
        switch self { case let .unavailable(message): message }
    }
}

@available(macOS 26.0, iOS 26.0, *)
@MainActor
final class V2AppleSpeechBackend {
    private let microphone = V2AppleSpeechMicrophone()
    private var analyzer: SpeechAnalyzer?

    static func makeTranscriber() async throws -> SpeechTranscriber {
        guard SpeechTranscriber.isAvailable else {
            throw V2AppleSpeechError.unavailable("这台设备暂不支持苹果新版语音模型。")
        }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "zh_CN")) else {
            throw V2AppleSpeechError.unavailable("当前系统暂不支持苹果中文语音模型。")
        }
        return SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults, .fastResults], attributeOptions: [])
    }

    static func prepareModel(status: (String) -> Void) async throws {
        let transcriber = try await makeTranscriber()
        try await install(transcriber, status: status)
    }

    private static func install(_ transcriber: SpeechTranscriber, status: (String) -> Void) async throws {
        try Task.checkCancellation()
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            status("正在下载中文语音模型，首次使用可能需要一些时间…")
            try await request.downloadAndInstall()
        }
        try Task.checkCancellation()
    }

    func run(update: @escaping @MainActor (V2AppleSpeechEvent) -> Void) async throws {
        let transcriber = try await Self.makeTranscriber()
        try await Self.install(transcriber) { update(.preparing($0)) }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw V2SpeechAudioError.unsupportedFormat
        }
        try Task.checkCancellation()
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        update(.preparing("正在启动苹果语音…"))
        try await analyzer.prepareToAnalyze(in: format)
        try Task.checkCancellation()
        let input = try microphone.start(format: format)
        try await analyzer.start(inputSequence: input)
        try Task.checkCancellation()
        update(.ready)
        for try await result in transcriber.results {
            try Task.checkCancellation()
            update(.text(start: result.range.start.seconds, end: result.range.end.seconds,
                         text: String(result.text.characters), final: result.isFinal))
        }
    }

    func finish() async throws {
        microphone.stop()
        try await analyzer?.finalizeAndFinishThroughEndOfInput()
    }

    func cancel() {
        microphone.stop()
        if let analyzer { Task { await analyzer.cancelAndFinishNow() } }
        analyzer = nil
    }
}

@available(macOS 26.0, iOS 26.0, *)
@MainActor
private final class V2AppleSpeechMicrophone {
    private let engine = AVAudioEngine()
    private var continuation: AsyncThrowingStream<AnalyzerInput, Error>.Continuation?
    private var converter: V2AppleAudioConverter?
    private var hasTap = false
    private var active = false

    func start(format: AVAudioFormat) throws -> AsyncThrowingStream<AnalyzerInput, Error> {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true)
        #endif
        active = true
        do {
            let input = engine.inputNode
            let source = input.outputFormat(forBus: 0)
            let converter = try V2AppleAudioConverter(input: source, output: format)
            self.converter = converter
            let (stream, continuation) = AsyncThrowingStream<AnalyzerInput, Error>.makeStream(bufferingPolicy: .bufferingOldest(256))
            self.continuation = continuation
            input.installTap(onBus: 0, bufferSize: 2048, format: source) { @Sendable buffer, _ in
                do {
                    for converted in try converter.convert(buffer) {
                        if case .dropped = continuation.yield(AnalyzerInput(buffer: converted)) {
                            continuation.finish(throwing: V2SpeechAudioError.bufferOverflow)
                        }
                    }
                } catch { continuation.finish(throwing: error) }
            }
            hasTap = true
            engine.prepare()
            try engine.start()
            return stream
        } catch { stop(); throw error }
    }

    func stop() {
        if hasTap { engine.inputNode.removeTap(onBus: 0); hasTap = false }
        engine.stop()
        do {
            for buffer in try converter?.convert(nil) ?? [] {
                if case .dropped = continuation?.yield(AnalyzerInput(buffer: buffer)) {
                    continuation?.finish(throwing: V2SpeechAudioError.bufferOverflow)
                }
            }
        } catch { continuation?.finish(throwing: error) }
        converter = nil
        continuation?.finish(); continuation = nil
        if active {
            #if os(iOS)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            #endif
            active = false
        }
    }
}

/// The tap and stop/drain can run on different threads. Buffers returned here are owned copies.
final class V2AppleAudioConverter: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let output: AVAudioFormat
    private let lock = NSLock()
    private var ended = false
    private var pendingInput: AVAudioPCMBuffer?

    init(input: AVAudioFormat, output: AVAudioFormat) throws {
        guard input.sampleRate > 0, let converter = AVAudioConverter(from: input, to: output) else {
            throw V2SpeechAudioError.unsupportedFormat
        }
        self.converter = converter
        self.output = output
    }

    func convert(_ input: AVAudioPCMBuffer?) throws -> [AVAudioPCMBuffer] {
        lock.lock(); defer { lock.unlock() }
        guard !ended else { return [] }
        ended = input == nil
        pendingInput = input
        defer { pendingInput = nil }
        var buffers: [AVAudioPCMBuffer] = []
        let capacity = input.map { AVAudioFrameCount(ceil(Double($0.frameLength) * output.sampleRate / $0.format.sampleRate)) + 32 } ?? 4096
        while true {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: capacity) else { throw V2SpeechAudioError.conversion }
            var error: NSError?
            let status = converter.convert(to: buffer, error: &error) { [self] _, state in
                if ended { state.pointee = .endOfStream; return nil }
                guard let pendingInput else { state.pointee = .noDataNow; return nil }
                self.pendingInput = nil
                state.pointee = .haveData
                return pendingInput
            }
            guard status != .error, error == nil else { throw V2SpeechAudioError.conversion }
            if buffer.frameLength > 0 { buffers.append(buffer) }
            if status == .endOfStream || status == .inputRanDry || buffer.frameLength == 0 { break }
        }
        return buffers
    }
}

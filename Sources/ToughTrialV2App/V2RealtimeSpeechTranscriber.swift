import AVFoundation
import Combine
import Foundation
import ToughTrialV2Core

@MainActor
struct V2SpeechConnection {
    var send: (URLSessionWebSocketTask.Message) async throws -> Void
    var receive: () async throws -> URLSessionWebSocketTask.Message
    var close: () -> Void

    static func live(key: String) -> Self {
        var request = URLRequest(url: V2FunASR.endpoint)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let session = URLSession(configuration: .ephemeral)
        let socket = session.webSocketTask(with: request)
        socket.resume()
        return Self(send: { try await socket.send($0) }, receive: { try await socket.receive() }, close: {
            socket.cancel(with: .goingAway, reason: nil)
            session.invalidateAndCancel()
        })
    }
}

@MainActor
final class V2RealtimeSpeechTranscriber: ObservableObject {
    enum State { case idle, connecting, recording, finishing }
    @Published private(set) var state: State = .idle
    @Published private(set) var transcript = ""
    @Published private(set) var errorMessage: String?
    var isActive: Bool { state != .idle }

    private let permission: () async -> Bool
    private let open: (String) -> V2SpeechConnection
    private let startAudio: () throws -> AsyncThrowingStream<Data, Error>
    private let stopAudio: () -> Void
    private var connection: V2SpeechConnection?
    private var receiver: Task<Void, Never>?
    private var sender: Task<Void, Never>?
    private var finisher: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    private var token: UUID?
    private var didSendFinish = false
    private var reducer = V2FunASRTranscript(taskID: "")
    private var onComplete: ((String) -> Void)?

    convenience init() {
        let microphone = V2SpeechMicrophone()
        self.init(permission: {
            await V2MicrophonePermission.requestAccess()
        }, open: V2SpeechConnection.live, startAudio: { try microphone.start() }, stopAudio: { microphone.stop() })
    }

    init(permission: @escaping () async -> Bool,
         open: @escaping (String) -> V2SpeechConnection,
         startAudio: @escaping () throws -> AsyncThrowingStream<Data, Error>,
         stopAudio: @escaping () -> Void) {
        self.permission = permission
        self.open = open
        self.startAudio = startAudio
        self.stopAudio = stopAudio
    }

    func start(key: String) {
        guard !isActive else { return }
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            errorMessage = "请先配置阿里云语音输入。"
            return
        }
        let id = UUID()
        token = id
        didSendFinish = false
        reducer = V2FunASRTranscript(taskID: id.uuidString)
        transcript = ""
        errorMessage = nil
        state = .connecting
        receiver = Task { [weak self] in
            guard let self else { return }
            guard await permission(), token == id else {
                if token == id { fail("麦克风权限未开启，可以在系统设置中更改。", id: id) }
                return
            }
            do {
                let socket = open(key)
                connection = socket
                setDeadline(id: id, seconds: 20)
                try await socket.send(.string(V2FunASR.startMessage(taskID: id.uuidString)))
                while token == id {
                    let message = try await socket.receive()
                    guard token == id else { return }
                    let data: Data
                    switch message {
                    case let .data(value): data = value
                    case let .string(value): data = Data(value.utf8)
                    @unknown default: continue
                    }
                    let event = try JSONDecoder().decode(V2FunASREvent.self, from: data)
                    guard event.header.task_id == id.uuidString else { continue }
                    switch event.header.event {
                    case "task-started":
                        guard state == .connecting else { continue }
                        deadline?.cancel()
                        let stream = try startAudio()
                        state = .recording
                        sender = Task { [weak self] in
                            do {
                                for try await chunk in stream {
                                    guard self?.token == id, !Task.isCancelled else { return }
                                    try await socket.send(.data(chunk))
                                }
                            } catch {
                                self?.fail("音频传输中断，已保留文字，请检查后再发送。", id: id)
                            }
                        }
                    case "result-generated":
                        reducer.apply(event)
                        transcript = reducer.text
                    case "task-finished":
                        guard state == .finishing, didSendFinish, !reducer.hasUnfinishedText else {
                            fail("转写提前结束，已保留文字，请检查后再发送。", id: id)
                            return
                        }
                        let text = reducer.text.trimmingCharacters(in: .whitespacesAndNewlines)
                        let completion = onComplete
                        cancel()
                        if text.isEmpty { errorMessage = "没有识别到文字，可以重新录音。" }
                        else { completion?(text) }
                        return
                    case "task-failed":
                        fail("语音服务未完成转写，请检查密钥、额度和网络。已保留文字。", id: id)
                        return
                    default: continue
                    }
                }
            } catch {
                fail("实时语音连接中断，请检查网络和语音配置。已保留文字。", id: id)
            }
        }
    }

    func finish(onComplete: @escaping (String) -> Void) {
        guard state == .recording, let id = token, let socket = connection else { return }
        state = .finishing
        self.onComplete = onComplete
        stopAudio()
        setDeadline(id: id, seconds: 15)
        let pendingAudio = sender
        finisher = Task { [weak self] in
            await pendingAudio?.value
            guard let self, token == id else { return }
            didSendFinish = true
            do { try await socket.send(.string(V2FunASR.finishMessage(taskID: id.uuidString))) }
            catch { fail("语音收尾失败，已保留文字，请检查后再发送。", id: id) }
        }
    }

    /// Cancellation preserves the visible draft and invalidates every late callback.
    func cancel() {
        token = nil
        onComplete = nil
        stopAudio()
        receiver?.cancel()
        sender?.cancel()
        finisher?.cancel()
        deadline?.cancel()
        connection?.close()
        connection = nil
        receiver = nil
        sender = nil
        finisher = nil
        deadline = nil
        state = .idle
    }

    func dismissError() { errorMessage = nil }

    private func fail(_ message: String, id: UUID) {
        guard token == id else { return }
        cancel()
        errorMessage = message
    }

    private func setDeadline(id: UUID, seconds: Int) {
        deadline?.cancel()
        deadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) }
            catch { return }
            self?.fail("语音服务响应超时，已保留文字，请检查后再发送。", id: id)
        }
    }
}

@MainActor
final class V2SpeechMicrophone {
    private let engine = AVAudioEngine()
    private var continuation: AsyncThrowingStream<Data, Error>.Continuation?
    private var hasTap = false
    private var active = false
    private var converter: V2SpeechPCMConverter?

    func start() throws -> AsyncThrowingStream<Data, Error> {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true)
        #endif
        active = true
        do {
            let input = engine.inputNode
            let converter = try V2SpeechPCMConverter(input: input.outputFormat(forBus: 0))
            self.converter = converter
            let (stream, continuation) = AsyncThrowingStream<Data, Error>.makeStream(bufferingPolicy: .bufferingOldest(256))
            self.continuation = continuation
            input.installTap(onBus: 0, bufferSize: 2048, format: input.outputFormat(forBus: 0)) { @Sendable buffer, _ in
                do {
                    let data = try converter.convert(buffer)
                    if case .dropped = continuation.yield(data) {
                        continuation.finish(throwing: V2SpeechAudioError.bufferOverflow)
                    }
                } catch { continuation.finish(throwing: error) }
            }
            hasTap = true
            engine.prepare()
            try engine.start()
            return stream
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        if hasTap { engine.inputNode.removeTap(onBus: 0); hasTap = false }
        engine.stop()
        do {
            if let tail = try converter?.finish(), !tail.isEmpty,
               case .dropped = continuation?.yield(tail) {
                continuation?.finish(throwing: V2SpeechAudioError.bufferOverflow)
            }
        } catch { continuation?.finish(throwing: error) }
        converter = nil
        continuation?.finish()
        continuation = nil
        if active {
            #if os(iOS)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            #endif
            active = false
        }
    }
}

enum V2SpeechAudioError: Error { case unsupportedFormat, conversion, bufferOverflow }

/// Serializes audio-tap conversion with the final drain after the engine has stopped.
final class V2SpeechPCMConverter: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let lock = NSLock()
    private var ended = false
    private let output: AVAudioFormat

    init(input: AVAudioFormat) throws {
        guard input.sampleRate > 0, input.channelCount > 0,
              let output = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: input, to: output) else { throw V2SpeechAudioError.unsupportedFormat }
        self.output = output
        self.converter = converter
    }

    func convert(_ input: AVAudioPCMBuffer) throws -> Data {
        lock.lock()
        defer { lock.unlock() }
        guard !ended else { return Data() }
        let frames = AVAudioFrameCount(ceil(Double(input.frameLength) * 16000 / input.format.sampleRate)) + 32
        guard let buffer = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: frames) else { throw V2SpeechAudioError.conversion }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: buffer, error: &error) { _, state in
            guard !supplied else { state.pointee = .noDataNow; return nil }
            supplied = true
            state.pointee = .haveData
            return input
        }
        guard status != .error, error == nil, let samples = buffer.int16ChannelData?[0] else { throw V2SpeechAudioError.conversion }
        return Data(bytes: samples, count: Int(buffer.frameLength) * 2)
    }
    func finish() throws -> Data {
        lock.lock()
        defer { lock.unlock() }
        guard !ended else { return Data() }
        ended = true
        var result = Data()
        // endOfStream releases samples retained by the resampling filter.
        while true {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: 4096) else {
                throw V2SpeechAudioError.conversion
            }
            var error: NSError?
            let status = converter.convert(to: buffer, error: &error) { _, state in
                state.pointee = .endOfStream
                return nil
            }
            guard status != .error, error == nil, let samples = buffer.int16ChannelData?[0] else {
                throw V2SpeechAudioError.conversion
            }
            result.append(Data(bytes: samples, count: Int(buffer.frameLength) * 2))
            if status == .endOfStream || buffer.frameLength == 0 { return result }
        }
    }

}

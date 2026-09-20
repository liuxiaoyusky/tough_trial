import AVFoundation
import Combine
import ToughTrialV2Core

@MainActor
final class V2RecordedSpeechTranscriber: ObservableObject {
    @Published private(set) var state: V2RealtimeSpeechTranscriber.State = .idle
    @Published private(set) var transcript = ""
    @Published private(set) var errorMessage: String?
    @Published private(set) var canRetry = false
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var reachedLimit = false
    var onRecordingCaptured: ((Data) throws -> Void)?

    private let permission: () async -> Bool
    private let startAudio: () throws -> AsyncThrowingStream<Data, Error>
    private let stopAudio: () -> Void
    private let transcribe: (Data, String) async throws -> String
    private let maximumBytes: Int
    private var pcm = Data()
    private var key = ""
    private var capturedRecording = false
    private var token: UUID?
    private var capture: Task<Void, Never>?
    private var upload: Task<Void, Never>?

    convenience init() {
        let microphone = V2SpeechMicrophone()
        self.init(permission: {
            await V2MicrophonePermission.requestAccess()
        }, startAudio: { try microphone.start() }, stopAudio: { microphone.stop() },
           transcribe: { try await V2RecordedSpeechClient.transcribe(pcm: $0, key: $1) })
    }

    init(permission: @escaping () async -> Bool,
         startAudio: @escaping () throws -> AsyncThrowingStream<Data, Error>,
         stopAudio: @escaping () -> Void,
         transcribe: @escaping (Data, String) async throws -> String,
         maximumBytes: Int = V2RecordedSpeechClient.maximumPCMBytes) {
        self.permission = permission; self.startAudio = startAudio
        self.stopAudio = stopAudio; self.transcribe = transcribe; self.maximumBytes = maximumBytes
    }

    func start(key: String) {
        guard state == .idle, !canRetry else { return }
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "请先配置百炼语音密钥。"; return
        }
        let id = UUID()
        token = id; self.key = key; pcm = Data(); capturedRecording = false; transcript = ""
        duration = 0; reachedLimit = false; errorMessage = nil
        state = .connecting
        capture = Task { [weak self] in
            guard let self else { return }
            guard await permission(), token == id else {
                if token == id { cancel(); errorMessage = "麦克风权限未开启，可以在系统设置中更改。" }
                return
            }
            do {
                let stream = try startAudio()
                state = .recording
                for try await chunk in stream {
                    guard token == id, !Task.isCancelled else { return }
                    pcm.append(chunk.prefix(maximumBytes - pcm.count))
                    duration = Double(pcm.count) / 32_000
                    if pcm.count >= maximumBytes {
                        reachedLimit = true
                        stopAudio()
                        break
                    }
                }
            } catch {
                guard token == id else { return }
                cancel()
                errorMessage = "录音中断，请重新录音。"
            }
        }
    }

    func finish(key updatedKey: String? = nil, onComplete: @escaping (String) -> Void) {
        guard state == .recording || canRetry, let id = token else { return }
        if let updatedKey { key = updatedKey }
        state = .finishing; canRetry = false; errorMessage = nil
        stopAudio()
        let pending = capture
        upload = Task { [weak self] in
            await pending?.value
            guard let self, token == id, !Task.isCancelled else { return }
            guard !pcm.isEmpty else { cancel(); errorMessage = "没有录到声音，请重新录音。"; return }

            if !capturedRecording, let onRecordingCaptured {
                do {
                    let wav = try V2RecordedSpeechClient.wavData(pcm: pcm)
                    try onRecordingCaptured(wav)
                    capturedRecording = true
                } catch {
                    state = .idle
                    canRetry = true
                    errorMessage = "原始录音保存失败，录音暂存在当前页面，可重试或放弃。"
                    return
                }
            }

            do {
                let text = try await transcribe(pcm, key)
                guard token == id, !Task.isCancelled else { return }
                cancel()
                transcript = text
                onComplete(text)
            } catch {
                guard token == id, !Task.isCancelled else { return }
                state = .idle; canRetry = true
                let detail = (error as? V2RecordedSpeechClient.Failure)?.localizedDescription ?? "转写未完成，请检查网络后重试。"
                errorMessage = detail + "录音暂存在当前页面，可重试或放弃。"
            }
        }
    }

    func cancel() {
        token = nil
        capture?.cancel(); upload?.cancel()
        stopAudio()
        capture = nil; upload = nil
        pcm = Data(); capturedRecording = false; key = ""; canRetry = false; state = .idle
    }

    func dismissError() { errorMessage = nil }
}

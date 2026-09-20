import Combine
import Foundation
import ToughTrialV2Core

/// Select once per recording so a settings change cannot reroute an active microphone.
@MainActor
final class V2AssistantSpeechTranscriber: ObservableObject {
    private let cloud: V2RecordedSpeechTranscriber
    private let apple: V2AppleSpeechTranscriber
    @Published private(set) var provider: V2SpeechProvider = .funASR
    private var moduleTicket: V2ModuleTicket?
    private var recordingHandler: ((Data) throws -> Void)?
    private var observations: Set<AnyCancellable> = []

    init(cloud: V2RecordedSpeechTranscriber = V2RecordedSpeechTranscriber(),
         apple: V2AppleSpeechTranscriber = V2AppleSpeechTranscriber()) {
        self.cloud = cloud
        self.apple = apple
        NotificationCenter.default.publisher(for: .v2ModulesChanged).sink { [weak self] _ in
            guard let self, let ticket = self.moduleTicket else { return }
            if (try? V2PluginStore.shared.validate(ticket)) == nil { self.cancel() }
        }.store(in: &observations)
        cloud.onRecordingCaptured = { [weak self] data in
            guard let self, let ticket = self.moduleTicket else { throw CancellationError() }
            try V2PluginStore.shared.validate(ticket)
            try self.recordingHandler?(data)
        }
        cloud.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &observations)
        apple.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &observations)
    }

    var state: V2RealtimeSpeechTranscriber.State { provider == .apple ? apple.state : cloud.state }
    var transcript: String { provider == .apple ? apple.transcript : cloud.transcript }
    var errorMessage: String? { provider == .apple ? apple.errorMessage : cloud.errorMessage }
    var canRetry: Bool { provider == .funASR && cloud.canRetry }
    var isActive: Bool { state != .idle || canRetry }
    var onRecordingCaptured: ((Data) throws -> Void)? {
        get { recordingHandler }
        set { recordingHandler = newValue }
    }
    var status: String {
        if canRetry { return "录音已保留 · 可以重试或放弃" }
        switch state {
        case .idle: return ""
        case .connecting: return provider == .apple ? apple.preparationStatus : "正在准备录音…"
        case .recording:
            if provider == .apple { return "苹果原生 · 点完成后交给助手" }
            if cloud.reachedLimit { return "已录满 5 分钟 · 点完成转写" }
            let seconds = Int(cloud.duration)
            return String(format: "正在录音 %02d:%02d / 05:00 · 完成后转写", seconds / 60, seconds % 60)
        case .finishing: return provider == .apple ? "正在接收最后一句…" : "正在转写整段录音…"
        }
    }

    func start(provider: V2SpeechProvider, key: String = "", ownerModuleID: String = "core.assistant") {
        guard V2PluginStore.shared.enabled("speech") else { return }
        guard !isActive else { return }
        guard let ticket = try? V2PluginStore.shared.ticket(["speech", ownerModuleID]) else { return }
        moduleTicket = ticket
        self.provider = provider
        if provider == .apple { apple.start() } else { cloud.start(key: key) }
    }
    func finish(onComplete: @escaping (String) -> Void) {
        guard let ticket = moduleTicket, (try? V2PluginStore.shared.validate(ticket)) != nil else { cancel(); return }
        let complete: (String) -> Void = { text in
            guard (try? V2PluginStore.shared.validate(ticket)) != nil else { return }
            onComplete(text)
        }
        if provider == .apple { apple.finish(onComplete: complete) }
        else { cloud.finish(key: try? V2SpeechSettings.loadKey(), onComplete: complete) }
    }
    func cancel() { moduleTicket = nil; cloud.cancel(); apple.cancel() }
    func dismissError() { cloud.dismissError(); apple.dismissError() }
}

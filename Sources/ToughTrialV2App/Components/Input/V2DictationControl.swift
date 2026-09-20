import Combine
import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// A small, field-local voice input control.
///
/// The control only changes the supplied draft. It does not create a task,
/// save a capture, or submit anything to an assistant. Each instance owns its
/// own speech orchestrator and draft baseline so multiple fields cannot share
/// callbacks or transcript text.
struct V2DictationControl: View {
    @Binding private var text: String
    @Binding private var isActive: Bool
    private let ownerModuleID: String
    private let identifierPrefix: String
    private let selection: Binding<NSRange>?

    @StateObject private var model: V2DictationControlModel
    @AppStorage(V2SpeechSettings.providerKey) private var speechProvider = V2SpeechProvider.funASR
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingSpeechSettings = false

    init(
        text: Binding<String>,
        isActive: Binding<Bool>,
        selection: Binding<NSRange>? = nil,
        ownerModuleID: String,
        identifierPrefix: String
    ) {
        _text = text
        _isActive = isActive
        self.selection = selection
        self.ownerModuleID = ownerModuleID
        self.identifierPrefix = identifierPrefix
        _model = StateObject(wrappedValue: V2DictationControlModel(ownerModuleID: ownerModuleID))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if model.isActive {
                    Button("取消听写", role: .cancel) {
                        model.cancel()
                    }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier(identifier("cancel"))

                    Button(model.canRetry ? "重试转写" : "完成听写") {
                        model.finish()
                    }
                    .disabled(model.state == .connecting || model.state == .finishing)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier(identifier("finish"))
                } else {
                    Button {
                        V2Platform.endEditing()
                        model.start(preRecordingText: text, provider: speechProvider, selection: selection?.wrappedValue)
                    } label: {
                        Label("语音输入", systemImage: "mic")
                    }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier(identifier("start"))
                }

                Spacer(minLength: 0)
                Button {
                    showingSpeechSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .disabled(model.isActive)
                .accessibilityLabel("语音设置")
                .accessibilityIdentifier(identifier("settings"))
            }
            .buttonStyle(.borderless)

            if !model.status.isEmpty {
                Text(model.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(identifier("status"))
            }
            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier(identifier("error"))
            }
        }
        .onAppear {
            model.adoptIdleText(text)
            isActive = model.isActive
        }
        .onChange(of: model.pendingText) { _, value in
            guard let value else { return }
            if text != value { text = value }
        }
        .onChange(of: model.pendingSelection) { _, value in
            if let value, selection?.wrappedValue != value { selection?.wrappedValue = value }
        }
        .onChange(of: text) { _, value in
            model.adoptIdleText(value)
        }
        .onChange(of: model.isActive) { _, value in
            if isActive != value { isActive = value }
        }
        .onChange(of: scenePhase) { _, phase in
            // System permission prompts temporarily make the scene inactive.
            // Keep that request alive so its grant/denial reaches the draft.
            guard phase == .background else { return }
            model.cancel()
        }
        .onDisappear {
            model.cancel()
            isActive = false
        }
        .v2Sheet(isPresented: $showingSpeechSettings) {
            NavigationStack {
                V2SpeechSettingsView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("关闭") { showingSpeechSettings = false }
                        }
                    }
            }
        }
    }

    private func identifier(_ suffix: String) -> String {
        identifierPrefix.isEmpty ? suffix : "\(identifierPrefix).\(suffix)"
    }
}

/// The lifecycle bridge behind `V2DictationControl`.
///
/// It is intentionally independent from SwiftUI bindings so the speech
/// lifecycle can be tested with the existing injected cloud and Apple speech
/// transcribers. Speech-originated changes are exposed through `pendingText`;
/// idle changes from the parent binding only update the local baseline.
@MainActor
final class V2DictationControlModel: ObservableObject {
    let speech: V2AssistantSpeechTranscriber

    private(set) var renderedText = ""
    /// A value the control should write to its parent binding. Idle parent
    /// edits never populate this, which prevents an asynchronous model echo
    /// from overwriting a newer TextField value.
    @Published private(set) var pendingText: String?
    @Published private(set) var pendingSelection: NSRange?
    @Published private(set) var isActive = false
    @Published private(set) var state: V2RealtimeSpeechTranscriber.State = .idle
    @Published private(set) var transcript = ""
    @Published private(set) var status = ""
    @Published private(set) var errorMessage: String?
    @Published private(set) var canRetry = false

    private let ownerModuleID: String
    private var preRecordingText = ""
    private var dictationSeparator = ""
    private var insertionRange: NSRange?
    private var hasSession = false
    private var localError: String?
    private var refreshTask: Task<Void, Never>?
    private var speechObservation: AnyCancellable?

    init(ownerModuleID: String, speech: V2AssistantSpeechTranscriber = V2AssistantSpeechTranscriber()) {
        self.ownerModuleID = ownerModuleID
        self.speech = speech
        speechObservation = speech.objectWillChange.sink { [weak self] _ in
            self?.scheduleRefresh()
        }
    }

    /// Adopt the view's current draft when the control appears without
    /// changing an active session's baseline.
    func adoptIdleText(_ text: String) {
        guard !hasSession, !speech.isActive else { return }
        renderedText = text
        pendingText = nil
        pendingSelection = nil
    }

    func start(preRecordingText: String, provider: V2SpeechProvider, selection: NSRange? = nil) {
        guard !hasSession, !speech.isActive else { return }

        if let reason = unavailableReason {
            renderedText = preRecordingText
            localError = reason
            refreshFromSpeech()
            return
        }

        self.preRecordingText = preRecordingText
        if let selection {
            let length = (preRecordingText as NSString).length
            let start = min(selection.location, length)
            insertionRange = NSRange(location: start, length: min(selection.length, length - start))
        } else { insertionRange = nil }
        dictationSeparator = Self.separator(after: preRecordingText)
        renderedText = preRecordingText
        transcript = ""
        localError = nil
        errorMessage = nil
        hasSession = true

        let key = provider == .funASR ? ((try? V2SpeechSettings.loadKey()) ?? "") : ""
        speech.start(provider: provider, key: key, ownerModuleID: ownerModuleID)
        refreshFromSpeech()

        // The orchestrator owns the authoritative gate. This fallback keeps
        // an unavailable module from leaving the parent save button disabled
        // when the gate changes between the check above and start().
        if !speech.isActive {
            hasSession = false
            if speech.errorMessage == nil && localError == nil {
                localError = unavailableReason ?? "语音输入暂不可用。"
            }
            refreshFromSpeech()
        }
    }

    func finish() {
        guard hasSession, speech.isActive else { return }
        speech.finish { [weak self] text in
            self?.accept(text)
        }
        refreshFromSpeech()
    }

    /// Cancel removes the temporary dictation segment and restores exactly
    /// the text that was present when recording started. The surrounding field
    /// remains untouched and can be edited or dictated again immediately.
    func cancel() {
        let hadSession = hasSession || speech.isActive
        let restoredText = hadSession ? preRecordingText : renderedText
        speech.cancel()
        speech.dismissError()
        refreshTask?.cancel()
        hasSession = false
        localError = nil
        preRecordingText = ""
        dictationSeparator = ""
        transcript = ""
        renderedText = restoredText
        if hadSession { pendingText = restoredText; pendingSelection = insertionRange }
        insertionRange = nil
        refreshFromSpeech()
    }

    private func accept(_ text: String) {
        guard hasSession else { return }
        transcript = text
        renderedText = composedText(for: text)
        pendingText = renderedText
        pendingSelection = resultSelection(for: text)
        insertionRange = nil
        preRecordingText = ""
        dictationSeparator = ""
        hasSession = false
        localError = nil
        refreshFromSpeech()
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled else { return }
            self?.refreshFromSpeech()
        }
    }

    private func refreshFromSpeech() {
        if hasSession {
            transcript = speech.transcript
            let nextText = composedText(for: speech.transcript)
            renderedText = nextText
            pendingText = nextText
            pendingSelection = resultSelection(for: speech.transcript)
        }

        state = speech.state
        status = speech.provider == .apple && speech.state == .recording
            ? "苹果原生 · 完成后回填当前输入" : speech.status
        canRetry = speech.canRetry
        isActive = speech.isActive
        errorMessage = speech.errorMessage ?? localError

        guard hasSession else { return }
        if !speech.isActive && !speech.canRetry {
            // A permission, provider, module, or backend failure leaves any
            // recognized text in place so the user can edit and retry later.
            // A successful finish calls accept() before this deferred refresh.
            hasSession = false
        }
    }

    private var unavailableReason: String? {
        guard V2PluginStore.shared.enabled("speech") else {
            return V2PluginStore.shared.reason("speech") ?? "语音输入暂不可用。"
        }
        guard V2PluginStore.shared.enabled(ownerModuleID) else {
            return V2PluginStore.shared.reason(ownerModuleID) ?? "当前页面暂不可使用语音输入。"
        }
        return nil
    }

    private func composedText(for transcript: String) -> String {
        guard !transcript.isEmpty else { return preRecordingText }
        if let insertionRange {
            return (preRecordingText as NSString).replacingCharacters(in: insertionRange, with: transcript)
        }
        return preRecordingText + dictationSeparator + transcript
    }

    private func resultSelection(for transcript: String) -> NSRange? {
        guard let insertionRange else { return nil }
        if transcript.isEmpty { return insertionRange }
        return NSRange(location: insertionRange.location + (transcript as NSString).length, length: 0)
    }

    private static func separator(after text: String) -> String {
        guard !text.isEmpty, text.last?.isWhitespace == false else { return "" }
        return "\n"
    }
}

import SwiftUI
import ToughTrialV2Core
#if os(iOS)
import UIKit
#else
import AppKit
#endif
import AVFoundation

struct V2AssistantView: View {
    @ObservedObject var store: V2AssistantStore
    @ObservedObject var appStore: V2AppStore
    let onExit: () -> Void
    var embedded = false
    var onOpenSource: (String) -> Void = { _ in }

    @StateObject private var speech = V2AssistantSpeechTranscriber()
    @AppStorage(V2SpeechSettings.providerKey) private var speechProvider = V2SpeechProvider.funASR
    @Environment(\.scenePhase) private var scenePhase
    @State private var speechPrefix = ""
    @State private var isSpeechDraft = false
    @State private var showSpeechSettings = false
    @State private var showUsageTrace = false
    @State private var showScheduleSettings = false
    @State private var showScheduleFiles = false
    @State private var showGitHubSync = false
    @State private var speechStartedAt: Date?
    @State private var speechDraftOriginal: String?
    @State private var speechConfigurationError: String?
    @State private var promptText = ""
    @State private var draftID = UUID().uuidString
    @State private var draftSessionID: String?
    @State private var references: [V2AssistantMessageReference] = []
    @State private var isComposerExpanded = false
    @State private var quotedMessageID: String?
    @State private var attachments: [V2AssistantAttachment] = []
    @State private var showAttachmentPicker = false
    @State private var isAttaching = false
    @State private var previewAttachment: V2AssistantAttachment?
    @State private var scrollPositions: [String: String] = [:]
    @State private var showSessions = false
    @State private var showSettings = false
    @State private var showModelSelection = false
    @State private var showDetails = false
    @State private var showContext = false
    @State private var editingPlanItem: V2AssistantPlanItemEditorContext?
    @State private var editingTask: V2AssistantTaskEditorContext?
    @State private var fullscreenBrowser: V2AssistantBrowserPresentation?
    @StateObject private var browserRegistry = V2AssistantBrowserRegistry()
    @FocusState private var isComposerFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            HStack {
                Button { showContext = true } label: {
                    Label("记忆与上下文", systemImage: "books.vertical")
                        .font(V2Theme.TypeRole.labelSmall)
                }
                .accessibilityIdentifier("assistant.context")
                Spacer()
                if store.contextIssueMessage != nil {
                    Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                }
            }
            .foregroundStyle(V2Theme.secondary)
            .padding(.horizontal, 22).padding(.bottom, 8)
            GeometryReader { proxy in
                content(availableHeight: proxy.size.height)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if store.providerStatus.isConfigured {
                VStack(spacing: 0) {
                    draftAccessories
                    Button { showModelSelection = true } label: {
                        HStack(spacing: 5) {
                            Text(modelSelectionLabel).lineLimit(1)
                            Image(systemName: "chevron.down").font(.system(size: 9))
                            Spacer()
                        }.font(.caption).foregroundStyle(V2Theme.secondary).padding(.horizontal, 22).padding(.top, 6)
                    }.accessibilityIdentifier("assistant.model.selection")
                    V2AssistantComposer(
                    text: $promptText,
                    isFocused: $isComposerFocused,
                    isBusy: store.isRunningTurn,
                    speechState: speech.state,
                    speechStatus: speech.status,
                    speechProvider: $speechProvider,
                    canRetrySpeech: speech.canRetry,
                    onSpeechSettings: { showSpeechSettings = true },
                    onMic: startSpeech,
                    onFinishSpeech: finishSpeech,
                    onCancelSpeech: cancelSpeech,
                    onSend: sendPrompt,
                    onCancel: store.cancelCurrentTurn,
                    isExpanded: $isComposerExpanded,
                    onAttach: { showAttachmentPicker = true }
                    )
                }
            }
        }
        .v2Sheet(isPresented: $showAttachmentPicker) {
            NavigationStack {
                V2FileAttachmentPicker(maximumFileCount: max(1, 4 - attachments.count), ownerModuleID: "core.assistant") { files in
                    showAttachmentPicker = false
                    let targetID = draftSessionID
                    isAttaching = true
                    Task {
                        defer { isAttaching = false }
                        do {
                            for file in files.prefix(max(0, 4 - attachments.count)) {
                                let attachment = try await V2AssistantAttachments.save(file, appStore: appStore)
                                if draftSessionID == targetID {
                                    attachments.append(attachment)
                                    if promptText.isEmpty { promptText = "请阅读这些附件" }
                                }
                                else if let targetID {
                                    var draft = store.workspace.session(id: targetID)?.composerDraft ?? .init()
                                    draft.attachments = (draft.attachments ?? []) + [attachment]
                                    store.saveDraft(draft, in: targetID)
                                }
                            }
                        } catch { store.operationErrorMessage = error.localizedDescription }
                    }
                }.padding().navigationTitle("附件")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showAttachmentPicker = false } } }
            }
        }
        .v2Sheet(item: $previewAttachment) { attachment in
            NavigationStack { V2AssistantAttachmentPreview(attachment: attachment, appStore: appStore)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { previewAttachment = nil } } } }
        }
        .task(id: currentDraft) {
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            persistDraft()
        }
        .v2Sheet(isPresented: $showGitHubSync) {
            NavigationStack { V2ScheduleGitHubView(store: appStore) }
        }
        .v2Sheet(isPresented: $showContext) {
            NavigationStack { V2AssistantContextView(store: store, appStore: appStore) }
        }
        .v2Sheet(isPresented: $showScheduleFiles) {
            NavigationStack { V2ScheduleFilesView(store: appStore) }
        }
        .v2Sheet(isPresented: $showScheduleSettings) {
            NavigationStack { V2ScheduleSettingsView() }
        }
        .v2Sheet(isPresented: $showUsageTrace) {
            NavigationStack { V2UsageTraceView() }
        }
        .v2Sheet(isPresented: $showSpeechSettings) {
            NavigationStack {
                V2SpeechSettingsView()
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { showSpeechSettings = false } } }
            }
        }
        .alert("语音输入", isPresented: Binding(
            get: { speech.errorMessage != nil || speechConfigurationError != nil },
            set: { if !$0 { speech.dismissError(); speechConfigurationError = nil } }
        )) {
            Button("知道了") { speech.dismissError(); speechConfigurationError = nil }
            Button("语音设置") { speech.dismissError(); speechConfigurationError = nil; showSpeechSettings = true }
        } message: {
            Text(speech.errorMessage ?? speechConfigurationError ?? "语音输入暂不可用。")
        }
        .onChange(of: speech.errorMessage) { _, message in
            if message != nil, let started = speechStartedAt {
                V2UsageTrace.shared.record(.init(kind: .speechFailed, source: speechTraceSource,
                    sessionID: store.selectedSession?.id, duration: Date().timeIntervalSince(started)))
                speechStartedAt = nil
            }
        }
        .onChange(of: speech.transcript) { _, text in
            guard isSpeechDraft else { return }
            promptText = combinedSpeech(text)
        }
        .onChange(of: store.selectedSession?.id) { oldID, _ in
            if let oldID, oldID == draftSessionID { store.saveDraft(currentDraft, in: oldID) }
            isSpeechDraft = false
            speech.cancel()
            speechPrefix = ""
            restoreDraft()
            speechStartedAt = nil
            speechDraftOriginal = nil
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { cancelSpeech(); persistDraft() }
        }
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in
            cancelSpeech()
        }
        #endif
        .onDisappear { cancelSpeech(); persistDraft(); store.flushVisibleDraft = nil }
        .v2Sheet(isPresented: $showSessions) {
            V2AssistantSessionListView(store: store)
        }
        .v2Sheet(isPresented: $showModelSelection) {
            V2AssistantModelSelectionView(store: store, appStore: appStore)
        }
        .v2Sheet(isPresented: $showSettings) {
            V2AIProviderSettingsView(store: appStore)
        }
        .v2Sheet(isPresented: $showDetails) {
            if let session = store.selectedSession {
                V2AssistantSessionDetailView(session: session)
            }
        }
        .v2Sheet(item: $editingTask) { context in
            V2AssistantTaskEditor(task: context.task, isSaved: store.receipt(for: context.card) != nil, store: store) { title, note, day, instruction in
                if let index = context.task.operationIndex {
                    return store.editPendingTask(context.card, operationIndex: index, title: title, note: note, day: day)
                }
                store.adjustSavedTask(context.task, card: context.card, instruction: instruction)
                return true
            }
        }
        .v2Sheet(item: $editingPlanItem) { context in
            V2PlanScheduleItemEditor(item: context.item) { updatedItem in
                _ = store.updatePlanItem(updatedItem, in: context.planID)
            }
        }
        .v2FullScreenCover(item: $fullscreenBrowser) { presentation in
            V2AssistantBrowserFullscreenView(
                store: store,
                registry: browserRegistry,
                sessionID: presentation.sessionID,
                browserID: presentation.browserID,
                source: presentation.source,
                onMinimize: { fullscreenBrowser = nil },
                onDisappear: { finishFullscreenBrowserPresentation(presentation) }
            )
        }
        .v2ScreenBackground()
        .interactiveDismissDisabled()
        .onAppear {
            restoreDraft()
            store.flushVisibleDraft = {
                persistDraft()
                return store.storageState == .healthy
            }
            browserRegistry.prune(keeping: persistedBrowserKeys)
        }
        .onChange(of: persistedBrowserKeyIDs) { _, _ in
            browserRegistry.prune(keeping: persistedBrowserKeys)
        }
        #if os(iOS)
        .onReceive(
            NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
        ) { _ in
            browserRegistry.prune(keeping: activeBrowserKeys)
        }
        #endif
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                Text("助手")
                    .font(V2Theme.TypeRole.displayMedium)
                    .foregroundStyle(V2Theme.ink)
                Text(assistantHeaderTitle == "助手" ? "新会话" : assistantHeaderTitle)
                    .font(V2Theme.TypeRole.labelSmall)
                    .foregroundStyle(V2Theme.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            V2AssistantHeaderButton(systemName: "text.bubble", action: { showSessions = true })
                .accessibilityLabel("会话列表")
                .accessibilityIdentifier("assistant.sessions")
                .disabled(speech.isActive)

            V2AssistantHeaderButton(systemName: "plus") {
                store.createSession()
            }
            .accessibilityLabel("新建会话")
            .accessibilityIdentifier("assistant.newSession")
            .disabled(speech.isActive)

            Menu {
                Button {
                    presentMenuSheet { showDetails = true }
                } label: {
                    Label("会话详情", systemImage: "info.circle")
                }
                .accessibilityIdentifier("assistant.details")

                Button {
                    presentMenuSheet { showSettings = true }
                } label: {
                    Label("AI 服务", systemImage: "slider.horizontal.3")
                }
                .accessibilityIdentifier("assistant.settings")

                Button {
                    presentMenuSheet { showUsageTrace = true }
                } label: {
                    Label("使用记录", systemImage: "clock.arrow.circlepath")
                }
                .accessibilityIdentifier("assistant.trace")
                Button {
                    presentMenuSheet { showScheduleSettings = true }
                } label: {
                    Label("日程修改", systemImage: "checklist")
                }
                .accessibilityIdentifier("assistant.schedule.settings")
                Button {
                    presentMenuSheet { showScheduleFiles = true }
                } label: {
                    Label("日程文件", systemImage: "doc.text")
                }
                .accessibilityIdentifier("assistant.schedule.files")
                Button {
                    presentMenuSheet { showGitHubSync = true }
                } label: {
                    Label("GitHub 同步", systemImage: "arrow.triangle.2.circlepath")
                }
                .accessibilityIdentifier("assistant.schedule.github")
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(V2Theme.secondary)
                    .frame(width: 42, height: 42)
                    .background(V2Theme.ColorRole.surfaceRaised, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(V2Theme.line.opacity(0.5)))
            }
            .accessibilityLabel("更多操作")
            .accessibilityIdentifier("assistant.more")
            .disabled(speech.isActive)

            if !embedded {
                V2AssistantHeaderButton(systemName: "xmark", action: onExit)
                    .accessibilityLabel("退出助手")
                    .accessibilityIdentifier("assistant.exit")
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .background(V2Theme.page)
    }

    @ViewBuilder
    private func content(availableHeight: CGFloat) -> some View {
        if !store.providerStatus.isConfigured {
            VStack {
                V2AssistantConfigurationPrompt(message: store.providerStatus.message) { showSettings = true }
                Button("选择已配置的模型") { showModelSelection = true }
                    .accessibilityIdentifier("assistant.model.selection").padding()
            }
        } else if let session = store.selectedSession {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if let sourceTask = session.sourceTask {
                            Button { onOpenSource(sourceTask.id) } label: {
                                V2AssistantTaskContextRow(sourceTask: sourceTask)
                            }.buttonStyle(.plain).accessibilityIdentifier("assistant.context.openTask")
                        }

                        if session.messages.isEmpty {
                            V2AssistantStarterView(onStart: sendStarter)
                                .padding(.top, 10)
                        } else {
                            ForEach(session.messages) { message in
                                V2AssistantMessageView(
                                    message: message,
                                    session: session,
                                    store: store,
                                    browserRegistry: browserRegistry,
                                    availableHeight: availableHeight,
                                    onPresentFullscreen: presentFullscreenBrowser,
                                    onQuote: { message, excerpt in
                                        let ref = V2AssistantMessageReference(sessionID: session.id, messageID: message.id, excerpt: excerpt)
                                        references.removeAll { $0.id == ref.id }
                                        references = Array((references + [ref]).suffix(4))
                                        isComposerFocused = true
                                    },
                                    onJumpToReference: { quotedMessageID = $0.messageID },
                                    onOpenAttachment: { previewAttachment = $0 },
                                    onEditPlanItem: { planID, item in
                                        editingPlanItem = V2AssistantPlanItemEditorContext(
                                            planID: planID,
                                            item: item
                                        )
                                    },
                                    onEditTask: { card, task in
                                        isComposerFocused = false
                                        editingTask = V2AssistantTaskEditorContext(card: card, task: task)
                                    }
                                )
                                .id(message.id)
                            }
                        }

                        if let issue = store.storageIssueMessage {
                            V2AssistantStorageIssueView(
                                message: issue,
                                canRetry: store.storageState == .transientWriteFailure,
                                onRetry: { _ = store.retryStorage() }
                            )
                        }
                    }
                    .scrollTargetLayout()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
                .scrollPosition(id: Binding(get: { scrollPositions[session.id] }, set: { scrollPositions[session.id] = $0 }))
                .scrollDismissesKeyboard(.interactively)
                .accessibilityIdentifier("assistant.conversation")
                .onChange(of: quotedMessageID) { _, id in
                    if let id { withAnimation { proxy.scrollTo(id, anchor: .center) } }
                    quotedMessageID = nil
                }
                .onChange(of: session.messages) { _, messages in
                    guard let last = messages.last else { return }
                    withAnimation(.snappy(duration: 0.24)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
                .task(id: session.id) {
                    let restored = scrollPositions[session.id]
                    guard let target = restored ?? session.messages.last?.id else { return }
                    await Task.yield()
                    proxy.scrollTo(target, anchor: restored == nil ? .bottom : .top)
                }
            }
            .id(session.id)
        }
    }

    private func presentFullscreenBrowser(_ presentation: V2AssistantBrowserPresentation) {
        guard fullscreenBrowser == nil || fullscreenBrowser?.id == presentation.id,
              browserRegistry.claimFullscreen(presentation.key) else {
            return
        }

        guard store.updateBrowserPresentation(
            browserID: presentation.browserID,
            sessionID: presentation.sessionID,
            isExpanded: true,
            isFullscreen: true
        ) else {
            browserRegistry.releaseFullscreen(presentation.key)
            return
        }
        fullscreenBrowser = presentation
    }

    private func finishFullscreenBrowserPresentation(_ presentation: V2AssistantBrowserPresentation) {
        _ = store.updateBrowserPresentation(
            browserID: presentation.browserID,
            sessionID: presentation.sessionID,
            isFullscreen: false
        )
        browserRegistry.releaseFullscreen(presentation.key)
    }

    private var persistedBrowserKeys: Set<V2AssistantBrowserKey> {
        Set(store.workspace.sessions.flatMap { session in
            session.browserSessions.map {
                V2AssistantBrowserKey(sessionID: session.id, browserID: $0.id)
            }
        })
    }

    private var activeBrowserKeys: Set<V2AssistantBrowserKey> {
        Set(store.workspace.sessions.flatMap { session in
            session.browserSessions.compactMap { browser in
                guard browser.isExpanded || browser.isFullscreen else { return nil }
                return V2AssistantBrowserKey(sessionID: session.id, browserID: browser.id)
            }
        })
    }

    private var persistedBrowserKeyIDs: [String] {
        persistedBrowserKeys.map(\.id).sorted()
    }

    private func sendStarter(_ prompt: String) {
        guard !speech.isActive else { return }
        promptText = ""
        isComposerFocused = false
        store.send(prompt)
    }

    private func sendPrompt() {
        guard !speech.isActive, !isAttaching else { return }
        let source: V2UsageEvent.Source = isSpeechDraft || speechDraftOriginal != nil ? speechTraceSource : .keyboard
        isSpeechDraft = false
        let rawText = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = rawText.isEmpty && !attachments.isEmpty ? "请阅读这些附件" : rawText
        guard !text.isEmpty else { return }
        isComposerFocused = false
        if let original = speechDraftOriginal, original != text {
            V2UsageTrace.shared.record(.init(kind: .transcriptEdited, source: source,
                sessionID: store.selectedSession?.id, characterCount: text.count))
        }
        speechDraftOriginal = nil
        if store.submitDraft(.init(id: draftID, text: text, references: references, attachments: attachments), source: source) {
            promptText = ""; references = []; attachments = []; draftID = UUID().uuidString
        }
    }

    private var modelSelectionLabel: String {
        let choice = store.selectedSession?.modelSelection
        let settings = appStore.aiProviderSettings
        let provider = choice.flatMap { V2AIProviderPreset(rawValue: $0.providerID) } ?? settings.provider
        return "\(provider.title) · \(choice?.model ?? settings.model) · 思考 \((choice?.thinking ?? settings.thinking).title)"
    }

    private var currentDraft: V2AssistantDraft {
        .init(id: draftID, text: promptText, references: references, attachments: attachments)
    }

    private func restoreDraft() {
        let draft = store.selectedSession?.composerDraft ?? .init()
        draftSessionID = store.selectedSession?.id
        draftID = draft.id; promptText = draft.text; references = draft.references; attachments = draft.attachments ?? []
    }

    private func persistDraft() {
        guard let id = draftSessionID, id == store.selectedSession?.id else { return }
        store.saveDraft(currentDraft, in: id)
    }

    private var draftAccessories: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isAttaching { ProgressView("正在读取附件…").font(.caption) }
            ForEach(attachments) { attachment in
                HStack {
                    Button { previewAttachment = attachment } label: { Label(attachment.fileName, systemImage: "paperclip").lineLimit(1) }
                    Spacer()
                    Button { attachments.removeAll { $0.id == attachment.id } } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("移除附件")
                }.font(.caption)
            }
            ForEach(references) { reference in
                HStack {
                    Label(reference.excerpt, systemImage: "quote.opening").lineLimit(2)
                    Spacer()
                    Button { references.removeAll { $0.id == reference.id } } label: { Image(systemName: "xmark.circle.fill") }
                        .accessibilityLabel("取消引用")
                }.font(.caption).padding(10).background(V2Theme.panel, in: RoundedRectangle(cornerRadius: 10))
            }
            if let session = store.selectedSession, let queue = session.queuedDrafts, !queue.isEmpty {
                ForEach(queue) { draft in
                    HStack {
                        Text("待发送 · \(draft.text)").lineLimit(1)
                        Spacer()
                        Button("撤回") {
                            promptText = promptText.isEmpty ? draft.text : promptText + "\n" + draft.text
                            references = Array((references + draft.references).prefix(4))
                            attachments = Array((attachments + (draft.attachments ?? [])).prefix(4))
                            store.removeQueuedDraft(draft.id, in: session.id)
                        }
                    }.font(.caption).accessibilityIdentifier("assistant.queued")
                }
                if !store.isRunningTurn {
                    Button("继续发送补充") { store.sendNextQueuedDraft(in: session.id) }.font(.caption)
                }
            }
            if let error = store.operationErrorMessage { Text(error).font(.caption).foregroundStyle(.orange) }
        }.padding(.horizontal, 20)
    }

    private var speechTraceSource: V2UsageEvent.Source { speech.provider == .apple ? .apple : .funASR }

    private func combinedSpeech(_ text: String) -> String {
        speechPrefix.isEmpty ? text : "\(speechPrefix) \(text)"
    }

    private func startSpeech() {
        do {
            let provider = V2SpeechSettings.provider
            let key = provider == .funASR ? try V2SpeechSettings.loadKey() : ""
            guard provider == .apple || !key.isEmpty else { showSpeechSettings = true; return }
            speechPrefix = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
            isComposerFocused = false
            isSpeechDraft = true
            speechStartedAt = Date()
            speechDraftOriginal = nil
            speech.start(provider: provider, key: key)
            V2UsageTrace.shared.record(.init(kind: .speechStarted, source: speechTraceSource,
                sessionID: store.selectedSession?.id))
        } catch {
            speechConfigurationError = "无法读取语音配置，请点输入框旁的语音设置检查。"
        }
    }

    private func cancelSpeech() {
        guard speech.isActive else { return }
        promptText = combinedSpeech(speech.transcript)
        speechDraftOriginal = promptText
        V2UsageTrace.shared.record(.init(kind: .speechCancelled, source: speechTraceSource,
            sessionID: store.selectedSession?.id, duration: speechStartedAt.map { Date().timeIntervalSince($0) }))
        speechStartedAt = nil
        isSpeechDraft = false
        speech.cancel()
    }

    private func finishSpeech() {
        let sessionID = store.selectedSession?.id
        speech.finish { text in
            guard store.selectedSession?.id == sessionID else { return }
            V2UsageTrace.shared.record(.init(kind: .speechFinished, source: speechTraceSource,
                sessionID: sessionID, duration: speechStartedAt.map { Date().timeIntervalSince($0) }, characterCount: text.count))
            speechStartedAt = nil
            promptText = combinedSpeech(text)
            sendPrompt()
        }
    }

    private var assistantHeaderTitle: String {
        guard let session = store.selectedSession else { return "助手" }
        return session.title == "新会话" && session.messages.isEmpty ? "助手" : session.title
    }

    private func presentMenuSheet(_ presentation: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            presentation()
        }
    }
}

private struct V2AssistantPlanItemEditorContext: Identifiable {
    let planID: String
    let item: V2PlanDraftScheduleItem
    var id: String { "\(planID)-\(item.id)" }
}

private struct V2AssistantHeaderButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(V2Theme.secondary)
                .frame(width: 42, height: 42)
                .background(V2Theme.ColorRole.surfaceRaised, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(V2Theme.line.opacity(0.5)))
        }
        .buttonStyle(.plain)
    }
}

private struct V2AssistantConfigurationPrompt: View {
    let message: String?
    let onConfigure: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "key.horizontal")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(V2Theme.blue)
                .frame(width: 42, height: 42)
                .background(V2Theme.ColorRole.primaryContainer)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text("先连接 AI")
                .font(.system(size: 29, weight: .bold, design: .rounded))
                .foregroundStyle(V2Theme.ink)

            Text(message ?? "配置一个 AI 服务后，才能开始对话。")
                .font(V2Theme.TypeRole.bodyMedium)
                .foregroundStyle(V2Theme.secondary)

            Button(action: onConfigure) {
                Label("配置 AI 服务", systemImage: "arrow.right")
                    .font(V2Theme.TypeRole.labelMedium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .background(V2Theme.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("assistant.configureAI")

            Text("支持 SiliconFlow、Kimi、GLM 和 OpenAI 兼容服务")
                .font(V2Theme.TypeRole.bodySmall)
                .foregroundStyle(V2Theme.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 28)
        .padding(.top, 112)
    }
}

private struct V2AssistantStarterView: View {
    let onStart: (String) -> Void

    private let starters = [
        V2AssistantStarter(title: "随便聊聊", example: "最近有什么烦心事？", prompt: "随便聊聊", icon: "quote.bubble.fill", color: V2Theme.blue, identifier: "chat"),
        V2AssistantStarter(title: "搜索网页", example: "查一下香港周末天气", prompt: "搜索网页", icon: "globe.asia.australia.fill", color: V2Theme.mint, identifier: "web"),
        V2AssistantStarter(title: "查找我的资料", example: "找之前记录的计划", prompt: "查找我的资料", icon: "doc.text.magnifyingglass", color: V2Theme.violet, identifier: "local"),
        V2AssistantStarter(title: "帮我安排计划", example: "把近期任务排一下", prompt: "帮我安排计划", icon: "calendar.badge.clock", color: V2Theme.orange, identifier: "plan")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(V2Theme.blue)
                    .frame(width: 50, height: 50)
                    .background(V2Theme.ColorRole.primaryContainer, in: RoundedRectangle(cornerRadius: 18))

                Text("想一起处理什么？")
                    .font(V2Theme.TypeRole.headlineMedium)
                    .foregroundStyle(V2Theme.ink)
                Text("说说要做的事，或直接录一段语音。")
                    .font(V2Theme.TypeRole.bodyMedium)
                    .foregroundStyle(V2Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
            .background(V2Theme.panel, in: RoundedRectangle(cornerRadius: 28))

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], alignment: .leading, spacing: 12) {
                ForEach(starters) { starter in
                    Button {
                        onStart(starter.prompt)
                    } label: {
                        VStack(alignment: .leading, spacing: 12) {
                            Image(systemName: starter.icon)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(starter.color)
                                .frame(width: 38, height: 38)
                                .background(starter.color.opacity(0.09), in: RoundedRectangle(cornerRadius: 13))
                            VStack(alignment: .leading, spacing: 5) {
                                Text(starter.title)
                                    .font(V2Theme.TypeRole.labelLarge)
                                    .foregroundStyle(V2Theme.ink)
                                Text(starter.example)
                                    .font(V2Theme.TypeRole.labelSmall)
                                    .foregroundStyle(V2Theme.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
                        .padding(16)
                        .background(V2Theme.ColorRole.surfaceRaised, in: RoundedRectangle(cornerRadius: 22))
                        .contentShape(RoundedRectangle(cornerRadius: 22))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("assistant.starter.\(starter.identifier)")
                }
            }
        }
    }
}

private struct V2AssistantStarter: Identifiable {
    let title: String
    let example: String
    let prompt: String
    let icon: String
    let color: Color
    let identifier: String
    var id: String { identifier }
}

private struct V2AssistantComposer: View {
    @ObservedObject private var plugins = V2PluginStore.shared
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let isBusy: Bool
    let speechState: V2RealtimeSpeechTranscriber.State
    let speechStatus: String
    @Binding var speechProvider: V2SpeechProvider
    let canRetrySpeech: Bool
    let onSpeechSettings: () -> Void
    let onMic: () -> Void
    let onFinishSpeech: () -> Void
    let onCancelSpeech: () -> Void
    let onSend: () -> Void
    let onCancel: () -> Void
    @Binding var isExpanded: Bool
    let onAttach: () -> Void

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
                } label: {
                    Label(
                        isExpanded ? "收起编辑" : "展开编辑",
                        systemImage: isExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
                    )
                }
                    .font(.caption).accessibilityIdentifier("assistant.composer.expand")
                if plugins.enabled("attachments") {
                    Button(action: onAttach) { Label("附件", systemImage: "paperclip") }.font(.caption)
                        .accessibilityIdentifier("assistant.attachment.add")
                }
                Spacer()
                if isFocused.wrappedValue {
                    Button { isFocused.wrappedValue = false } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("收起键盘")
                    .accessibilityIdentifier("assistant.composer.dismissKeyboard")
                }
                if isBusy {
                    Button(action: onCancel) { Label("停止", systemImage: "stop.fill") }
                        .font(.caption).accessibilityIdentifier("assistant.cancel")
                }
            }.foregroundStyle(V2Theme.secondary)
            if plugins.enabled("speech") { HStack {
                Menu {
                    Picker("听写方式", selection: $speechProvider) {
                        ForEach(V2SpeechProvider.allCases, id: \.self) { provider in
                            Text(provider.title).tag(provider)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text("听写 · \(speechProvider == .apple ? "苹果原生" : "FunASR")")
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                    }
                    .font(V2Theme.TypeRole.labelSmall)
                    .foregroundStyle(V2Theme.secondary)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 32)
                    .background(V2Theme.ColorRole.surfaceMuted, in: Capsule())
                }
                .accessibilityIdentifier("assistant.speech.provider")
                .disabled(speechState != .idle || canRetrySpeech)
                Spacer()
                Button(action: onSpeechSettings) { Image(systemName: "slider.horizontal.3").frame(width: 36, height: 32) }
                    .foregroundStyle(V2Theme.secondary)
                    .accessibilityLabel("语音设置")
                    .accessibilityIdentifier("assistant.speech.settings")
                    .disabled(speechState != .idle || canRetrySpeech)
            }
            }
            if speechState != .idle || canRetrySpeech {
                HStack {
                    Text(speechStatus)
                        .font(.caption)
                        .foregroundStyle(V2Theme.secondary)
                        .accessibilityIdentifier("assistant.speech.status")
                    Spacer()
                    Button(canRetrySpeech ? "放弃录音" : "取消", action: onCancelSpeech)
                        .accessibilityIdentifier("assistant.speech.cancel")
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                V2MultilineInput(
                    text: $text,
                    placeholder: isBusy ? "补充想法，下一轮发送…" : "问点什么，或记录一个想法…",
                    minHeight: isExpanded ? 160 : 44,
                    maxHeight: isExpanded ? 190 : 140,
                    accessibilityIdentifier: "assistant.composer",
                    isEnabled: speechState == .idle && !canRetrySpeech,
                    focus: isFocused
                )

                if plugins.enabled("speech") && speechState == .idle && !canRetrySpeech {
                    Button(action: onMic) {
                        Image(systemName: "mic")
                            .font(.system(size: 18))
                            .foregroundStyle(V2Theme.blue)
                            .frame(width: 42, height: 42)
                            .background(V2Theme.ColorRole.primaryContainer, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .accessibilityLabel("开始语音输入")
                    .accessibilityIdentifier("assistant.speech.start")
                }
                if speechState != .idle || canRetrySpeech {
                    Button(canRetrySpeech ? "重试转写" : "完成", action: onFinishSpeech)
                        .font(.system(size: 15, weight: .semibold))
                        .frame(minWidth: 44, minHeight: 38)
                        .disabled(speechState != .recording && !canRetrySpeech)
                        .accessibilityIdentifier("assistant.speech.finish")
                } else {
                    Button(action: onSend) {
                        Image(systemName: isBusy ? "text.badge.plus" : "arrow.up")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(isBusy || canSend ? V2Theme.blue : V2Theme.tertiary)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                    .accessibilityLabel(isBusy ? "排队发送" : "发送")
                    .accessibilityIdentifier("assistant.send")
                }
            }
        }
        .padding(14)
        .background(V2Theme.ColorRole.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(V2Theme.line.opacity(0.65), lineWidth: 1)
        }
        .shadow(color: V2Theme.ink.opacity(0.04), radius: 16, y: 6)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(V2Theme.page)
    }


}

private struct V2AssistantTaskContextRow: View {
    let sourceTask: V2AgentSourceTask

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.turn.down.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(V2Theme.violet)
            Text("来自任务：\(sourceTask.title)")
                .font(V2Theme.TypeRole.labelMedium)
                .foregroundStyle(V2Theme.secondary)
                .accessibilityIdentifier("assistant.context.task")
            Spacer()
        }
        .padding(.top, 16)
        .padding(.bottom, 2)
    }
}

private struct V2AssistantStorageIssueView: View {
    let message: String
    let canRetry: Bool
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(message)
                .font(V2Theme.TypeRole.bodySmall)
                .foregroundStyle(V2Theme.secondary)
            if canRetry {
                Button("重试保存", action: onRetry)
                    .font(V2Theme.TypeRole.labelMedium)
                    .foregroundStyle(V2Theme.blue)
                    .accessibilityIdentifier("assistant.storage.retry")
            }
        }
        .padding(.leading, 12)
        .overlay(alignment: .leading) {
            Rectangle().fill(V2Theme.orange).frame(width: 3)
        }
    }
}

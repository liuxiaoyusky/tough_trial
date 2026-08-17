import SwiftUI
import ToughTrialV2Core

struct V2PlanAgentView: View {
    @ObservedObject var store: V2AppStore
    @StateObject private var speech = V2SpeechTranscriber()
    @State private var promptText = ""
    @State private var speechPrefix = ""
    @State private var showHistory = false
    @State private var showMemory = false
    @State private var showAISettings = false
    @State private var editingScheduleItem: V2PlanDraftScheduleItem?
    @FocusState private var isComposerFocused: Bool

    private let quickReplies = ["可以", "想分两次", "先看看时间"]

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if !store.canUsePlanningAI {
                            V2PlanAISetupPrompt {
                                showAISettings = true
                            }
                        } else if store.state.planConversationPhase == .empty {
                            V2PlanOpeningPrompt(
                                suggestion: store.dreamingCandidates.first,
                                usesOnlineAI: store.hasConnectedAIService,
                                onSelect: beginConversation,
                                onOpenSuggestion: store.openDreamingCandidate,
                                onConnectAI: { showAISettings = true }
                            )
                        } else {
                            conversation
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(
                        .top,
                        !store.canUsePlanningAI || store.state.planConversationPhase == .empty
                            ? 112
                            : 22
                    )
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: store.state.planMessages.count) { _, _ in
                    scrollToBottom(proxy)
                }
                .onChange(of: store.state.currentPlanDraft) { _, _ in
                    scrollToBottom(proxy)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if store.canUsePlanningAI {
                V2PlanComposer(
                    promptText: $promptText,
                    placeholder: composerPlaceholder,
                    isFocused: $isComposerFocused,
                    isBusy: store.isPlanning,
                    isListening: speech.isListening,
                    onMic: toggleSpeech,
                    onSend: sendPrompt
                )
            }
        }
        .sheet(isPresented: $showHistory) {
            V2PlanHistorySheet(
                drafts: store.pendingPlanDrafts,
                onResume: { draft in
                    store.resumePlanDraft(draft)
                    showHistory = false
                },
                onNew: {
                    store.startNewPlanConversation()
                    showHistory = false
                },
                onOpenAISettings: {
                    showHistory = false
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(350))
                        showAISettings = true
                    }
                },
                onOpenMemory: {
                    showHistory = false
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(350))
                        showMemory = true
                    }
                }
            )
        }
        .sheet(isPresented: $showMemory) {
            V2MemorySheet(store: store)
        }
        .sheet(isPresented: $showAISettings) {
            V2AIProviderSettingsView(store: store)
        }
        .sheet(item: $editingScheduleItem) { item in
            V2PlanScheduleItemEditor(item: item) { updatedItem in
                store.updateCurrentPlanScheduleItem(updatedItem)
            }
        }
        .alert("操作未完成", isPresented: errorBinding) {
            Button("知道了") {
                store.dismissError()
            }
        } message: {
            Text(store.errorMessage ?? "请稍后再试。")
        }
        .alert("语音输入", isPresented: speechErrorBinding) {
            Button("知道了") {
                speech.dismissError()
            }
        } message: {
            Text(speech.errorMessage ?? "语音输入暂不可用。")
        }
        .onChange(of: speech.transcript) { _, transcript in
            guard !transcript.isEmpty else { return }
            promptText = speechPrefix.isEmpty
                ? transcript
                : "\(speechPrefix) \(transcript)"
        }
        .onDisappear {
            speech.stop()
        }
        .v2ScreenBackground()
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { store.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    store.dismissError()
                }
            }
        )
    }

    private var speechErrorBinding: Binding<Bool> {
        Binding(
            get: { speech.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    speech.dismissError()
                }
            }
        )
    }

    private var conversation: some View {
        Group {
            ForEach(store.state.planMessages, id: \.id) { message in
                V2PlanMessageRow(message: message)
                    .id(message.id)
            }

            if store.isPlanning {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("\(store.planningProviderLabel)正在整理...")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(V2Theme.tertiary)
                }
                .id("plan-loading")
            } else if store.state.planConversationPhase == .clarifying,
                      store.planningFailureMessage == nil {
                V2PlanQuickReplies(replies: displayedQuickReplies) { reply in
                    Task { @MainActor in
                        await store.submitPlanClarification(reply)
                    }
                }
                .id("plan-quick-replies")
            }

            if let failure = store.planningFailureMessage {
                V2PlanFailureRow(message: failure) {
                    showAISettings = true
                }
                .id("plan-failure")
            }

            if let draft = store.state.currentPlanDraft {
                V2PlanInlineDraft(
                    draft: draft,
                    onEdit: { editingScheduleItem = $0 },
                    onAccept: { store.acceptCurrentPlanDraft() }
                )
                .id("current-plan-draft")
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            V2IconButton(systemName: "xmark") {
                store.closePlanAgent()
            }
            .accessibilityLabel("关闭计划")

            VStack(alignment: .leading, spacing: 1) {
                Text("计划")
                    .font(.system(size: 23, weight: .bold))
                    .foregroundStyle(V2Theme.ink)

                if let detail = headerDetail {
                    Text(detail)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(V2Theme.tertiary)
                        .accessibilityIdentifier(
                            store.planningSourceTask == nil
                                ? "plan.context.general"
                                : "plan.context.task"
                        )
                }
            }

            Spacer()

            Button {
                showHistory = true
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(V2Theme.secondary)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("计划历史")
            .accessibilityIdentifier("plan.history")
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(V2Theme.page)
    }

    private var headerDetail: String? {
        if store.state.planConversationPhase == .reviewingDraft {
            return "草稿已自动保存"
        }
        if let task = store.planningSourceTask {
            return "来自任务：\(task.title)"
        }
        return nil
    }

    private var displayedQuickReplies: [String] {
        store.planningSuggestedReplies.isEmpty ? quickReplies : store.planningSuggestedReplies
    }

    private var composerPlaceholder: String {
        switch store.state.planConversationPhase {
        case .empty:
            "说说你想安排什么..."
        case .clarifying:
            "也可以直接补充..."
        case .reviewingDraft:
            "继续补充或调整..."
        case .complete:
            "继续安排其他事情..."
        }
    }

    private func beginConversation(_ prompt: String) {
        promptText = ""
        Task { @MainActor in
            await store.submitPlanPrompt(prompt)
        }
    }

    private func sendPrompt() {
        let trimmed = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        speech.stop()
        speechPrefix = ""
        promptText = ""
        isComposerFocused = false
        Task { @MainActor in
            if store.state.planConversationPhase == .clarifying {
                await store.submitPlanClarification(trimmed)
            } else {
                await store.submitPlanPrompt(trimmed)
            }
        }
    }

    private func toggleSpeech() {
        if !speech.isListening {
            speechPrefix = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
            isComposerFocused = false
        }
        speech.toggle()
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.snappy(duration: 0.25)) {
            if store.state.currentPlanDraft != nil {
                proxy.scrollTo("current-plan-draft", anchor: .bottom)
            } else if store.state.planConversationPhase == .clarifying {
                proxy.scrollTo("plan-quick-replies", anchor: .bottom)
            } else if let last = store.state.planMessages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}

private struct V2PlanAISetupPrompt: View {
    let onConfigure: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "sparkles")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(V2Theme.violet)
                .frame(width: 44, height: 44)
                .background(V2Theme.violet.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text("先连接 AI")
                    .font(V2Theme.TypeRole.displayMedium)
                    .foregroundStyle(V2Theme.ink)

                Text("配置一个 AI 服务后，才能开始规划。")
                    .font(V2Theme.TypeRole.bodyMedium)
                    .foregroundStyle(V2Theme.secondary)
            }

            Button(action: onConfigure) {
                Label("配置 AI 服务", systemImage: "arrow.right")
                    .font(V2Theme.TypeRole.labelMedium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 46)
                    .background(V2Theme.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("plan.configureAI")

            Text("支持 SiliconFlow、Kimi、GLM 和 OpenAI 兼容服务")
                .font(V2Theme.TypeRole.bodySmall)
                .foregroundStyle(V2Theme.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct V2PlanOpeningPrompt: View {
    let suggestion: V2DreamingCandidate?
    let usesOnlineAI: Bool
    let onSelect: (String) -> Void
    let onOpenSuggestion: (V2DreamingCandidate) -> Void
    let onConnectAI: () -> Void

    private let prompts = ["这周想跑 10 公里", "明天安排得轻一点"]

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Text("想怎么安排？")
                .font(V2Theme.TypeRole.displayMedium)
                .foregroundStyle(V2Theme.ink)

            VStack(spacing: 0) {
                ForEach(Array(prompts.enumerated()), id: \.element) { index, prompt in
                    Button {
                        onSelect(prompt)
                    } label: {
                        HStack(spacing: 12) {
                            Text(prompt)
                                .font(V2Theme.TypeRole.bodyMedium)
                                .foregroundStyle(V2Theme.secondary)
                            Spacer(minLength: 12)
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(V2Theme.tertiary)
                        }
                        .frame(minHeight: 48)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index < prompts.count - 1 {
                        Divider().overlay(V2Theme.line.opacity(0.75))
                    }
                }
            }

            if let suggestion {
                VStack(alignment: .leading, spacing: 8) {
                    Text("一个建议")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(V2Theme.tertiary)

                    Button {
                        onOpenSuggestion(suggestion)
                    } label: {
                        HStack(spacing: 11) {
                            Image(systemName: suggestion.kind == .schedule
                                ? "calendar.badge.clock"
                                : "arrow.triangle.branch")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(V2Theme.violet)
                                .frame(width: 26)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(suggestion.title)
                                    .font(V2Theme.TypeRole.labelMedium)
                                    .foregroundStyle(V2Theme.ink)
                                Text(suggestion.summary)
                                    .font(V2Theme.TypeRole.bodySmall)
                                    .foregroundStyle(V2Theme.tertiary)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(V2Theme.tertiary)
                        }
                        .frame(minHeight: 48)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            if !usesOnlineAI {
                HStack(spacing: 8) {
                    Circle()
                        .fill(V2Theme.orange)
                        .frame(width: 6, height: 6)
                    Text("当前使用基础规划")
                        .font(V2Theme.TypeRole.bodySmall)
                        .foregroundStyle(V2Theme.tertiary)
                    Spacer()
                    Button("连接在线 AI", action: onConnectAI)
                        .font(V2Theme.TypeRole.labelMedium)
                        .foregroundStyle(V2Theme.blue)
                        .accessibilityIdentifier("plan.connectAI")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct V2PlanMessageRow: View {
    let message: V2PlanMessage

    var body: some View {
        if message.role == .user {
            HStack {
                Spacer(minLength: 56)
                Text(message.text)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 12)
                    .background(V2Theme.ink)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(V2Theme.violet)
                        .frame(width: 18, height: 18)
                        .background(V2Theme.violet.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

                    Text("计划 Agent")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(V2Theme.secondary)
                }

                Text(message.text)
                    .font(.system(size: 16))
                    .foregroundStyle(V2Theme.ink)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct V2PlanQuickReplies: View {
    let replies: [String]
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(replies, id: \.self) { reply in
                Button(reply) {
                    onSelect(reply)
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(V2Theme.secondary)
                .padding(.horizontal, 13)
                .frame(height: 36)
                .background(V2Theme.ColorRole.surfaceRaised)
                .clipShape(Capsule())
                .overlay {
                    Capsule().stroke(V2Theme.line, lineWidth: 1)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct V2PlanFailureRow: View {
    let message: String
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("没有收到可用回复", systemImage: "exclamationmark.bubble")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(V2Theme.ink)

            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(V2Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("检查 AI 服务", action: onOpenSettings)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(V2Theme.blue)
                .accessibilityIdentifier("plan.failure.settings")
        }
        .padding(.leading, 13)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(V2Theme.orange)
                .frame(width: 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct V2PlanInlineDraft: View {
    let draft: V2PlanDraft
    let onEdit: (V2PlanDraftScheduleItem) -> Void
    let onAccept: () -> Void
    @State private var showsReasons = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(V2Theme.violet)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("计划草稿 · 自动保存")
                        .font(V2Theme.TypeRole.labelSmall)
                        .foregroundStyle(V2Theme.violet)

                    Text(draft.title)
                        .font(V2Theme.TypeRole.titleLarge)
                        .foregroundStyle(V2Theme.ink)
                    Text(draft.summary)
                        .font(V2Theme.TypeRole.bodySmall)
                        .foregroundStyle(V2Theme.tertiary)
                }

                if !draft.taskChanges.isEmpty {
                    Label(
                        "同时建立 \(draft.taskChanges.count) 个任务节点",
                        systemImage: "arrow.triangle.branch"
                    )
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(V2Theme.secondary)
                }

                VStack(spacing: 0) {
                    ForEach(Array(draft.scheduleItems.enumerated()), id: \.element.id) { index, item in
                        V2PlanDraftRow(
                            item: item,
                            isLast: index == draft.scheduleItems.count - 1,
                            onEdit: { onEdit(item) }
                        )
                    }
                }

                if !draft.decisions.isEmpty {
                    DisclosureGroup(isExpanded: $showsReasons) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(draft.decisions, id: \.self) { decision in
                                Text(decision)
                                    .font(V2Theme.TypeRole.bodySmall)
                                    .foregroundStyle(V2Theme.secondary)
                            }
                        }
                        .padding(.top, 8)
                    } label: {
                        Text("为什么这样安排")
                            .font(V2Theme.TypeRole.labelMedium)
                            .foregroundStyle(V2Theme.secondary)
                    }
                    .tint(V2Theme.tertiary)
                }

                HStack(spacing: 10) {
                    Spacer(minLength: 8)
                    Button("加入计划", action: onAccept)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .frame(height: 44)
                        .background(V2Theme.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .accessibilityIdentifier("plan.acceptDraft")
                }
                .font(.system(size: 14, weight: .semibold))
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct V2PlanDraftRow: View {
    let item: V2PlanDraftScheduleItem
    let isLast: Bool
    let onEdit: () -> Void

    var body: some View {
        Button(action: onEdit) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(Self.weekdayFormatter.string(from: item.date))
                        .font(V2Theme.TypeRole.labelMedium)
                        .foregroundStyle(V2Theme.secondary)
                    Text(Self.dateFormatter.string(from: item.date))
                        .font(V2Theme.TypeRole.labelSmall)
                        .foregroundStyle(V2Theme.tertiary)
                }
                .frame(width: 48, alignment: .leading)

                timelineMarker

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(V2Theme.TypeRole.labelLarge)
                        .foregroundStyle(V2Theme.ink)
                        .lineLimit(2)
                    Text(timeLabel)
                        .font(V2Theme.TypeRole.bodySmall)
                        .foregroundStyle(V2Theme.tertiary)
                        .monospacedDigit()
                }

                Spacer(minLength: 8)

                Image(systemName: "pencil")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(V2Theme.tertiary)
                    .frame(width: 26, height: 26)
            }
            .frame(minHeight: 62, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("编辑安排：\(item.title)")
        .accessibilityIdentifier("plan.draft.item.\(item.id)")
    }

    private var timelineMarker: some View {
        ZStack(alignment: .top) {
            if !isLast {
                Rectangle()
                    .fill(V2Theme.violet.opacity(0.28))
                    .frame(width: 1.5, height: 62)
                    .offset(y: 9)
            }
            Circle()
                .fill(V2Theme.page)
                .frame(width: 11, height: 11)
                .overlay {
                    Circle().stroke(V2Theme.violet, lineWidth: 2)
                }
                .padding(.top, 4)
        }
        .frame(width: 12, height: 62, alignment: .top)
    }

    private var timeLabel: String {
        guard let startAt = item.startAt else { return "时间待定" }
        return Self.timeFormatter.string(from: startAt)
    }

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "EEE"
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M.d"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

private struct V2PlanComposer: View {
    @Binding var promptText: String
    let placeholder: String
    var isFocused: FocusState<Bool>.Binding
    let isBusy: Bool
    let isListening: Bool
    let onMic: () -> Void
    let onSend: () -> Void

    private var canSend: Bool {
        !isBusy && !promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 9) {
            TextField(
                "",
                text: $promptText,
                prompt: Text(placeholder).foregroundColor(V2Theme.tertiary),
                axis: .vertical
            )
                .lineLimit(1...4)
                .font(.system(size: 15))
                .foregroundStyle(V2Theme.ink)
                .tint(V2Theme.blue)
                .focused(isFocused)
                .disabled(isBusy)
                .padding(.vertical, 8)
                .accessibilityIdentifier("plan.composer")

            Button(action: onMic) {
                Image(systemName: isListening ? "waveform" : "mic")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(
                        isListening
                            ? V2Theme.ColorRole.textInverse
                            : V2Theme.ColorRole.textSecondary
                    )
                    .frame(width: 36, height: 36)
                    .background(
                        isListening
                            ? V2Theme.ColorRole.destructive
                            : V2Theme.ColorRole.surfaceMuted,
                        in: Circle()
                    )
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
            .accessibilityLabel(isListening ? "停止语音输入" : "开始语音输入")

            Button(action: onSend) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(canSend ? V2Theme.ink : V2Theme.tertiary)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel("发送")
        }
        .padding(10)
        .background(V2Theme.ColorRole.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(
            V2Theme.page
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(V2Theme.line.opacity(0.7))
                        .frame(height: 1)
                }
        )
    }
}

private struct V2PlanScheduleItemEditor: View {
    let item: V2PlanDraftScheduleItem
    let onSave: (V2PlanDraftScheduleItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var date: Date
    @State private var hasTime: Bool
    @State private var time: Date

    init(
        item: V2PlanDraftScheduleItem,
        onSave: @escaping (V2PlanDraftScheduleItem) -> Void
    ) {
        self.item = item
        self.onSave = onSave
        _title = State(initialValue: item.title)
        _date = State(initialValue: item.date)
        _hasTime = State(initialValue: item.startAt != nil)
        _time = State(initialValue: item.startAt ?? item.date)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("安排") {
                    TextField("任务名称", text: $title, axis: .vertical)
                        .lineLimit(1...3)
                        .accessibilityIdentifier("plan.editor.title")
                }

                Section("日期与时间") {
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                        .accessibilityIdentifier("plan.editor.date")

                    Toggle("指定时间", isOn: $hasTime)
                        .accessibilityIdentifier("plan.editor.hasTime")

                    if hasTime {
                        DatePicker("开始", selection: $time, displayedComponents: .hourAndMinute)
                            .accessibilityIdentifier("plan.editor.time")
                    }
                }
            }
            .navigationTitle("修改安排")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(updatedItem)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("plan.editor.save")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var updatedItem: V2PlanDraftScheduleItem {
        var calendar = Calendar.current
        calendar.timeZone = .current
        let day = calendar.startOfDay(for: date)
        let startAt: Date?
        let endAt: Date?

        if hasTime {
            let components = calendar.dateComponents([.hour, .minute], from: time)
            startAt = calendar.date(
                bySettingHour: components.hour ?? 9,
                minute: components.minute ?? 0,
                second: 0,
                of: day
            )
            let originalDuration = item.startAt.flatMap { start in
                item.endAt.map { max(15 * 60, $0.timeIntervalSince(start)) }
            } ?? 30 * 60
            endAt = startAt?.addingTimeInterval(originalDuration)
        } else {
            startAt = nil
            endAt = nil
        }

        return V2PlanDraftScheduleItem(
            id: item.id,
            date: day,
            startAt: startAt,
            endAt: endAt,
            taskID: item.taskID,
            proposedTaskID: item.proposedTaskID,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

private struct V2MemorySheet: View {
    @ObservedObject var store: V2AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var editingRecord: V2UserMemoryRecord?
    @State private var isAdding = false

    var body: some View {
        NavigationStack {
            Group {
                if let issue = store.memoryIssueMessage {
                    ContentUnavailableView(
                        "记忆暂不可用",
                        systemImage: "externaldrive.badge.exclamationmark",
                        description: Text(issue)
                    )
                } else if store.memoryRecords.isEmpty {
                    ContentUnavailableView(
                        "还没有记忆",
                        systemImage: "brain",
                        description: Text("记录你愿意让计划助手参考的习惯、偏好或约束。")
                    )
                } else {
                    List {
                        ForEach(store.memoryRecords) { record in
                            Button {
                                editingRecord = record
                            } label: {
                                V2MemoryRow(record: record)
                            }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button("忘记", role: .destructive) {
                                    _ = store.forgetMemory(id: record.id)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("记忆")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isAdding = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(store.memoryIssueMessage != nil)
                    .accessibilityLabel("新增记忆")
                }
            }
        }
        .sheet(isPresented: $isAdding) {
            V2MemoryEditorSheet(store: store, record: nil)
        }
        .sheet(item: $editingRecord) { record in
            V2MemoryEditorSheet(store: store, record: record)
        }
        .presentationDetents([.medium, .large])
    }
}

private struct V2MemoryRow: View {
    let record: V2UserMemoryRecord

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(V2Theme.violet)
                .frame(width: 30, height: 30)
                .background(V2Theme.violet.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(record.statement)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(V2Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text(detail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(V2Theme.tertiary)
            }

            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(V2Theme.tertiary)
                .padding(.top, 8)
        }
        .padding(.vertical, 5)
    }

    private var iconName: String {
        switch record.kind {
        case .preference: "heart"
        case .routine: "repeat"
        case .availability: "calendar.badge.clock"
        case .constraint: "exclamationmark.shield"
        }
    }

    private var detail: String {
        let kind: String
        switch record.kind {
        case .preference: kind = "偏好"
        case .routine: kind = "日常"
        case .availability: kind = "空闲"
        case .constraint: kind = "约束"
        }
        let source: String
        switch record.origin {
        case .explicitUser: source = "你记录的"
        case .confirmedInference: source = "你确认的推断"
        case .temporaryContext: source = "7 天临时上下文"
        }
        return "\(kind) · \(source)"
    }
}

private struct V2MemoryEditorSheet: View {
    @ObservedObject var store: V2AppStore
    let record: V2UserMemoryRecord?
    @Environment(\.dismiss) private var dismiss
    @State private var statement: String
    @State private var kind: V2UserMemoryRecord.Kind
    @State private var isTemporary: Bool
    @State private var availabilityWeekday: Int
    @State private var availabilityStart: Date
    @State private var availabilityDuration: Int

    init(store: V2AppStore, record: V2UserMemoryRecord?) {
        self.store = store
        self.record = record
        _statement = State(initialValue: record?.statement ?? "")
        _kind = State(initialValue: record?.kind ?? .preference)
        _isTemporary = State(initialValue: record?.origin == .temporaryContext)
        let availability = record?.availability
        _availabilityWeekday = State(initialValue: availability?.weekday ?? 7)
        _availabilityStart = State(
            initialValue: Calendar.current.date(
                from: DateComponents(
                    year: 2001,
                    month: 1,
                    day: 1,
                    hour: (availability?.startMinute ?? 9 * 60) / 60,
                    minute: (availability?.startMinute ?? 9 * 60) % 60
                )
            ) ?? Date()
        )
        _availabilityDuration = State(initialValue: availability?.durationMinutes ?? 60)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("计划助手可以参考") {
                    TextField(
                        "例如：工作日晚上最多安排 30 分钟运动",
                        text: $statement,
                        axis: .vertical
                    )
                    .lineLimit(3...6)
                }

                Section("类型") {
                    Picker("类型", selection: $kind) {
                        Text("偏好").tag(V2UserMemoryRecord.Kind.preference)
                        Text("日常").tag(V2UserMemoryRecord.Kind.routine)
                        Text("空闲").tag(V2UserMemoryRecord.Kind.availability)
                        Text("约束").tag(V2UserMemoryRecord.Kind.constraint)
                    }
                    .pickerStyle(.segmented)
                }

                if kind == .availability {
                    Section("明确的空闲窗口") {
                        Picker("星期", selection: $availabilityWeekday) {
                            ForEach(Array(Self.weekdays.enumerated()), id: \.offset) { index, title in
                                Text(title).tag(index + 1)
                            }
                        }
                        DatePicker(
                            "开始",
                            selection: $availabilityStart,
                            displayedComponents: .hourAndMinute
                        )
                        Stepper(
                            "可用 \(availabilityDuration) 分钟",
                            value: $availabilityDuration,
                            in: 15...180,
                            step: 15
                        )
                    }
                }

                Section {
                    Toggle("仅作为 7 天临时上下文", isOn: $isTemporary)
                } footer: {
                    Text("记忆只影响建议；任何任务或计划仍需你确认。")
                }
            }
            .navigationTitle(record == nil ? "新增记忆" : "纠正记忆")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let saved: Bool
                        if let record {
                            saved = store.correctMemory(
                                id: record.id,
                                statement: statement,
                                kind: kind,
                                isTemporary: isTemporary,
                                availability: availability
                            )
                        } else {
                            saved = store.addMemory(
                                statement: statement,
                                kind: kind,
                                isTemporary: isTemporary,
                                availability: availability
                            )
                        }
                        if saved {
                            dismiss()
                        }
                    }
                    .disabled(statement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var availability: V2WeeklyAvailability? {
        guard kind == .availability else { return nil }
        let components = Calendar.current.dateComponents([.hour, .minute], from: availabilityStart)
        return V2WeeklyAvailability(
            weekday: availabilityWeekday,
            startMinute: (components.hour ?? 0) * 60 + (components.minute ?? 0),
            durationMinutes: availabilityDuration
        )
    }

    private static let weekdays = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
}

private struct V2PlanHistorySheet: View {
    let drafts: [V2PlanDraftRecord]
    let onResume: (V2PlanDraftRecord) -> Void
    let onNew: () -> Void
    let onOpenAISettings: () -> Void
    let onOpenMemory: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if drafts.isEmpty {
                    ContentUnavailableView(
                        "还没有草稿",
                        systemImage: "doc.text",
                        description: Text("保存的计划草稿会出现在这里。")
                    )
                } else {
                    List(drafts) { draft in
                        Button {
                            onResume(draft)
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(draft.userPrompt)
                                        .font(.headline)
                                        .foregroundStyle(V2Theme.ink)
                                    Text(draft.summary)
                                        .font(.subheadline)
                                        .foregroundStyle(V2Theme.secondary)
                                        .lineLimit(2)
                                    Text(Self.dateFormatter.string(from: draft.updatedAt))
                                        .font(.caption)
                                        .foregroundStyle(V2Theme.tertiary)
                                }

                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(V2Theme.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 4)
                        .accessibilityLabel("继续计划：\(draft.userPrompt)")
                        .accessibilityIdentifier("plan.history.resume.\(draft.id)")
                    }
                }
            }
            .navigationTitle("草稿历史")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button(action: onOpenAISettings) {
                            Label("AI 服务", systemImage: "server.rack")
                        }
                        Button(action: onOpenMemory) {
                            Label("记忆", systemImage: "brain")
                        }
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel("计划设置")
                    .accessibilityIdentifier("plan.history.settings")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("新计划", action: onNew)
                        .accessibilityIdentifier("plan.history.new")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()
}

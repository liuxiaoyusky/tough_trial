import SwiftUI
import ToughTrialV2Core

struct V2PlanAgentView: View {
    @ObservedObject var store: V2AppStore
    @State private var promptText = ""
    @State private var showHistory = false
    @FocusState private var isComposerFocused: Bool

    private let quickReplies = ["可以", "想分两次", "先看看时间"]

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if store.state.planConversationPhase == .empty {
                            V2PlanOpeningPrompt(onSelect: beginConversation)
                        } else {
                            conversation
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.top, store.state.planConversationPhase == .empty ? 112 : 22)
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
            V2PlanComposer(
                scope: Binding(
                    get: { store.state.planScope },
                    set: { store.setPlanScope($0) }
                ),
                promptText: $promptText,
                placeholder: composerPlaceholder,
                isFocused: $isComposerFocused,
                isBusy: store.isPlanning,
                onSend: sendPrompt
            )
        }
        .sheet(isPresented: $showHistory) {
            V2PlanHistorySheet(drafts: store.pendingPlanDrafts)
        }
        .alert("操作未完成", isPresented: errorBinding) {
            Button("知道了") {
                store.dismissError()
            }
        } message: {
            Text(store.errorMessage ?? "请稍后再试。")
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
            } else if store.state.planConversationPhase == .clarifying {
                V2PlanQuickReplies(replies: displayedQuickReplies) { reply in
                    Task { @MainActor in
                        await store.submitPlanClarification(reply)
                    }
                }
                .id("plan-quick-replies")
            }

            if let draft = store.state.currentPlanDraft {
                V2PlanInlineDraft(
                    draft: draft,
                    onSave: { store.saveCurrentPlanDraft() },
                    onContinue: {
                        isComposerFocused = true
                    },
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
                }
            }

            Spacer()

            Button("历史") {
                showHistory = true
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(V2Theme.secondary)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(V2Theme.page)
    }

    private var headerDetail: String? {
        if store.state.planConversationPhase == .reviewingDraft {
            return "\(max(1, store.planDraftCount))个草稿"
        }
        return store.state.planScope ?? store.planningProviderLabel
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

private struct V2PlanOpeningPrompt: View {
    let onSelect: (String) -> Void

    private let firstRow = ["这周想跑 10 公里", "明天安排得轻一点"]
    private let secondRow = ["帮我拆解论文写作"]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("想怎么安排？")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(V2Theme.ink)

            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    ForEach(firstRow, id: \.self) { prompt in
                        promptButton(prompt)
                    }
                }

                HStack(spacing: 8) {
                    ForEach(secondRow, id: \.self) { prompt in
                        promptButton(prompt)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func promptButton(_ prompt: String) -> some View {
        Button(prompt) {
            onSelect(prompt)
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(V2Theme.secondary)
        .lineLimit(1)
        .padding(.horizontal, 13)
        .frame(height: 38)
        .background(V2Theme.ColorRole.surfaceRaised)
        .clipShape(Capsule())
        .overlay {
            Capsule().stroke(V2Theme.line, lineWidth: 1)
        }
        .buttonStyle(.plain)
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

private struct V2PlanInlineDraft: View {
    let draft: V2PlanDraft
    let onSave: () -> Void
    let onContinue: () -> Void
    let onAccept: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(V2Theme.violet)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(draft.title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(V2Theme.ink)
                    Text(draft.summary)
                        .font(.system(size: 13, weight: .medium))
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
                        V2PlanDraftRow(item: item)
                        if index < draft.scheduleItems.count - 1 {
                            Divider()
                                .overlay(V2Theme.line)
                        }
                    }
                }

                HStack(spacing: 10) {
                    Button("存草稿", action: onSave)
                        .foregroundStyle(V2Theme.tertiary)

                    Spacer(minLength: 8)

                    Button("继续聊", action: onContinue)
                        .foregroundStyle(V2Theme.ink)

                    Button("加入计划", action: onAccept)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 42)
                        .background(V2Theme.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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

    var body: some View {
        HStack(spacing: 10) {
            Text(Self.weekdayFormatter.string(from: item.date))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(V2Theme.tertiary)
                .frame(width: 44, alignment: .leading)

            Text(item.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(V2Theme.ink)
                .lineLimit(2)

            Spacer(minLength: 8)

            Text(timeLabel)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(V2Theme.tertiary)
                .monospacedDigit()
        }
        .frame(minHeight: 44)
    }

    private var timeLabel: String {
        guard let startAt = item.startAt else { return "待定" }
        let hour = Calendar.current.component(.hour, from: startAt)
        return hour < 12 ? "上午" : Self.timeFormatter.string(from: startAt)
    }

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "EEE"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

private struct V2PlanComposer: View {
    @Binding var scope: String?
    @Binding var promptText: String
    let placeholder: String
    var isFocused: FocusState<Bool>.Binding
    let isBusy: Bool
    let onSend: () -> Void

    private let scopes = ["今天", "明天", "近三日", "本周", "本月"]

    private var canSend: Bool {
        !isBusy && !promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 9) {
            Menu {
                Button("不指定") { scope = nil }
                ForEach(scopes, id: \.self) { item in
                    Button(item) { scope = item }
                }
            } label: {
                HStack(spacing: 3) {
                    Text(scope ?? "选项")
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(V2Theme.secondary)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(V2Theme.panel)
                .clipShape(Capsule())
                .overlay {
                    Capsule().stroke(V2Theme.line, lineWidth: 1)
                }
            }

            TextField(placeholder, text: $promptText, axis: .vertical)
                .lineLimit(1...4)
                .font(.system(size: 15))
                .focused(isFocused)
                .disabled(isBusy)
                .padding(.vertical, 8)

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

private struct V2PlanHistorySheet: View {
    let drafts: [V2PlanDraftRecord]
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
                        VStack(alignment: .leading, spacing: 5) {
                            Text(draft.userPrompt)
                                .font(.headline)
                            Text(draft.summary)
                                .font(.subheadline)
                                .foregroundStyle(V2Theme.secondary)
                                .lineLimit(2)
                            Text(Self.dateFormatter.string(from: draft.updatedAt))
                                .font(.caption)
                                .foregroundStyle(V2Theme.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("草稿历史")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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

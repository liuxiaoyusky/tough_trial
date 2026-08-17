import SwiftUI
import ToughTrialV2Core

struct V2AssistantView: View {
    @ObservedObject var store: V2AssistantStore
    @ObservedObject var appStore: V2AppStore
    let onExit: () -> Void

    @State private var promptText = ""
    @State private var showSessions = false
    @State private var showSettings = false
    @State private var showDetails = false
    @State private var editingPlanItem: V2AssistantPlanItemEditorContext?
    @FocusState private var isComposerFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(V2Theme.line.opacity(0.7))
            content
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if store.providerStatus.isConfigured {
                V2AssistantComposer(
                    text: $promptText,
                    isFocused: $isComposerFocused,
                    isBusy: store.isRunningTurn,
                    onSend: sendPrompt,
                    onCancel: store.cancelCurrentTurn
                )
            }
        }
        .sheet(isPresented: $showSessions) {
            V2AssistantSessionListView(store: store)
        }
        .sheet(isPresented: $showSettings) {
            V2AIProviderSettingsView(store: appStore)
        }
        .sheet(isPresented: $showDetails) {
            if let session = store.selectedSession {
                V2AssistantSessionDetailView(session: session)
            }
        }
        .sheet(item: $editingPlanItem) { context in
            V2PlanScheduleItemEditor(item: context.item) { updatedItem in
                _ = store.updatePlanItem(updatedItem, in: context.planID)
            }
        }
        .v2ScreenBackground()
        .interactiveDismissDisabled()
    }

    private var header: some View {
        HStack(spacing: 4) {
            V2AssistantHeaderButton(systemName: "xmark", action: onExit)
                .accessibilityLabel("退出助手")
                .accessibilityIdentifier("assistant.exit")

            V2AssistantHeaderButton(systemName: "line.3.horizontal", action: { showSessions = true })
                .accessibilityLabel("会话列表")
                .accessibilityIdentifier("assistant.sessions")

            VStack(spacing: 1) {
                Text(assistantHeaderTitle)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(V2Theme.ink)
                    .lineLimit(1)
                if store.selectedSession?.messages.isEmpty == true {
                    Text("新会话")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(V2Theme.tertiary)
                }
            }
            .frame(maxWidth: .infinity)

            V2AssistantHeaderButton(systemName: "plus") {
                store.createSession()
                promptText = ""
            }
            .accessibilityLabel("新建会话")
            .accessibilityIdentifier("assistant.newSession")

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
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(V2Theme.secondary)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("更多操作")
            .accessibilityIdentifier("assistant.more")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(V2Theme.page)
    }

    @ViewBuilder
    private var content: some View {
        if !store.providerStatus.isConfigured {
            V2AssistantConfigurationPrompt(message: store.providerStatus.message) {
                showSettings = true
            }
        } else if let session = store.selectedSession {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if let sourceTask = session.sourceTask {
                            V2AssistantTaskContextRow(sourceTask: sourceTask)
                        }

                        if session.messages.isEmpty {
                            V2AssistantStarterView(onStart: sendStarter)
                                .padding(.top, session.sourceTask == nil ? 74 : 26)
                        } else {
                            ForEach(session.messages) { message in
                                V2AssistantMessageView(
                                    message: message,
                                    session: session,
                                    store: store,
                                    onEditPlanItem: { planID, item in
                                        editingPlanItem = V2AssistantPlanItemEditorContext(
                                            planID: planID,
                                            item: item
                                        )
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 96)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: session.messages) { _, messages in
                    guard let last = messages.last else { return }
                    withAnimation(.snappy(duration: 0.24)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
                .task(id: session.id) {
                    guard let last = session.messages.last else { return }
                    await Task.yield()
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
            .id(session.id)
        }
    }

    private func sendStarter(_ prompt: String) {
        promptText = ""
        isComposerFocused = false
        store.send(prompt)
    }

    private func sendPrompt() {
        let text = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        promptText = ""
        isComposerFocused = false
        store.send(text)
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
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
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
        V2AssistantStarter(title: "随便聊聊", example: "最近有什么烦心事？", prompt: "随便聊聊", icon: "quote.bubble.fill", color: V2Theme.ink, identifier: "chat"),
        V2AssistantStarter(title: "搜索网页", example: "查一下香港周末天气", prompt: "搜索网页", icon: "globe.asia.australia.fill", color: V2Theme.mint, identifier: "web"),
        V2AssistantStarter(title: "查找我的资料", example: "找之前记录的计划", prompt: "查找我的资料", icon: "doc.text.magnifyingglass", color: V2Theme.violet, identifier: "local"),
        V2AssistantStarter(title: "帮我安排计划", example: "把近期任务排一下", prompt: "帮我安排计划", icon: "calendar.badge.clock", color: V2Theme.orange, identifier: "plan")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("A")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(V2Theme.ink)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(.bottom, 16)

            Text("想一起处理什么？")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(V2Theme.ink)
                .padding(.bottom, 7)

            Text("直接说就好。我会在需要时自动查找、阅读或整理。")
                .font(V2Theme.TypeRole.bodySmall)
                .foregroundStyle(V2Theme.secondary)
                .padding(.bottom, 20)

            Divider().overlay(V2Theme.line.opacity(0.75))

            ForEach(starters) { starter in
                Button {
                    onStart(starter.prompt)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: starter.icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(starter.color)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(starter.title)
                                .font(V2Theme.TypeRole.labelLarge)
                                .foregroundStyle(V2Theme.ink)
                            Text(starter.example)
                                .font(V2Theme.TypeRole.labelSmall)
                                .foregroundStyle(V2Theme.tertiary)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(V2Theme.tertiary)
                    }
                    .frame(minHeight: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("assistant.starter.\(starter.identifier)")

                Divider().overlay(V2Theme.line.opacity(0.75))
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
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let isBusy: Bool
    let onSend: () -> Void
    let onCancel: () -> Void

    private var canSend: Bool {
        !isBusy && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(
                "",
                text: $text,
                prompt: Text("问点什么...").foregroundColor(V2Theme.tertiary),
                axis: .vertical
            )
            .lineLimit(1...4)
            .font(.system(size: 15))
            .foregroundStyle(V2Theme.ink)
            .tint(V2Theme.blue)
            .focused(isFocused)
            .disabled(isBusy)
            .padding(.vertical, 8)
            .accessibilityIdentifier("assistant.composer")

            Button(action: isBusy ? onCancel : onSend) {
                Image(systemName: isBusy ? "stop.fill" : "arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(isBusy || canSend ? V2Theme.blue : V2Theme.tertiary)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!isBusy && !canSend)
            .accessibilityLabel(isBusy ? "停止" : "发送")
            .accessibilityIdentifier(isBusy ? "assistant.cancel" : "assistant.send")
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(V2Theme.ColorRole.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(V2Theme.line, lineWidth: 1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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

import SwiftUI
import ToughTrialV2Core

struct V2PlanAgentView: View {
    @ObservedObject var store: V2AppStore
    @State private var promptText = ""
    @State private var selectedRange = "今天"
    @FocusState private var isComposerFocused: Bool

    private let ranges = ["今天", "三日", "本周", "本月"]

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        V2PlanOpeningPrompt()

                        ForEach(store.state.planMessages, id: \.id) { message in
                            V2PlanMessageBubble(message: message)
                                .id(message.id)
                        }

                        if let draft = store.state.currentPlanDraft {
                            V2PlanDraftCard(
                                draft: draft,
                                onContinue: {
                                    isComposerFocused = true
                                },
                                onSave: {
                                    store.state.saveCurrentPlanDraft()
                                },
                                onAccept: {
                                    store.state.acceptCurrentPlanDraft()
                                }
                            )
                            .id("current-draft")
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                    .padding(.bottom, 18)
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
                ranges: ranges,
                selectedRange: $selectedRange,
                promptText: $promptText,
                isFocused: $isComposerFocused,
                onSend: sendPrompt
            )
        }
        .v2ScreenBackground()
    }

    private var header: some View {
        HStack(spacing: 12) {
            V2IconButton(systemName: "xmark") {
                store.closePlanAgent()
            }
            .accessibilityLabel("关闭计划")

            VStack(alignment: .leading, spacing: 2) {
                Text("计划 Agent")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(V2Theme.ink)
                Text("草稿 \(store.state.savedPlanDrafts.count)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(V2Theme.tertiary)
            }

            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(V2Theme.page)
    }

    private func sendPrompt() {
        let trimmed = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        store.state.sendPlanPrompt("\(selectedRange)：\(trimmed)")
        promptText = ""
        isComposerFocused = false
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.snappy(duration: 0.25)) {
            if store.state.currentPlanDraft != nil {
                proxy.scrollTo("current-draft", anchor: .bottom)
            } else if let last = store.state.planMessages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}

private struct V2PlanOpeningPrompt: View {
    private let examples = ["这周想跑 10 公里", "明天安排得轻一点", "这几天想推进论文"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("想怎么安排？")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(V2Theme.ink)

            Text("直接说目标、时间感或限制，我会先整理成草稿。")
                .font(.system(size: 15))
                .foregroundStyle(V2Theme.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(examples, id: \.self) { example in
                        Text(example)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(V2Theme.secondary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .background(V2Theme.panel)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(V2Theme.line, lineWidth: 1)
                            )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
    }
}

private struct V2PlanMessageBubble: View {
    let message: V2PlanMessage

    private var isUser: Bool {
        message.role == .user
    }

    var body: some View {
        HStack(alignment: .bottom) {
            if isUser {
                Spacer(minLength: 48)
            }

            Text(message.text)
                .font(.system(size: 15))
                .foregroundStyle(isUser ? .white : V2Theme.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(isUser ? V2Theme.ink : V2Theme.panel)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isUser ? Color.clear : V2Theme.line, lineWidth: 1)
                )

            if !isUser {
                Spacer(minLength: 48)
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }
}

private struct V2PlanDraftCard: View {
    let draft: V2PlanDraft
    let onContinue: () -> Void
    let onSave: () -> Void
    let onAccept: () -> Void

    var body: some View {
        V2Panel(padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "doc.text.sparkle")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(V2Theme.violet)
                        .frame(width: 28, height: 28)
                        .background(V2Theme.violet.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(draft.title)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(V2Theme.ink)
                        Text(draft.summary)
                            .font(.system(size: 14))
                            .foregroundStyle(V2Theme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                V2DraftSection(title: "决策", items: draft.decisions, systemName: "checkmark.circle")
                V2DraftSection(title: "安排", items: draft.scheduleItems, systemName: "calendar")

                HStack(spacing: 10) {
                    Button("继续聊", action: onContinue)
                        .buttonStyle(V2PlanSecondaryButtonStyle())

                    Button("存草稿", action: onSave)
                        .buttonStyle(V2PlanSecondaryButtonStyle())

                    Button("接受", action: onAccept)
                        .buttonStyle(V2PlanPrimaryButtonStyle())
                }
                .padding(.top, 2)
            }
        }
    }
}

private struct V2DraftSection: View {
    let title: String
    let items: [String]
    let systemName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(V2Theme.tertiary)

            VStack(alignment: .leading, spacing: 7) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(V2Theme.mint)
                            .frame(width: 5, height: 5)
                            .padding(.top, 7)

                        Text(item)
                            .font(.system(size: 14))
                            .foregroundStyle(V2Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

private struct V2PlanComposer: View {
    let ranges: [String]
    @Binding var selectedRange: String
    @Binding var promptText: String
    var isFocused: FocusState<Bool>.Binding
    let onSend: () -> Void

    private var canSend: Bool {
        !promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 12) {
            V2SegmentedPicker(items: ranges, selection: $selectedRange)

            HStack(alignment: .bottom, spacing: 10) {
                TextField("说说你想安排什么", text: $promptText, axis: .vertical)
                    .lineLimit(1...4)
                    .font(.system(size: 16))
                    .focused(isFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(V2Theme.page)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Button(action: onSend) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(canSend ? V2Theme.ink : V2Theme.tertiary)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .accessibilityLabel("发送")
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(
            V2Theme.panel
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(V2Theme.line)
                        .frame(height: 1)
                }
        )
    }
}

private struct V2PlanPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(V2Theme.ink.opacity(configuration.isPressed ? 0.82 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct V2PlanSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(V2Theme.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(V2Theme.page.opacity(configuration.isPressed ? 0.72 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(V2Theme.line, lineWidth: 1)
            )
    }
}

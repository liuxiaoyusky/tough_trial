import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif
import ToughTrialV2Core

struct V2AssistantSessionListView: View {
    @ObservedObject var store: V2AssistantStore
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(V2Theme.tertiary)
                    TextField("搜索会话", text: $searchText)
                        .font(.system(size: 14))
                        .v2Autocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("assistant.sessions.search")
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(V2Theme.tertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("清除搜索")
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 42)
                .background(V2Theme.ColorRole.surfaceRaised)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(V2Theme.line, lineWidth: 1)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                if filteredSessions.isEmpty {
                    ContentUnavailableView(
                        "没有找到会话",
                        systemImage: "text.magnifyingglass",
                        description: Text("换一个关键词试试。")
                    )
                } else {
                    List {
                        ForEach(groupedSessions, id: \.title) { group in
                            Section(group.title) {
                                ForEach(group.sessions) { session in
                                    Button {
                                        _ = store.selectSession(id: session.id)
                                        dismiss()
                                    } label: {
                                        V2AssistantSessionRow(
                                            session: session,
                                            isSelected: session.id == store.workspace.selectedSessionID
                                        )
                                        .accessibilityElement(children: .ignore)
                                        .accessibilityLabel(session.title)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("assistant.session.\(session.id)")
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        if store.workspace.sessions.count > 1 && !store.isRunningTurn {
                                            Button("删除", role: .destructive) {
                                                _ = store.deleteSession(id: session.id)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .v2GroupedList()
                    .scrollContentBackground(.hidden)
                    .background(V2Theme.page)
                }
            }
            .background(V2Theme.page)
            .navigationTitle("会话")
            .v2InlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        store.createSession()
                        dismiss()
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .disabled(store.storageState != .healthy)
                    .accessibilityLabel("新建会话")
                    .accessibilityIdentifier("assistant.sessions.new")
                }
            }
        }
        .presentationDetents([.large])
    }

    private var filteredSessions: [V2AgentSession] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.workspace.sessions
            .filter { session in
                query.isEmpty
                    || session.title.localizedCaseInsensitiveContains(query)
                    || session.messages.contains { $0.plainText.localizedCaseInsensitiveContains(query) }
            }
            .sorted {
                if $0.updatedAt == $1.updatedAt { return $0.id < $1.id }
                return $0.updatedAt > $1.updatedAt
            }
    }

    private var groupedSessions: [V2AssistantSessionGroup] {
        let calendar = Calendar.current
        let today = Date()
        let todaySessions = filteredSessions.filter { calendar.isDate($0.updatedAt, inSameDayAs: today) }
        let earlierSessions = filteredSessions.filter { !calendar.isDate($0.updatedAt, inSameDayAs: today) }
        return [
            V2AssistantSessionGroup(title: "今天", sessions: todaySessions),
            V2AssistantSessionGroup(title: "更早", sessions: earlierSessions)
        ].filter { !$0.sessions.isEmpty }
    }
}

private struct V2AssistantSessionGroup {
    let title: String
    let sessions: [V2AgentSession]
}

private struct V2AssistantSessionRow: View {
    let session: V2AgentSession
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(isSelected ? V2Theme.blue : Color.clear)
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 3) {
                Text(session.title)
                    .font(V2Theme.TypeRole.labelLarge)
                    .foregroundStyle(V2Theme.ink)
                    .lineLimit(1)
                Text(summary)
                    .font(V2Theme.TypeRole.labelSmall)
                    .foregroundStyle(V2Theme.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)
            Text(session.updatedAt, style: .time)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(V2Theme.tertiary)
        }
        .frame(minHeight: 50)
        .contentShape(Rectangle())
    }

    private var summary: String {
        if let task = session.sourceTask { return "来自任务：\(task.title)" }
        return session.messages.last(where: { !$0.plainText.isEmpty })?.plainText ?? "还没有消息"
    }
}

struct V2AssistantMessageView: View {
    let message: V2AgentMessage
    let session: V2AgentSession
    @ObservedObject var store: V2AssistantStore
    @ObservedObject var browserRegistry: V2AssistantBrowserRegistry
    let availableHeight: CGFloat
    let onPresentFullscreen: (V2AssistantBrowserPresentation) -> Void
    var onQuote: (V2AgentMessage, String) -> Void = { _, _ in }
    var onJumpToReference: (V2AssistantMessageReference) -> Void = { _ in }
    var onOpenAttachment: (V2AssistantAttachment) -> Void = { _ in }
    let onEditPlanItem: (String, V2PlanDraftScheduleItem) -> Void
    var onEditTask: (V2AgentScheduleCard, V2AssistantTaskPreview) -> Void = { _, _ in }
    @State private var showSelection = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(message.references ?? []) { reference in
                Button { onJumpToReference(reference) } label: {
                    Label(reference.excerpt, systemImage: "quote.opening").font(.caption).lineLimit(3)
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(V2Theme.panel, in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain).accessibilityIdentifier("assistant.message.reference")
            }
            ForEach(message.attachments ?? []) { attachment in
                Button { onOpenAttachment(attachment) } label: { Label(attachment.fileName, systemImage: "paperclip").font(.caption) }
            }
            messageContent
            if !message.plainText.isEmpty && message.status != .pending && message.status != .streaming {
                HStack(spacing: 20) {
                    Button { V2Platform.copy(message.plainText) } label: { Label("复制", systemImage: "doc.on.doc") }
                        .accessibilityIdentifier("assistant.message.copy")
                    Button { onQuote(message, message.plainText) } label: { Label("引用", systemImage: "quote.opening") }
                        .accessibilityIdentifier("assistant.message.quote")
                    Button("选择文字") { showSelection = true }
                        .accessibilityIdentifier("assistant.message.select")
                }.font(.caption).foregroundStyle(V2Theme.secondary)
            }
        }
        .contextMenu {
            Button("复制") { V2Platform.copy(message.plainText) }
            Button("引用") { onQuote(message, message.plainText) }
            Button("选择文字") { showSelection = true }
        }
        .v2Sheet(isPresented: $showSelection) {
            V2AssistantMessageSelection(text: message.plainText) { excerpt in
                onQuote(message, excerpt); showSelection = false
            }
        }
    }

    @ViewBuilder
    private var messageContent: some View {
        if message.role == .user {
            HStack {
                Spacer(minLength: 42)
                Text(message.plainText)
                    .textSelection(.enabled)
                    .font(V2Theme.TypeRole.bodyMedium)
                    .lineSpacing(4)
                    .foregroundStyle(V2Theme.ink)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(V2Theme.ColorRole.primaryContainer.opacity(0.65))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Label("助手", systemImage: "sparkles")
                    .font(V2Theme.TypeRole.labelMedium)
                    .foregroundStyle(V2Theme.blue)
                    .padding(.top, 4)

                ForEach(Array(message.parts.enumerated()), id: \.offset) { _, part in
                    partView(part)
                }

                if message.status == .pending || message.status == .streaming {
                    HStack(spacing: 12) {
                        ProgressView()
                            .tint(V2Theme.blue)
                            .frame(width: 40, height: 40)
                            .background(V2Theme.ColorRole.primaryContainer, in: RoundedRectangle(cornerRadius: 14))
                        VStack(alignment: .leading, spacing: 5) {
                            Text(progressText)
                                .font(V2Theme.TypeRole.labelLarge)
                                .foregroundStyle(V2Theme.ink)
                            Text("可以继续补充想法，或停止本轮")
                                .font(V2Theme.TypeRole.bodySmall)
                                .foregroundStyle(V2Theme.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(V2Theme.ColorRole.surfaceRaised, in: RoundedRectangle(cornerRadius: 22))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(V2Theme.line.opacity(0.65)))
                    .accessibilityIdentifier("assistant.progress")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var progressText: String {
        guard let activity = store.activity, activity.messageID == message.id else { return "正在处理…" }
        switch activity.tool {
        case .model: return "正在理解你的意思…"
        case .schedule: return "正在整理日程…"
        case .plan: return "正在整理计划…"
        case .webSearch: return "正在搜索网页…"
        case .webRead: return "正在阅读网页…"
        case .localSearch: return "正在查找你的资料…"
        case .other: return "正在处理…"
        }
    }

    @ViewBuilder
    private func partView(_ part: V2AgentMessagePart) -> some View {
        switch part {
        case let .text(text):
            Text(text)
                .textSelection(.enabled)
                .font(V2Theme.TypeRole.bodyMedium)
                .lineSpacing(5)
                .foregroundStyle(V2Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        case let .trace(summary):
            if summary.toolCount > 0, matchingTrace?.steps.contains(where: { $0.tool != .model }) == true {
                V2AssistantTraceDisclosure(
                    summary: summary,
                    trace: matchingTrace,
                    identifier: message.id
                )
            }
        case let .sources(sources):
            V2AssistantSourcesView(
                sources: sources,
                session: session,
                store: store,
                browserRegistry: browserRegistry,
                availableHeight: availableHeight,
                onPresentFullscreen: onPresentFullscreen
            )
        case let .schedule(card):
            V2AssistantScheduleCardView(card: card, store: store) { onEditTask(card, $0) }
        case let .tool(result):
            V2AssistantToolResultCard(result: result, store: store)
        case let .plan(draft):
            V2PlanInlineDraft(
                draft: draft,
                isAccepted: store.isPlanAccepted(draft),
                onEdit: { onEditPlanItem(draft.id, $0) },
                onAccept: { store.acceptPlan(draft) }
            )
        case let .error(error):
            V2AssistantErrorView(
                error: error,
                canRetry: (message.status == .failed || message.status == .cancelled) && !store.isRunningTurn,
                isCancelled: message.status == .cancelled,
                onRetry: { store.retry(messageID: message.id) }
            )
        }
    }

    private var matchingTrace: V2AgentTrace? {
        session.traces.min { lhs, rhs in
            abs(lhs.startedAt.timeIntervalSince(message.createdAt))
                < abs(rhs.startedAt.timeIntervalSince(message.createdAt))
        }
    }
}

private struct V2AssistantTraceDisclosure: View {
    let summary: V2AgentTraceSummary
    let trace: V2AgentTrace?
    let identifier: String
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.snappy(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: statusIcon)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(statusColor)
                    Text(summary.displayText)
                        .font(V2Theme.TypeRole.labelMedium)
                        .foregroundStyle(V2Theme.secondary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(V2Theme.tertiary)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("assistant.trace.\(identifier)")

            if isExpanded, let trace {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(trace.steps) { step in
                        V2AssistantTraceStepRow(step: step)
                    }
                }
                .padding(.leading, 4)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .background(V2Theme.ColorRole.surfaceMuted, in: RoundedRectangle(cornerRadius: 18))
    }

    private var statusIcon: String {
        switch summary.status {
        case .succeeded: "checkmark.circle.fill"
        case .running: "clock.fill"
        case .failed: "exclamationmark.circle.fill"
        case .cancelled: "stop.circle.fill"
        }
    }

    private var statusColor: Color {
        switch summary.status {
        case .succeeded: V2Theme.mint
        case .running: V2Theme.blue
        case .failed, .cancelled: V2Theme.orange
        }
    }
}

private struct V2AssistantTraceStepRow: View {
    let step: V2AgentTraceStep

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(step.status == .succeeded ? V2Theme.mint : step.status == .running ? V2Theme.blue : V2Theme.orange)
                .frame(width: 7, height: 7)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 2) {
                Text(step.tool.assistantTitle)
                    .font(V2Theme.TypeRole.labelMedium)
                    .foregroundStyle(V2Theme.ink)
                if let subject = step.subject {
                    Text(subject.assistantDisplayText)
                        .font(V2Theme.TypeRole.labelSmall)
                        .foregroundStyle(V2Theme.tertiary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            Text(step.duration.assistantDuration)
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(V2Theme.tertiary)
        }
        .padding(.vertical, 7)
    }
}

private struct V2AssistantSourcesView: View {
    let sources: [V2WebSource]
    let session: V2AgentSession
    @ObservedObject var store: V2AssistantStore
    @ObservedObject var browserRegistry: V2AssistantBrowserRegistry
    let availableHeight: CGFloat
    let onPresentFullscreen: (V2AssistantBrowserPresentation) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("参考来源", systemImage: "link")
                .font(V2Theme.TypeRole.labelMedium)
                .foregroundStyle(V2Theme.secondary)
                .padding(.bottom, 2)
            ForEach(sources) { source in
                Button {
                    _ = store.toggleBrowser(source: source, sessionID: session.id)
                } label: {
                    HStack(spacing: 11) {
                        Image(systemName: "chart.bar.doc.horizontal.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(V2Theme.blue)
                            .frame(width: 36, height: 36)
                            .background(V2Theme.ColorRole.primaryContainer)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(source.title)
                                .font(V2Theme.TypeRole.labelMedium)
                                .foregroundStyle(V2Theme.ink)
                                .lineLimit(2)
                            Text(source.siteName ?? source.url.host ?? source.url.absoluteString)
                                .font(V2Theme.TypeRole.labelSmall)
                                .foregroundStyle(V2Theme.tertiary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Image(
                            systemName: isExpanded(source)
                                ? "chevron.up"
                                : "chevron.down"
                        )
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(V2Theme.blue)
                    }
                    .frame(minHeight: 50)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(source.title)
                .accessibilityIdentifier("assistant.source.\(source.id)")

                if let browser = browserState(for: source), browser.isExpanded, !browser.isFullscreen {
                    V2AssistantInlineBrowser(
                        store: store,
                        registry: browserRegistry,
                        sessionID: session.id,
                        source: source,
                        state: browser,
                        availableHeight: availableHeight,
                        onFullscreen: onPresentFullscreen
                    )
                }

            }
        }
        .padding(14)
        .background(V2Theme.ColorRole.surfaceRaised, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(V2Theme.line.opacity(0.65)))
    }

    private func browserState(for source: V2WebSource) -> V2BrowserSessionState? {
        session.browserSessions.first { $0.sourceID == source.id }
    }

    private func isExpanded(_ source: V2WebSource) -> Bool {
        browserState(for: source)?.isExpanded == true
    }
}

private struct V2AssistantToolResultCard: View {
    let result: V2ToolExecutionResult
    @ObservedObject var store: V2AssistantStore

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 9) {
                Image(systemName: iconName)
                    .foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(V2Theme.TypeRole.labelLarge)
                        .foregroundStyle(V2Theme.ink)
                    Text(statusText)
                        .font(V2Theme.TypeRole.labelSmall)
                        .foregroundStyle(V2Theme.secondary)
                }
                Spacer(minLength: 8)
            }
            Text(result.summary)
                .font(V2Theme.TypeRole.bodySmall)
                .foregroundStyle(V2Theme.ink)
                .fixedSize(horizontal: false, vertical: true)

            if result.state == .pendingConfirmation {
                Button("确认执行") { store.confirmTool(result) }
                    .buttonStyle(.borderedProminent)
                    .tint(V2Theme.blue)
                    .accessibilityIdentifier("assistant.tool.confirm.\(result.operationID)")
            } else if [.failed, .conflict, .blocked].contains(result.state), result.argumentsJSON != nil {
                Button("重试") { store.retryTool(result) }
                    .buttonStyle(.bordered)
                    .tint(V2Theme.blue)
                    .accessibilityIdentifier("assistant.tool.retry.\(result.operationID)")
            } else if result.canUndo {
                Button("撤销这次修改") { store.undoTool(result) }
                    .buttonStyle(.bordered)
                    .tint(V2Theme.orange)
                    .accessibilityIdentifier("assistant.tool.undo.\(result.operationID)")
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(V2Theme.ColorRole.surfaceRaised, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(accent.opacity(0.35)))
    }

    private var title: String {
        switch result.toolID {
        case "core.tasks.create": return "任务"
        case "core.tasks.schedule": return "日程修改"
        case "core.tasks.query": return "任务查询"
        case "core.ledger.createPending": return "账单记录"
        case "core.ledger.proposeCategory": return "账单分类建议"
        case "core.finance.createPlan": return "财务计划"
        case "core.finance.markPaid": return "付款确认"
        case "core.budget.set": return "预算设置"
        case "core.budget.queryProgress": return "预算进度"
        case "core.recall.append": return "当天回响"
        case "core.capture.create": return "随手记"
        case "core.notes.create": return "灵感记录"
        default: return "AI 工具结果"
        }
    }

    private var statusText: String {
        switch result.state {
        case .applied: return "已执行"
        case .pendingConfirmation: return "等待你的确认"
        case .needsInformation: return "还需要补充信息"
        case .blocked: return "当前功能不可用"
        case .conflict: return "数据发生变化，需要重新确认"
        case .failed: return "执行失败，可重试"
        case .cancelled: return "已取消"
        case .undone: return "已撤销"
        }
    }

    private var iconName: String {
        switch result.state {
        case .applied: return "checkmark.circle.fill"
        case .pendingConfirmation: return "hand.raised.fill"
        case .needsInformation: return "questionmark.circle.fill"
        case .blocked, .conflict, .failed: return "exclamationmark.circle.fill"
        case .cancelled: return "stop.circle.fill"
        case .undone: return "arrow.uturn.backward.circle.fill"
        }
    }

    private var accent: Color {
        switch result.state {
        case .applied: return V2Theme.mint
        case .pendingConfirmation, .needsInformation: return V2Theme.blue
        case .blocked, .conflict, .failed: return V2Theme.orange
        case .cancelled, .undone: return V2Theme.secondary
        }
    }
}

private struct V2AssistantErrorView: View {
    let error: V2AgentMessageError
    let canRetry: Bool
    let isCancelled: Bool
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(isCancelled ? "已停止处理" : "没有收到可用回复",
                  systemImage: isCancelled ? "stop.circle" : "exclamationmark.circle")
                .font(V2Theme.TypeRole.labelLarge)
                .foregroundStyle(V2Theme.ink)
            Text(error.message)
                .font(V2Theme.TypeRole.bodySmall)
                .foregroundStyle(V2Theme.secondary)
            if canRetry {
                Button("重试", action: onRetry)
                    .font(V2Theme.TypeRole.labelMedium)
                    .buttonStyle(.bordered)
                    .tint(V2Theme.blue)
                    .controlSize(.regular)
                    .accessibilityIdentifier("assistant.retry")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isCancelled ? V2Theme.ColorRole.surfaceMuted : V2Theme.ColorRole.taskPausedContainer,
                    in: RoundedRectangle(cornerRadius: 22))
    }
}

struct V2AssistantSessionDetailView: View {
    let session: V2AgentSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("会话") {
                    V2AssistantDetailValue(label: "标题", value: session.title)
                    V2AssistantDetailValue(label: "会话 ID", value: session.id)
                    if let task = session.sourceTask {
                        V2AssistantDetailValue(label: "来源任务", value: task.title)
                    }
                }

                if let provider = session.providerState {
                    Section("AI 服务") {
                        V2AssistantDetailValue(label: "提供商", value: provider.providerLabel)
                        V2AssistantDetailValue(label: "模型", value: provider.model)
                        if let conversationID = provider.remoteConversationID {
                            V2AssistantDetailValue(label: "远端会话", value: conversationID)
                        }
                        if let responseID = provider.remoteResponseID {
                            V2AssistantDetailValue(label: "最近响应", value: responseID)
                        }
                    }
                }

                ForEach(Array(session.traces.enumerated()), id: \.element.id) { index, trace in
                    Section("Trace \(index + 1)") {
                        V2AssistantDetailValue(label: "状态", value: trace.status.assistantTitle)
                        if let provider = trace.providerLabel {
                            V2AssistantDetailValue(label: "提供商", value: provider)
                        }
                        if let model = trace.model {
                            V2AssistantDetailValue(label: "模型", value: model)
                        }
                        if let requestID = trace.requestID {
                            V2AssistantDetailValue(label: "请求 ID", value: requestID)
                        }
                        if let responseID = trace.responseID {
                            V2AssistantDetailValue(label: "响应 ID", value: responseID)
                        }
                        if let sessionID = trace.providerSessionID {
                            V2AssistantDetailValue(label: "供应商会话", value: sessionID)
                        }
                        if let duration = trace.duration {
                            V2AssistantDetailValue(label: "总耗时", value: duration.assistantDuration)
                        }
                        if let total = trace.totalTokens {
                            V2AssistantDetailValue(
                                label: "Token",
                                value: "总计 \(total) · 输入 \(trace.promptTokens ?? 0) · 输出 \(trace.completionTokens ?? 0)"
                            )
                        }
                        ForEach(Array(trace.steps.enumerated()), id: \.element.id) { stepIndex, step in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(stepIndex + 1). \(step.tool.assistantTitle) · \(step.status.assistantTitle)")
                                    .font(V2Theme.TypeRole.labelMedium)
                                    .foregroundStyle(V2Theme.ink)
                                HStack {
                                    if let subject = step.subject {
                                        Text(subject.assistantDisplayText)
                                            .lineLimit(3)
                                    }
                                    Spacer()
                                    Text(step.duration.assistantDuration)
                                        .monospacedDigit()
                                }
                                .font(V2Theme.TypeRole.labelSmall)
                                .foregroundStyle(V2Theme.tertiary)
                                if let error = step.error {
                                    Text("\(error.category.rawValue) · \(error.code.rawValue)")
                                        .font(V2Theme.TypeRole.labelSmall)
                                        .foregroundStyle(V2Theme.orange)
                                }
                            }
                            .accessibilityIdentifier("assistant.trace.detail.\(trace.id).\(stepIndex)")
                        }
                    }
                }
            }
            .navigationTitle("会话详情")
            .v2InlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct V2AssistantDetailValue: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(V2Theme.TypeRole.labelSmall)
                .foregroundStyle(V2Theme.tertiary)
            Text(V2AssistantStore.redactCredentials(in: value))
                .font(V2Theme.TypeRole.bodySmall)
                .foregroundStyle(V2Theme.ink)
                .textSelection(.enabled)
        }
    }
}

private extension V2AgentTool {
    var assistantTitle: String {
        switch self {
        case .model: "生成回复"
        case .webSearch: "搜索网页"
        case .webRead: "读取网页"
        case .localSearch: "查找资料"
        case .plan: "整理计划"
        case .schedule: "修改日程"
        case .other: "执行工具"
        }
    }
}

private extension V2AgentTraceStatus {
    var assistantTitle: String {
        switch self {
        case .running: "进行中"
        case .succeeded: "完成"
        case .failed: "失败"
        case .cancelled: "已取消"
        }
    }
}

private extension V2AgentTraceSubject {
    var assistantDisplayText: String {
        switch self {
        case let .searchQuery(query): "查询：\(query.displayText)"
        case let .sourceURL(url): "来源：\(url.displayText)"
        case .sourceID: "已读取来源"
        case let .localScope(scope):
            switch scope {
            case .tasks: "任务记录"
            case .plans: "计划记录"
            case .memory: "个人资料"
            case .mixed: "任务、计划与个人资料"
            }
        case .planArtifact: "已生成计划草稿"
        }
    }
}

private extension TimeInterval {
    var assistantDuration: String {
        String(format: "%.1f 秒", max(0, self))
    }
}

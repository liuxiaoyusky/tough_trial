import SwiftUI
import ToughTrialV2Core
import UIKit

struct V2TodayView: View {
    @ObservedObject var store: V2AppStore
    @StateObject private var speech = V2SpeechTranscriber()
    @State private var isQuickAddPresented = false
    @State private var quickAddTitle = ""
    @State private var speechPrefix = ""
    @State private var isFocusExpanded = true
    @State private var isZenTaskPickerPresented = false
    @State private var zenTaskSearchText = ""
    @State private var pendingZenStart: V2PendingZenStart?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                V2TodayBackground()

                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture {
                        collapseFocus()
                    }

                VStack(alignment: .leading, spacing: 16) {
                    V2TodayHeader {
                        Task {
                            await store.enablePlanReminders()
                        }
                    }

                    V2TodayFocusCanvas(
                        sessions: store.state.activeSessions,
                        isExpanded: isFocusExpanded,
                        onFocus: focusSession,
                        onExpand: expandFocus,
                        onToggle: { store.toggleSession($0.id) },
                        onEnd: endSession,
                        onStartUnlinkedZen: startUnlinkedZen,
                        onChooseZenTask: presentZenTaskPicker,
                        onZen: {
                            store.startZen(
                                planItemID: $0.planItemID,
                                taskID: $0.taskID,
                                title: $0.title
                            )
                        }
                    )

                    V2TodayFlowStrip(
                        items: store.state.timelineItems,
                        selectedItemID: store.state.selectedTimelineItemID,
                        focusedTaskID: store.state.activeSessions.first?.taskID,
                        onSelect: selectTimelineItem,
                        onStart: startTimelineItem,
                        onComplete: completeTimelineItem,
                        onRestore: restoreTimelineItem,
                        onZen: {
                            store.startZen(
                                planItemID: $0.planItemID,
                                taskID: $0.taskID,
                                title: $0.title
                            )
                        }
                    )
                    .frame(maxHeight: .infinity)
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)

                V2TodayCaptureButton(
                    onTap: {
                        isQuickAddPresented = true
                    },
                    onVoiceStart: beginVoiceQuickAdd,
                    onVoiceLock: {
                        isQuickAddPresented = true
                    },
                    onVoiceEnd: {
                        speech.stop()
                        isQuickAddPresented = true
                    }
                )
                .frame(width: 60, height: 60)
                .shadow(color: V2Theme.ColorRole.primary.opacity(0.24), radius: 18, y: 10)
                .padding(.trailing, 24)
                .padding(.bottom, 78)
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $isQuickAddPresented) {
                V2TodayQuickAddSheet(
                    title: $quickAddTitle,
                    isListening: speech.isListening,
                    onMic: toggleQuickAddSpeech,
                    onCancel: dismissQuickAdd,
                    onSubmit: submitQuickAdd
                )
                .presentationDetents([.height(184)])
                .presentationDragIndicator(.visible)
            }
            .sheet(
                isPresented: $isZenTaskPickerPresented,
                onDismiss: startPendingZen
            ) {
                V2TodayZenTaskPicker(
                    tasks: zenSelectableTasks,
                    searchText: $zenTaskSearchText,
                    onSelect: { queueZenStart(.task($0)) },
                    onStartUnlinked: { queueZenStart(.unlinked) },
                    onCancel: dismissZenTaskPicker
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .alert("操作未完成", isPresented: errorBinding) {
                Button("知道了") {
                    store.dismissError()
                }
            } message: {
                Text(store.errorMessage ?? "请稍后再试。")
            }
            .alert("计划提醒", isPresented: noticeBinding) {
                Button("知道了") {
                    store.dismissNotice()
                }
            } message: {
                Text(store.noticeMessage ?? "")
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
                quickAddTitle = speechPrefix.isEmpty
                    ? transcript
                    : "\(speechPrefix) \(transcript)"
            }
            .onDisappear {
                speech.stop()
            }
        }
    }

    private func selectTimelineItem(_ item: V2TimelineItem) {
        store.selectTodayItem(item)
    }

    private func focusSession(_ session: V2ActiveSession) {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            store.focusSession(session.id)
            isFocusExpanded = true
        }
    }

    private func expandFocus() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            isFocusExpanded = true
        }
    }

    private func collapseFocus() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
            isFocusExpanded = false
            store.clearTodaySelection()
        }
    }

    private func startTimelineItem(_ item: V2TimelineItem) {
        store.startTodayItem(item)
    }

    private func completeTimelineItem(_ item: V2TimelineItem) {
        store.completeTodayItem(item)
    }

    private func restoreTimelineItem(_ item: V2TimelineItem) {
        store.restoreTodayItem(item)
    }

    private func endSession(_ session: V2ActiveSession) {
        store.endSession(session.id)
    }

    private var zenSelectableTasks: [V2TaskNode] {
        store.state.flattenTasks().filter { $0.status != .done }
    }

    private func startUnlinkedZen() {
        store.startZen(
            planItemID: nil,
            taskID: nil,
            title: "自由专注"
        )
    }

    private func presentZenTaskPicker() {
        pendingZenStart = nil
        zenTaskSearchText = ""
        isZenTaskPickerPresented = true
    }

    private func queueZenStart(_ start: V2PendingZenStart) {
        pendingZenStart = start
        isZenTaskPickerPresented = false
    }

    private func dismissZenTaskPicker() {
        pendingZenStart = nil
        isZenTaskPickerPresented = false
    }

    private func startPendingZen() {
        defer {
            pendingZenStart = nil
            zenTaskSearchText = ""
        }
        guard let pendingZenStart else { return }

        switch pendingZenStart {
        case .unlinked:
            startUnlinkedZen()
        case .task(let task):
            store.startZen(
                planItemID: nil,
                taskID: task.id,
                title: task.title
            )
        }
    }

    private func submitQuickAdd() {
        let title = quickAddTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        speech.stop()
        if store.quickAddTodayTask(title: title) {
            dismissQuickAdd()
        }
    }

    private func dismissQuickAdd() {
        speech.stop()
        speechPrefix = ""
        quickAddTitle = ""
        isQuickAddPresented = false
    }

    private func beginVoiceQuickAdd() {
        speechPrefix = quickAddTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        speech.toggle()
    }

    private func toggleQuickAddSpeech() {
        if !speech.isListening {
            speechPrefix = quickAddTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        speech.toggle()
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

    private var noticeBinding: Binding<Bool> {
        Binding(
            get: { store.noticeMessage != nil },
            set: { isPresented in
                if !isPresented {
                    store.dismissNotice()
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
}

private struct V2TodayBackground: View {
    var body: some View {
        V2Theme.ColorRole.canvas
            .ignoresSafeArea()
    }
}

private struct V2TodayHeader: View {
    let onEnableReminders: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text("今天")
                    .font(V2Theme.TypeRole.displayLarge)
                    .foregroundStyle(V2Theme.ColorRole.textPrimary)
                    .lineLimit(1)

                Text(Self.dateLabel)
                    .font(V2Theme.TypeRole.labelLarge)
                    .foregroundStyle(V2Theme.ColorRole.textSecondary)
            }

            Spacer()

            Menu {
                Button(action: onEnableReminders) {
                    Label("开启计划提醒", systemImage: "bell")
                }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(V2Theme.TypeRole.titleMedium)
                    .foregroundStyle(V2Theme.ColorRole.textPrimary.opacity(0.82))
                    .frame(width: 46, height: 46)
                    .background(
                        V2Theme.ColorRole.surfaceRaised.opacity(0.92),
                        in: RoundedRectangle(cornerRadius: 19, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 19, style: .continuous)
                            .stroke(V2Theme.ColorRole.outline.opacity(0.46), lineWidth: 1)
                    )
                    .shadow(
                        color: V2Theme.ColorRole.textPrimary.opacity(0.05),
                        radius: 14,
                        y: 7
                    )
            }
            .accessibilityLabel("今天选项")
        }
    }

    private static var dateLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 · EEEE"
        return formatter.string(from: Date())
    }
}

private struct V2TodayFocusCanvas: View {
    let sessions: [V2ActiveSession]
    let isExpanded: Bool
    let onFocus: (V2ActiveSession) -> Void
    let onExpand: () -> Void
    let onToggle: (V2ActiveSession) -> Void
    let onEnd: (V2ActiveSession) -> Void
    let onStartUnlinkedZen: () -> Void
    let onChooseZenTask: () -> Void
    let onZen: (V2ActiveSession) -> Void

    private var primarySession: V2ActiveSession? {
        sessions.first
    }

    private var secondarySessions: [V2ActiveSession] {
        Array(sessions.dropFirst())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if sessions.isEmpty {
                V2TodayEmptyFocus(
                    onStartUnlinkedZen: onStartUnlinkedZen,
                    onChooseZenTask: onChooseZenTask
                )
            } else if isExpanded, let primarySession {
                V2TodayPrimaryFocus(
                    session: primarySession,
                    onToggle: { onToggle(primarySession) },
                    onEnd: { onEnd(primarySession) },
                    onZen: { onZen(primarySession) }
                )
            } else {
                V2TodayCollapsedFocus(
                    sessions: sessions,
                    onFocus: onFocus,
                    onExpand: onExpand
                )
            }

            if isExpanded && !secondarySessions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(secondarySessions, id: \.id) { session in
                            V2TodaySessionPill(session: session) {
                                onFocus(session)
                            }
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }
        }
    }
}

private struct V2TodayPrimaryFocus: View {
    let session: V2ActiveSession
    let onToggle: () -> Void
    let onEnd: () -> Void
    let onZen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(session.status == .running ? "正在发生" : "暂停中")
                    .font(V2Theme.TypeRole.labelMedium)
                    .foregroundStyle(session.status == .running ? V2Theme.ColorRole.taskActive : V2Theme.ColorRole.taskPaused)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(
                        session.status == .running
                            ? V2Theme.ColorRole.taskActiveContainer
                            : V2Theme.ColorRole.taskPausedContainer,
                        in: Capsule()
                    )

                Spacer()

                Text("从 \(session.startedAtLabel)")
                    .font(V2Theme.TypeRole.labelMedium)
                    .monospacedDigit()
                    .foregroundStyle(V2Theme.ColorRole.textSecondary.opacity(0.86))
            }

            HStack(alignment: .bottom, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(session.title)
                        .font(V2Theme.TypeRole.headlineMedium)
                        .foregroundStyle(V2Theme.ColorRole.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.80)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(V2TodayFormat.duration(session.currentElapsedSeconds))
                        .font(V2Theme.TypeRole.timerLarge)
                        .foregroundStyle(V2Theme.ColorRole.textPrimary)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 4) {
                    Text("当前")
                        .font(V2Theme.TypeRole.labelSmall)
                        .foregroundStyle(V2Theme.ColorRole.textTertiary)
                    Text("今日 \(V2TodayFormat.duration(session.totalElapsedSeconds))")
                        .font(V2Theme.TypeRole.timerSmall)
                        .foregroundStyle(V2Theme.ColorRole.textSecondary)
                }
            }

            HStack(spacing: 10) {
                Button(action: onToggle) {
                    Image(systemName: session.status == .running ? "pause.fill" : "play.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(V2Theme.ColorRole.textInverse)
                        .frame(width: 50, height: 42)
                        .background(V2Theme.ColorRole.textPrimary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(session.status == .running ? "暂停" : "继续")

                Button(action: onZen) {
                    Label("Zen", systemImage: "leaf.fill")
                        .font(V2Theme.TypeRole.titleMedium)
                        .foregroundStyle(V2Theme.ColorRole.onPrimaryContainer)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(V2Theme.ColorRole.primaryContainer, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("today.focus.zen")

                Button(action: onEnd) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(V2Theme.ColorRole.textSecondary)
                        .frame(width: 44, height: 42)
                        .background(V2Theme.ColorRole.surfaceMuted.opacity(0.56), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("结束时间段")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 182, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(V2Theme.ColorRole.surfaceRaised.opacity(0.96))
                .shadow(color: V2Theme.ColorRole.textPrimary.opacity(0.06), radius: 28, y: 16)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .stroke(V2Theme.ColorRole.outline.opacity(0.42), lineWidth: 1)
        )
    }
}

private struct V2TodayEmptyFocus: View {
    let onStartUnlinkedZen: () -> Void
    let onChooseZenTask: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "circle.dashed")
                .font(.system(size: 36, weight: .regular))
                .foregroundStyle(V2Theme.ColorRole.textTertiary)

            Text("先开始一件事")
                .font(V2Theme.TypeRole.headlineLarge)
                .foregroundStyle(V2Theme.ColorRole.textPrimary)

            Text("今天页只负责记录今天真实发生的时间。")
                .font(V2Theme.TypeRole.bodyMedium)
                .foregroundStyle(V2Theme.ColorRole.textSecondary)

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                Button(action: onStartUnlinkedZen) {
                    Label("直接开始 Zen", systemImage: "leaf.fill")
                        .font(V2Theme.TypeRole.titleMedium)
                        .foregroundStyle(V2Theme.ColorRole.onPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 46)
                        .background(
                            V2Theme.ColorRole.primary,
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("today.emptyZen.startUnlinked")

                Button(action: onChooseZenTask) {
                    Label("选择任务", systemImage: "magnifyingglass")
                        .font(V2Theme.TypeRole.titleMedium)
                        .foregroundStyle(V2Theme.ColorRole.onPrimaryContainer)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 46)
                        .background(
                            V2Theme.ColorRole.primaryContainer,
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("today.emptyZen.chooseTask")
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 296, alignment: .topLeading)
        .background(V2Theme.ColorRole.surfaceRaised.opacity(0.92), in: RoundedRectangle(cornerRadius: 34, style: .continuous))
    }
}

private struct V2TodayZenTaskPicker: View {
    let tasks: [V2TaskNode]
    @Binding var searchText: String
    let onSelect: (V2TaskNode) -> Void
    let onStartUnlinked: () -> Void
    let onCancel: () -> Void
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(V2Theme.ColorRole.textTertiary)

                    TextField("搜索任务", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(V2Theme.TypeRole.bodyMedium)
                        .foregroundStyle(V2Theme.ColorRole.textPrimary)
                        .focused($isSearchFocused)
                        .submitLabel(.search)
                        .accessibilityIdentifier("today.zenTaskPicker.search")

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(V2Theme.ColorRole.textTertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("清除搜索")
                        .accessibilityIdentifier("today.zenTaskPicker.clearSearch")
                    }
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .background(
                    V2Theme.ColorRole.surfaceMuted,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

                if filteredTasks.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(V2Theme.ColorRole.textTertiary)

                        Text(searchText.isEmpty ? "没有可选择的任务" : "没有找到任务")
                            .font(V2Theme.TypeRole.titleMedium)
                            .foregroundStyle(V2Theme.ColorRole.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("today.zenTaskPicker.empty")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(filteredTasks, id: \.id) { task in
                                Button {
                                    onSelect(task)
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "circle")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(V2Theme.ColorRole.primary)

                                        Text(task.title)
                                            .font(V2Theme.TypeRole.titleMedium)
                                            .foregroundStyle(V2Theme.ColorRole.textPrimary)
                                            .multilineTextAlignment(.leading)
                                            .lineLimit(2)

                                        Spacer(minLength: 12)

                                        Image(systemName: "play.fill")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(V2Theme.ColorRole.primary)
                                    }
                                    .padding(.horizontal, 20)
                                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("开始 \(task.title) 的 Zen")
                                .accessibilityIdentifier("today.zenTaskPicker.task.\(task.id)")

                                Divider()
                                    .padding(.leading, 43)
                            }
                        }
                    }
                }

                Divider()

                Button(action: onStartUnlinked) {
                    Label("不关联任务，直接开始", systemImage: "leaf.fill")
                        .font(V2Theme.TypeRole.titleMedium)
                        .foregroundStyle(V2Theme.ColorRole.onPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                        .background(
                            V2Theme.ColorRole.primary,
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("today.zenTaskPicker.startUnlinked")
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
            .background(V2Theme.ColorRole.canvas)
            .navigationTitle("选择任务")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: onCancel)
                        .accessibilityIdentifier("today.zenTaskPicker.cancel")
                }
            }
            .onAppear {
                isSearchFocused = true
            }
        }
    }

    private var filteredTasks: [V2TaskNode] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return tasks }
        return tasks.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.subtitle.localizedCaseInsensitiveContains(query)
        }
    }
}

private enum V2PendingZenStart {
    case unlinked
    case task(V2TaskNode)
}

private struct V2TodayCollapsedFocus: View {
    let sessions: [V2ActiveSession]
    let onFocus: (V2ActiveSession) -> Void
    let onExpand: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("进行中")
                    .font(V2Theme.TypeRole.labelMedium)
                    .foregroundStyle(V2Theme.ColorRole.textSecondary)

                Spacer()

                Button(action: onExpand) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(V2Theme.ColorRole.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(V2Theme.ColorRole.surfaceMuted.opacity(0.62), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("展开当前任务")
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 9) {
                    ForEach(sessions, id: \.id) { session in
                        V2TodaySessionPill(session: session) {
                            onFocus(session)
                        }
                    }
                }
                .padding(.horizontal, 1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(V2Theme.ColorRole.surfaceRaised.opacity(0.90), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(V2Theme.ColorRole.outline.opacity(0.38), lineWidth: 1)
        )
    }
}

private struct V2TodaySessionPill: View {
    let session: V2ActiveSession
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 9) {
                Image(systemName: session.status == .running ? "play.fill" : "pause.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(session.status == .running ? V2Theme.ColorRole.taskActive : V2Theme.ColorRole.taskPaused)

                Text(session.title)
                    .font(V2Theme.TypeRole.titleMedium)
                    .foregroundStyle(V2Theme.ColorRole.textPrimary.opacity(0.86))
                    .lineLimit(1)

                Text(V2TodayFormat.duration(session.totalElapsedSeconds))
                    .font(V2Theme.TypeRole.timerSmall)
                    .foregroundStyle(V2Theme.ColorRole.textSecondary)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(V2Theme.ColorRole.surfaceRaised.opacity(0.94), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(V2Theme.ColorRole.outline.opacity(0.36), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct V2TodayFlowStrip: View {
    let items: [V2TimelineItem]
    let selectedItemID: String?
    let focusedTaskID: String?
    let onSelect: (V2TimelineItem) -> Void
    let onStart: (V2TimelineItem) -> Void
    let onComplete: (V2TimelineItem) -> Void
    let onRestore: (V2TimelineItem) -> Void
    let onZen: (V2TimelineItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .firstTextBaseline) {
                Text("今天的流")
                    .font(V2Theme.TypeRole.titleLarge)
                    .foregroundStyle(V2Theme.ColorRole.textPrimary.opacity(0.92))

                Spacer()

                Text(Self.currentTime)
                    .font(V2Theme.TypeRole.labelMedium)
                    .monospacedDigit()
                    .foregroundStyle(V2Theme.ColorRole.primary)
            }

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        V2TodayFlowRow(
                            item: item,
                            isSelected: isSelected(item),
                            isFocused: item.taskID == focusedTaskID,
                            isLast: index == items.count - 1,
                            onSelect: { onSelect(item) },
                            onStart: { onStart(item) },
                            onComplete: { onComplete(item) },
                            onRestore: { onRestore(item) },
                            onZen: { onZen(item) }
                        )
                    }
                }
                .padding(.bottom, 118)
            }
        }
    }

    private static var currentTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date())
    }

    private func isSelected(_ item: V2TimelineItem) -> Bool {
        item.kind == .task && item.id == selectedItemID
    }
}

private struct V2TodayFlowRow: View {
    let item: V2TimelineItem
    let isSelected: Bool
    let isFocused: Bool
    let isLast: Bool
    let onSelect: () -> Void
    let onStart: () -> Void
    let onComplete: () -> Void
    let onRestore: () -> Void
    let onZen: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            VStack(spacing: 0) {
                Text(item.timeLabel)
                    .font(V2Theme.TypeRole.labelMedium)
                    .monospacedDigit()
                    .foregroundStyle(timeColor)
                    .frame(width: 50, alignment: .trailing)
                    .padding(.top, 16)
                    .accessibilityIdentifier("today.timeline.time.\(item.title)")

                if !isLast {
                    Rectangle()
                        .fill(V2Theme.ColorRole.outline.opacity(0.58))
                        .frame(width: 1.2, height: isSelected ? 76 : 42)
                        .padding(.top, 5)
                }
            }

            VStack(alignment: .leading, spacing: isSelected ? 10 : 5) {
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    V2TodayFlowDot(
                        isDone: isCompletedTask,
                        isFocused: isFocused,
                        color: dotColor,
                        onRestore: onRestore
                    )

                    Text(item.title)
                        .font(isSelected ? V2Theme.TypeRole.titleLarge : V2Theme.TypeRole.titleMedium)
                        .foregroundStyle(isCompletedTask ? V2Theme.ColorRole.textTertiary : V2Theme.ColorRole.textPrimary)
                        .strikethrough(isCompletedTask, color: V2Theme.ColorRole.textTertiary)
                        .lineLimit(2)

                    if isFocused {
                        Text("现在")
                            .font(V2Theme.TypeRole.labelSmall)
                            .foregroundStyle(V2Theme.ColorRole.textInverse)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(V2Theme.ColorRole.taskActive, in: Capsule())
                    } else if isCompletedTask {
                        Button(action: onRestore) {
                            Label("恢复", systemImage: "arrow.uturn.backward")
                                .font(V2Theme.TypeRole.labelSmall)
                                .foregroundStyle(V2Theme.ColorRole.textSecondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(V2Theme.ColorRole.surfaceMuted.opacity(0.66), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }

                if isSelected || isFocused || item.kind == .executionRecord {
                    Text(item.detail)
                        .font(V2Theme.TypeRole.bodySmall)
                        .foregroundStyle(V2Theme.ColorRole.textSecondary)
                        .lineLimit(2)
                        .padding(.leading, 21)
                }

                if isSelected && item.kind == .task && !item.isDone {
                    HStack(spacing: 8) {
                        if !isFocused {
                            V2TodayFlowAction(title: "开始", systemName: "play.fill", isPrimary: true, action: onStart)
                        }
                        V2TodayFlowAction(title: "Zen", systemName: "leaf.fill", isPrimary: false, action: onZen)
                        V2TodayFlowAction(title: "完成", systemName: "checkmark", isPrimary: false, action: onComplete)
                    }
                    .padding(.leading, 21)
                }
            }
            .padding(.vertical, isSelected ? 15 : 13)
            .padding(.horizontal, isSelected ? 15 : 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground)
            .overlay(
                RoundedRectangle(cornerRadius: isSelected ? 24 : 20, style: .continuous)
                    .stroke(rowBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: isSelected ? 24 : 20, style: .continuous))
            .opacity(isCompletedTask ? 0.58 : 1)
            .contentShape(RoundedRectangle(cornerRadius: isSelected ? 24 : 20, style: .continuous))
            .onTapGesture(perform: onSelect)
        }
        .padding(.bottom, isLast ? 0 : 6)
    }

    private var timeColor: Color {
        if isCompletedTask { return V2Theme.ColorRole.textTertiary.opacity(0.72) }
        if isFocused { return V2Theme.ColorRole.primary }
        return V2Theme.ColorRole.textSecondary
    }

    private var dotColor: Color {
        // Completed work recedes on Today; unfinished work remains easy to spot.
        if item.kind == .executionRecord { return V2Theme.ColorRole.textTertiary.opacity(0.58) }
        if isCompletedTask { return V2Theme.ColorRole.textTertiary.opacity(0.42) }
        if isFocused { return V2Theme.ColorRole.taskActive }
        return V2Theme.ColorRole.taskIncomplete.opacity(item.taskID == nil ? 1 : 0.78)
    }

    private var rowBackground: Color {
        if isSelected { return V2Theme.ColorRole.surfaceRaised.opacity(0.98) }
        if isFocused { return V2Theme.ColorRole.surfaceRaised.opacity(0.94) }
        return V2Theme.ColorRole.surface.opacity(0.66)
    }

    private var rowBorder: Color {
        if isSelected { return V2Theme.ColorRole.primary.opacity(0.16) }
        return V2Theme.ColorRole.outline.opacity(0.40)
    }

    private var isCompletedTask: Bool {
        item.kind == .task && item.isDone
    }
}

private struct V2TodayFlowAction: View {
    let title: String
    let systemName: String
    let isPrimary: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemName)
                .font(V2Theme.TypeRole.labelMedium)
                .foregroundStyle(isPrimary ? V2Theme.ColorRole.textInverse : V2Theme.ColorRole.onPrimaryContainer)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(isPrimary ? V2Theme.ColorRole.textPrimary : V2Theme.ColorRole.primaryContainer, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct V2TodayFlowDot: View {
    let isDone: Bool
    let isFocused: Bool
    let color: Color
    let onRestore: () -> Void

    var body: some View {
        if isDone {
            Button(action: onRestore) {
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
                    .overlay(
                        Circle()
                            .stroke(V2Theme.ColorRole.surfaceRaised, lineWidth: 2)
                            .frame(width: 18, height: 18)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("恢复为未完成")
        } else {
            Circle()
                .fill(color)
                .frame(width: isFocused ? 12 : 8, height: isFocused ? 12 : 8)
        }
    }
}

private struct V2TodayQuickAddSheet: View {
    @Binding var title: String
    let isListening: Bool
    let onMic: () -> Void
    let onCancel: () -> Void
    let onSubmit: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("快速插入")
                    .font(V2Theme.TypeRole.titleLarge)
                    .foregroundStyle(V2Theme.ColorRole.textPrimary)

                Spacer()

                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(V2Theme.ColorRole.textSecondary)
                        .frame(width: 34, height: 34)
                        .background(V2Theme.ColorRole.surfaceMuted, in: Circle())
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                TextField("记一件要处理的事", text: $title)
                    .textFieldStyle(.plain)
                    .font(V2Theme.TypeRole.titleMedium)
                    .foregroundStyle(V2Theme.ColorRole.textPrimary)
                    .submitLabel(.done)
                    .focused($isFocused)
                    .onSubmit(onSubmit)
                    .accessibilityIdentifier("today.quickAdd.title")

                Button(action: onMic) {
                    Image(systemName: isListening ? "waveform" : "mic")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(
                            isListening
                                ? V2Theme.ColorRole.textInverse
                                : V2Theme.ColorRole.textSecondary
                        )
                        .frame(width: 38, height: 38)
                        .background(
                            isListening
                                ? V2Theme.ColorRole.destructive
                                : V2Theme.ColorRole.surfaceRaised,
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isListening ? "停止语音输入" : "开始语音输入")

                Button(action: onSubmit) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(V2Theme.ColorRole.onPrimary)
                        .frame(width: 38, height: 38)
                        .background(
                            title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? V2Theme.ColorRole.textTertiary
                                : V2Theme.ColorRole.primary
                        )
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("添加任务")
            }
            .padding(.horizontal, 14)
            .frame(height: 54)
            .background(V2Theme.ColorRole.surfaceMuted, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Spacer(minLength: 0)
        }
        .padding(20)
        .presentationBackground(V2Theme.ColorRole.canvas)
        .onAppear {
            isFocused = !isListening
        }
        .onChange(of: isListening) { _, listening in
            isFocused = !listening
        }
    }
}

private struct V2TodayCaptureButton: UIViewRepresentable {
    let onTap: () -> Void
    let onVoiceStart: () -> Void
    let onVoiceLock: () -> Void
    let onVoiceEnd: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> V2CaptureControl {
        let control = V2CaptureControl()
        control.backgroundColor = UIColor(V2Theme.ColorRole.primary)
        control.layer.cornerRadius = 30
        control.layer.masksToBounds = true
        control.isAccessibilityElement = true
        control.accessibilityTraits = .button
        control.accessibilityLabel = "快速添加今日任务"
        control.accessibilityHint = "点按输入文字；长按语音输入，上拖锁定"
        control.accessibilityIdentifier = "today.quickAdd"

        let configuration = UIImage.SymbolConfiguration(pointSize: 28, weight: .medium)
        let icon = UIImageView(
            image: UIImage(systemName: "plus", withConfiguration: configuration)
        )
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.tintColor = UIColor(V2Theme.ColorRole.onPrimary)
        icon.isUserInteractionEnabled = false
        control.addSubview(icon)
        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: control.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: control.centerYAnchor)
        ])

        connect(control, coordinator: context.coordinator)
        return control
    }

    func updateUIView(_ control: V2CaptureControl, context: Context) {
        context.coordinator.parent = self
        connect(control, coordinator: context.coordinator)
    }

    private func connect(_ control: V2CaptureControl, coordinator: Coordinator) {
        control.onTap = { coordinator.parent.onTap() }
        control.onVoiceStart = { coordinator.parent.onVoiceStart() }
        control.onVoiceLock = { coordinator.parent.onVoiceLock() }
        control.onVoiceEnd = { coordinator.parent.onVoiceEnd() }
    }

    final class Coordinator {
        var parent: V2TodayCaptureButton

        init(parent: V2TodayCaptureButton) {
            self.parent = parent
        }
    }
}

private final class V2CaptureControl: UIControl {
    var onTap: (() -> Void)?
    var onVoiceStart: (() -> Void)?
    var onVoiceLock: (() -> Void)?
    var onVoiceEnd: (() -> Void)?

    private var startPoint = CGPoint.zero
    private var isVoiceActive = false
    private var isVoiceLocked = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        addTarget(self, action: #selector(handleTap), for: .touchUpInside)

        let longPress = UILongPressGestureRecognizer(
            target: self,
            action: #selector(handleLongPress)
        )
        longPress.minimumPressDuration = 0.45
        longPress.allowableMovement = 1_000
        addGestureRecognizer(longPress)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func accessibilityActivate() -> Bool {
        onTap?()
        return true
    }

    @objc private func handleTap() {
        onTap?()
    }

    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        let point = recognizer.location(in: self)
        switch recognizer.state {
        case .began:
            startPoint = point
            isVoiceActive = true
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onVoiceStart?()
        case .changed where
            isVoiceActive && !isVoiceLocked && point.y - startPoint.y < -56:
            isVoiceLocked = true
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            onVoiceLock?()
        case .ended, .cancelled, .failed:
            if isVoiceActive && !isVoiceLocked {
                onVoiceEnd?()
            }
            isVoiceActive = false
            isVoiceLocked = false
        default:
            break
        }
    }
}

private enum V2TodayFormat {
    static func duration(_ seconds: Int) -> String {
        let value = max(0, seconds)
        if value >= 3_600 {
            return "\(value / 3_600):\(String(format: "%02d", (value % 3_600) / 60)):\(String(format: "%02d", value % 60))"
        }
        return "\(value / 60):\(String(format: "%02d", value % 60))"
    }
}

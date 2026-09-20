import SwiftUI
import ToughTrialV2Core
#if os(iOS)
import UIKit
#else
import AppKit
#endif

struct V2TodayView: View {
    @ObservedObject var store: V2AppStore
    @State private var isQuickAddPresented = false
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
                        sessions: Array(store.todayRunningSessions.prefix(1)),
                        lifetimeSeconds: store.todayRunningSessions.first.map { store.lifetimeSeconds(for: $0) } ?? 0,
                        isExpanded: isFocusExpanded,
                        onFocus: focusSession,
                        onExpand: expandFocus,
                        onToggle: { store.pauseTodaySession($0.id) },
                        onEnd: { store.completeTodaySession($0) },
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

                    V2TodayExecutionBoard(store: store, onFocus: focusSession)
                    .frame(maxHeight: .infinity)
                    .environment(\.scheduleHighlightedIDs, store.highlightedScheduleIDs)
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)

                Button { isQuickAddPresented = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(V2Theme.ColorRole.onPrimary)
                        .frame(width: 60, height: 60)
                        .background(V2Theme.ColorRole.primary, in: Circle())
                }
                .accessibilityLabel("快速添加今日任务")
                .accessibilityIdentifier("today.quickAdd")
                .frame(width: 60, height: 60)
                .shadow(color: V2Theme.ColorRole.primary.opacity(0.24), radius: 18, y: 10)
                .padding(.trailing, 24)
                .padding(.bottom, 78)
            }
            #if os(iOS)
            .navigationBarHidden(true)
            #endif
            .onChange(of: store.todayRunningSessions.first?.id) { _, _ in
                isFocusExpanded = true
            }
            .v2Sheet(isPresented: $isQuickAddPresented) {
                NavigationStack {
                    V2TaskEditor(mode: .create(location: "今天 · 加入当天安排", identifier: "today.quickAdd"), onSave: { title, note in
                        if store.quickAddTodayTask(title: title, note: note) {
                            isQuickAddPresented = false
                            return nil
                        }
                        return store.errorMessage ?? "保存失败，请重试。"
                    }, onCancel: { isQuickAddPresented = false })
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .v2Sheet(
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

        }
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
    let lifetimeSeconds: Int
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
                    lifetimeSeconds: lifetimeSeconds,
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
    let lifetimeSeconds: Int
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
                    Text("累计 \(V2TodayFormat.duration(lifetimeSeconds))")
                        .font(V2Theme.TypeRole.labelSmall)
                        .foregroundStyle(V2Theme.ColorRole.textTertiary)
                    Text("今日 \(V2TodayFormat.duration(session.totalElapsedSeconds))")
                        .font(V2Theme.TypeRole.timerSmall)
                        .foregroundStyle(V2Theme.ColorRole.textSecondary)
                }
            }

            HStack(spacing: 10) {
                Button(action: onToggle) {
                    Label("暂停", systemImage: "pause.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(V2Theme.ColorRole.textInverse)
                        .frame(width: 86, height: 44)
                        .background(V2Theme.ColorRole.textPrimary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("暂停")
                .accessibilityIdentifier("today.focus.pause")

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
                    Label(session.taskID == nil ? "结束" : "完成", systemImage: session.taskID == nil ? "stop.fill" : "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(V2Theme.ColorRole.textSecondary)
                        .frame(width: 86, height: 44)
                        .background(V2Theme.ColorRole.surfaceMuted.opacity(0.56), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(session.taskID == nil ? "结束时间段" : "完成任务")
                .accessibilityIdentifier("today.focus.complete")
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
            .v2InlineNavigationTitle()
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

private enum V2TodayFormat {
    static func duration(_ seconds: Int) -> String {
        let value = max(0, seconds)
        if value >= 3_600 {
            return "\(value / 3_600):\(String(format: "%02d", (value % 3_600) / 60)):\(String(format: "%02d", value % 60))"
        }
        return "\(value / 60):\(String(format: "%02d", value % 60))"
    }
}

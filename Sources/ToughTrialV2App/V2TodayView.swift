import SwiftUI
import ToughTrialV2Core

struct V2TodayView: View {
    @ObservedObject var store: V2AppStore
    @State private var isQuickAddPresented = false
    @State private var quickAddTitle = ""
    @State private var isFocusExpanded = true

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
                    V2TodayHeader()

                    V2TodayFocusCanvas(
                        sessions: store.state.activeSessions,
                        isExpanded: isFocusExpanded,
                        onFocus: focusSession,
                        onExpand: expandFocus,
                        onToggle: { store.state.toggleSession($0.id) },
                        onEnd: endSession,
                        onZen: { store.startZen(taskID: $0.taskID, title: $0.title) }
                    )

                    V2TodayFlowStrip(
                        items: store.state.timelineItems,
                        selectedTaskID: store.state.selectedTaskID,
                        focusedTaskID: store.state.activeSessions.first?.taskID,
                        onSelect: selectTimelineItem,
                        onStart: startTimelineItem,
                        onComplete: completeTimelineItem,
                        onRestore: restoreTimelineItem,
                        onZen: { store.startZen(taskID: $0.taskID, title: $0.title) }
                    )
                    .frame(maxHeight: .infinity)
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)

                Button {
                    isQuickAddPresented = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(V2Theme.ColorRole.onPrimary)
                        .frame(width: 60, height: 60)
                        .background(V2Theme.ColorRole.primary, in: Circle())
                        .shadow(color: V2Theme.ColorRole.primary.opacity(0.24), radius: 18, y: 10)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("快速添加今日任务")
                .padding(.trailing, 24)
                .padding(.bottom, 78)
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $isQuickAddPresented) {
                V2TodayQuickAddSheet(
                    title: $quickAddTitle,
                    onCancel: dismissQuickAdd,
                    onSubmit: submitQuickAdd
                )
                .presentationDetents([.height(184)])
                .presentationDragIndicator(.visible)
            }
        }
    }

    private func selectTimelineItem(_ item: V2TimelineItem) {
        guard let taskID = item.taskID else {
            store.state.selectedTaskID = nil
            return
        }
        store.state.selectedTaskID = taskID
    }

    private func focusSession(_ session: V2ActiveSession) {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            _ = store.state.focusActiveSession(session.id)
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
            store.state.selectedTaskID = nil
        }
    }

    private func startTimelineItem(_ item: V2TimelineItem) {
        let title = item.taskID.flatMap { store.state.taskTitle(for: $0) } ?? item.title
        _ = store.state.startSession(taskID: item.taskID, title: title, startedAtLabel: currentTimeLabel())
    }

    private func completeTimelineItem(_ item: V2TimelineItem) {
        _ = store.state.completeTimelineItem(item.id)
    }

    private func restoreTimelineItem(_ item: V2TimelineItem) {
        _ = store.state.restoreTimelineItem(item.id)
        if let taskID = item.taskID {
            store.state.selectedTaskID = taskID
        }
    }

    private func endSession(_ session: V2ActiveSession) {
        let elapsed = max(session.currentElapsed, 1)
        store.state.endSession(session.id, totalElapsed: elapsed, endLabel: currentTimeLabel())
    }

    private func submitQuickAdd() {
        let title = quickAddTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        store.state.quickAddTodayTask(title: title)
        dismissQuickAdd()
    }

    private func dismissQuickAdd() {
        quickAddTitle = ""
        isQuickAddPresented = false
    }

    private func currentTimeLabel() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date())
    }
}

private struct V2TodayBackground: View {
    var body: some View {
        V2Theme.ColorRole.canvas
            .ignoresSafeArea()
    }
}

private struct V2TodayHeader: View {
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

            Image(systemName: "line.3.horizontal")
                .font(V2Theme.TypeRole.titleMedium)
                .foregroundStyle(V2Theme.ColorRole.textPrimary.opacity(0.82))
                .frame(width: 46, height: 46)
                .background(V2Theme.ColorRole.surfaceRaised.opacity(0.92), in: RoundedRectangle(cornerRadius: 19, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 19, style: .continuous)
                        .stroke(V2Theme.ColorRole.outline.opacity(0.46), lineWidth: 1)
                )
                .shadow(color: V2Theme.ColorRole.textPrimary.opacity(0.05), radius: 14, y: 7)
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
                V2TodayEmptyFocus()
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

                    Text(V2TodayFormat.minutes(session.currentElapsed))
                        .font(V2Theme.TypeRole.timerLarge)
                        .foregroundStyle(V2Theme.ColorRole.textPrimary)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 4) {
                    Text("当前")
                        .font(V2Theme.TypeRole.labelSmall)
                        .foregroundStyle(V2Theme.ColorRole.textTertiary)
                    Text("今日 \(V2TodayFormat.minutes(session.totalElapsed))")
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
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 296, alignment: .topLeading)
        .background(V2Theme.ColorRole.surfaceRaised.opacity(0.92), in: RoundedRectangle(cornerRadius: 34, style: .continuous))
    }
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

                Text(V2TodayFormat.minutes(session.totalElapsed))
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
    let selectedTaskID: String?
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
        guard let selectedTaskID else {
            return item.taskID == nil && !item.isDone
        }
        return item.taskID == selectedTaskID
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
                        isDone: item.isDone,
                        isFocused: isFocused,
                        color: dotColor,
                        onRestore: onRestore
                    )

                    Text(item.title)
                        .font(isSelected ? V2Theme.TypeRole.titleLarge : V2Theme.TypeRole.titleMedium)
                        .foregroundStyle(item.isDone ? V2Theme.ColorRole.textTertiary : V2Theme.ColorRole.textPrimary)
                        .strikethrough(item.isDone, color: V2Theme.ColorRole.textTertiary)
                        .lineLimit(2)

                    if isFocused {
                        Text("现在")
                            .font(V2Theme.TypeRole.labelSmall)
                            .foregroundStyle(V2Theme.ColorRole.textInverse)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(V2Theme.ColorRole.taskActive, in: Capsule())
                    } else if item.isDone {
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

                if isSelected || isFocused {
                    Text(item.detail)
                        .font(V2Theme.TypeRole.bodySmall)
                        .foregroundStyle(V2Theme.ColorRole.textSecondary)
                        .lineLimit(2)
                        .padding(.leading, 21)
                }

                if isSelected && !item.isDone {
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
            .opacity(item.isDone ? 0.58 : 1)
            .contentShape(RoundedRectangle(cornerRadius: isSelected ? 24 : 20, style: .continuous))
            .onTapGesture(perform: onSelect)
        }
        .padding(.bottom, isLast ? 0 : 6)
    }

    private var timeColor: Color {
        if item.isDone { return V2Theme.ColorRole.textTertiary.opacity(0.72) }
        if isFocused { return V2Theme.ColorRole.primary }
        return V2Theme.ColorRole.textSecondary
    }

    private var dotColor: Color {
        // Completed work recedes on Today; unfinished work remains easy to spot.
        if item.isDone { return V2Theme.ColorRole.textTertiary.opacity(0.42) }
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
            }
            .padding(.horizontal, 14)
            .frame(height: 54)
            .background(V2Theme.ColorRole.surfaceMuted, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Spacer(minLength: 0)
        }
        .padding(20)
        .presentationBackground(V2Theme.ColorRole.canvas)
        .onAppear {
            isFocused = true
        }
    }
}

private enum V2TodayFormat {
    static func minutes(_ minutes: Int) -> String {
        if minutes >= 60 {
            return "\(minutes / 60):\(String(format: "%02d", minutes % 60))"
        }
        return "\(minutes)m"
    }
}

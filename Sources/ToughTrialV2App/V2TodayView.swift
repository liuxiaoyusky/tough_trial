import SwiftUI
import ToughTrialV2Core

struct V2TodayView: View {
    @ObservedObject var store: V2AppStore
    @State private var isQuickAddPresented = false
    @State private var quickAddTitle = ""

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        todayHeader

                        if !store.state.activeSessions.isEmpty {
                            V2TodayActiveSessions(
                                sessions: store.state.activeSessions,
                                onToggle: { store.state.toggleSession($0) },
                                onEnd: { endSession($0) }
                            )
                        }

                        V2TodayTimeline(
                            items: store.state.timelineItems,
                            selectedTaskID: store.state.selectedTaskID,
                            activeTaskIDs: activeTaskIDs,
                            onSelect: selectTimelineItem,
                            onStart: startTimelineItem,
                            onComplete: completeTimelineItem,
                            onZen: { item in
                                store.startZen(taskID: item.taskID, title: item.title)
                            }
                        )
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 112)
                }

                Button {
                    isQuickAddPresented = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                        Text("添加")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(minWidth: 92, minHeight: 54)
                    .padding(.horizontal, 18)
                    .background(V2Theme.blue)
                    .clipShape(Capsule())
                    .shadow(color: V2Theme.blue.opacity(0.25), radius: 16, y: 8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("快速添加")
                .padding(.trailing, 22)
                .padding(.bottom, 24)
            }
            .navigationTitle("今天")
            .navigationBarTitleDisplayMode(.inline)
            .v2ScreenBackground()
            .sheet(isPresented: $isQuickAddPresented) {
                V2TodayQuickAddSheet(
                    title: $quickAddTitle,
                    onCancel: dismissQuickAdd,
                    onSubmit: submitQuickAdd
                )
                .presentationDetents([.height(210)])
                .presentationDragIndicator(.visible)
            }
        }
    }

    private var todayHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("正在发生")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(V2Theme.ink)
            Text("只保留今天需要执行的节奏。")
                .font(.subheadline)
                .foregroundStyle(V2Theme.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var activeTaskIDs: Set<String> {
        Set(store.state.activeSessions.compactMap(\.taskID))
    }

    private func selectTimelineItem(_ item: V2TimelineItem) {
        guard let taskID = item.taskID else { return }
        store.state.selectedTaskID = taskID
    }

    private func startTimelineItem(_ item: V2TimelineItem) {
        let title = item.taskID.flatMap { store.state.taskTitle(for: $0) } ?? item.title
        _ = store.state.startSession(taskID: item.taskID, title: title, startedAtLabel: currentTimeLabel())
    }

    private func completeTimelineItem(_ item: V2TimelineItem) {
        _ = store.state.completeTimelineItem(item.id)
    }

    private func endSession(_ session: V2ActiveSession) {
        let elapsed = max(session.totalElapsed, session.currentElapsed, 1)
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

private struct V2TodayActiveSessions: View {
    let sessions: [V2ActiveSession]
    let onToggle: (String) -> Void
    let onEnd: (V2ActiveSession) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("执行中")
                .font(.headline.weight(.semibold))
                .foregroundStyle(V2Theme.ink)

            VStack(spacing: 10) {
                ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                    V2TodaySessionRow(
                        session: session,
                        isPrimary: index == 0,
                        onToggle: { onToggle(session.id) },
                        onEnd: { onEnd(session) }
                    )
                }
            }
        }
    }
}

private struct V2TodaySessionRow: View {
    let session: V2ActiveSession
    let isPrimary: Bool
    let onToggle: () -> Void
    let onEnd: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(session.status == .running ? V2Theme.mint : V2Theme.orange)
                .frame(width: isPrimary ? 14 : 10, height: isPrimary ? 14 : 10)

            VStack(alignment: .leading, spacing: isPrimary ? 8 : 4) {
                Text(session.title)
                    .font(.system(size: isPrimary ? 22 : 17, weight: .semibold))
                    .foregroundStyle(V2Theme.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    Label(session.status == .running ? "进行中" : "已暂停", systemImage: session.status == .running ? "play.fill" : "pause.fill")
                    Text("开始 \(session.startedAtLabel)")
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(V2Theme.secondary)

                if isPrimary {
                    HStack(spacing: 16) {
                        V2TodayTimeBlock(label: "本次", minutes: session.currentElapsed)
                        V2TodayTimeBlock(label: "累计", minutes: session.totalElapsed)
                    }
                }
            }

            Spacer(minLength: 10)

            HStack(spacing: 8) {
                Button(action: onToggle) {
                    Image(systemName: session.status == .running ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(V2Theme.ink)
                        .frame(width: 38, height: 38)
                        .background(V2Theme.page)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(session.status == .running ? "暂停" : "继续")

                Button(action: onEnd) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(V2Theme.blue)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("结束")
            }
        }
        .padding(isPrimary ? 18 : 14)
        .background(V2Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isPrimary ? V2Theme.blue.opacity(0.28) : V2Theme.line, lineWidth: 1)
        )
    }
}

private struct V2TodayTimeBlock: View {
    let label: String
    let minutes: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(V2Theme.tertiary)
            Text(Self.formattedMinutes(minutes))
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(V2Theme.ink)
                .frame(minWidth: 54, alignment: .leading)
        }
    }

    private static func formattedMinutes(_ minutes: Int) -> String {
        if minutes >= 60 {
            return "\(minutes / 60)h \(minutes % 60)m"
        }
        return "\(minutes)m"
    }
}

private struct V2TodayTimeline: View {
    let items: [V2TimelineItem]
    let selectedTaskID: String?
    let activeTaskIDs: Set<String>
    let onSelect: (V2TimelineItem) -> Void
    let onStart: (V2TimelineItem) -> Void
    let onComplete: (V2TimelineItem) -> Void
    let onZen: (V2TimelineItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("时间线")
                .font(.headline.weight(.semibold))
                .foregroundStyle(V2Theme.ink)

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    V2TodayTimelineRow(
                        item: item,
                        isSelected: item.taskID == selectedTaskID,
                        isActive: item.taskID.map { activeTaskIDs.contains($0) } ?? false,
                        isLast: index == items.count - 1,
                        onSelect: { onSelect(item) },
                        onStart: { onStart(item) },
                        onComplete: { onComplete(item) },
                        onZen: { onZen(item) }
                    )
                }
            }
        }
    }
}

private struct V2TodayTimelineRow: View {
    let item: V2TimelineItem
    let isSelected: Bool
    let isActive: Bool
    let isLast: Bool
    let onSelect: () -> Void
    let onStart: () -> Void
    let onComplete: () -> Void
    let onZen: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 13, height: 13)
                    if item.isDone {
                        Image(systemName: "checkmark")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                if !isLast {
                    Rectangle()
                        .fill(V2Theme.line)
                        .frame(width: 2, height: 74)
                }
            }
            .frame(width: 18)

            Text(item.timeLabel)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(item.isDone ? V2Theme.tertiary : V2Theme.secondary)
                .frame(width: 48, alignment: .leading)
                .padding(.top, 1)

            HStack(alignment: .center, spacing: 12) {
                Button(action: onSelect) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(item.title)
                                .font(.system(size: isSelected ? 18 : 16, weight: .semibold))
                                .foregroundStyle(item.isDone ? V2Theme.tertiary : V2Theme.ink)
                                .strikethrough(item.isDone, color: V2Theme.tertiary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)

                            if isActive {
                                Text("现在")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(V2Theme.mint)
                                    .clipShape(Capsule())
                            }
                        }

                        Text(item.detail)
                            .font(.footnote)
                            .foregroundStyle(item.isDone ? V2Theme.tertiary : V2Theme.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                HStack(spacing: 6) {
                    if !item.isDone && !isActive {
                        V2TodayRowIcon(systemName: "play.fill", action: onStart)
                    }
                    if !item.isDone {
                        V2TodayRowIcon(systemName: "checkmark", action: onComplete)
                        V2TodayRowIcon(systemName: "moon.fill", action: onZen)
                    }
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
            .background(isSelected ? V2Theme.blue.opacity(0.08) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(item.taskID == nil ? 0.72 : 1)
        }
        .padding(.bottom, isLast ? 0 : 8)
    }

    private var dotColor: Color {
        if item.isDone {
            return V2Theme.tertiary
        }
        if isActive || isSelected {
            return V2Theme.blue
        }
        return V2Theme.line
    }
}

private struct V2TodayRowIcon: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(systemName == "moon.fill" || systemName == "checkmark" ? V2Theme.blue : V2Theme.ink)
                .frame(width: 34, height: 34)
                .background(V2Theme.panel)
                .clipShape(Circle())
                .overlay(Circle().stroke(V2Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
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
                Text("快速添加")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(V2Theme.ink)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(V2Theme.secondary)
                        .frame(width: 34, height: 34)
                        .background(V2Theme.page)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                TextField("记一件要做的事", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18))
                    .submitLabel(.done)
                    .focused($isFocused)
                    .onSubmit(onSubmit)

                Button(action: onSubmit) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? V2Theme.tertiary : V2Theme.blue)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 14)
            .frame(height: 52)
            .background(V2Theme.page)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Label("长按并上滑可录音，当前原型仅展示入口。", systemImage: "mic.fill")
                .font(.footnote)
                .foregroundStyle(V2Theme.secondary)

            Spacer(minLength: 0)
        }
        .padding(20)
        .presentationBackground(V2Theme.panel)
        .onAppear {
            isFocused = true
        }
    }
}

import SwiftUI
import ToughTrialV2Core

struct V2TodayView: View {
    @ObservedObject var store: V2AppStore
    @State private var isQuickAddPresented = false
    @State private var quickAddTitle = ""

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                V2TodayBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        V2TodayHeader()

                        V2TodayLiveTray(
                            sessions: store.state.activeSessions,
                            onToggle: { store.state.toggleSession($0.id) },
                            onEnd: endSession,
                            onZen: { store.startZen(taskID: $0.taskID, title: $0.title) }
                        )

                        V2TodayFlowTimeline(
                            items: store.state.timelineItems,
                            selectedTaskID: store.state.selectedTaskID,
                            activeTaskIDs: activeTaskIDs,
                            onSelect: selectTimelineItem,
                            onStart: startTimelineItem,
                            onComplete: completeTimelineItem,
                            onZen: { store.startZen(taskID: $0.taskID, title: $0.title) }
                        )
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                    .padding(.bottom, 184)
                }

                Button {
                    isQuickAddPresented = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 72, height: 56)
                        .background(V2Theme.blue, in: Capsule())
                        .shadow(color: V2Theme.blue.opacity(0.34), radius: 18, y: 10)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("快速添加今日任务")
                .padding(.trailing, 22)
                .padding(.bottom, 104)
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

    private var activeTaskIDs: Set<String> {
        Set(store.state.activeSessions.compactMap(\.taskID))
    }

    private func selectTimelineItem(_ item: V2TimelineItem) {
        guard let taskID = item.taskID else {
            store.state.selectedTaskID = nil
            return
        }
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
        LinearGradient(
            colors: [
                Color(red: 0.97, green: 0.96, blue: 0.92),
                Color(red: 0.93, green: 0.92, blue: 0.87)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay(alignment: .topLeading) {
            Circle()
                .fill(V2Theme.mint.opacity(0.12))
                .frame(width: 220, height: 220)
                .blur(radius: 36)
                .offset(x: -92, y: -86)
        }
        .ignoresSafeArea()
    }
}

private struct V2TodayHeader: View {
    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 7) {
                Text("今天")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(V2Theme.ink)
                    .lineLimit(1)

                Text(Self.dateLabel)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(V2Theme.secondary)
            }

            Spacer()

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(V2Theme.ink)
                .frame(width: 42, height: 42)
                .background(.white.opacity(0.64), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(.black.opacity(0.06), lineWidth: 1)
                )
        }
        .padding(.top, 2)
    }

    private static var dateLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 · EEEE"
        return formatter.string(from: Date())
    }
}

private struct V2TodayLiveTray: View {
    let sessions: [V2ActiveSession]
    let onToggle: (V2ActiveSession) -> Void
    let onEnd: (V2ActiveSession) -> Void
    let onZen: (V2ActiveSession) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("当前任务区")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(V2Theme.secondary)
                Spacer()
                Text(sessions.isEmpty ? "未开始计时" : "\(sessions.count) 个时间段")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(V2Theme.tertiary)
            }

            if sessions.isEmpty {
                V2TodayEmptyTray()
            } else {
                ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                    V2TodaySessionCard(
                        session: session,
                        isPrimary: index == 0,
                        onToggle: { onToggle(session) },
                        onEnd: { onEnd(session) },
                        onZen: { onZen(session) }
                    )
                }
            }
        }
        .padding(16)
        .background(.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(.black.opacity(0.07), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 24, y: 14)
    }
}

private struct V2TodayEmptyTray: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "pause.circle")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(V2Theme.tertiary)
                .frame(width: 44, height: 44)
                .background(V2Theme.page.opacity(0.82), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text("还没有开始记录")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(V2Theme.ink)
                Text("从时间线点开始，或进入 Zen。")
                    .font(.caption)
                    .foregroundStyle(V2Theme.secondary)
            }

            Spacer()
        }
        .padding(12)
        .background(V2Theme.page.opacity(0.54), in: RoundedRectangle(cornerRadius: 19, style: .continuous))
    }
}

private struct V2TodaySessionCard: View {
    let session: V2ActiveSession
    let isPrimary: Bool
    let onToggle: () -> Void
    let onEnd: () -> Void
    let onZen: () -> Void

    var body: some View {
        if isPrimary {
            primaryCard
        } else {
            compactCard
        }
    }

    private var primaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Button(action: onToggle) {
                    Image(systemName: session.status == .running ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(session.status == .running ? V2Theme.ink : V2Theme.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(session.status == .running ? "暂停" : "继续")

                VStack(alignment: .leading, spacing: 4) {
                    Text(session.title)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(V2Theme.ink)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(session.status == .running ? "进行中 · 从 \(session.startedAtLabel) 开始" : "暂停中 · 从 \(session.startedAtLabel) 开始")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(V2Theme.secondary)
                }

                Spacer(minLength: 8)
            }

            HStack(alignment: .bottom) {
                HStack(spacing: 10) {
                    V2TodayTimePair(title: "当前", minutes: session.currentElapsed)
                    Text("/")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(V2Theme.tertiary)
                    V2TodayTimePair(title: "今日", minutes: session.totalElapsed)
                }

                Spacer()

                HStack(spacing: 8) {
                    V2TodayCapsuleButton(title: "Zen", systemName: "leaf.fill", action: onZen)
                    V2TodayCapsuleButton(title: "结束", systemName: "stop.fill", action: onEnd)
                }
            }
        }
        .padding(15)
        .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(V2Theme.blue.opacity(0.18), lineWidth: 1)
        )
    }

    private var compactCard: some View {
        HStack(spacing: 10) {
            Image(systemName: session.status == .running ? "play.fill" : "pause.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(session.status == .running ? V2Theme.mint : V2Theme.orange)
                .frame(width: 28, height: 28)
                .background(V2Theme.page.opacity(0.82), in: Circle())

            Text(session.status == .running ? "进行中" : "暂停")
                .font(.caption.weight(.bold))
                .foregroundStyle(V2Theme.secondary)

            Text(session.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(V2Theme.ink)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(V2TodayFormat.minutes(session.totalElapsed))
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(V2Theme.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(V2Theme.page.opacity(0.68), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
    }
}

private struct V2TodayTimePair: View {
    let title: String
    let minutes: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(V2Theme.tertiary)

            Text(V2TodayFormat.minutes(minutes))
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(V2Theme.ink)
                .frame(minWidth: 54, alignment: .leading)
        }
    }
}

private struct V2TodayCapsuleButton: View {
    let title: String
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemName)
                .font(.caption.weight(.bold))
                .foregroundStyle(systemName == "stop.fill" ? .white : V2Theme.blue)
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .background(systemName == "stop.fill" ? V2Theme.blue : V2Theme.blue.opacity(0.10), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct V2TodayFlowTimeline: View {
    let items: [V2TimelineItem]
    let selectedTaskID: String?
    let activeTaskIDs: Set<String>
    let onSelect: (V2TimelineItem) -> Void
    let onStart: (V2TimelineItem) -> Void
    let onComplete: (V2TimelineItem) -> Void
    let onZen: (V2TimelineItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("今日时间线")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(V2Theme.ink)
                Spacer()
                Text("现在 \(currentTime)")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(V2Theme.blue)
            }

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    V2TodayTimelineRow(
                        item: item,
                        isSelected: isSelected(item),
                        isActive: item.taskID.map { activeTaskIDs.contains($0) } ?? false,
                        isLast: index == items.count - 1,
                        onSelect: { onSelect(item) },
                        onStart: { onStart(item) },
                        onComplete: { onComplete(item) },
                        onZen: { onZen(item) }
                    )
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var currentTime: String {
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
                Text(item.timeLabel)
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(item.isDone ? V2Theme.tertiary : V2Theme.secondary)
                    .frame(width: 54, alignment: .trailing)
                    .padding(.top, 14)

                if !isLast {
                    Rectangle()
                        .fill(V2Theme.line.opacity(0.7))
                        .frame(width: 1.5, height: isSelected ? 88 : 46)
                        .padding(.top, 6)
                }
            }

            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(alignment: .top, spacing: 9) {
                        Circle()
                            .fill(dotColor)
                            .frame(width: isSelected ? 12 : 9, height: isSelected ? 12 : 9)
                            .padding(.top, 4)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 7) {
                                Text(item.title)
                                    .font(.system(size: isSelected ? 17 : 15, weight: .bold))
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
                                        .background(V2Theme.mint, in: Capsule())
                                } else if item.taskID == nil && !item.isDone {
                                    Text("临时")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(V2Theme.blue)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(V2Theme.blue.opacity(0.10), in: Capsule())
                                }
                            }

                            Text(item.detail)
                                .font(.caption)
                                .foregroundStyle(item.isDone ? V2Theme.tertiary : V2Theme.secondary)
                                .lineLimit(isSelected ? 3 : 2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if isSelected && !item.isDone {
                        HStack(spacing: 8) {
                            if !isActive {
                                V2TodayTimelineAction(title: "开始", systemName: "play.fill", action: onStart)
                            }
                            V2TodayTimelineAction(title: "Zen", systemName: "leaf.fill", action: onZen)
                            V2TodayTimelineAction(title: "完成", systemName: "checkmark", action: onComplete)
                            V2TodayTimelineAction(title: "编辑", systemName: "pencil", action: {})
                        }
                        .padding(.leading, 21)
                    }
                }
                .padding(.vertical, isSelected ? 14 : 12)
                .padding(.horizontal, 13)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(rowBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: isSelected ? 21 : 18, style: .continuous)
                        .stroke(rowBorder, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: isSelected ? 21 : 18, style: .continuous))
                .scaleEffect(isSelected ? 1.018 : 1, anchor: .leading)
                .opacity(item.isDone ? 0.66 : 1)
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, isLast ? 0 : 7)
    }

    private var dotColor: Color {
        if item.isDone { return V2Theme.tertiary }
        if isActive { return V2Theme.mint }
        if isSelected { return V2Theme.blue }
        if item.taskID == nil { return V2Theme.blue.opacity(0.78) }
        return V2Theme.line
    }

    private var rowBackground: Color {
        if isSelected { return Color.white.opacity(0.82) }
        if item.taskID == nil && !item.isDone { return V2Theme.blue.opacity(0.07) }
        return Color.white.opacity(0.46)
    }

    private var rowBorder: Color {
        if isSelected { return V2Theme.blue.opacity(0.22) }
        return Color.black.opacity(0.06)
    }
}

private struct V2TodayTimelineAction: View {
    let title: String
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemName)
                .font(.caption2.weight(.bold))
                .foregroundStyle(systemName == "play.fill" ? .white : V2Theme.blue)
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .background(systemName == "play.fill" ? V2Theme.ink : V2Theme.blue.opacity(0.10), in: Capsule())
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
                VStack(alignment: .leading, spacing: 4) {
                    Text("快速插入")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(V2Theme.ink)
                }

                Spacer()

                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(V2Theme.secondary)
                        .frame(width: 34, height: 34)
                        .background(V2Theme.page.opacity(0.82), in: Circle())
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                TextField("记一件要处理的事", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .medium))
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
            .frame(height: 54)
            .background(V2Theme.page.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Spacer(minLength: 0)
        }
        .padding(20)
        .presentationBackground(Color(red: 0.97, green: 0.96, blue: 0.92))
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

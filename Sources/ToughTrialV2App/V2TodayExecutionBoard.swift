import SwiftUI
import ToughTrialV2Core

/// One chronological timeline; the focus card is part of the same page scroll.
struct V2TodayExecutionBoard: View {
    @ObservedObject var store: V2AppStore
    let onFocus: (V2ActiveSession) -> Void

    var body: some View {
        let items = store.todayTimelineItems
        VStack(alignment: .leading, spacing: 12) {
            Text("今日规划 · \(items.count)")
                .font(V2Theme.TypeRole.titleLarge)
                .foregroundStyle(V2Theme.ColorRole.textPrimary)
                .padding(.bottom, 2)
            if items.isEmpty {
                Text("暂无其他安排，点右下角添加")
                    .font(.subheadline).foregroundStyle(V2Theme.ColorRole.textSecondary)
            }
            ForEach(items, id: \.id) { item in
                timelineRow(item, isFirst: item.id == items.first?.id, isLast: item.id == items.last?.id)
            }
        }
    }

    private func timelineRow(_ item: V2TimelineItem, isFirst: Bool, isLast: Bool) -> some View {
        let session = store.todayRunningSession(for: item)
        let nodeY: CGFloat = item.isDone ? 20 : 24
        let nodeColor = session != nil ? V2Theme.ColorRole.taskActive
            : item.isDone ? V2Theme.ColorRole.textTertiary : V2Theme.ColorRole.taskIncomplete
        return HStack(alignment: .top, spacing: 18) {
            Text(item.timeLabel)
                .font(V2Theme.TypeRole.labelSmall).monospacedDigit()
                .foregroundStyle(V2Theme.ColorRole.textSecondary)
                .frame(width: 42, height: 20, alignment: .trailing)
                .padding(.top, nodeY - 10)
                .accessibilityIdentifier("today.timeline.time.\(item.title)")
            planRow(item, session: session)
        }
        .background {
            GeometryReader { geometry in
                Path { path in
                    path.move(to: CGPoint(x: 51, y: isFirst ? nodeY : 0))
                    path.addLine(to: CGPoint(x: 51, y: isLast ? nodeY : geometry.size.height + 12))
                }
                .stroke(V2Theme.ColorRole.outline, lineWidth: 1)
                Circle().fill(nodeColor).frame(width: 8, height: 8)
                    .position(x: 51, y: nodeY)
            }
            .accessibilityHidden(true)
        }
    }

    private func planRow(_ item: V2TimelineItem, session: V2ActiveSession?) -> some View {
        let selected = store.state.selectedTimelineItemID == item.id
        return VStack(alignment: .leading, spacing: item.isDone ? 4 : 8) {
            Button {
                if let session { onFocus(session) }
                else { store.selectTodayItem(item) }
            } label: {
                VStack(alignment: .leading, spacing: item.isDone ? 4 : 7) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Label(item.title, systemImage: session != nil ? "timer"
                            : item.kind == .executionRecord ? "waveform.path"
                            : item.isDone ? "checkmark.circle.fill" : "circle.dashed")
                            .font(item.isDone ? V2Theme.TypeRole.bodyMedium : V2Theme.TypeRole.titleMedium)
                            .strikethrough(item.isDone)
                            .foregroundStyle(item.isDone ? V2Theme.ColorRole.textSecondary : V2Theme.ColorRole.textPrimary)
                        if item.isDone {
                            Text("已完成").font(V2Theme.TypeRole.labelSmall)
                                .foregroundStyle(V2Theme.ColorRole.textSecondary)
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(V2Theme.ColorRole.surfaceMuted, in: Capsule())
                                .fixedSize()
                        }
                    }
                    if let session {
                        Text("计时中 · 本段 \(duration(session.currentElapsedSeconds))")
                            .font(V2Theme.TypeRole.bodySmall)
                            .foregroundStyle(V2Theme.ColorRole.taskActive)
                    }
                    Text(item.detail)
                        .font(V2Theme.TypeRole.bodySmall)
                        .foregroundStyle(V2Theme.ColorRole.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(item.isDone ? 10 : 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(item.kind != .task && session == nil)
            .accessibilityIdentifier(session != nil ? "today.queue.\(item.title)" : "today.plan.\(item.title)")
            .accessibilityLabel("\(item.timeLabel) \(item.title) \(item.isDone ? "已完成，" : "")\(item.detail)")
            .accessibilityValue(session != nil ? "计时中" : item.isDone ? "已完成" : "未完成")
            .accessibilityHint(session != nil ? "切换到主卡片，保持其他任务计时" : "点按查看任务操作")

            if item.kind == .task && session == nil && selected {
                HStack(spacing: 8) {
                    if item.isDone {
                        Button("恢复", systemImage: "arrow.uturn.backward") { store.restoreTodayItem(item) }
                            .accessibilityIdentifier("today.restore.\(item.title)")
                    } else {
                        Button("开始 / 继续", systemImage: "play.fill") { store.startTodayItem(item) }
                            .accessibilityIdentifier("today.start.\(item.title)")
                        Button("Zen", systemImage: "leaf.fill") {
                            store.startZen(planItemID: item.planItemID, taskID: item.taskID, title: item.title)
                        }
                        Button("完成", systemImage: "checkmark") { store.completeTodayItem(item) }
                            .accessibilityIdentifier("today.complete.\(item.title)")
                    }
                }
                .font(V2Theme.TypeRole.labelMedium).buttonStyle(.bordered)
                .tint(V2Theme.ColorRole.primary)
                .padding(.horizontal, item.isDone ? 10 : 14)
                .padding(.bottom, item.isDone ? 10 : 14)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(item.isDone && !selected ? .clear : V2Theme.ColorRole.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(selected ? V2Theme.blue.opacity(0.3) : .clear))
    }

    private func duration(_ seconds: Int) -> String {
        let seconds = max(0, seconds)
        return String(format: "%02d:%02d:%02d", seconds / 3600, seconds % 3600 / 60, seconds % 60)
    }
}

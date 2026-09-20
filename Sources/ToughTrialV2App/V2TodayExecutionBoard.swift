import SwiftUI
import ToughTrialV2Core

/// The focus card owns the head; this board shows the remaining execution queue
/// and today's non-running plans, including completed work.
struct V2TodayExecutionBoard: View {
    @ObservedObject var store: V2AppStore
    let onFocus: (V2ActiveSession) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("执行中 · \(max(0, store.todayRunningSessions.count - 1))")
                    .font(V2Theme.TypeRole.titleLarge)
                if store.todayRunningSessions.count <= 1 {
                    Text("没有其他执行中的任务")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(Array(store.todayRunningSessions.dropFirst()), id: \.id) { session in
                    Button { onFocus(session) } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Text(session.startedAtLabel).font(.caption).monospacedDigit()
                            VStack(alignment: .leading, spacing: 7) {
                                Label(session.title, systemImage: "timer")
                                    .font(.headline)
                                Text("本段 \(duration(session.currentElapsedSeconds))")
                                    .foregroundStyle(V2Theme.ColorRole.taskActive)
                                Text("累计 \(duration(store.lifetimeSeconds(for: session))) · 今日 \(duration(session.totalElapsedSeconds))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(V2Theme.ColorRole.surfaceRaised, in: RoundedRectangle(cornerRadius: 20))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("today.queue.\(session.title)")
                    .accessibilityHint("切换到主卡片，保持其他任务计时")
                }

                Text("今日规划 · \(store.todayPlannedItems.count)")
                    .font(V2Theme.TypeRole.titleLarge).padding(.top, 8)
                if store.todayPlannedItems.isEmpty {
                    Text("暂无其他安排，点右下角添加")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(store.todayPlannedItems, id: \.id) { item in
                    planRow(item)
                }
            }
            .padding(.bottom, 150)
        }
        .accessibilityIdentifier("today.executionBoard")
    }

    private func planRow(_ item: V2TimelineItem) -> some View {
        let selected = store.state.selectedTimelineItemID == item.id
        return VStack(alignment: .leading, spacing: 10) {
            Button { store.selectTodayItem(item) } label: {
                HStack(alignment: .top, spacing: 12) {
                    Text(item.timeLabel).font(.caption).monospacedDigit()
                    VStack(alignment: .leading, spacing: 7) {
                        Label(item.title, systemImage: item.isDone ? "checkmark.circle.fill" : "circle.dashed")
                            .font(.headline).strikethrough(item.isDone)
                        Text(item.detail).font(.caption).foregroundStyle(.secondary)
                        if item.isDone { Text("已完成").font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(item.kind != .task)
            .accessibilityIdentifier("today.plan.\(item.title)")

            if item.kind == .task && (selected || item.isDone) {
                HStack(spacing: 12) {
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
                .font(.subheadline).buttonStyle(.bordered)
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(item.isDone ? V2Theme.ColorRole.surfaceMuted : V2Theme.ColorRole.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(selected ? V2Theme.blue.opacity(0.3) : .clear))
    }

    private func duration(_ seconds: Int) -> String {
        let seconds = max(0, seconds)
        return String(format: "%02d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
    }
}

import FocusTimelineCore
import SwiftUI

struct TodayView: View {
    @ObservedObject var store: DemoAppStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    focusCandidate
                    timeline
                }
                .padding(20)
            }
            .dailyScreen()
            .navigationBarHidden(true)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("今天")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                Text("5月27日 · 周三")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.muted)
            }

            Spacer()

            Text("晨间绿")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.white.opacity(0.72), in: Capsule())
        }
    }

    @ViewBuilder
    private var focusCandidate: some View {
        let candidate = store.state.focusCandidate
        let selectedTime = store.state.todayEvents.first(where: { $0.id == store.state.selectedTodayEventID })?.timeLabel ?? "任务列表"

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("专注候选")
                Spacer()
                Text("来自 \(selectedTime)")
            }
            .font(.caption.weight(.bold))
            .textCase(.uppercase)
            .foregroundStyle(AppTheme.ink.opacity(0.62))

            VStack(alignment: .leading, spacing: 6) {
                Text(candidate?.title ?? "选择一个任务")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text(candidate?.detail ?? "从时间线或任务列表选择后开始。")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.ink.opacity(0.7))
            }

            HStack {
                durationButton(minutes: 25)
                durationButton(minutes: 45)
                Spacer()
                Button("开始") {
                    store.startZen()
                }
                .buttonStyle(CapsuleButtonStyle(filled: true))
                .disabled(candidate == nil)
            }
        }
        .padding(18)
        .background(AppTheme.focusGradient, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: AppTheme.sage.opacity(0.35), radius: 24, x: 0, y: 16)
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(store.state.todayEvents) { event in
                timelineRow(
                    event: event,
                    isSelected: store.state.selectedTodayEventID == event.id
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.26, dampingFraction: 0.86)) {
                        store.state.selectTodayEvent(id: event.id)
                    }
                }
            }
        }
        .padding(.leading, 4)
    }

    private func durationButton(minutes: Int) -> some View {
        Button("\(minutes) 分钟") {
            store.state.selectDuration(minutes: minutes)
        }
        .buttonStyle(CapsuleButtonStyle(filled: store.state.selectedDurationMinutes == minutes))
    }

    private func timelineRow(event: DemoTimelineEntry, isSelected: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(event.timeLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? Color.white.opacity(0.7) : AppTheme.muted)
                .frame(width: 48, alignment: .leading)

            TimelineMarker(isSelected: isSelected)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(.subheadline.weight(.bold))
                Text(event.note)
                    .font(.caption)
                    .foregroundStyle(isSelected ? Color.white.opacity(0.64) : AppTheme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, isSelected ? 12 : 0)
        .background(isSelected ? AppTheme.night : Color.clear, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .foregroundStyle(isSelected ? Color.white : AppTheme.ink)
    }
}

#Preview {
    TodayView(store: DemoAppStore())
}

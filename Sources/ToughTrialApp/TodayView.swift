import SwiftUI

struct TodayView: View {
    @State private var selectedEvent = "写作提纲"
    @State private var showZenMode = false

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
            .fullScreenCover(isPresented: $showZenMode) {
                ZenModeView(taskTitle: selectedEvent)
            }
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

    private var focusCandidate: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("专注候选")
                Spacer()
                Text("来自 14:00")
            }
            .font(.caption.weight(.bold))
            .textCase(.uppercase)
            .foregroundStyle(AppTheme.ink.opacity(0.62))

            VStack(alignment: .leading, spacing: 6) {
                Text(selectedEvent)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("从时间线任务选中。可以切换时长，也可以直接开始。")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.ink.opacity(0.7))
            }

            HStack {
                Button("25 分钟") {}
                    .buttonStyle(CapsuleButtonStyle(filled: true))
                Button("45 分钟") {}
                    .buttonStyle(CapsuleButtonStyle())
                Spacer()
                Button("开始") {
                    showZenMode = true
                }
                .buttonStyle(CapsuleButtonStyle(filled: true))
            }
        }
        .padding(18)
        .background(AppTheme.focusGradient, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: AppTheme.sage.opacity(0.35), radius: 24, x: 0, y: 16)
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 0) {
            timelineRow(time: "10:30", title: "出门", note: "通勤通常约 28 分钟")

            timelineRow(
                time: "14:00",
                title: "写作提纲",
                note: "已选为专注候选 · 关联任务",
                isSelected: selectedEvent == "写作提纲"
            )
            .onTapGesture {
                selectedEvent = "写作提纲"
            }

            timelineRow(time: "16:20", title: "读书 20 页", note: "进度：50 / 1000 页")
                .onTapGesture {
                    selectedEvent = "读书 20 页"
                }

            timelineRow(time: "今晚", title: "回想", note: "可引用今天的完成记录")
        }
        .padding(.leading, 4)
    }

    private func timelineRow(time: String, title: String, note: String, isSelected: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(time)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? Color.white.opacity(0.7) : AppTheme.muted)
                .frame(width: 48, alignment: .leading)

            TimelineMarker(isSelected: isSelected)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                Text(note)
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
    TodayView()
}

import SwiftUI

struct RecallView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("回想")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                        Text("引用今天完成的任务、专注和进度记录。")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.muted)
                    }

                    VStack(spacing: 10) {
                        recallEvent("10:30", "Focus 25m", "写作提纲 completed")
                        recallEvent("16:20", "读书 20 页", "Book progress: 50 / 1000")
                        recallEvent("18:00", "站立休息", "2 分钟 completed")
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("今天下午的")
                            + Text(" 写作提纲 ")
                            .foregroundStyle(AppTheme.ink)
                            .fontWeight(.bold)
                            + Text("比预期顺。读书只推进了")
                            + Text(" 20 页 ")
                            .foregroundStyle(AppTheme.ink)
                            .fontWeight(.bold)
                            + Text("，但晚上保持了空档。")
                    }
                    .font(.body)
                    .lineSpacing(5)
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .padding(20)
            }
            .dailyScreen()
            .navigationBarHidden(true)
        }
    }

    private func recallEvent(_ time: String, _ title: String, _ note: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(time)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.muted)
                .frame(width: 48, alignment: .leading)
            TimelineMarker()
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                Text(note)
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }
            Spacer()
        }
        .padding(12)
        .background(.white.opacity(0.74), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
    }
}

#Preview {
    RecallView()
}

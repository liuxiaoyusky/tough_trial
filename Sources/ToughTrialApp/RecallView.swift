import FocusTimelineCore
import SwiftUI

struct RecallView: View {
    @ObservedObject var store: DemoAppStore
    @State private var note = "今天下午的写作提纲比预期顺。读书只推进了 20 页，但晚上保持了空档。"

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
                        ForEach(store.state.todayEvents) { event in
                            recallEvent(event.timeLabel, event.title, event.note)
                        }
                    }

                    if !store.state.completedTodayTitles.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("可引用")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(AppTheme.muted)
                            HStack {
                                ForEach(store.state.completedTodayTitles, id: \.self) { title in
                                    Button(title) {
                                        note += " \(title)"
                                    }
                                    .buttonStyle(CapsuleButtonStyle())
                                }
                            }
                        }
                    }

                    TextEditor(text: $note)
                        .font(.body)
                        .lineSpacing(5)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 180)
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
    RecallView(store: DemoAppStore())
}

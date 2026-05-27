import SwiftUI

struct PlanView: View {
    @State private var showInbox = true

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    timeline
                    backlog
                    Spacer()
                    Button("AI 规划") {}
                        .buttonStyle(CapsuleButtonStyle(filled: true))
                        .frame(maxWidth: .infinity)
                }
                .padding(20)

                if showInbox {
                    inboxPopover
                        .padding(.top, 92)
                        .padding(.trailing, 18)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .dailyScreen()
            .navigationBarHidden(true)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("计划")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                Text("5月30日 · 时间线草稿")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.muted)
            }

            Spacer()

            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    showInbox.toggle()
                }
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "tray.full")
                        .font(.headline)
                        .frame(width: 36, height: 36)
                        .background(.white.opacity(0.76), in: Circle())
                    Circle()
                        .fill(AppTheme.copper)
                        .frame(width: 8, height: 8)
                        .offset(x: -4, y: 5)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 10) {
            planEvent(time: "09:30", title: "长跑", note: "AI 排入 · 预计 55 分钟")
            planEvent(time: "??:??", title: "读书 40 页", note: "未定时间 · 可拖入合适空档", uncertain: true)

            HStack(alignment: .top, spacing: 12) {
                Text("15:00")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.muted)
                    .frame(width: 48, alignment: .leading)
                TimelineMarker()
                    .padding(.top, 18)
                HStack(spacing: 8) {
                    parallelCard("回邮件", "25 分钟")
                    parallelCard("整理资料", "可并行")
                }
            }
        }
    }

    private var backlog: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("今天可能放不下")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.muted)
                Spacer()
                Text("拖入时间线")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.muted)
            }

            backlogChip(title: "学 SwiftUI", detail: "建议拆小后再安排")
            backlogChip(title: "整理相册", detail: "低优先级 · 可改天")
        }
        .padding(.top, 12)
    }

    private var inboxPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MESSAGE INBOX")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.white.opacity(0.64))
            Text("2 条待处理")
                .font(.headline.weight(.bold))
            Text("AI 建议和夜间酝酿不占主视图，点击后弹出处理。")
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.7))

            inboxRow("AI 建议", "周六适合安排长跑")
            inboxRow("夜间酝酿", "“学 SwiftUI”建议拆成 3 步")
        }
        .frame(width: 220, alignment: .leading)
        .padding(14)
        .foregroundStyle(Color.white)
        .background(AppTheme.night.opacity(0.96), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.28), radius: 24, x: 0, y: 16)
    }

    private func planEvent(time: String, title: String, note: String, uncertain: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(time)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.muted)
                .blur(radius: uncertain ? 2.4 : 0)
                .frame(width: 48, alignment: .leading)
            TimelineMarker()
                .padding(.top, 18)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                Text(note)
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.76), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
    }

    private func parallelCard(_ title: String, _ note: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.bold))
            Text(note)
                .font(.caption2)
                .foregroundStyle(AppTheme.muted)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.76), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private func backlogChip(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.subheadline.weight(.bold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(AppTheme.muted)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [5]))
                .foregroundStyle(AppTheme.ink.opacity(0.18))
        }
    }

    private func inboxRow(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.bold))
            Text(detail)
                .font(.caption2)
                .foregroundStyle(Color.white.opacity(0.68))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}

#Preview {
    PlanView()
}

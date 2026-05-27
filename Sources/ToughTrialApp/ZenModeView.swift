import SwiftUI

struct ZenModeView: View {
    let taskTitle: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack {
            HStack {
                Text("9:42")
                Spacer()
                Text("Zen")
            }
            .font(.caption.weight(.semibold))
            .padding(.top, 20)

            Spacer()

            VStack(spacing: 18) {
                Text(taskTitle == nil ? "短句" : "当前任务")
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(Color.white.opacity(0.62))

                Text("25:00")
                    .font(.system(size: 74, weight: .medium, design: .rounded))
                    .monospacedDigit()

                Text(taskTitle ?? "把注意力放回此刻。")
                    .font(.title3.weight(.medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.white.opacity(0.86))
                    .frame(maxWidth: 280)

                Text("下一次站立：专注结束后 2 分钟")
                    .font(.footnote)
                    .foregroundStyle(Color.white.opacity(0.56))
            }

            Spacer()

            HStack(spacing: 10) {
                Button("暂停") {}
                    .buttonStyle(ZenButtonStyle())
                Button("结束") {
                    dismiss()
                }
                .buttonStyle(ZenButtonStyle())
            }
            .padding(.bottom, 18)
        }
        .padding(20)
        .foregroundStyle(Color.white)
        .background(AppTheme.zenGradient.ignoresSafeArea())
    }
}

private struct ZenButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Color.white.opacity(configuration.isPressed ? 0.16 : 0.10), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(0.10))
            }
    }
}

#Preview {
    ZenModeView(taskTitle: "写作提纲")
}

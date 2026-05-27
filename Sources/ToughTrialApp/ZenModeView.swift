import FocusTimelineCore
import SwiftUI

struct ZenModeView: View {
    let onComplete: () -> Void
    let onClose: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var session: ZenSession

    init(initialSession: ZenSession, onComplete: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.onComplete = onComplete
        self.onClose = onClose
        _session = State(initialValue: initialSession)
    }

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
                Text(session.taskTitle == nil ? "短句" : "当前任务")
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(Color.white.opacity(0.62))

                Text(session.displayTime)
                    .font(.system(size: 74, weight: .medium, design: .rounded))
                    .monospacedDigit()

                Text(session.taskTitle ?? "把注意力放回此刻。")
                    .font(.title3.weight(.medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.white.opacity(0.86))
                    .frame(maxWidth: 280)

                Text(session.isComplete ? "完成后站立 2 分钟" : "下一次站立：专注结束后 2 分钟")
                    .font(.footnote)
                    .foregroundStyle(Color.white.opacity(0.56))
            }

            Spacer()

            HStack(spacing: 10) {
                Button(session.isRunning ? "暂停" : "继续") {
                    if session.isRunning {
                        session.pause()
                    } else {
                        session.resume()
                    }
                }
                    .buttonStyle(ZenButtonStyle())

                Button(session.isComplete ? "完成" : "结束") {
                    if session.isComplete {
                        onComplete()
                    } else {
                        onClose()
                    }
                    dismiss()
                }
                .buttonStyle(ZenButtonStyle())
            }
            .padding(.bottom, 18)
        }
        .padding(20)
        .foregroundStyle(Color.white)
        .background(AppTheme.zenGradient.ignoresSafeArea())
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            session.tick(seconds: 1)
        }
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
    ZenModeView(
        initialSession: ZenSession(taskTitle: "写作提纲", durationMinutes: 25),
        onComplete: {},
        onClose: {}
    )
}

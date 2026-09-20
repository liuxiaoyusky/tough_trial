import SwiftUI
import ToughTrialV2Core

struct V2ZenView: View {
    let session: V2ActiveSession
    let onToggle: () -> Void
    let onFinish: () -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.11, blue: 0.12),
                    Color(red: 0.13, green: 0.18, blue: 0.15),
                    Color(red: 0.06, green: 0.08, blue: 0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white.opacity(0.82))
                            .frame(width: 42, height: 42)
                            .background(.white.opacity(0.10), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("回到今天")
                    .accessibilityIdentifier("zen.close")

                    Spacer()

                    Text(session.status == .running ? "Zen" : "暂停中")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white.opacity(0.70))
                        .monospaced()
                        .accessibilityIdentifier("zen.status")
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)

                Spacer(minLength: 36)

                VStack(spacing: 15) {
                    Text(session.taskID == nil ? "未关联任务" : "当前任务")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.52))

                    Text(Self.formattedDuration(session.currentElapsedSeconds))
                        .font(.system(size: 74, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.72)
                        .lineLimit(1)
                        .accessibilityIdentifier("zen.timer")

                    Text(session.title)
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 28)
                        .accessibilityIdentifier("zen.title")

                    Text(footerText)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white.opacity(0.50))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 38)
                }
                .frame(maxWidth: .infinity)

                Spacer(minLength: 44)

                HStack(spacing: 12) {
                    Button(action: onToggle) {
                        Label(session.status == .running ? "暂停" : "继续", systemImage: session.status == .running ? "pause.fill" : "play.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white.opacity(0.92))
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(.white.opacity(0.13), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(.white.opacity(0.10), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("zen.toggle")

                    Button(action: onFinish) {
                        Text("结束时间段")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color(red: 0.08, green: 0.10, blue: 0.11))
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(Color(red: 0.94, green: 0.89, blue: 0.78), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("zen.finish")
                }
                .padding(.horizontal, 26)
                .padding(.bottom, 30)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private var footerText: String {
        if session.taskID == nil {
            return "结束后可以只保存时间段，也可以回到今天再关联任务。"
        }
        return "结束后写回任务用时；是否完成任务，回到今天时间线决定。"
    }

    private static func formattedDuration(_ seconds: Int) -> String {
        let value = max(seconds, 0)
        if value >= 3_600 {
            return "\(value / 3_600):\(String(format: "%02d", (value % 3_600) / 60)):\(String(format: "%02d", value % 60))"
        }
        return "\(value / 60):\(String(format: "%02d", value % 60))"
    }
}

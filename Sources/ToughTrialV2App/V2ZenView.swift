import SwiftUI
import ToughTrialV2Core

struct V2ZenView: View {
    let session: V2ActiveSession
    let onFinish: () -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.05, blue: 0.07),
                    Color(red: 0.08, green: 0.09, blue: 0.13)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white.opacity(0.82))
                            .frame(width: 42, height: 42)
                            .background(.white.opacity(0.10))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("关闭")

                    Spacer()

                    Text(session.status == .running ? "专注中" : "已暂停")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.72))
                        .frame(minWidth: 72)
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)

                Spacer(minLength: 34)

                VStack(spacing: 18) {
                    Text(session.title)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 28)

                    ZStack {
                        Circle()
                            .stroke(.white.opacity(0.08), lineWidth: 18)
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(
                                V2Theme.blue,
                                style: StrokeStyle(lineWidth: 18, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))

                        VStack(spacing: 8) {
                            Text(Self.formattedMinutes(session.currentElapsed))
                                .font(.system(size: 56, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                                .minimumScaleFactor(0.75)
                                .lineLimit(1)
                                .frame(minWidth: 190)

                            Text("累计 \(Self.formattedMinutes(session.totalElapsed))")
                                .font(.subheadline.weight(.medium))
                                .monospacedDigit()
                                .foregroundStyle(.white.opacity(0.62))
                        }
                    }
                    .frame(width: 272, height: 272)

                    Text("开始 \(session.startedAtLabel)")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white.opacity(0.50))
                        .monospacedDigit()
                }

                Spacer(minLength: 42)

                Button(action: onFinish) {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 17, weight: .bold))
                        Text("完成")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(V2Theme.blue)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 34)
                .padding(.bottom, 30)
            }
        }
    }

    private var progress: CGFloat {
        let targetMinutes = max(session.totalElapsed + session.currentElapsed, 25)
        return min(max(CGFloat(session.currentElapsed) / CGFloat(targetMinutes), 0.08), 1)
    }

    private static func formattedMinutes(_ minutes: Int) -> String {
        if minutes >= 60 {
            return "\(minutes / 60):\(String(format: "%02d", minutes % 60))"
        }
        return "\(minutes):00"
    }
}

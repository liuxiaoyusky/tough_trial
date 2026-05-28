import SwiftUI
import ToughTrialV2Core

struct V2ZenView: View {
    let session: V2ActiveSession
    let onFinish: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Zen")
                .font(.title.weight(.semibold))
                .foregroundStyle(V2Theme.ink)

            Text(session.title)
                .foregroundStyle(V2Theme.secondary)

            HStack(spacing: 12) {
                Button("完成") {
                    onFinish()
                }
                .buttonStyle(.borderedProminent)
                .tint(V2Theme.blue)

                Button("关闭") {
                    onClose()
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .v2ScreenBackground()
    }
}

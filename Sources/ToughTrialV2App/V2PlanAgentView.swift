import SwiftUI

struct V2PlanAgentView: View {
    @ObservedObject var store: V2AppStore

    var body: some View {
        VStack(spacing: 16) {
            Text("计划")
                .font(.title.weight(.semibold))
                .foregroundStyle(V2Theme.ink)

            Button("关闭") {
                store.closePlanAgent()
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .v2ScreenBackground()
    }
}

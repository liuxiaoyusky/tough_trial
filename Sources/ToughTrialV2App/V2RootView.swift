import SwiftUI
import ToughTrialV2Core

struct V2RootView: View {
    @StateObject private var store = V2AppStore()

    var body: some View {
        TabView {
            V2TodayView(store: store)
                .tabItem {
                    Label("今天", systemImage: "calendar")
                }

            V2TasksView(store: store)
                .tabItem {
                    Label("任务", systemImage: "square.stack.3d.up")
                }

            V2PlanLauncherView(store: store)
                .tabItem {
                    Label("计划", systemImage: "sparkles")
                }

            V2RecallView(store: store)
                .tabItem {
                    Label("回想", systemImage: "clock.arrow.circlepath")
                }
        }
        .tint(V2Theme.blue)
        .fullScreenCover(isPresented: $store.isPlanPresented) {
            V2PlanAgentView(store: store)
        }
        .fullScreenCover(isPresented: zenPresentationBinding) {
            if let session = store.zenSession {
                V2ZenView(
                    session: session,
                    onFinish: store.finishZen,
                    onClose: store.closeZen
                )
            }
        }
    }

    private var zenPresentationBinding: Binding<Bool> {
        Binding(
            get: { store.zenSession != nil },
            set: { isPresented in
                if !isPresented {
                    store.closeZen()
                }
            }
        )
    }
}

private struct V2PlanLauncherView: View {
    @ObservedObject var store: V2AppStore

    var body: some View {
        VStack(spacing: 16) {
            Text("计划")
                .font(.title.weight(.semibold))
                .foregroundStyle(V2Theme.ink)

            Button("打开计划 Agent") {
                store.openPlanAgent()
            }
            .buttonStyle(.borderedProminent)
            .tint(V2Theme.blue)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .v2ScreenBackground()
    }
}

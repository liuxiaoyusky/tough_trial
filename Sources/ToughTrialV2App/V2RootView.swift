import SwiftUI
import ToughTrialV2Core

struct V2RootView: View {
    @StateObject private var store = V2AppStore()
    @State private var selectedTab = V2RootTab.today

    var body: some View {
        TabView(selection: tabSelection) {
            V2TodayView(store: store)
                .tabItem {
                    Label("今天", systemImage: "calendar")
                }
                .tag(V2RootTab.today)

            V2TasksView(store: store)
                .tabItem {
                    Label("任务", systemImage: "square.stack.3d.up")
                }
                .tag(V2RootTab.tasks)

            Color.clear
                .tabItem {
                    Label("计划", systemImage: "sparkles")
                }
                .tag(V2RootTab.plan)

            V2RecallView(store: store)
                .tabItem {
                    Label("回想", systemImage: "clock.arrow.circlepath")
                }
                .tag(V2RootTab.recall)
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

    private var tabSelection: Binding<V2RootTab> {
        Binding(
            get: { selectedTab },
            set: { newTab in
                if newTab == .plan {
                    store.openPlanAgent()
                } else {
                    selectedTab = newTab
                }
            }
        )
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

private enum V2RootTab: Hashable {
    case today
    case tasks
    case plan
    case recall
}

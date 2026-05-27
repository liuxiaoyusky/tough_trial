import FocusTimelineCore
import SwiftUI

@MainActor
final class DemoAppStore: ObservableObject {
    @Published var state = InteractiveDemoState.sample()
    @Published var activeZenSession: ZenSession?

    func startZen() {
        activeZenSession = ZenSession(
            taskTitle: state.focusCandidate?.title,
            durationMinutes: state.selectedDurationMinutes
        )
    }

    func finishCurrentFocus() {
        state.completeFocusCandidate(atLabel: "刚刚")
        activeZenSession = nil
    }

    func closeZen() {
        activeZenSession = nil
    }
}

struct RootView: View {
    @StateObject private var store = DemoAppStore()

    var body: some View {
        TabView {
            TodayView(store: store)
            .tabItem {
                Label("今天", systemImage: "timeline.selection")
            }

            TasksView(store: store)
            .tabItem {
                Label("任务", systemImage: "checklist")
            }

            PlanView(store: store)
            .tabItem {
                Label("计划", systemImage: "calendar")
            }

            RecallView(store: store)
            .tabItem {
                Label("回想", systemImage: "book.pages")
            }
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { store.activeZenSession != nil },
                set: { isPresented in
                    if !isPresented {
                        store.closeZen()
                    }
                }
            )
        ) {
            if let session = store.activeZenSession {
                ZenModeView(
                    initialSession: session,
                    onComplete: store.finishCurrentFocus,
                    onClose: store.closeZen
                )
            }
        }
    }
}

#Preview {
    RootView()
}

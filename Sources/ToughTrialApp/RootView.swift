import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            TodayView()
            .tabItem {
                Label("今天", systemImage: "timeline.selection")
            }

            TasksView()
            .tabItem {
                Label("任务", systemImage: "checklist")
            }

            PlanView()
            .tabItem {
                Label("计划", systemImage: "calendar")
            }

            RecallView()
            .tabItem {
                Label("回想", systemImage: "book.pages")
            }
        }
    }
}

#Preview {
    RootView()
}

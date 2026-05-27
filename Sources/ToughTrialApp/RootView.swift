import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            NavigationStack {
                TodayShellView()
            }
            .tabItem {
                Label("今天", systemImage: "timeline.selection")
            }

            NavigationStack {
                TasksShellView()
            }
            .tabItem {
                Label("任务", systemImage: "checklist")
            }

            NavigationStack {
                PlanShellView()
            }
            .tabItem {
                Label("计划", systemImage: "calendar")
            }

            NavigationStack {
                RecallShellView()
            }
            .tabItem {
                Label("回想", systemImage: "book.pages")
            }
        }
    }
}

private struct TodayShellView: View {
    var body: some View {
        Text("今天")
            .font(.largeTitle.weight(.bold))
            .navigationTitle("今天")
    }
}

private struct TasksShellView: View {
    var body: some View {
        Text("任务")
            .font(.largeTitle.weight(.bold))
            .navigationTitle("任务")
    }
}

private struct PlanShellView: View {
    var body: some View {
        Text("计划")
            .font(.largeTitle.weight(.bold))
            .navigationTitle("计划")
    }
}

private struct RecallShellView: View {
    var body: some View {
        Text("回想")
            .font(.largeTitle.weight(.bold))
            .navigationTitle("回想")
    }
}

#Preview {
    RootView()
}

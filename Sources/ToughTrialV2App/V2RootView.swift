import SwiftUI
import ToughTrialV2Core

struct V2RootView: View {
    @StateObject private var store: V2AppStore
    @State private var selectedTab = V2RootTab.today
    private let recallDrawingStore: V2RecallDrawingStore

    init() {
        let isUITesting =
            ProcessInfo.processInfo.environment["TOUGH_TRIAL_UI_TESTING"] == "1"
        recallDrawingStore = isUITesting
            ? V2RecallDrawingStore(
                baseDirectory: FileManager.default.temporaryDirectory
                    .appendingPathComponent(
                        "ToughTrialUITesting-\(UUID().uuidString)",
                        isDirectory: true
                    )
            )
            : V2RecallDrawingStore()
        _store = StateObject(
            wrappedValue: isUITesting
                ? Self.makeUITestStore()
                : V2AppStore()
        )
    }

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

            V2RecallView(
                store: store,
                drawingStore: recallDrawingStore
            )
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
                    onToggle: { store.toggleZenSession() },
                    onFinish: { store.finishZen() },
                    onClose: store.closeZen
                )
            }
        }
        .task {
            await store.runClock()
        }
        .onOpenURL { url in
            guard url.scheme == "toughtrial", url.host == "today" else { return }
            store.closePlanAgent()
            store.closeZen()
            selectedTab = .today
        }
    }

    private var tabSelection: Binding<V2RootTab> {
        Binding(
            get: { selectedTab },
            set: { newTab in
                if newTab == .plan {
                    store.openPlanAgent()
                } else {
                    if newTab == .recall {
                        store.refreshRecallEvidence()
                    }
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

    private static func makeUITestStore() -> V2AppStore {
        let engine = V2Engine()
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)

        if let context = try? engine.createTaskContext(
            title: "自媒体成长",
            colorName: "teal",
            at: startedAt
        ), let root = try? engine.createTask(
            title: "建立稳定创作系统",
            contextID: context.id,
            kind: .goal,
            at: startedAt.addingTimeInterval(1)
        ) {
            if let positioning = try? engine.createTask(
                title: "定位",
                parentID: root.id,
                at: startedAt.addingTimeInterval(2)
            ) {
                let boundary = try? engine.createTask(
                    title: "内容边界",
                    parentID: positioning.id,
                    at: startedAt.addingTimeInterval(3)
                )
                _ = try? engine.createTask(
                    title: "目标读者",
                    parentID: positioning.id,
                    at: startedAt.addingTimeInterval(4)
                )
                if let boundary {
                    _ = try? engine.completeTask(
                        id: boundary.id,
                        at: startedAt.addingTimeInterval(5)
                    )
                }
            }

            if let topics = try? engine.createTask(
                title: "选题库",
                parentID: root.id,
                at: startedAt.addingTimeInterval(6)
            ) {
                _ = try? engine.createTask(
                    title: "建立对标账号",
                    parentID: topics.id,
                    at: startedAt.addingTimeInterval(7)
                )
                _ = try? engine.createTask(
                    title: "找对标爆款",
                    parentID: topics.id,
                    at: startedAt.addingTimeInterval(8)
                )
            }
        }

        return V2AppStore(
            engine: engine,
            memoryEngine: V2MemoryEngine()
        )
    }
}

private enum V2RootTab: Hashable {
    case today
    case tasks
    case plan
    case recall
}

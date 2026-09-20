import SwiftUI
import ToughTrialV2Core

struct V2RootView: View {
    @StateObject private var store: V2AppStore
    @StateObject private var assistantStore: V2AssistantStore
    @ObservedObject private var plugins = V2PluginStore.shared
    @ObservedObject private var navigation = V2NavigationStore.shared
    @State private var showPlugins = false
    @State private var showHiddenCapture = false
    @State private var showHiddenToday = false
    @State private var showHiddenTasks = false
    @State private var standaloneQuickAction: V2QuickCaptureRequest?
    @ObservedObject private var financeNotifications = V2FinanceNotifications.shared
    @State private var financeDestination: V2FinancePlan?
    @State private var quickCaptureRequest: V2QuickCaptureRequest?
    @State private var selectedTab = V2NavigationID.assistant
    @State private var standaloneModule: V2NavigationID?
    @State private var showHiddenAssistant = false
    @Environment(\.scenePhase) private var scenePhase
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
        let appStore = isUITesting ? Self.makeUITestStore() : V2AppStore()
        _store = StateObject(wrappedValue: appStore)
        _assistantStore = StateObject(wrappedValue: V2AssistantStore(appStore: appStore))
    }

    var body: some View {
        ZStack {
            if store.zenSession == nil {
                rootContent
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        V2BottomNavigationBar(
                            navigation: navigation,
                            availableIDs: availableNavigationIDs,
                            selection: tabSelection
                        )
                    }
            } else {
                Color.clear
                    .accessibilityHidden(true)
            }
        }
        .v2Sheet(isPresented: $showPlugins) {
            NavigationStack { V2PluginsView(appStore: store).toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showPlugins = false }.accessibilityIdentifier("plugins.done") } } }
        }
        .v2Sheet(isPresented: $showHiddenCapture) {
            V2CaptureView(appStore: store, client: Self.captureTestClient, quickRequest: $quickCaptureRequest)
        }
        .v2Sheet(isPresented: $showHiddenToday) { V2TodayView(store: store) }
        .v2Sheet(isPresented: $showHiddenTasks) { V2TasksView(store: store) }
        .v2Sheet(item: $standaloneModule) { item in
            standaloneContent(item)
        }
        .v2Sheet(item: $standaloneQuickAction) { request in
            if request.action == .ledger { V2CaptureLedgerForm(store: V2CaptureStore(appStore: store)) }
            else if request.action == .task { V2QuickTaskForm(store: V2CaptureStore(appStore: store)) }
        }
        .v2Sheet(item: $financeDestination) { plan in
            NavigationStack {
                V2FinanceView(captureStore: V2CaptureStore(appStore: store), initialPlanID: plan.id)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { financeDestination = nil } } }
            }
        }
        .onChange(of: financeNotifications.selectedPlanID) { _, id in
            guard let id else { return }
            if plugins.enabled("finance") { financeDestination = store.engine.snapshot.capture.finance?.plans.first { $0.id == id } }
            else { showPlugins = true }
            financeNotifications.selectedPlanID = nil
        }
        .onAppear {
            navigation.reconcile(availableIDs: availableNavigationIDs)
            if !navigation.orderedTabs.contains(selectedTab) { selectedTab = preferredNavigationTab }
            store.moduleSceneActive = scenePhase == .active
            store.reconcileStoppedModules()
            if scenePhase == .active { store.startForegroundScheduleSync() }
            #if DEBUG
            if ProcessInfo.processInfo.environment["TOUGH_TRIAL_UI_TESTING"] == "1",
               let value = ProcessInfo.processInfo.environment["TOUGH_TRIAL_UI_TEST_QUICK_URL"],
               let url = URL(string: value), let action = V2QuickCaptureAction(url: url), quickCaptureRequest == nil {
                quickCaptureRequest = .init(action: action); selectedTab = .capture
            }
            #endif
        }
        .onReceive(NotificationCenter.default.publisher(for: .v2ModulesChanged)) { _ in
            store.reconcileStoppedModules()
            if plugins.enabled("sync") { store.startForegroundScheduleSync() } else { store.stopForegroundScheduleSync() }
            if !plugins.enabled("tasks") {
                store.scheduleReminderTask?.cancel()
                store.notificationService.cancel(planIDs: Set(store.engine.snapshot.planItems.map(\.id)))
            }
            Task { await financeNotifications.refresh(store.engine.snapshot.capture.finance?.plans ?? []) }
        }
        .onChange(of: plugins.preferences) { _, _ in
            navigation.reconcile(availableIDs: availableNavigationIDs)
            if !navigation.orderedTabs.contains(selectedTab) { selectedTab = preferredNavigationTab }
            if !plugins.enabled("assistant") { assistantStore.cancelCurrentTurn(); store.closePlanAgent() }
            if !plugins.enabled("sync") { store.pendingScheduleConflict = nil }
            if !plugins.enabled("capture") { showHiddenCapture = false }
            if !plugins.enabled("tasks") { showHiddenToday = false; showHiddenTasks = false }
        }
        .onChange(of: navigation.preferences) { _, _ in
            if !navigation.orderedTabs.contains(selectedTab) {
                selectedTab = preferredNavigationTab
            }
        }
        .onChange(of: scenePhase) { _, phase in
            store.moduleSceneActive = phase == .active
            if phase == .active {
                store.startForegroundScheduleSync()
                Task { await financeNotifications.refresh(store.engine.snapshot.capture.finance?.plans ?? []) }
            }
            else { store.stopForegroundScheduleSync() }
        }
        .v2Sheet(isPresented: $showHiddenAssistant) { assistantHome }
        .onChange(of: store.isPlanPresented) { _, presented in
            guard presented else { return }
            if let task = store.planningSourceTask {
                _ = assistantStore.openContextSession(for: V2AgentSourceTask(id: task.id, title: task.title, note: task.subtitle))
            }
            if navigation.orderedTabs.contains(.assistant) { selectedTab = .assistant }
            else { showHiddenAssistant = true }
            store.closePlanAgent()
        }
        .v2FullScreenCover(isPresented: zenPresentationBinding) {
            if let session = store.zenSession {
                V2ZenView(
                    session: session,
                    onToggle: { store.toggleZenSession() },
                    onFinish: { store.finishZen() },
                    onClose: store.closeZen
                )
                .interactiveDismissDisabled()
            }
        }
        .task {
            await financeNotifications.refresh(store.engine.snapshot.capture.finance?.plans ?? [])
            await store.runClock()
        }
        .onOpenURL { url in
            if let action = V2QuickCaptureAction(url: url) {
                guard action != .ledger || plugins.enabled("ledger"), action != .task || plugins.enabled("tasks"), action != .note || plugins.enabled("capture") else { showPlugins = true; return }
                store.closePlanAgent(); store.closeZen()
                if !plugins.enabled("capture") {
                    standaloneQuickAction = .init(action: action)
                    return
                }
                quickCaptureRequest = .init(action: action)
                if navigation.orderedTabs.contains(.capture) { selectedTab = .capture } else { showHiddenCapture = true }
            } else if url.scheme == "toughtrial", url.host == "today" {
                guard plugins.enabled("tasks") else { showPlugins = true; return }
                store.closePlanAgent(); store.closeZen()
                if navigation.orderedTabs.contains(.today) { selectedTab = .today } else { showHiddenToday = true }
            }
        }
    }

    private var availableNavigationIDs: Set<V2NavigationID> {
        Set(V2NavigationID.allCases.filter { item in
            guard let moduleID = item.requiredModuleID else { return true }
            return plugins.enabled(moduleID)
        })
    }

    private var preferredNavigationTab: V2NavigationID {
        navigation.orderedTabs.first(where: { $0 != .morePlugins }) ?? .morePlugins
    }

    @ViewBuilder
    private var rootContent: some View {
        switch selectedTab {
        case .assistant:
            assistantHome
        case .today:
            V2TodayView(store: store)
        case .tasks:
            V2TasksView(store: store)
        case .capture:
            V2CaptureView(appStore: store, client: Self.captureTestClient, quickRequest: $quickCaptureRequest)
        case .recall:
            V2RecallView(store: store, drawingStore: recallDrawingStore)
        case .ownProfile:
            V2OwnProfileView()
        case .morePlugins:
            V2MorePluginsView(
                appStore: store,
                navigation: navigation,
                availableIDs: availableNavigationIDs,
                openModule: openModuleFromMore
            )
        }
    }

    @ViewBuilder
    private func standaloneContent(_ item: V2NavigationID) -> some View {
        switch item {
        case .assistant: assistantHome
        case .today: V2TodayView(store: store)
        case .tasks: V2TasksView(store: store)
        case .capture: V2CaptureView(appStore: store, client: Self.captureTestClient, quickRequest: $quickCaptureRequest)
        case .recall: V2RecallView(store: store, drawingStore: recallDrawingStore)
        case .ownProfile: V2OwnProfileView()
        case .morePlugins: EmptyView()
        }
    }

    private func openModuleFromMore(_ item: V2NavigationID) {
        if navigation.orderedTabs.contains(item) { selectedTab = item }
        else { standaloneModule = item }
    }

    private var assistantHome: some View {
        V2AssistantView(store: assistantStore, appStore: store, onExit: {
            showHiddenAssistant = false
            selectedTab = navigation.orderedTabs.contains(.today) ? .today : preferredNavigationTab
        }, embedded: true, onOpenSource: { id in
            guard plugins.enabled("tasks") else { showPlugins = true; return }
            store.assistantReturnTaskID = id
            if navigation.orderedTabs.contains(.tasks) { selectedTab = .tasks }
            else { showHiddenTasks = true }
        })
    }

    private var assistantEntry: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(V2Theme.blue)
            Text("说点什么，交给助手整理").font(.headline)
            Button("打开助手") { store.openPlanAgent() }
                .buttonStyle(.borderedProminent).accessibilityIdentifier("plugins.assistant.fallback")
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(V2Theme.page)
    }

    private static var captureTestClient: (any V2CaptureClient)? {
        #if DEBUG
        if ProcessInfo.processInfo.environment["TOUGH_TRIAL_UI_TEST_CAPTURE"] == "1" { return V2CaptureUITestClient() }
        #endif
        return nil
    }

    private var tabSelection: Binding<V2NavigationID> {
        Binding(
            get: { selectedTab },
            set: { newTab in
                if newTab == .recall { store.refreshRecallEvidence() }
                selectedTab = newTab
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
#if DEBUG
        if let fixtureID = ProcessInfo.processInfo.environment["TOUGH_TRIAL_UI_FILE_FIXTURE"],
           let id = UUID(uuidString: fixtureID) {
            return makeFileUITestStore(id: id)
        }
#endif
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

#if DEBUG
    /// Seed files only; all reads, writes, and recovery run through the normal UI.
    private static func makeFileUITestStore(id: UUID) -> V2AppStore {
        do {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("ScheduleFileUITest-\(id.uuidString)", isDirectory: true)
            let snapshotURL = directory.appendingPathComponent("snapshot.json")
            let baselineURL = directory.appendingPathComponent("baseline.json")
            let file = directory.appendingPathComponent("日程.md")
            let snapshotStore = V2JSONSnapshotStore(fileURL: snapshotURL)
            let mode = ProcessInfo.processInfo.environment["TOUGH_TRIAL_UI_FILE_MODE"]
            if mode == "seed" {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let engine = V2Engine(store: snapshotStore)
                _ = try engine.createTask(title: "文件原始任务")
                let document = try engine.prepareScheduleDocument(timeZoneIdentifier: "Asia/Shanghai")
                try Data(V2ScheduleMarkdown.encode(document).utf8).write(to: file, options: .atomic)
                let read = try V2ScheduleFileIO.read(url: file)
                try engine.recordScheduleFileWrite(document, bookmark: read.bookmark, fileName: file.lastPathComponent)
                try V2JSONSnapshotStore(fileURL: baselineURL).save(engine.snapshot)
                var edited = document
                edited.tasks[0].title = "电脑修改后的任务"
                try Data(V2ScheduleMarkdown.encode(edited).utf8).write(to: file, options: .atomic)
            } else if mode == "readback" {
                // Keep the written Markdown, but remove all local changes made by the test.
                try snapshotStore.save(V2JSONSnapshotStore(fileURL: baselineURL).load())
            }
            return V2AppStore(engine: try V2Engine.load(from: snapshotStore), memoryEngine: V2MemoryEngine())
        } catch {
            fatalError("Schedule file UI fixture failed: \(error)")
        }
    }
#endif
}

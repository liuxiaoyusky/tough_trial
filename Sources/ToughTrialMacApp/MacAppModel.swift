import SwiftUI
import Combine
import ToughTrialAppShared
import ToughTrialV2Core

/// One desktop document owner. Every surface writes through the same engine.
@MainActor
final class MacAppModel: ObservableObject {
    let workspace: V2TaskWorkspace
    let store: V2AppStore
    let capture: V2CaptureStore
    let assistant: V2AssistantStore
    let directory: URL
    @Published var page = MacPage.tasks
    @Published var closeIssue: String?
    @Published private(set) var isShuttingDown = false
    private var clockTask: Task<Void, Never>?

    func startServices() {
        guard !isShuttingDown, clockTask == nil else { return }
        store.reconcileStoppedModules()
        store.startForegroundScheduleSync()
        clockTask = Task { [store] in
            await V2FinanceNotifications.shared.refresh(store.engine.snapshot.capture.finance?.plans ?? [])
            guard !Task.isCancelled else { return }
            await store.runClock()
        }
    }

    init(directory: URL) throws {
        self.directory = directory
        workspace = try V2TaskWorkspace(directory: directory)
        store = V2AppStore(engine: workspace.engine, memoryStoreURL: directory.appendingPathComponent("memory.json"))
        capture = V2CaptureStore(appStore: store, assetDirectory: directory.appendingPathComponent("capture-assets", isDirectory: true))
        assistant = V2AssistantStore(dependencies: store.makeAssistantDependencies(),
            persistence: V2AssistantWorkspacePersistence(store: V2AgentWorkspaceJSONStore(fileURL: directory.appendingPathComponent("assistant.json"))),
            archive: V2AssistantArchive(rootURL: directory.appendingPathComponent("assistant-context")))
        let previous = workspace.engine.onCommandCommitted
        workspace.engine.onCommandCommitted = { [weak self] command in
            previous?(command)
            // Defer projection until the command's atomic commit has returned.
            Task { @MainActor in
                guard let self else { return }
                self.workspace.refreshExternalChanges()
                self.store.refreshProjection(at: Date())
                self.capture.refresh()
            }
        }
    }

    func select(_ page: MacPage) {
        guard preserve() else { return }
        self.page = page
        if page == .recall { store.refreshRecallEvidence() }
    }

    func openTaskPlan(_ id: String) {
        guard !workspace.hasChanges || workspace.save() else { closeIssue = workspace.issue; return }
        store.refreshProjection(at: Date())
        guard let current = store.state.flattenTasks().first(where: { $0.id == id }) else { return }
        store.openPlanAgent(for: current)
    }

    func openSourceTask(_ id: String) {
        guard workspace.select(id) else { closeIssue = workspace.issue; return }
        select(.tasks)
    }

    func shutdown() async -> Bool {
        guard !isShuttingDown else { return false }
        isShuttingDown = true
        defer { isShuttingDown = false; store.isStoppingServices = false }
        guard preserve() else { return false }
        store.isStoppingServices = true
        store.moduleSceneActive = false
        let clock = clockTask
        clockTask = nil
        clock?.cancel()
        let syncing = store.foregroundScheduleSyncTask
        store.stopForegroundScheduleSync()
        assistant.cancelCurrentTurn()
        await capture.cancelAndWait()
        await assistant.waitForCurrentTurn()
        await clock?.value
        await syncing?.value
        let saved = preserve()
        if !saved {
            store.isStoppingServices = false
            store.moduleSceneActive = true
            isShuttingDown = false
            startServices()
        }
        return saved
    }

    func preserve() -> Bool {
        guard assistant.flushVisibleDraft?() != false else {
            closeIssue = assistant.storageIssueMessage ?? "助手输入尚未保存，请重试。"; return false
        }
        guard workspace.preserveBeforeClosing() else { closeIssue = workspace.issue; return false }
        if !capture.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !capture.mediaBlocks.isEmpty {
            guard capture.saveDraft() != nil else { closeIssue = capture.issue; return false }
        }
        if store.isRecallDirty, !store.saveRecall() { closeIssue = store.errorMessage; return false }
        closeIssue = nil
        return true
    }
}

enum MacPage: String, CaseIterable, Identifiable {
    case today = "今天", tasks = "任务", capture = "随手记", finance = "理账", assistant = "助手", recall = "回想", settings = "设置"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .today: "sun.max"
        case .tasks: "checklist"
        case .capture: "square.and.pencil"
        case .finance: "chart.bar.xaxis"
        case .assistant: "sparkles"
        case .recall: "clock.arrow.circlepath"
        case .settings: "slider.horizontal.3"
        }
    }
    var module: String {
        switch self {
        case .today, .tasks: "tasks"
        case .capture: "capture"
        case .finance: "finance"
        case .assistant: "assistant"
        case .recall: "recall"
        case .settings: "settings"
        }
    }
}

import SwiftUI
import AppKit
import ToughTrialV2Core

struct MacRootView: View {
    @ObservedObject var model: MacAppModel
    @ObservedObject var store: V2AppStore
    @ObservedObject private var plugins = V2PluginStore.shared
    @ObservedObject private var financeNotifications = V2FinanceNotifications.shared
    @State private var financeDestination: V2FinancePlan?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tough Trial").font(.system(size: 21, weight: .bold, design: .rounded))
                    Text("留一点空间，做重要的事").font(.caption).foregroundStyle(V2Theme.secondary)
                }.padding(.vertical, 24).padding(.horizontal, 10)
                ForEach(MacPage.allCases.filter { $0 != .settings && isVisible($0) }) { page in navigation(page) }
                Spacer()
                Label("本地优先", systemImage: "externaldrive").font(.caption).foregroundStyle(V2Theme.secondary).padding(10)
                navigation(.settings)
            }.padding(14).frame(width: 185).background(V2Theme.ColorRole.surfaceMuted)
            Group {
                if model.page != .settings && !isVisible(model.page) {
                    ContentUnavailableView {
                        Label("功能已停用", systemImage: model.page.symbol)
                    } description: { Text("已有资料仍保留，重新开启后可以继续使用。") }
                    actions: { Button("打开设置") { model.select(.settings) } }
                } else {
                    switch model.page {
                    case .today: V2TodayView(store: store)
                    case .tasks: MacTaskWorkspaceView(workspace: model.workspace, store: store, onPlan: { model.openTaskPlan($0) })
                    case .capture: V2CaptureView(store: model.capture)
                    case .finance: MacFinanceWorkspace(store: model.capture)
                    case .assistant:
                        V2AssistantView(store: model.assistant, appStore: store, onExit: { model.select(.today) }, embedded: true,
                            onOpenSource: { model.openSourceTask($0) })
                    case .recall: MacRecallView(store: store)
                    case .settings: MacSettingsView(store: store, directory: model.directory)
                    }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .disabled(model.isShuttingDown)
        .background(V2Theme.page).tint(V2Theme.blue)
        .sheet(isPresented: Binding(get: { store.zenSession != nil }, set: { if !$0 { store.closeZen() } })) {
            if let session = store.zenSession {
                V2ZenView(session: session, onToggle: { store.toggleZenSession() }, onFinish: { store.finishZen() }, onClose: store.closeZen)
                    .frame(minWidth: 650, minHeight: 550)
            }
        }
        .sheet(item: $financeDestination) { plan in
            NavigationStack {
                V2FinanceView(captureStore: model.capture, initialPlanID: plan.id)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { financeDestination = nil } } }
            }.frame(minWidth: 600, minHeight: 580)
        }
        .onChange(of: financeNotifications.selectedPlanID) { _, id in
            if let id, plugins.enabled("finance") {
                financeDestination = store.engine.snapshot.capture.finance?.plans.first { $0.id == id }
            }
            financeNotifications.selectedPlanID = nil
        }
        .alert("内容暂未保存", isPresented: Binding(get: { model.closeIssue != nil }, set: { if !$0 { model.closeIssue = nil } })) {
            Button("返回编辑", role: .cancel) {}
        } message: { Text(model.closeIssue ?? "请检查资料目录的访问权限。") }
        .onChange(of: store.isPlanPresented) { _, presented in
            guard presented else { return }
            if let task = store.planningSourceTask {
                _ = model.assistant.openContextSession(for: V2AgentSourceTask(id: task.id, title: task.title, note: task.subtitle))
            }
            model.select(.assistant); store.closePlanAgent()
        }
        .onChange(of: scenePhase) { _, phase in
            guard !model.isShuttingDown else { return }
            store.moduleSceneActive = phase == .active
            if phase == .active { store.startForegroundScheduleSync() }
            else { store.stopForegroundScheduleSync(); _ = model.preserve() }
        }
        .onChange(of: plugins.preferences) { _, _ in
            if !isVisible(model.page) { model.select(.settings) }
            if !plugins.enabled("assistant") { model.assistant.cancelCurrentTurn(); store.closePlanAgent() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .v2ModulesChanged)) { _ in
            guard !model.isShuttingDown else { return }
            store.reconcileStoppedModules()
            if plugins.enabled("sync") { store.startForegroundScheduleSync() } else { store.stopForegroundScheduleSync() }
        }
        .onAppear { model.startServices() }
    }
    private func isVisible(_ page: MacPage) -> Bool {
        if page == .settings { return true }
        if page == .finance { return ["ledger", "finance", "budget"].contains { plugins.enabled($0) } }
        return plugins.visible(page == .today ? "today" : page.module)
    }
    private func navigation(_ page: MacPage) -> some View {
        Button { model.select(page) } label: {
            Label(page.rawValue, systemImage: page.symbol).font(.system(size: 15, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                .foregroundStyle(model.page == page ? V2Theme.blue : V2Theme.secondary)
                .background(model.page == page ? V2Theme.panel : .clear, in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).accessibilityIdentifier("mac.nav.\(page.module).\(page.rawValue)")
            .accessibilityAddTraits(model.page == page ? .isSelected : [])
    }
}

struct MacSettingsView: View {
    @ObservedObject var store: V2AppStore
    let directory: URL
    var body: some View {
        NavigationStack {
            Form {
                Section("连接与输入") {
                    NavigationLink("AI 服务与模型") { V2AIProviderSettingsView(store: store) }
                    NavigationLink("语音输入") { V2SpeechSettingsView() }
                }
                Section("资料与同步") {
                    NavigationLink("GitHub 日程同步") { V2ScheduleGitHubView(store: store) }
                    NavigationLink("日程文件与历史版本") { V2ScheduleFilesView(store: store) }
                    Text("当前 GitHub 同步范围为任务与日程。随手记、账单、回想、聊天和附件仅保存在本机；全量内容同步尚未开放。")
                        .font(.callout).foregroundStyle(V2Theme.secondary)
                    Button("在 Finder 中查看本机资料") { NSWorkspace.shared.open(directory) }
                }
                Section("功能") {
                    NavigationLink("功能与插件") { V2PluginsView(appStore: store) }
                    NavigationLink("运行记录") { V2UsageTraceView() }
                }
            }.formStyle(.grouped).navigationTitle("设置")
        }
    }
}

struct MacRecallView: View {
    @ObservedObject var store: V2AppStore
    @State private var feedback: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("回想").font(V2Theme.TypeRole.displayLarge)
                Spacer()
                DatePicker("日期", selection: Binding(get: { store.recallDate }, set: { date in
                    if store.isRecallDirty && !store.saveRecall() { return }
                    store.selectRecallDate(date); feedback = nil
                }), displayedComponents: .date).labelsHidden().frame(width: 150)
                Button("保存回想") { feedback = store.saveRecall() ? "已保存到本机" : store.errorMessage }
                    .buttonStyle(.borderedProminent).disabled(!store.isRecallDirty)
                    .accessibilityIdentifier("mac.recall.save")
            }
            HStack(alignment: .top, spacing: 22) {
                TextEditor(text: Binding(get: { store.recallText }, set: { store.updateRecallText($0) }))
                    .font(.system(size: 18, design: .serif)).scrollContentBackground(.hidden)
                    .padding(20).background(V2Theme.panel, in: RoundedRectangle(cornerRadius: 18))
                    .accessibilityIdentifier("mac.recall.text")
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("这一天的依据").font(.headline)
                        if store.recallCandidates.isEmpty {
                            Text("还没有可引用的执行记录。可以先写下感受，之后再补充。")
                                .foregroundStyle(V2Theme.secondary)
                        }
                        ForEach(store.recallCandidates) { candidate in
                            Toggle(isOn: Binding(get: { store.isRecallReferenceSelected(candidate) }, set: { _ in store.toggleRecallReference(candidate) })) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(candidate.title)
                                    Text(candidate.detail).font(.caption).foregroundStyle(V2Theme.secondary)
                                }
                            }.toggleStyle(.checkbox)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(width: 260)
            }
            Text(feedback ?? (store.isRecallDirty ? "编辑中 · 离开页面时保存到本机" : "用真实经历，慢慢看清自己。"))
                .font(.caption).foregroundStyle(V2Theme.secondary)
        }.padding(28).background(V2Theme.page)
    }
}

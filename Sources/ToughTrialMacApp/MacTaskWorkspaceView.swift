import SwiftUI
import ToughTrialV2Core
import ToughTrialAppShared

struct MacTaskWorkspaceView: View {
    @ObservedObject var workspace: V2TaskWorkspace
    @ObservedObject var store: V2AppStore
    var onPlan: (String) -> Void
    @State private var scale = V2TaskTimeScale.week
    @State private var anchor = Date()
    @State private var goalIDs: Set<String>?
    @State private var lens: Lens = .list
    @State private var search = ""
    @State private var autosave: Task<Void, Never>?
    @State private var discardConfirmation = false
    @FocusState private var searchFocused: Bool
    enum Lens: String, CaseIterable { case list = "列表", structure = "结构", time = "时间", fishbone = "鱼骨" }

    private var visible: [V2Task] {
        workspace.tasks.filter { search.isEmpty || ($0.title + "\n" + $0.note).localizedCaseInsensitiveContains(search) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                header
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(V2Theme.secondary)
                    TextField("搜索任务与正文", text: $search).textFieldStyle(.plain).focused($searchFocused)
                        .accessibilityIdentifier("mac.tasks.search")
                }.padding(12).background(V2Theme.panel, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 24).padding(.bottom, 18)
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 12) {
                        if visible.isEmpty {
                            ContentUnavailableView(search.isEmpty ? "给想做的事一个位置" : "没有匹配的任务",
                                systemImage: search.isEmpty ? "square.and.pencil" : "magnifyingglass",
                                description: Text(search.isEmpty ? "点击新增任务，第一段写标题，回车继续写内容。" : "试试标题或正文里的其他词。"))
                                .frame(minWidth: 370, minHeight: 280)
                        } else {
                            switch lens {
                            case .list: ForEach(visible) { task in row(task) }
                            case .structure: ScrollView(.horizontal) { tree }
                            case .time: timeline
                            case .fishbone: ScrollView(.horizontal) { fishbone }
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24).padding(.bottom, 24)
                }
            }.frame(minWidth: 430, maxWidth: .infinity)
            Rectangle().fill(V2Theme.line).frame(width: 1)
            editor.frame(minWidth: 330, idealWidth: 410, maxWidth: 480)
        }
        .background(V2Theme.page)
        .tint(V2Theme.blue)
        .onChange(of: workspace.draft?.id) { autosave?.cancel() }
        .onDisappear { autosave?.cancel() }
        .toolbar {
            Button("查找", systemImage: "magnifyingglass") { searchFocused = true }.keyboardShortcut("f")
        }
        .confirmationDialog("放弃当前草稿？", isPresented: $discardConfirmation) {
            Button("放弃草稿", role: .destructive) { autosave?.cancel(); workspace.discardDraft() }
            Button("继续编辑", role: .cancel) { scheduleAutosave() }
        } message: { Text("已保存的任务不会删除。") }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text("任务").font(V2Theme.TypeRole.displayLarge)
                Spacer()
                Button { workspace.beginNew() } label: { Label("新增任务", systemImage: "plus") }
                    .buttonStyle(.borderedProminent).controlSize(.large).accessibilityIdentifier("mac.tasks.new")
            }
            HStack(spacing: 4) {
                ForEach(Lens.allCases, id: \.self) { item in
                    Button { lens = item } label: {
                        Text(item.rawValue).font(.system(size: 14, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 10)
                    }.buttonStyle(.plain).foregroundStyle(lens == item ? V2Theme.ink : V2Theme.secondary)
                        .background(lens == item ? V2Theme.panel : .clear, in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityIdentifier("mac.tasks.lens.\(item.rawValue)")
                        .accessibilityAddTraits(lens == item ? .isSelected : [])
                }
            }.padding(4).background(V2Theme.ColorRole.surfaceMuted, in: RoundedRectangle(cornerRadius: 14))
        }.padding(24)
    }

    private func row(_ task: V2Task) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button { workspace.toggleCompletion(task.id) } label: {
                Image(systemName: task.status == .done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22)).foregroundStyle(task.status == .done ? V2Theme.ColorRole.taskComplete : V2Theme.blue)
                    .frame(width: 32, height: 36)
            }.buttonStyle(.plain).accessibilityLabel(task.status == .done ? "恢复待办：\(task.title)" : "完成任务：\(task.title)")
                .accessibilityIdentifier("mac.tasks.complete.\(task.id)")
            Button { workspace.select(task.id) } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(task.title).font(.system(size: 16, weight: .semibold)).lineLimit(3)
                        .strikethrough(task.status == .done)
                    if !task.note.isEmpty { Text(task.note).font(.system(size: 13)).foregroundStyle(V2Theme.secondary).lineLimit(2) }
                }.frame(maxWidth: .infinity, minHeight: 36, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("mac.tasks.open.\(task.id)")
        }.padding(14).frame(minWidth: 300, maxWidth: 600, alignment: .leading)
            .background(workspace.selectedID == task.id ? V2Theme.ColorRole.primaryContainer : V2Theme.panel,
                        in: RoundedRectangle(cornerRadius: 16))
    }

    private var tree: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(search.isEmpty ? "任务之间的关系" : "匹配任务及其上级路径").font(.caption).foregroundStyle(V2Theme.secondary)
            ForEach(workspace.tasks.filter { task in task.parentID == nil || !workspace.tasks.contains(where: { parent in parent.id == task.parentID }) }) { root in
                branch(root, ancestors: [])
            }
        }
    }

    private func branch(_ task: V2Task, ancestors: Set<String>) -> AnyView {
        guard !ancestors.contains(task.id) else { return AnyView(EmptyView()) }
        let next = ancestors.union([task.id])
        let children = workspace.tasks.filter { $0.parentID == task.id }
        let matches = search.isEmpty || visible.contains(where: { $0.id == task.id }) || children.contains { hasMatch($0, visited: next) }
        guard matches else { return AnyView(EmptyView()) }
        return AnyView(VStack(alignment: .leading, spacing: 10) {
            row(task)
            if !children.isEmpty {
                HStack(alignment: .top, spacing: 14) {
                    Rectangle().fill(V2Theme.line).frame(width: 2)
                    VStack(alignment: .leading, spacing: 10) { ForEach(children) { branch($0, ancestors: next) } }
                }.padding(.leading, 28)
            }
        })
    }

    private func hasMatch(_ task: V2Task, visited: Set<String>) -> Bool {
        guard !visited.contains(task.id) else { return false }
        return visible.contains { $0.id == task.id } || workspace.tasks.filter { $0.parentID == task.id }
            .contains { hasMatch($0, visited: visited.union([task.id])) }
    }

    private var timeline: some View {
        V2TimeLensView(scale: $scale, anchor: $anchor,
            scheduledTasks: store.state.scheduledTasks.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) },
            activeTaskIDs: Set(store.state.activeSessions.compactMap(\.taskID)), onOpenTask: { workspace.select($0) })
            .frame(minHeight: 520)
    }
    private var goals: [V2GoalFilter] {
        var seen = Set<String>()
        return store.state.flattenTasks().compactMap { task in
            let id = task.goal.isEmpty ? "未归类" : task.goal
            guard seen.insert(id).inserted else { return nil }
            return V2GoalFilter(id: id, title: id, color: V2Theme.goalColor(task.colorName))
        }
    }
    private var fishbone: some View {
        V2FishboneLensView(goals: goals, visibleGoalIDs: goalIDs ?? Set(goals.map(\.id)),
            timelineItems: store.state.timelineItems, tasks: store.state.flattenTasks(),
            onToggleGoal: { id in
                var selection = goalIDs ?? Set(goals.map(\.id))
                if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
                goalIDs = selection
            }, onOpenTask: { workspace.select($0) })
    }

    @ViewBuilder private var editor: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let draft = workspace.draft {
                HStack {
                    Text(draft.isNew ? "新增任务" : "任务内容").font(.headline)
                    Spacer()
                    if !draft.isNew, let id = draft.original?.id {
                        Button("AI 计划") { onPlan(id) }
                    }
                    Button(draft.isNew ? "取消" : (workspace.hasExternalChange && !workspace.hasChanges ? "查看最新版本" : "放弃修改")) {
                        autosave?.cancel()
                        if workspace.hasChanges { discardConfirmation = true } else { workspace.discardDraft() }
                    }.disabled(!draft.isNew && !workspace.hasChanges && !workspace.hasExternalChange).accessibilityIdentifier("mac.tasks.cancel")
                }.padding(24)
                if !draft.isNew { MacTaskOptions(workspace: workspace, store: store) }
                if draft.text.isEmpty {
                    Text("第一段写标题，回车继续写正文").font(.caption).foregroundStyle(V2Theme.tertiary).padding(.horizontal, 26)
                }
                MacTaskDocumentInput(text: draft.text) { text, composing in
                    autosave?.cancel()
                    workspace.updateText(text, isComposing: composing)
                    if !composing { scheduleAutosave() }
                }.id(draft.id)
                if let issue = workspace.issue {
                    Text(issue).font(.callout).foregroundStyle(V2Theme.ColorRole.destructive)
                        .padding(.horizontal, 24).padding(.bottom, 12).accessibilityIdentifier("mac.tasks.issue")
                }
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(workspace.hasChanges ? "草稿保留在本机" : "已保存到本机").font(.caption)
                        Text("正文可留空 · ⌘S 保存").font(.caption2).foregroundStyle(V2Theme.tertiary)
                    }.foregroundStyle(V2Theme.secondary)
                    Spacer()
                    Button(draft.isNew ? "创建任务" : "保存") { autosave?.cancel(); workspace.save() }
                        .buttonStyle(.borderedProminent).disabled(!workspace.canSave).accessibilityIdentifier("mac.tasks.save")
                }.padding(24)
            } else {
                ContentUnavailableView("从一件事开始", systemImage: "text.alignleft",
                    description: Text("选择任务直接编辑，或按 ⌘N 新建。"))
                if let issue = workspace.issue { Text(issue).foregroundStyle(V2Theme.ColorRole.destructive).padding() }
            }
            if workspace.lastReceiptID != nil {
                Button("撤销上次保存") { autosave?.cancel(); workspace.undoLastSave() }
                    .disabled(workspace.hasChanges).padding(.horizontal, 24).padding(.bottom, 20)
                    .accessibilityIdentifier("mac.tasks.undoSave")
            }
        }.background(V2Theme.ColorRole.surfaceRaised)
    }

    private func scheduleAutosave() {
        autosave?.cancel()
        guard let pending = workspace.draft, !pending.isNew, workspace.canSave else { return }
        autosave = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(700)) } catch { return }
            guard workspace.draft?.id == pending.id, workspace.draft?.text == pending.text,
                  workspace.draft?.isNew == false, !workspace.isComposing, !discardConfirmation else { return }
            workspace.save()
        }
    }
}

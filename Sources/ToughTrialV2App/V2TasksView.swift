import Foundation
import SwiftUI
import ToughTrialV2Core

struct V2TasksView: View {
    @ObservedObject var store: V2AppStore

    @State private var lens = V2TaskLens.list
    @State private var timeScale = V2TaskTimeScale.week
    @State private var timeAnchor = Calendar.current.startOfDay(for: Date())
    @State private var visibleGoalIDs: Set<String> = []
    @State private var isTaskCapturePresented = false
    @State private var presentedTask: V2TaskDetailContext?
    @State private var lastTaskReceiptID: String?
    @State private var taskActionMessage: String?
    @State private var planTaskAfterDetail: V2TaskNode?

    private var rootTasks: [V2TaskNode] {
        store.state.tasks
    }

    private var allTasks: [V2TaskNode] {
        store.state.flattenTasks()
    }

    private var goals: [V2GoalFilter] {
        var seen = Set<String>()
        return allTasks.compactMap { task in
            let id = task.goal.isEmpty ? "未归类" : task.goal
            guard seen.insert(id).inserted else { return nil }
            return V2GoalFilter(id: id, title: id, color: V2Theme.goalColor(task.colorName))
        }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if lens == .list || lens == .structure {
                taskContent
            } else if lens == .time {
                timeContent
            } else {
                scrollingLensContent
            }

            captureControl
        }
        .v2ScreenBackground()
        .environment(\.scheduleHighlightedIDs, store.highlightedScheduleIDs)
        .onAppear {
            if visibleGoalIDs.isEmpty {
                visibleGoalIDs = Set(goals.map(\.id))
            }
            openAssistantSource()
        }
        .safeAreaInset(edge: .bottom) {
            if let message = taskActionMessage {
                HStack {
                    Text(message).font(.subheadline)
                    Spacer()
                    if let receiptID = lastTaskReceiptID {
                        Button("撤销") {
                            if store.undoTaskChange(receiptID: receiptID) {
                                lastTaskReceiptID = nil
                                taskActionMessage = "已撤销"
                            } else { taskActionMessage = store.errorMessage }
                        }.accessibilityIdentifier("tasks.action.undo")
                    }
                    Button { taskActionMessage = nil; lastTaskReceiptID = nil } label: {
                        Image(systemName: "xmark").frame(width: 44, height: 44)
                    }.accessibilityLabel("关闭操作提示")
                }.padding(.horizontal).background(.regularMaterial)
            }
        }
        .onChange(of: store.assistantReturnTaskID) { _, _ in openAssistantSource() }
        .v2Sheet(isPresented: $isTaskCapturePresented) {
            NavigationStack {
                V2TaskEditor(mode: .create(location: taskCaptureLocationTitle, identifier: lens == .time ? "tasks.timeCapture" : "tasks.capture"), onSave: { title, note in
                    let saved = lens == .time
                        ? store.quickAddScheduledTask(title: title, note: note, on: timeAnchor)
                        : store.createTaskFromTasks(title: title, note: note, parentTaskID: nil)
                    if saved {
                        isTaskCapturePresented = false
                        return nil
                    }
                    return store.errorMessage ?? "保存失败，请重试。"
                }, onCancel: dismissTaskCapture)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .v2Sheet(item: $presentedTask, onDismiss: openPendingPlanTask) { context in
            V2TaskDetailSheet(
                context: context,
                store: store,
                onClose: { presentedTask = nil },
                onPlan: {
                    planTaskAfterDetail = allTasks.first { $0.id == context.id }
                    presentedTask = nil
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private var timeContent: some View {
        VStack(spacing: 8) {
            header
                .padding(.horizontal, 18)

            V2TimeLensView(
                scale: $timeScale,
                anchor: $timeAnchor,
                scheduledTasks: store.state.scheduledTasks,
                activeTaskIDs: activeTaskIDs,
                onOpenTask: presentTaskDetailsByID
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.top, 12)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var taskContent: some View {
        VStack(spacing: 8) {
            header
                .padding(.horizontal, 18)

            Group {
                if lens == .list {
                    V2TaskListView(tasks: allTasks, onOpenDetails: presentTaskDetails,
                                   onToggleCompletion: toggleTaskCompletion)
                } else {
                    V2StructureLensView(tasks: rootTasks, selectedTaskID: store.state.selectedTaskID,
                                        onOpenDetails: presentTaskDetails)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.top, 12)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var scrollingLensContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                header

                switch lens {
                case .list, .structure:
                    EmptyView()
                case .time:
                    EmptyView()
                case .fishbone:
                    V2FishboneLensView(
                        goals: goals,
                        visibleGoalIDs: activeGoalIDs,
                        timelineItems: store.state.timelineItems,
                        tasks: allTasks,
                        onToggleGoal: toggleGoal,
                        onOpenTask: presentTaskDetailsByID
                    )
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 112)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var captureControl: some View {
        Button { isTaskCapturePresented = true } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(V2Theme.ColorRole.onPrimary)
                .frame(width: 52, height: 52)
                .background(V2Theme.ColorRole.primary, in: Circle())
                .shadow(color: V2Theme.ColorRole.primary.opacity(0.24), radius: 16, y: 7)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("新增任务记录")
        .accessibilityIdentifier("tasks.capture.open")
        .padding(.trailing, 20)
        .padding(.bottom, 20)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Text("任务")
                .font(V2Theme.TypeRole.displayMedium)
                .foregroundStyle(V2Theme.ColorRole.textPrimary)
                .lineLimit(1)
                .layoutPriority(1)

            HStack(spacing: 2) {
                ForEach(V2TaskLens.allCases) { item in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            lens = item
                        }
                    } label: {
                        Text(item.rawValue)
                            .font(V2Theme.TypeRole.labelMedium)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .foregroundStyle(
                                lens == item
                                    ? V2Theme.ColorRole.textPrimary
                                    : V2Theme.ColorRole.textSecondary
                            )
                            .background(
                                lens == item
                                    ? V2Theme.ColorRole.surfaceRaised
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                            )
                            .shadow(
                                color: lens == item ? V2Theme.ColorRole.textPrimary.opacity(0.07) : .clear,
                                radius: 6,
                                y: 2
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(lens == item ? "已选中" : "未选中")
                    .accessibilityIdentifier("tasks.lens.\(item.identifierComponent)")
                }
            }
            .padding(3)
            .background(
                V2Theme.ColorRole.surfaceMuted,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
    }

    private var activeGoalIDs: Set<String> {
        visibleGoalIDs.isEmpty ? Set(goals.map(\.id)) : visibleGoalIDs
    }

    private var activeTaskIDs: Set<String> {
        Set(
            store.state.activeSessions.compactMap { session in
                session.status == .running ? session.taskID : nil
            }
        )
    }

    private var taskCaptureLocationTitle: String {
        switch lens {
        case .list:
            return "列表 / 新建任务"
        case .structure:
            return "结构 / 新建根任务"
        case .fishbone:
            return "鱼骨 / 未归类"
        case .time:
            return timeAnchor.formatted(.dateTime.month(.defaultDigits).day())
        }
    }

    private func toggleTaskCompletion(_ task: V2TaskNode) {
        if let receipt = store.setTaskCompletion(taskID: task.id, completed: task.status != .done) {
            lastTaskReceiptID = receipt.changes.isEmpty ? nil : receipt.id
            taskActionMessage = receipt.summary
        } else { taskActionMessage = store.errorMessage; lastTaskReceiptID = nil }
    }

    private func dismissTaskCapture() {
        isTaskCapturePresented = false
    }

    private func presentTaskDetailsByID(_ id: String) {
        guard let task = allTasks.first(where: { $0.id == id }) else { return }
        presentTaskDetails(task)
    }

    private func presentTaskDetails(_ task: V2TaskNode) {
        let path = rootTasks.compactMap { taskPath(to: task.id, in: $0) }.first ?? [task]
        presentedTask = V2TaskDetailContext(task: task, path: path.dropLast().map(\.title))
    }

    private func taskPath(to id: String, in node: V2TaskNode) -> [V2TaskNode]? {
        if node.id == id {
            return [node]
        }

        for child in node.children {
            if let path = taskPath(to: id, in: child) {
                return [node] + path
            }
        }
        return nil
    }

    private func openAssistantSource() {
        guard let id = store.assistantReturnTaskID,
              let task = allTasks.first(where: { $0.id == id }) else { return }
        store.assistantReturnTaskID = nil
        presentTaskDetails(task)
    }

    private func openPendingPlanTask() {
        guard let task = planTaskAfterDetail else { return }
        planTaskAfterDetail = nil
        store.openPlanAgent(for: task)
    }

    private func toggleGoal(_ id: String) {
        if visibleGoalIDs.isEmpty {
            visibleGoalIDs = Set(goals.map(\.id))
        }

        if visibleGoalIDs.contains(id) {
            visibleGoalIDs.remove(id)
        } else {
            visibleGoalIDs.insert(id)
        }
    }
}

private enum V2TaskLens: String, CaseIterable, Identifiable {
    case list = "列表"
    case structure = "结构"
    case time = "时间"
    case fishbone = "鱼骨"

    var id: String { rawValue }

    var identifierComponent: String {
        switch self {
        case .list: "list"
        case .structure: "structure"
        case .time: "time"
        case .fishbone: "fishbone"
        }
    }
}

enum V2TaskTimeScale: String, CaseIterable, Identifiable {
    case year = "年"
    case month = "月"
    case week = "周"
    case threeDay = "3日"
    case day = "日"

    var id: String { rawValue }

}

struct V2GoalFilter: Identifiable {
    let id: String
    let title: String
    let color: Color
}

private struct V2TaskDetailContext: Identifiable {
    let task: V2TaskNode
    let path: [String]

    var id: String { task.id }
}

private struct V2TaskDetailSheet: View {
    let context: V2TaskDetailContext
    @ObservedObject var store: V2AppStore
    let onClose: () -> Void
    let onPlan: () -> Void
    @State private var editingTask: V2Task?
    @State private var draftKind: V2Task.Kind?
    @State private var lastReceiptID: String?
    @State private var actionMessage: String?

    private var task: V2TaskNode? { store.state.flattenTasks().first { $0.id == context.id } }
    private var currentTask: V2Task? { store.engine.snapshot.tasks.first { $0.id == context.id } }

    private var classificationSummary: String {
        let kind: String
        switch currentTask?.kind {
        case .goal: kind = "目标"
        case .commitment: kind = "承诺"
        case .maintenance: kind = "维护"
        case nil: kind = "未分类"
        }
        return kind
    }

    private func classificationIsDirty(for task: V2Task) -> Bool {
        draftKind != task.kind
    }

    var body: some View {
        NavigationStack {
            if let editingTask {
                V2TaskEditor(mode: .edit(taskID: editingTask.id), title: editingTask.title, note: editingTask.note,
                    additionalDirty: classificationIsDirty(for: editingTask),
                    onSave: { title, note in
                        let classification = V2TaskClassification(kind: draftKind)
                        if let receipt = store.editTask(editingTask, title: title, note: note, classification: classification) {
                            self.editingTask = nil
                            lastReceiptID = receipt.changes.isEmpty ? nil : receipt.id
                            actionMessage = "已保存修改"
                            return nil
                        }
                        return store.errorMessage ?? "保存失败，请重试。"
                    }, onCancel: { self.editingTask = nil }) {
                        V2TaskClassificationFields(
                            kind: $draftKind,
                            identifierPrefix: "tasks.editor.classification"
                        )
                    }
            } else {
                detail
            }
        }
        .interactiveDismissDisabled(editingTask != nil)
        .accessibilityIdentifier("tasks.detail.sheet")
    }

    private func beginEditing() {
        guard store.canWrite,
              let editable = currentTask, editable.status != .archived else { return }
        draftKind = editable.kind
        editingTask = editable
    }

    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let task {
                    if !context.path.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("路径").font(.caption).foregroundStyle(V2Theme.secondary)
                            Text(context.path.joined(separator: " / ")).font(.subheadline)
                        }.accessibilityIdentifier("tasks.detail.path")
                    }
                    Button(action: beginEditing) {
                        Text(task.title)
                            .font(V2Theme.TypeRole.headlineSmall)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("点击编辑任务内容")
                    .accessibilityIdentifier("tasks.detail.title")
                    .disabled(!store.canWrite)
                    Button(action: beginEditing) {
                        Text(task.subtitle.isEmpty ? "点击编辑内容…" : task.subtitle)
                            .foregroundStyle(task.subtitle.isEmpty ? V2Theme.secondary : V2Theme.ColorRole.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("在同一份文档中编辑标题和正文")
                    .accessibilityIdentifier(task.subtitle.isEmpty ? "tasks.detail.emptyBody" : "tasks.detail.note")
                    .disabled(!store.canWrite)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("分类").font(.caption).foregroundStyle(V2Theme.secondary)
                        Text(classificationSummary)
                            .font(V2Theme.TypeRole.bodySmall)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("tasks.detail.classification")
                    Divider()
                    VStack(alignment: .leading, spacing: 10) {
                        Text(task.status == .done ? "已完成" : task.status == .active ? "进行中" : task.status == .paused ? "已暂停" : "未开始")
                            .accessibilityIdentifier("tasks.detail.status")
                        Label("累计用时 \(task.spentMinutes) 分钟", systemImage: "clock")
                            .accessibilityIdentifier("tasks.detail.duration")
                        if store.state.activeSessions.contains(where: { $0.taskID == task.id }) {
                            Text("此任务仍有计时记录进行中或暂停中。标记完成不会结束计时，可在今天结束时间段。")
                                .font(.footnote).foregroundStyle(V2Theme.secondary)
                        }
                    }
                } else {
                    Text("此任务已不可用，请关闭后重新查看。")
                }
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(V2Theme.ColorRole.canvas)
        .foregroundStyle(V2Theme.ColorRole.textPrimary)
        .navigationTitle("任务详情")
        .v2InlineNavigationTitle()
        #if os(iOS)
        .toolbarBackground(V2Theme.ColorRole.canvas, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭", action: onClose).accessibilityIdentifier("tasks.detail.close")
            }

        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                if let actionMessage {
                    HStack {
                        Text(actionMessage).font(.footnote)
                        Spacer()
                        if let lastReceiptID {
                            Button("撤销") {
                                if store.undoTaskChange(receiptID: lastReceiptID) {
                                    self.lastReceiptID = nil
                                    self.actionMessage = "已撤销"
                                } else { self.actionMessage = store.errorMessage }
                            }.accessibilityIdentifier("tasks.detail.undo")
                        }
                    }
                }
                if let task {
                    Button(task.status == .done ? "恢复为未完成" : "标记完成") {
                        if let receipt = store.setTaskCompletion(taskID: task.id, completed: task.status != .done) {
                            lastReceiptID = receipt.changes.isEmpty ? nil : receipt.id
                            actionMessage = receipt.summary
                        } else { actionMessage = store.errorMessage; lastReceiptID = nil }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("tasks.detail.complete")
                    Button(action: onPlan) { Label("AI 计划", systemImage: "sparkles").frame(maxWidth: .infinity, minHeight: 44) }
                        .accessibilityIdentifier("tasks.detail.aiPlan")
                }
            }.padding(.horizontal, 20).padding(.vertical, 10).background(.regularMaterial)
        }
    }
}

private struct V2TaskListView: View {
    @Environment(\.scheduleHighlightedIDs) private var highlightedIDs
    let tasks: [V2TaskNode]
    let onOpenDetails: (V2TaskNode) -> Void
    let onToggleCompletion: (V2TaskNode) -> Void

    var body: some View {
        if tasks.isEmpty {
            V2EmptyLensView(title: "还没有任务", detail: "记下要做的事，从一件小事开始。")
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(tasks, id: \.id) { task in
                        HStack(spacing: 8) {
                            if task.children.isEmpty {
                                Button { onToggleCompletion(task) } label: {
                                    Image(systemName: task.status == .done ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(task.status == .done ? V2Theme.mint : V2Theme.blue)
                                        .frame(width: 44, height: 44)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(task.status == .done ? "恢复未完成" : "完成")：\(task.title)")
                                .accessibilityValue(task.status == .done ? "已完成" : "未完成")
                                .accessibilityIdentifier("tasks.complete.\(task.id)")
                            } else {
                                Image(systemName: "arrow.triangle.branch")
                                    .foregroundStyle(V2Theme.blue).frame(width: 44, height: 44)
                                    .accessibilityHidden(true)
                            }
                            Button { onOpenDetails(task) } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(task.title)
                                            .font(V2Theme.TypeRole.titleMedium)
                                            .foregroundStyle(V2Theme.ink)
                                            .multilineTextAlignment(.leading)
                                        if !task.children.isEmpty {
                                            Text("\(task.children.count) 个子任务")
                                                .font(V2Theme.TypeRole.bodySmall)
                                                .foregroundStyle(V2Theme.secondary)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right")
                                        .font(V2Theme.TypeRole.labelSmall)
                                        .foregroundStyle(V2Theme.tertiary)
                                }
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(task.title)

                        }
                        .padding(14)
                        .background(V2Theme.ColorRole.surfaceRaised, in: RoundedRectangle(cornerRadius: 20))
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(
                            highlightedIDs.contains(task.id) ? V2Theme.blue.opacity(0.4) : V2Theme.line.opacity(0.65)))
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 100)
            }
            .accessibilityIdentifier("tasks.list")
        }
    }
}

private struct V2StructureLensView: View {
    let tasks: [V2TaskNode]
    let selectedTaskID: String?
    let onOpenDetails: (V2TaskNode) -> Void

    // Presentation-only root: never passed to commands or used as a new task's parent.
    private var overview: V2TaskNode {
        V2TaskNode(id: "task-overview", title: "全部任务", subtitle: "", goal: "",
                   colorName: "blue", status: .planned, spentMinutes: 0, children: tasks)
    }

    var body: some View {
        if tasks.isEmpty {
            V2EmptyLensView(title: "还没有任务", detail: "记下要做的事，从一件小事开始。")
        } else {
            V2TaskMapCanvas(task: overview, selectedTaskID: selectedTaskID,
                            onOpenDetails: onOpenDetails, isOverview: true)
                .accessibilityIdentifier("tasks.structure.overview")
        }
    }
}

private struct V2TaskMapCanvas: View {
    let task: V2TaskNode
    let selectedTaskID: String?
    let onOpenDetails: (V2TaskNode) -> Void
    var isOverview = false

    @State private var focusedNodeID: String?
    @State private var expandedNodeIDs: Set<String> = []
    @State private var zoomScale: CGFloat = 0.92
    @GestureState private var pinchScale: CGFloat = 1

    private let minimumCanvasWidth: CGFloat = 940
    private let minimumCanvasHeight: CGFloat = 650
    private let rootX: CGFloat = 126
    private let columnSpacing: CGFloat = 224

    private var defaultFocusedBranch: V2TaskNode? {
        task.children.first { branch in
            guard let selectedTaskID else { return false }
            return branch.containsTask(id: selectedTaskID) && branch.children.contains { !$0.children.isEmpty }
        }
            ?? task.children.first { $0.children.contains { !$0.children.isEmpty } && $0.status == .active }
            ?? task.children.first { $0.children.contains { !$0.children.isEmpty } && $0.status != .done }
            ?? task.children.first { branch in
                guard let selectedTaskID else { return false }
                return branch.containsTask(id: selectedTaskID)
            }
            ?? task.children.first { !$0.children.isEmpty && $0.status == .active }
            ?? task.children.first { !$0.children.isEmpty && $0.status != .done }
            ?? task.children.first
    }

    private var defaultFocusPath: [V2TaskNode] {
        if let selectedTaskID,
           let path = path(to: selectedTaskID, in: task) {
            return path
        }

        guard let branch = defaultFocusedBranch else {
            return [task]
        }

        var result = [task, branch]
        if let detail = defaultFocusedDetail(in: branch) {
            result.append(detail)
        }
        return result
    }

    private var defaultExpandedNodeIDs: Set<String> {
        Set(defaultFocusPath.filter { !$0.children.isEmpty }.map(\.id))
            .union([task.id])
    }

    private var effectiveExpandedNodeIDs: Set<String> {
        (expandedNodeIDs.isEmpty ? defaultExpandedNodeIDs : expandedNodeIDs)
            .union([task.id])
    }

    private var layout: V2TaskTreeLayout {
        V2TaskTreeLayout(
            root: task,
            expandedNodeIDs: effectiveExpandedNodeIDs
        )
    }

    private var canvasWidth: CGFloat {
        max(
            minimumCanvasWidth,
            rootX + CGFloat(layout.maxDepth) * columnSpacing + 260
        )
    }

    private var canvasHeight: CGFloat {
        max(minimumCanvasHeight, CGFloat(layout.contentHeight))
    }

    private var effectiveZoom: CGFloat {
        clampedZoom(zoomScale * pinchScale)
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView([.vertical, .horizontal], showsIndicators: false) {
                let currentLayout = layout

                ZStack(alignment: .topLeading) {
                    mapLines(layout: currentLayout)

                    ForEach(currentLayout.entries) { entry in
                        mapNode(for: entry)
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                            .position(
                                x: nodeX(depth: entry.depth),
                                y: CGFloat(entry.centerY)
                            )
                    }
                }
                .frame(width: canvasWidth, height: canvasHeight)
                .scaleEffect(effectiveZoom, anchor: .topLeading)
                .frame(
                    width: canvasWidth * effectiveZoom,
                    height: canvasHeight * effectiveZoom,
                    alignment: .topLeading
                )
                .padding(.trailing, 24)
                .padding(.vertical, 10)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background(V2Theme.ColorRole.canvas)
            .scrollBounceBehavior(.basedOnSize)
            .simultaneousGesture(
                MagnificationGesture()
                    .updating($pinchScale) { value, state, _ in
                        state = value
                    }
                    .onEnded { value in
                        zoomScale = clampedZoom(zoomScale * value)
                    }
            )
            .overlay(alignment: .topTrailing) {
                mapControls
                    .padding(.top, 8)
                    .padding(.trailing, 14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minHeight: 520)
        .onAppear {
            seedFocus(force: false)
        }
        .onChange(of: selectedTaskID) { _, _ in
            withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                seedFocus(force: true)
            }
        }
    }

    @ViewBuilder
    private func mapNode(for entry: V2TaskTreeLayout.Entry) -> some View {
        if isOverview && entry.depth == 0 {
            Text("全部任务")
                .font(V2Theme.TypeRole.headlineSmall)
                .foregroundStyle(V2Theme.ColorRole.textPrimary)
                .accessibilityIdentifier("tasks.structure.overviewTitle")
        } else {
            mapNodeLabel(for: entry)
        }
    }

    private func mapNodeLabel(for entry: V2TaskTreeLayout.Entry) -> some View {
        let style = nodeStyle(for: entry)
        let onToggleExpansion: (() -> Void)?
        if entry.depth > 0, !entry.node.children.isEmpty {
            onToggleExpansion = { toggleExpansion(for: entry.node) }
        } else {
            onToggleExpansion = nil
        }

        return V2TaskMapNode(
            id: entry.node.id,
            title: entry.node.title,
            color: entry.depth == 0
                ? V2Theme.ColorRole.textPrimary
                : V2Theme.goalColor(entry.node.colorName),
            status: entry.node.status,
            completionSignal: entry.node.completionSignal,
            style: style,
            childCount: entry.depth == 0 ? 0 : entry.node.children.count,
            isExpanded: effectiveExpandedNodeIDs.contains(entry.node.id),
            onOpenDetails: { onOpenDetails(entry.node) },
            onToggleExpansion: onToggleExpansion
        )
        .scaleEffect(effectiveFocusedNodeID == entry.node.id ? 1 : 0.98)
        .opacity(nodeOpacity(for: entry))
    }

    private var effectiveFocusedNodeID: String? {
        focusedNodeID ?? defaultFocusPath.dropFirst().first?.id
    }

    private func nodeStyle(for entry: V2TaskTreeLayout.Entry) -> V2TaskMapNode.Style {
        let isFocused = effectiveFocusedNodeID == entry.node.id
        switch entry.depth {
        case 0:
            return .root
        case 1:
            return isFocused ? .selectedBranch : .branch
        case 2:
            return isFocused ? .selectedDetail : .detail
        default:
            return entry.node.children.isEmpty
                ? .leaf
                : (isFocused ? .selectedDetail : .detail)
        }
    }

    private func nodeOpacity(for entry: V2TaskTreeLayout.Entry) -> Double {
        guard entry.depth > 0 else { return 1 }
        return effectiveFocusedNodeID == entry.node.id ? 1 : 0.78
    }

    private func toggleExpansion(for node: V2TaskNode) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
            focusedNodeID = node.id
            if expandedNodeIDs.contains(node.id) {
                expandedNodeIDs.remove(node.id)
            } else {
                expandedNodeIDs.insert(node.id)
            }
        }
    }

    private func seedFocus(force: Bool) {
        let path = defaultFocusPath
        let pathParents = Set(path.filter { !$0.children.isEmpty }.map(\.id))

        if expandedNodeIDs.isEmpty {
            expandedNodeIDs = defaultExpandedNodeIDs
        } else if force {
            expandedNodeIDs.formUnion(pathParents)
        }
        expandedNodeIDs.insert(task.id)

        if force || focusedNodeID == nil {
            focusedNodeID = path.dropFirst().first?.id
        }
    }

    private func path(to id: String, in node: V2TaskNode) -> [V2TaskNode]? {
        if node.id == id {
            return [node]
        }

        for child in node.children {
            if let childPath = path(to: id, in: child) {
                return [node] + childPath
            }
        }
        return nil
    }

    private func defaultFocusedDetail(in branch: V2TaskNode) -> V2TaskNode? {
        branch.children.first { detail in
            guard let selectedTaskID else { return false }
            return detail.containsTask(id: selectedTaskID)
        }
            ?? branch.children.first { !$0.children.isEmpty && $0.status != .done }
            ?? branch.children.first { !$0.children.isEmpty }
            ?? branch.children.first
    }

    private func clampedZoom(_ value: CGFloat) -> CGFloat {
        min(1.35, max(0.62, value))
    }

    private var mapControls: some View {
        HStack(spacing: 4) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    zoomScale = clampedZoom(zoomScale - 0.12)
                }
            } label: {
                Image(systemName: "minus")
                    .frame(width: 30, height: 30)
            }
            .accessibilityLabel("缩小任务地图")

            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    zoomScale = 0.92
                }
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .frame(width: 30, height: 30)
            }
            .accessibilityLabel("重置地图缩放")

            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    zoomScale = clampedZoom(zoomScale + 0.12)
                }
            } label: {
                Image(systemName: "plus")
                    .frame(width: 30, height: 30)
            }
            .accessibilityLabel("放大任务地图")
        }
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(V2Theme.ColorRole.textSecondary)
        .padding(4)
        .background(V2Theme.ColorRole.surfaceRaised.opacity(0.84))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(V2Theme.ColorRole.outline.opacity(0.52), lineWidth: 1)
        )
        .shadow(color: V2Theme.ColorRole.textPrimary.opacity(0.06), radius: 14, y: 7)
        .buttonStyle(.plain)
    }

    private func mapLines(layout: V2TaskTreeLayout) -> some View {
        ZStack {
            ForEach(layout.entries.filter { $0.parentID != nil }) { entry in
                if let parentID = entry.parentID,
                   let parent = layout.entry(id: parentID) {
                    let from = CGPoint(
                        x: nodeAnchorX(for: parent),
                        y: CGFloat(parent.centerY)
                    )
                    let to = CGPoint(
                        x: nodeAnchorX(for: entry),
                        y: CGFloat(entry.centerY)
                    )
                    let controlDistance = max(72, (to.x - from.x) * 0.46)
                    let color = V2Theme.goalColor(entry.node.colorName)
                    let isFocused = effectiveFocusedNodeID == entry.node.id

                    Path { path in
                        path.move(to: from)
                        path.addCurve(
                            to: to,
                            control1: CGPoint(
                                x: from.x + controlDistance,
                                y: from.y
                            ),
                            control2: CGPoint(
                                x: to.x - controlDistance,
                                y: to.y
                            )
                        )
                    }
                    .stroke(
                        color.opacity(isFocused ? 0.92 : 0.50),
                        style: StrokeStyle(
                            lineWidth: isFocused ? 3.2 : 2.4,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    .shadow(
                        color: color.opacity(isFocused ? 0.08 : 0.03),
                        radius: 3,
                        y: 2
                    )
                }
            }
        }
    }

    private func nodeX(depth: Int) -> CGFloat {
        rootX + CGFloat(depth) * columnSpacing
    }

    private func nodeAnchorX(for entry: V2TaskTreeLayout.Entry) -> CGFloat {
        nodeX(depth: entry.depth)
            - nodeWidth(for: entry) / 2
            + statusDotSize(for: entry) / 2
    }

    private func nodeWidth(for entry: V2TaskTreeLayout.Entry) -> CGFloat {
        switch nodeStyle(for: entry) {
        case .root:
            return 206
        case .selectedBranch, .branch:
            return 183
        case .selectedDetail, .detail:
            return 189
        case .leaf:
            return 161
        }
    }

    private func statusDotSize(for entry: V2TaskTreeLayout.Entry) -> CGFloat {
        switch nodeStyle(for: entry) {
        case .root:
            return 22
        case .selectedBranch:
            return 18
        case .branch, .selectedDetail:
            return 15
        case .detail, .leaf:
            return 13
        }
    }
}

private struct V2TaskMapNode: View {
    enum Style {
        case root
        case branch
        case selectedBranch
        case detail
        case selectedDetail
        case leaf
    }

    let id: String
    let title: String
    let color: Color
    let status: V2TaskNode.Status
    let completionSignal: Double
    let style: Style
    let childCount: Int
    let isExpanded: Bool
    let onOpenDetails: () -> Void
    let onToggleExpansion: (() -> Void)?

    var body: some View {
        HStack(spacing: 5) {
            Button(action: onOpenDetails) {
                HStack(spacing: 8) {
                    V2TaskMapStatusDot(
                        color: color,
                        completionSignal: completionSignal,
                        style: style
                    )

                    Text(title)
                        .font(font)
                        .foregroundStyle(textColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .padding(.horizontal, 3)
                        .background(V2Theme.ColorRole.canvas)
                        .overlay(alignment: .bottom) {
                            Capsule()
                                .fill(textColor.opacity(underlineOpacity))
                                .frame(height: style == .detail ? 2 : 3)
                                .offset(y: 5)
                        }
                }
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(bodyAccessibilityLabel)
            .accessibilityValue(status == .done ? "已完成" : "未完成")
            .accessibilityHint("打开任务详情")
            .accessibilityIdentifier("tasks.node.\(id).details")

            if let onToggleExpansion {
                Button(action: onToggleExpansion) {
                    HStack(spacing: 2) {
                        Text("\(childCount)")
                        Image(systemName: "chevron.right")
                            .rotationEffect(isExpanded ? .degrees(90) : .zero)
                    }
                    .font(V2Theme.TypeRole.labelSmall)
                    .foregroundStyle(color.opacity(0.78))
                    .padding(.horizontal, 6)
                    .frame(minWidth: 34, minHeight: 32)
                    .background(V2Theme.ColorRole.canvas, in: Capsule())
                    .overlay(Capsule().fill(color.opacity(0.10)))
                    .animation(.easeInOut(duration: 0.18), value: isExpanded)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title)
                .accessibilityValue(isExpanded ? "已展开" : "已收起")
                .accessibilityHint(isExpanded ? "收起子任务" : "展开子任务")
                .accessibilityIdentifier("tasks.node.\(id).disclosure")
            }
        }
        .frame(width: nodeWidth, alignment: .leading)
        .modifier(V2ScheduleHighlight(ids: [id]))
    }

    private var bodyAccessibilityLabel: String {
        onToggleExpansion == nil ? title : "查看详情：\(title)"
    }

    private var nodeWidth: CGFloat {
        switch style {
        case .root:
            206
        case .selectedBranch, .branch:
            183
        case .selectedDetail, .detail:
            189
        case .leaf:
            161
        }
    }

    private var font: Font {
        switch style {
        case .root:
            V2Theme.TypeRole.headlineSmall
        case .selectedBranch:
            V2Theme.TypeRole.titleLarge
        case .branch:
            V2Theme.TypeRole.titleMedium
        case .selectedDetail:
            V2Theme.TypeRole.titleMedium
        case .detail:
            V2Theme.TypeRole.bodyMedium
        case .leaf:
            V2Theme.TypeRole.bodySmall
        }
    }

    private var textColor: Color {
        if status == .done {
            return V2Theme.ColorRole.textSecondary
        }

        switch style {
        case .root, .selectedBranch, .selectedDetail:
            return V2Theme.ColorRole.textPrimary
        case .branch:
            return color
        case .detail, .leaf:
            return V2Theme.ColorRole.textSecondary
        }
    }

    private var underlineOpacity: Double {
        switch status {
        case .done: 0.16
        case .planned, .active, .paused: baseUnderlineOpacity
        }
    }

    private var baseUnderlineOpacity: Double {
        switch style {
        case .root:
            0.32
        case .selectedBranch:
            0.36
        case .selectedDetail:
            0.3
        case .branch:
            0.26
        case .detail:
            0.18
        case .leaf:
            0.14
        }
    }

}

private struct V2TaskMapStatusDot: View {
    let color: Color
    let completionSignal: Double
    let style: V2TaskMapNode.Style

    var body: some View {
        ZStack(alignment: .bottom) {
            Circle()
                .fill(dotBackground)

            GeometryReader { proxy in
                VStack {
                    Spacer(minLength: 0)
                    Rectangle()
                        .fill(progressFill)
                        .frame(height: proxy.size.height * min(1, max(0, completionSignal)))
                }
            }
            .clipShape(Circle())
        }
        .frame(width: size, height: size)
        .overlay(
            Circle()
                .stroke(border, lineWidth: strokeWidth)
        )
        .background(
            Circle()
                .fill(haloFill)
                .frame(width: haloSize, height: haloSize)
                .shadow(color: border.opacity(0.16), radius: 5, y: 2)
        )
    }

    private var size: CGFloat {
        switch style {
        case .root:
            22
        case .selectedBranch:
            18
        case .branch, .selectedDetail:
            15
        case .detail, .leaf:
            13
        }
    }

    private var haloSize: CGFloat {
        switch style {
        case .root:
            33
        case .selectedBranch:
            34
        case .selectedDetail:
            29
        case .branch:
            23
        case .detail, .leaf:
            20
        }
    }

    private var strokeWidth: CGFloat {
        switch style {
        case .root:
            3
        case .selectedBranch:
            2.6
        case .branch, .selectedDetail:
            2.2
        case .detail, .leaf:
            1.9
        }
    }

    private var progressFill: Color {
        V2Theme.ColorRole.taskComplete
    }

    private var dotBackground: Color {
        completionSignal >= 1
            ? V2Theme.ColorRole.taskCompleteContainer
            : V2Theme.ColorRole.taskIncompleteContainer
    }

    private var border: Color {
        color.opacity(completionSignal > 0 ? 0.88 : 0.68)
    }

    private var haloFill: Color {
        switch style {
        case .selectedBranch, .selectedDetail:
            color.opacity(0.10)
        case .root, .branch, .detail, .leaf:
            V2Theme.ColorRole.canvas
        }
    }
}

struct V2FishboneLensView: View {
    let goals: [V2GoalFilter]
    let visibleGoalIDs: Set<String>
    let timelineItems: [V2TimelineItem]
    let tasks: [V2TaskNode]
    let onToggleGoal: (String) -> Void
    let onOpenTask: (String) -> Void

    private var visibleDoneItems: [V2FishboneItem] {
        timelineItems.compactMap { item in
            guard item.isDone else { return nil }
            let task = tasks.first { $0.id == item.taskID }
            let goalID = task?.goal.isEmpty == false ? task?.goal ?? "未归类" : "未归类"
            guard visibleGoalIDs.contains(goalID) else { return nil }
            return V2FishboneItem(
                id: item.id,
                taskID: task?.id,
                timeLabel: item.timeLabel,
                title: item.title,
                detail: item.detail,
                goalID: goalID,
                color: task.map { V2Theme.goalColor($0.colorName) } ?? V2Theme.ColorRole.textSecondary
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(goals) { goal in
                        Button {
                            onToggleGoal(goal.id)
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: visibleGoalIDs.contains(goal.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 15, weight: .semibold))
                                Text(goal.title)
                                    .font(V2Theme.TypeRole.labelMedium)
                                    .lineLimit(1)
                            }
                            .foregroundStyle(
                                visibleGoalIDs.contains(goal.id)
                                    ? goal.color
                                    : V2Theme.ColorRole.textTertiary
                            )
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                (visibleGoalIDs.contains(goal.id)
                                    ? goal.color
                                    : V2Theme.ColorRole.outline).opacity(0.12)
                            )
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(goal.color.opacity(0.22), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.trailing, 18)
            }

            if visibleDoneItems.isEmpty {
                V2EmptyLensView(title: "还没有可见完成节点", detail: "勾选目标后，完成过的任务会沉到同一条轴线上。")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    V2FishboneAxis(items: visibleDoneItems, onOpenTask: onOpenTask)
                        .frame(width: max(360, CGFloat(visibleDoneItems.count) * 150 + 180), height: 410)
                        .padding(.vertical, 8)
                        .padding(.trailing, 18)
                }
            }
        }
    }
}

private struct V2FishboneItem: Identifiable {
    let id: String
    let taskID: String?
    let timeLabel: String
    let title: String
    let detail: String
    let goalID: String
    let color: Color
}

private struct V2FishboneAxis: View {
    let items: [V2FishboneItem]
    let onOpenTask: (String) -> Void

    var body: some View {
        GeometryReader { proxy in
            let axisY = proxy.size.height * 0.52

            ZStack(alignment: .topLeading) {
                Path { path in
                    path.move(to: CGPoint(x: 24, y: axisY))
                    path.addLine(to: CGPoint(x: proxy.size.width - 24, y: axisY))
                }
                .stroke(
                    V2Theme.ColorRole.textPrimary.opacity(0.18),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )

                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    let x = xPosition(index: index, width: proxy.size.width)
                    let above = index.isMultiple(of: 2)
                    let nodeY = axisY + (above ? -132 : 38)

                    Path { path in
                        path.move(to: CGPoint(x: x, y: axisY))
                        path.addQuadCurve(
                            to: CGPoint(x: x + (above ? 26 : -26), y: nodeY + 58),
                            control: CGPoint(x: x + (above ? 18 : -18), y: axisY + (above ? -42 : 42))
                        )
                    }
                    .stroke(item.color.opacity(0.5), style: StrokeStyle(lineWidth: 2, lineCap: .round))

                    Circle()
                        .fill(item.color)
                        .frame(width: 17, height: 17)
                        .position(x: x, y: axisY)

                    Group {
                        if let taskID = item.taskID {
                            Button { onOpenTask(taskID) } label: {
                                V2FishboneEventCard(item: item, isAbove: above)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("查看详情：\(item.title)")
                            .accessibilityIdentifier("tasks.fishbone.details.\(taskID)")
                        } else {
                            V2FishboneEventCard(item: item, isAbove: above)
                        }
                    }
                        .frame(width: 132)
                        .position(x: x + (above ? 38 : -38), y: nodeY + 46)
                }
            }
        }
        .background(V2Theme.ColorRole.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(V2Theme.ColorRole.outline, lineWidth: 1)
        )
    }

    private func xPosition(index: Int, width: CGFloat) -> CGFloat {
        guard items.count > 1 else { return width * 0.5 }
        let usableWidth = width - 90
        return 45 + usableWidth * CGFloat(index) / CGFloat(items.count - 1)
    }
}

private struct V2FishboneEventCard: View {
    let item: V2FishboneItem
    let isAbove: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(item.timeLabel)
                .font(V2Theme.TypeRole.labelSmall)
                .foregroundStyle(item.color)
                .lineLimit(1)

            Text(item.title)
                .font(V2Theme.TypeRole.labelMedium)
                .foregroundStyle(V2Theme.ColorRole.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.78)

            Text(item.detail)
                .font(V2Theme.TypeRole.labelSmall)
                .foregroundStyle(V2Theme.ColorRole.textTertiary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(item.color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(item.color.opacity(0.24), lineWidth: 1)
        )
        .rotationEffect(.degrees(isAbove ? -2 : 2))
    }
}

private struct V2EmptyLensView: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(V2Theme.ColorRole.textTertiary)

            Text(title)
                .font(V2Theme.TypeRole.titleLarge)
                .foregroundStyle(V2Theme.ColorRole.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Text(detail)
                .font(V2Theme.TypeRole.bodyMedium)
                .foregroundStyle(V2Theme.ColorRole.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
        .padding(24)
        .background(V2Theme.ColorRole.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(V2Theme.ColorRole.outline, lineWidth: 1)
        )
    }
}

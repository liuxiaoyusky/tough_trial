import Foundation
import SwiftUI
import ToughTrialV2Core

struct V2TasksView: View {
    @ObservedObject var store: V2AppStore

    @State private var lens = V2TaskLens.structure
    @State private var timeScale = V2TaskTimeScale.week
    @State private var timeAnchor = Calendar.current.startOfDay(for: Date())
    @State private var visibleGoalIDs: Set<String> = []
    @State private var showsCaptureAffordance = false
    @State private var quickAddTitle = ""
    @FocusState private var isQuickAddFocused: Bool

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
            if lens == .structure {
                structureContent
            } else if lens == .time {
                timeContent
            } else {
                scrollingLensContent
            }

            captureControl
        }
        .v2ScreenBackground()
        .onAppear {
            if visibleGoalIDs.isEmpty {
                visibleGoalIDs = Set(goals.map(\.id))
            }
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
                activeTaskIDs: activeTaskIDs
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.top, 12)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var structureContent: some View {
        VStack(spacing: 8) {
            header
                .padding(.horizontal, 18)

            V2StructureLensView(tasks: rootTasks, selectedTaskID: store.state.selectedTaskID)
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
                case .structure:
                    EmptyView()
                case .time:
                    EmptyView()
                case .fishbone:
                    V2FishboneLensView(
                        goals: goals,
                        visibleGoalIDs: activeGoalIDs,
                        timelineItems: store.state.timelineItems,
                        tasks: allTasks,
                        onToggleGoal: toggleGoal
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
        VStack(alignment: .trailing, spacing: 10) {
            if showsCaptureAffordance {
                if lens == .time {
                    timeQuickAddPanel
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    Text("在当前视角轻记一笔")
                        .font(V2Theme.TypeRole.bodySmall)
                        .foregroundStyle(V2Theme.ColorRole.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(V2Theme.ColorRole.surfaceRaised)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(V2Theme.ColorRole.outline, lineWidth: 1))
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }

            if lens != .time || !showsCaptureAffordance {
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        showsCaptureAffordance.toggle()
                    }
                    if lens == .time {
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(180))
                            isQuickAddFocused = true
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(V2Theme.ColorRole.onPrimary)
                        .frame(width: 52, height: 52)
                        .background(V2Theme.ColorRole.primary)
                        .clipShape(Circle())
                        .shadow(color: V2Theme.ColorRole.primary.opacity(0.24), radius: 16, y: 7)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("新增任务记录")
            }
        }
        .frame(maxWidth: 360, alignment: .trailing)
        .padding(.trailing, 20)
        .padding(.bottom, 20)
    }

    private var timeQuickAddPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TextField("添加任务", text: $quickAddTitle)
                    .font(V2Theme.TypeRole.bodyMedium.weight(.semibold))
                    .foregroundStyle(V2Theme.ColorRole.textPrimary)
                    .focused($isQuickAddFocused)
                    .submitLabel(.done)
                    .onSubmit(submitScheduledTask)

                Button {
                    closeQuickAdd()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(V2Theme.ColorRole.textTertiary)
                        .frame(width: 28, height: 28)
                        .background(V2Theme.ColorRole.surfaceMuted, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭新增任务")
            }

            HStack(spacing: 10) {
                Label(timeAnchor.formatted(.dateTime.month(.defaultDigits).day()), systemImage: "calendar")
                    .font(V2Theme.TypeRole.labelSmall)
                    .foregroundStyle(V2Theme.ColorRole.textTertiary)

                Spacer(minLength: 8)

                Button("添加", action: submitScheduledTask)
                    .font(V2Theme.TypeRole.labelMedium)
                    .foregroundStyle(V2Theme.ColorRole.onPrimary)
                    .padding(.horizontal, 14)
                    .frame(height: 30)
                    .background(V2Theme.ColorRole.primary, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .disabled(quickAddTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(quickAddTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
            }
        }
        .padding(12)
        .background(V2Theme.ColorRole.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(V2Theme.ColorRole.textPrimary.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: V2Theme.ColorRole.textPrimary.opacity(0.12), radius: 22, y: 10)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Text("任务")
                .font(V2Theme.TypeRole.displayMedium)
                .foregroundStyle(V2Theme.ColorRole.textPrimary)
                .lineLimit(1)
                .layoutPriority(1)

            HStack(spacing: 8) {
                ForEach(V2TaskLens.allCases) { item in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            lens = item
                            showsCaptureAffordance = false
                            quickAddTitle = ""
                            isQuickAddFocused = false
                        }
                    } label: {
                        Text(item.rawValue)
                            .font(V2Theme.TypeRole.labelMedium)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
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

    private func submitScheduledTask() {
        let title = quickAddTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        store.state.quickAddScheduledTask(title: title, on: timeAnchor)
        closeQuickAdd()
    }

    private func closeQuickAdd() {
        quickAddTitle = ""
        isQuickAddFocused = false
        withAnimation(.easeOut(duration: 0.16)) {
            showsCaptureAffordance = false
        }
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
    case structure = "结构"
    case time = "时间"
    case fishbone = "鱼骨"

    var id: String { rawValue }
}

enum V2TaskTimeScale: String, CaseIterable, Identifiable {
    case year = "年"
    case month = "月"
    case week = "周"
    case threeDay = "3日"
    case day = "日"

    var id: String { rawValue }

}

private struct V2GoalFilter: Identifiable {
    let id: String
    let title: String
    let color: Color
}

private struct V2StructureLensView: View {
    let tasks: [V2TaskNode]
    let selectedTaskID: String?

    @State private var selectedRootID: String?

    private var defaultRootID: String? {
        tasks.first { root in
            guard let selectedTaskID else { return false }
            return root.containsTask(id: selectedTaskID)
        }?.id ?? tasks.first?.id
    }

    var body: some View {
        if tasks.isEmpty {
            V2EmptyLensView(title: "还没有任务结构", detail: "新的任务会先成为一个可以观察的节点。")
        } else {
            TabView(selection: $selectedRootID) {
                ForEach(tasks, id: \.id) { task in
                    V2TaskMapCanvas(task: task, selectedTaskID: selectedTaskID)
                        .padding(.horizontal, 2)
                        .tag(Optional(task.id))
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(minHeight: 520)
            .onAppear {
                syncRootSelectionIfNeeded(force: false)
            }
            .onChange(of: selectedTaskID) { _, _ in
                syncRootSelectionIfNeeded(force: true)
            }
        }
    }

    private func syncRootSelectionIfNeeded(force: Bool) {
        guard force || selectedRootID == nil || !hasRoot(id: selectedRootID) else { return }
        selectedRootID = defaultRootID
    }

    private func hasRoot(id: String?) -> Bool {
        guard let id else { return false }
        return tasks.contains { $0.id == id }
    }
}

private struct V2TaskMapCanvas: View {
    let task: V2TaskNode
    let selectedTaskID: String?

    @State private var focusedBranchID: String?
    @State private var focusedDetailID: String?
    @State private var collapsedNodeIDs: Set<String> = []
    @State private var zoomScale: CGFloat = 0.92
    @GestureState private var pinchScale: CGFloat = 1

    private var branches: [V2TaskNode] {
        task.children.isEmpty ? [task] : task.children
    }

    private let canvasWidth: CGFloat = 900
    private let canvasHeight: CGFloat = 650
    private let rootX: CGFloat = 125
    private let branchX: CGFloat = 250
    private let detailX: CGFloat = 400
    private let leafX: CGFloat = 570

    private var defaultFocusedBranch: V2TaskNode? {
        branches.first { branch in
            guard let selectedTaskID else { return false }
            return branch.containsTask(id: selectedTaskID) && branch.children.contains { !$0.children.isEmpty }
        }
            ?? branches.first { $0.children.contains { !$0.children.isEmpty } && $0.status == .active }
            ?? branches.first { $0.children.contains { !$0.children.isEmpty } && $0.status != .done }
            ?? branches.first { branch in
                guard let selectedTaskID else { return false }
                return branch.containsTask(id: selectedTaskID)
            }
            ?? branches.first { !$0.children.isEmpty && $0.status == .active }
            ?? branches.first { !$0.children.isEmpty && $0.status != .done }
            ?? branches.first
    }

    private var selectedBranch: V2TaskNode? {
        if let focusedBranchID,
           let branch = branches.first(where: { $0.id == focusedBranchID }) {
            return branch
        }

        return defaultFocusedBranch
    }

    private var selectedDetail: V2TaskNode? {
        guard let selectedBranch else { return nil }
        guard !collapsedNodeIDs.contains(selectedBranch.id) else { return nil }

        if let focusedDetailID,
           let detail = selectedBranch.children.first(where: { $0.id == focusedDetailID }) {
            return detail
        }

        return defaultFocusedDetail(in: selectedBranch)
    }

    private var selectedBranchIndex: Int {
        guard let selectedBranch else { return 0 }
        return branches.firstIndex { $0.id == selectedBranch.id } ?? 0
    }

    private var detailNodes: [V2TaskNode] {
        guard let selectedBranch else { return [] }
        guard !collapsedNodeIDs.contains(selectedBranch.id) else { return [] }
        return selectedBranch.children
    }

    private var leafNodes: [V2TaskNode] {
        guard let selectedDetail else { return [] }
        guard !collapsedNodeIDs.contains(selectedDetail.id) else { return [] }
        return selectedDetail.children
    }

    private var effectiveZoom: CGFloat {
        clampedZoom(zoomScale * pinchScale)
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView([.vertical, .horizontal], showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    mapLines

                    V2TaskMapNode(
                        title: task.title,
                        color: V2Theme.ColorRole.textPrimary,
                        status: task.status,
                        completionSignal: task.completionSignal,
                        style: .root,
                        childCount: 0,
                        isExpanded: true
                    )
                    .position(x: rootX, y: rootY)

                    ForEach(Array(branches.enumerated()), id: \.element.id) { index, branch in
                        let isSelected = index == selectedBranchIndex
                        let isExpanded = isSelected && !collapsedNodeIDs.contains(branch.id)

                        Button {
                            focusOrToggle(branch)
                        } label: {
                            V2TaskMapNode(
                                title: branch.title,
                                color: V2Theme.goalColor(branch.colorName),
                                status: branch.status,
                                completionSignal: branch.completionSignal,
                                style: isSelected ? .selectedBranch : .branch,
                                childCount: branch.children.count,
                                isExpanded: isExpanded
                            )
                        }
                        .buttonStyle(.plain)
                        .scaleEffect(isSelected ? 1 : 0.96)
                        .opacity(isSelected ? 1 : 0.42)
                        .position(x: branchX, y: branchY(index: index, count: branches.count))
                    }

                    ForEach(Array(detailNodes.enumerated()), id: \.element.id) { index, node in
                        let isFocusedDetail = selectedDetail?.id == node.id
                        let isExpanded = isFocusedDetail && !collapsedNodeIDs.contains(node.id)

                        Button {
                            focusOrToggleDetail(node)
                        } label: {
                            V2TaskMapNode(
                                title: node.title,
                                color: V2Theme.goalColor(selectedBranch?.colorName ?? node.colorName),
                                status: node.status,
                                completionSignal: node.completionSignal,
                                style: isFocusedDetail ? .selectedDetail : .detail,
                                childCount: node.children.count,
                                isExpanded: isExpanded
                            )
                        }
                        .buttonStyle(.plain)
                        .scaleEffect(isFocusedDetail ? 1 : 0.98)
                        .opacity(isFocusedDetail ? 1 : 0.68)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        .position(
                            x: detailX,
                            y: detailY(
                                index: index,
                                count: detailNodes.count,
                                anchorY: branchY(index: selectedBranchIndex, count: branches.count)
                            )
                        )
                    }

                    ForEach(Array(leafNodes.enumerated()), id: \.element.id) { index, node in
                        V2TaskMapNode(
                            title: node.title,
                            color: V2Theme.goalColor(selectedDetail?.colorName ?? node.colorName),
                            status: node.status,
                            completionSignal: node.completionSignal,
                            style: .leaf,
                            childCount: node.children.count,
                            isExpanded: false
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.94)))
                        .position(
                            x: leafX,
                            y: leafY(
                                index: index,
                                count: leafNodes.count,
                                anchorY: detailY(
                                    index: selectedDetailIndex,
                                    count: detailNodes.count,
                                    anchorY: branchY(index: selectedBranchIndex, count: branches.count)
                                )
                            )
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
            .gesture(
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
            if focusedBranchID == nil {
                let nextBranch = defaultFocusedBranch
                focusedBranchID = nextBranch?.id
                focusedDetailID = nextBranch.flatMap { defaultFocusedDetail(in: $0)?.id }
            }
        }
        .onChange(of: selectedTaskID) { _, _ in
            withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                let nextBranch = defaultFocusedBranch
                focusedBranchID = nextBranch?.id
                focusedDetailID = nextBranch.flatMap { defaultFocusedDetail(in: $0)?.id }
            }
        }
    }

    private func focusOrToggle(_ branch: V2TaskNode) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
            if focusedBranchID == branch.id {
                if collapsedNodeIDs.contains(branch.id) {
                    collapsedNodeIDs.remove(branch.id)
                } else if !branch.children.isEmpty {
                    collapsedNodeIDs.insert(branch.id)
                }
            } else {
                focusedBranchID = branch.id
                collapsedNodeIDs.remove(branch.id)
                focusedDetailID = defaultFocusedDetail(in: branch)?.id
            }
        }
    }

    private func focusOrToggleDetail(_ detail: V2TaskNode) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
            if focusedDetailID == detail.id {
                if collapsedNodeIDs.contains(detail.id) {
                    collapsedNodeIDs.remove(detail.id)
                } else if !detail.children.isEmpty {
                    collapsedNodeIDs.insert(detail.id)
                }
            } else {
                focusedDetailID = detail.id
                collapsedNodeIDs.remove(detail.id)
            }
        }
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

    private var rootY: CGFloat {
        325
    }

    private func clampedZoom(_ value: CGFloat) -> CGFloat {
        min(1.35, max(0.62, value))
    }

    private var rootAnchorX: CGFloat { 33 }
    private var branchAnchorX: CGFloat { 168 }
    private var detailAnchorX: CGFloat { 312 }
    private var leafAnchorX: CGFloat { 496 }

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

    private var mapLines: some View {
        ZStack {
            ForEach(Array(branches.enumerated()), id: \.element.id) { index, branch in
                let y = branchY(index: index, count: branches.count)
                let isSelected = index == selectedBranchIndex
                let color = V2Theme.goalColor(branch.colorName)

                Path { path in
                    path.move(to: CGPoint(x: rootAnchorX, y: rootY))
                    path.addCurve(
                        to: CGPoint(x: branchAnchorX, y: y),
                        control1: CGPoint(x: rootAnchorX + 76, y: rootY),
                        control2: CGPoint(x: branchAnchorX - 72, y: y)
                    )
                }
                .stroke(
                    color.opacity(isSelected ? 0.94 : 0.26),
                    style: StrokeStyle(lineWidth: isSelected ? 3.4 : 2.2, lineCap: .round, lineJoin: .round)
                )
                .shadow(color: color.opacity(isSelected ? 0.07 : 0), radius: 4, y: 2)
            }

            if let selectedBranch {
                let branchColor = V2Theme.goalColor(selectedBranch.colorName)
                let anchorY = branchY(index: selectedBranchIndex, count: branches.count)

                ForEach(Array(detailNodes.enumerated()), id: \.element.id) { index, _ in
                    let y = detailY(index: index, count: detailNodes.count, anchorY: anchorY)
                    Path { path in
                        path.move(to: CGPoint(x: branchAnchorX, y: anchorY))
                        path.addCurve(
                            to: CGPoint(x: detailAnchorX, y: y),
                            control1: CGPoint(x: branchAnchorX + 82, y: anchorY),
                            control2: CGPoint(x: detailAnchorX - 82, y: y)
                        )
                    }
                    .stroke(
                        branchColor.opacity(0.90),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                    )
                    .shadow(color: branchColor.opacity(0.06), radius: 3, y: 2)
                }
            }

            if let selectedDetail {
                let detailColor = V2Theme.goalColor(selectedDetail.colorName)
                let branchAnchorY = branchY(index: selectedBranchIndex, count: branches.count)
                let detailAnchorY = detailY(index: selectedDetailIndex, count: detailNodes.count, anchorY: branchAnchorY)

                ForEach(Array(leafNodes.enumerated()), id: \.element.id) { index, _ in
                    let y = leafY(index: index, count: leafNodes.count, anchorY: detailAnchorY)
                    Path { path in
                        path.move(to: CGPoint(x: detailAnchorX, y: detailAnchorY))
                        path.addCurve(
                            to: CGPoint(x: leafAnchorX, y: y),
                            control1: CGPoint(x: detailAnchorX + 88, y: detailAnchorY),
                            control2: CGPoint(x: leafAnchorX - 88, y: y)
                        )
                    }
                    .stroke(
                        detailColor.opacity(0.82),
                        style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round)
                    )
                    .shadow(color: detailColor.opacity(0.05), radius: 3, y: 2)
                }
            }
        }
    }

    private func branchY(index: Int, count: Int) -> CGFloat {
        guard count > 1 else { return rootY }
        let spacing: CGFloat = min(110, 390 / CGFloat(max(count - 1, 1)))
        let start = rootY - CGFloat(count - 1) * spacing / 2
        return start + CGFloat(index) * spacing
    }

    private func detailY(index: Int, count: Int, anchorY: CGFloat) -> CGFloat {
        guard count > 1 else { return anchorY + 42 }
        let spacing: CGFloat = 70
        let start = anchorY - CGFloat(count - 1) * spacing / 2
        return start + CGFloat(index) * spacing
    }

    private var selectedDetailIndex: Int {
        guard let selectedDetail else { return 0 }
        return detailNodes.firstIndex { $0.id == selectedDetail.id } ?? 0
    }

    private func leafY(index: Int, count: Int, anchorY: CGFloat) -> CGFloat {
        guard count > 1 else { return anchorY + 38 }
        let spacing: CGFloat = 54
        let start = anchorY - CGFloat(count - 1) * spacing / 2
        return start + CGFloat(index) * spacing
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

    let title: String
    let color: Color
    let status: V2TaskNode.Status
    let completionSignal: Double
    let style: Style
    let childCount: Int
    let isExpanded: Bool

    var body: some View {
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

            if childCount > 0, style != .root, style != .leaf {
                HStack(spacing: 2) {
                    Text("\(childCount)")
                    Image(systemName: "chevron.right")
                        .rotationEffect(isExpanded ? .degrees(90) : .zero)
                }
                .font(V2Theme.TypeRole.labelSmall)
                .foregroundStyle(color.opacity(0.78))
                .padding(.horizontal, 6)
                .frame(height: 20)
                .background(V2Theme.ColorRole.canvas, in: Capsule())
                .overlay(Capsule().fill(color.opacity(0.10)))
                .animation(.easeInOut(duration: 0.18), value: isExpanded)
            }
        }
        .frame(width: nodeWidth, alignment: .leading)
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

private struct V2FishboneLensView: View {
    let goals: [V2GoalFilter]
    let visibleGoalIDs: Set<String>
    let timelineItems: [V2TimelineItem]
    let tasks: [V2TaskNode]
    let onToggleGoal: (String) -> Void

    private var visibleDoneItems: [V2FishboneItem] {
        timelineItems.compactMap { item in
            guard item.isDone else { return nil }
            let task = tasks.first { $0.id == item.taskID }
            let goalID = task?.goal.isEmpty == false ? task?.goal ?? "未归类" : "未归类"
            guard visibleGoalIDs.contains(goalID) else { return nil }
            return V2FishboneItem(
                id: item.id,
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
                    V2FishboneAxis(items: visibleDoneItems)
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
    let timeLabel: String
    let title: String
    let detail: String
    let goalID: String
    let color: Color
}

private struct V2FishboneAxis: View {
    let items: [V2FishboneItem]

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

                    V2FishboneEventCard(item: item, isAbove: above)
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

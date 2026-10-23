import SwiftUI
import ToughTrialV2Core

private struct V2TreeNodeFrames: PreferenceKey {
    static var defaultValue: [String: CGRect] { [:] }
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct V2InvertedTaskTreeView: View {
    let tasks: [V2TaskNode]
    let onOpenDetails: (V2TaskNode) -> Void
    @State private var expanded: Set<String> = []
    @State private var initialized = false
    @State private var selectedID: String?
    @State private var focusID: String?
    @State private var zoom: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1
    @State private var frames: [String: CGRect] = [:]
    @ScaledMetric(relativeTo: .body) private var nodeHeight: CGFloat = 64

    private var allNodes: [V2TaskNode] {
        func flatten(_ node: V2TaskNode) -> [V2TaskNode] { [node] + node.children.flatMap(flatten) }
        return tasks.flatMap(flatten)
    }
    private var focused: V2TaskNode? { allNodes.first { $0.id == focusID } }
    private var selected: V2TaskNode? { allNodes.first { $0.id == selectedID } }
    private var roots: [V2TaskNode] { focused.map { [$0] } ?? tasks }
    private var branchColors: [String: Color] {
        let palette = [V2Theme.ColorRole.goalBlue, V2Theme.ColorRole.goalViolet,
                       V2Theme.ColorRole.goalOrange, V2Theme.ColorRole.goalTeal]
        var colors: [String: Color] = [:]
        func assign(_ task: V2TaskNode, color: Color) {
            colors[task.id] = color
            for child in task.children { assign(child, color: color) }
        }
        for (rootIndex, root) in tasks.enumerated() {
            colors[root.id] = V2Theme.goalColor(root.colorName)
            for (index, child) in root.children.enumerated() {
                assign(child, color: palette[(rootIndex + index) % palette.count])
            }
        }
        return colors
    }
    private var scale: CGFloat { clamp(zoom * pinch) }
    private var layout: V2InvertedTreeLayout {
        V2InvertedTreeLayout(roots: roots, expandedIDs: expanded, nodeHeight: nodeHeight,
                             includesOverviewRoot: focused == nil)
    }
    private func parent(of id: String) -> V2TaskNode? {
        allNodes.first { $0.children.contains { $0.id == id } }
    }
    private func clamp(_ value: CGFloat) -> CGFloat { min(1.35, max(0.85, value)) }

    var body: some View {
        ScrollViewReader { reader in
            VStack(spacing: 4) {
                toolbar(reader)
                GeometryReader { proxy in
                    let tree = layout
                    let colors = branchColors
                    let width = max(proxy.size.width, tree.width)
                    ScrollView([.horizontal, .vertical]) {
                        ZStack(alignment: .topLeading) {
                            Color.clear.frame(width: 1, height: 1).id("inverted-origin")
                            connectors(tree, colors: colors)
                            if let root = tree.overviewRoot {
                                Text("未分类")
                                    .font(V2Theme.TypeRole.labelMedium)
                                    .foregroundStyle(V2Theme.secondary)
                                    .frame(width: root.width, height: root.height)
                                    .background(V2Theme.ColorRole.surfaceMuted, in: Capsule())
                                    .accessibilityIdentifier("tasks.inverted.overviewRoot")
                                    .accessibilityHint("无父任务的展示分组")
                                    .id("inverted-overview")
                                    .offset(x: root.x, y: root.y)
                            }
                            ForEach(tree.entries) { entry in
                                node(entry, color: colors[entry.id] ?? V2Theme.ColorRole.goalTeal,
                                     reader: reader, viewport: proxy.size)
                                    .frame(width: entry.width, height: tree.nodeHeight)
                                    .background(GeometryReader { geometry in
                                        Color.clear.preference(key: V2TreeNodeFrames.self,
                                            value: [entry.id: geometry.frame(in: .named("inverted-viewport"))])
                                    })
                                    .id(entry.id)
                                    .offset(x: entry.x, y: entry.y)
                            }
                        }
                        .frame(width: tree.width, height: tree.height, alignment: .topLeading)
                        .padding(.horizontal, max(0, (width - tree.width) / 2))
                        .scaleEffect(scale, anchor: .topLeading)
                        .frame(width: width * scale, height: tree.height * scale, alignment: .topLeading)
                        .padding(.bottom, selected == nil ? 88 : 16)
                        .frame(minWidth: proxy.size.width, minHeight: proxy.size.height, alignment: .topLeading)
                    }
                    .coordinateSpace(name: "inverted-viewport")
                    .accessibilityIdentifier("tasks.inverted.canvas")
                    .onPreferenceChange(V2TreeNodeFrames.self) { frames = $0 }
                    .scrollBounceBehavior(.basedOnSize)
                    .simultaneousGesture(MagnificationGesture()
                        .updating($pinch) { value, state, _ in state = value }
                        .onEnded { zoom = clamp(zoom * $0) })
                    .onAppear { reset(reader) }
                }
                if let selected { selectionPanel(selected, reader: reader) }
            }
            .onAppear {
                if !initialized {
                    for root in tasks {
                        expanded.insert(root.id)
                        expanded.formUnion(root.children.map(\.id))
                    }
                    initialized = true
                }
            }
            .onChange(of: tasks.map(\.id)) { oldIDs, ids in
                expanded.formUnion(Set(ids).subtracting(oldIDs))
            }
        }
    }

    private func toolbar(_ reader: ScrollViewProxy) -> some View {
        HStack(spacing: 0) {
            if let focused {
                Button {
                    focusID = parent(of: focused.id)?.id
                    selectedID = nil
                    reset(reader)
                } label: {
                    Label("上一级", systemImage: "chevron.left")
                        .font(V2Theme.TypeRole.bodyMedium).frame(minHeight: 44)
                }.accessibilityIdentifier("tasks.inverted.back")
            } else {
                Text("全部任务").font(V2Theme.TypeRole.bodyMedium).foregroundStyle(V2Theme.secondary)
                    .accessibilityIdentifier("tasks.structure.overviewTitle")
            }
            Spacer(minLength: 4)
            Button { zoom = clamp(zoom - 0.1) } label: {
                Image(systemName: "minus").frame(width: 44, height: 44).contentShape(Rectangle())
            }.disabled(zoom <= 0.85).accessibilityLabel("缩小倒树").accessibilityIdentifier("tasks.inverted.zoomOut")
            Button { reset(reader) } label: {
                Image(systemName: "arrow.counterclockwise").frame(width: 44, height: 44).contentShape(Rectangle())
            }.accessibilityLabel("复位倒树").accessibilityIdentifier("tasks.inverted.reset")
            Button { zoom = clamp(zoom + 0.1) } label: {
                Image(systemName: "plus").frame(width: 44, height: 44).contentShape(Rectangle())
            }.disabled(zoom >= 1.35).accessibilityLabel("放大倒树").accessibilityIdentifier("tasks.inverted.zoomIn")
        }.buttonStyle(.plain).foregroundStyle(V2Theme.secondary).padding(.horizontal, 16)
    }

    private func reset(_ reader: ScrollViewProxy) {
        zoom = 1
        DispatchQueue.main.async {
            reader.scrollTo(focused?.id ?? "inverted-overview", anchor: .top)
        }
    }

    private func node(_ entry: V2InvertedTreeLayout.Entry, color: Color,
                      reader: ScrollViewProxy, viewport: CGSize) -> some View {
        let task = entry.node
        return HStack(spacing: 0) {
            Button { selectedID = task.id } label: {
                VStack(spacing: 2) {
                    Text(task.title)
                        .font(task.children.isEmpty && entry.depth > 0 ? V2Theme.TypeRole.bodyMedium : V2Theme.TypeRole.titleMedium)
                        .foregroundStyle(task.status == .done ? V2Theme.secondary : V2Theme.ink)
                        .strikethrough(task.status == .done)
                        .lineLimit(2).multilineTextAlignment(.center)
                    if task.status == .done {
                        Label("已完成", systemImage: "checkmark")
                            .font(V2Theme.TypeRole.labelSmall).foregroundStyle(V2Theme.secondary)
                    }
                }
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }.accessibilityLabel("选择任务：\(task.title)")
                .accessibilityValue(task.status == .done ? "已完成" : "未完成")
                .accessibilityIdentifier("tasks.inverted.node.\(task.id)")
            if !task.children.isEmpty {
                Button {
                    let frame = frames[task.id] ?? .zero
                    let anchor = UnitPoint(
                        x: max(0, min(1, frame.minX / max(1, viewport.width - frame.width))),
                        y: max(0, min(1, frame.minY / max(1, viewport.height - frame.height))))
                    if expanded.contains(task.id) { expanded.remove(task.id) }
                    else { expanded.insert(task.id) }
                    DispatchQueue.main.async { reader.scrollTo(task.id, anchor: anchor) }
                } label: {
                    HStack(spacing: 3) {
                        Text("\(task.children.count)")
                        Image(systemName: expanded.contains(task.id) ? "chevron.down" : "chevron.right")
                    }.font(V2Theme.TypeRole.labelSmall).foregroundStyle(V2Theme.secondary)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }.accessibilityLabel("\(expanded.contains(task.id) ? "收起" : "展开")子任务：\(task.title)")
                    .accessibilityIdentifier("tasks.inverted.disclosure.\(task.id)")
            }
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(selectedID == task.id ? V2Theme.ColorRole.primaryContainer :
                        task.status == .done ? V2Theme.ColorRole.surfaceMuted : color.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 16)
                    .stroke(selectedID == task.id ? V2Theme.blue :
                                task.status == .done ? V2Theme.line : color.opacity(0.35), lineWidth: 1))
                .frame(height: nodeHeight - 8)
        }
    }

    private func connectors(_ tree: V2InvertedTreeLayout, colors: [String: Color]) -> some View {
        let parents = Dictionary(uniqueKeysWithValues: tree.entries.map { ($0.id, $0) })
        return ZStack(alignment: .topLeading) {
            ForEach(tree.entries) { entry in
                let end = CGPoint(x: entry.x + entry.width / 2, y: entry.y + 4)
                let start: CGPoint = {
                    if let id = entry.parentID, let parent = parents[id] {
                        return CGPoint(x: parent.x + parent.width / 2, y: parent.y + tree.nodeHeight - 4)
                    }
                    if entry.parentID == nil, let root = tree.overviewRoot {
                        return CGPoint(x: root.x + root.width / 2, y: root.y + root.height)
                    }
                    return end
                }()
                let color = entry.node.status == .done ? V2Theme.secondary :
                    (colors[entry.id] ?? V2Theme.ColorRole.goalTeal)
                Path { path in
                    let bend = (end.y - start.y) / 2
                    path.move(to: start)
                    path.addCurve(to: end,
                                  control1: CGPoint(x: start.x, y: start.y + bend),
                                  control2: CGPoint(x: end.x, y: end.y - bend))
                }.stroke(color.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                if start != end {
                    Circle().fill(color.opacity(0.75)).frame(width: 5, height: 5).position(end)
                }
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }

    private func selectionPanel(_ task: V2TaskNode, reader: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(task.title).font(V2Theme.TypeRole.bodyMedium).lineLimit(3)
                Spacer()
                Button { selectedID = nil } label: {
                    Image(systemName: "xmark").frame(width: 44, height: 44).contentShape(Rectangle())
                }.accessibilityLabel("关闭任务预览").accessibilityIdentifier("tasks.inverted.dismissSelection")
            }
            if let parent = parent(of: task.id) {
                Text(parent.title).font(.subheadline).foregroundStyle(V2Theme.secondary).lineLimit(1)
            }
            HStack {
                Button("查看任务") { onOpenDetails(task) }
                    .buttonStyle(.borderedProminent).accessibilityIdentifier("tasks.inverted.details")
                let target = task.children.isEmpty ? parent(of: task.id)?.id : task.id
                let focusTitle = target == nil ? "没有所属分支" : (target == focusID ? "已在此分支" :
                    (task.children.isEmpty ? "聚焦所属分支" : "聚焦这一支"))
                Button(focusTitle) {
                    focusID = target
                    selectedID = nil
                    if let target { expanded.insert(target) }
                    reset(reader)
                }.buttonStyle(.bordered).disabled(target == nil || target == focusID)
                    .accessibilityIdentifier("tasks.inverted.focus")
            }.controlSize(.large)
        }.padding(14)
            .background(V2Theme.ColorRole.surfaceRaised, in: RoundedRectangle(cornerRadius: 18))
            .padding(.horizontal, 16).padding(.bottom, 76)
    }
}

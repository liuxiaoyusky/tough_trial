import SwiftUI
import ToughTrialV2Core

struct V2TasksView: View {
    @ObservedObject var store: V2AppStore

    @State private var lens = V2TaskLens.structure
    @State private var timeScale = V2TaskTimeScale.week
    @State private var visibleGoalIDs: Set<String> = []
    @State private var showsCaptureAffordance = false

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
            VStack(alignment: .leading, spacing: 18) {
                header

                switch lens {
                case .structure:
                    V2StructureLensView(tasks: rootTasks)
                case .time:
                    V2TimeLensView(
                        scale: $timeScale,
                        timelineItems: store.state.timelineItems,
                        tasks: allTasks
                    )
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
            .padding(.top, 18)
            .padding(.bottom, 92)

            VStack(alignment: .trailing, spacing: 10) {
                if showsCaptureAffordance {
                    Text("在当前视角轻记一笔")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(V2Theme.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(V2Theme.panel)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(V2Theme.line, lineWidth: 1))
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }

                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        showsCaptureAffordance.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .bold))
                        Text("记录")
                            .font(.system(size: 16, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .frame(height: 54)
                    .background(V2Theme.blue)
                    .clipShape(Capsule())
                    .shadow(color: V2Theme.blue.opacity(0.26), radius: 16, y: 7)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("新增任务记录")
            }
            .padding(.trailing, 18)
            .padding(.bottom, 22)
        }
        .v2ScreenBackground()
        .onAppear {
            if visibleGoalIDs.isEmpty {
                visibleGoalIDs = Set(goals.map(\.id))
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("任务")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(V2Theme.ink)
                    .lineLimit(1)

                Spacer()

                Text("观察任务如何生长")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(V2Theme.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            HStack(spacing: 8) {
                ForEach(V2TaskLens.allCases) { item in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            lens = item
                        }
                    } label: {
                        Text(item.rawValue)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .foregroundStyle(lens == item ? .white : V2Theme.secondary)
                            .background(lens == item ? V2Theme.ink : V2Theme.panel)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(lens == item ? Color.clear : V2Theme.line, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var activeGoalIDs: Set<String> {
        visibleGoalIDs.isEmpty ? Set(goals.map(\.id)) : visibleGoalIDs
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

private enum V2TaskTimeScale: String, CaseIterable, Identifiable {
    case year = "年"
    case month = "月"
    case week = "周"
    case threeDay = "3日"
    case day = "日"

    var id: String { rawValue }

    var slots: [String] {
        switch self {
        case .year:
            ["一月", "三月", "五月", "七月", "九月", "十一月"]
        case .month:
            ["第 1 周", "第 2 周", "第 3 周", "第 4 周"]
        case .week:
            ["周一", "周二", "周三", "周四", "周五", "周末"]
        case .threeDay:
            ["今天", "明天", "后天"]
        case .day:
            ["上午", "中午", "下午", "晚上"]
        }
    }
}

private struct V2GoalFilter: Identifiable {
    let id: String
    let title: String
    let color: Color
}

private struct V2StructureLensView: View {
    let tasks: [V2TaskNode]

    var body: some View {
        if tasks.isEmpty {
            V2EmptyLensView(title: "还没有任务结构", detail: "新的任务会先成为一个可以观察的节点。")
        } else {
            TabView {
                ForEach(tasks, id: \.id) { task in
                    V2TaskTreeCard(task: task)
                        .padding(.horizontal, 7)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .frame(maxWidth: .infinity)
        }
    }
}

private struct V2TaskTreeCard: View {
    let task: V2TaskNode

    var body: some View {
        GeometryReader { proxy in
            ScrollView([.vertical, .horizontal], showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    V2TreeRootNode(task: task)

                    if task.children.isEmpty {
                        V2TreeBranchRow(
                            parentColor: V2Theme.goalColor(task.colorName),
                            tasks: [task],
                            isSelfBranch: true
                        )
                    } else {
                        V2TreeBranchRow(
                            parentColor: V2Theme.goalColor(task.colorName),
                            tasks: task.children,
                            isSelfBranch: false
                        )
                    }
                }
                .frame(minWidth: proxy.size.width + 56, minHeight: proxy.size.height - 32, alignment: .topLeading)
                .padding(28)
            }
            .background(
                ZStack {
                    V2Theme.panel
                    V2TreeGrid()
                        .stroke(V2Theme.line.opacity(0.55), lineWidth: 1)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(V2Theme.line, lineWidth: 1)
            )
        }
        .frame(minHeight: 470)
    }
}

private struct V2TreeRootNode: View {
    let task: V2TaskNode

    var body: some View {
        let color = V2Theme.goalColor(task.colorName)

        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Circle()
                    .fill(color)
                    .frame(width: 13, height: 13)

                Text(task.goal.isEmpty ? "未归类" : task.goal)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }

            Text(task.title)
                .font(.system(size: 29, weight: .semibold))
                .foregroundStyle(V2Theme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
                .strikethrough(task.status == .done, color: V2Theme.secondary)

            Text(task.subtitle)
                .font(.subheadline)
                .foregroundStyle(V2Theme.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(width: 286, alignment: .leading)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(color.opacity(0.35), lineWidth: 1)
        )
    }
}

private struct V2TreeBranchRow: View {
    let parentColor: Color
    let tasks: [V2TaskNode]
    let isSelfBranch: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(parentColor.opacity(0.38))
                    .frame(width: 2, height: 30)
                Circle()
                    .stroke(parentColor.opacity(0.5), lineWidth: 2)
                    .frame(width: 12, height: 12)
                Rectangle()
                    .fill(parentColor.opacity(0.22))
                    .frame(width: 2, height: 118)
            }
            .padding(.leading, 34)

            HStack(alignment: .top, spacing: 14) {
                ForEach(tasks, id: \.id) { child in
                    V2TreeNodeColumn(task: child, muted: isSelfBranch)
                }
            }
            .padding(.leading, 18)
        }
    }
}

private struct V2TreeNodeColumn: View {
    let task: V2TaskNode
    let muted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            V2TreeNode(task: task, muted: muted)

            ForEach(task.children, id: \.id) { child in
                HStack(alignment: .top, spacing: 10) {
                    Rectangle()
                        .fill(V2Theme.goalColor(child.colorName).opacity(0.35))
                        .frame(width: 2, height: 52)
                        .padding(.leading, 18)

                    V2TreeNode(task: child, muted: child.status == .done)
                        .padding(.top, 8)
                }
            }
        }
        .frame(width: 218, alignment: .topLeading)
    }
}

private struct V2TreeNode: View {
    let task: V2TaskNode
    let muted: Bool

    var body: some View {
        let color = V2Theme.goalColor(task.colorName)
        let isDone = task.status == .done

        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Image(systemName: symbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color)

                Text(statusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
                    .lineLimit(1)
            }

            Text(task.title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isDone || muted ? V2Theme.secondary : V2Theme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .strikethrough(isDone, color: V2Theme.secondary)

            if !task.subtitle.isEmpty {
                Text(task.subtitle)
                    .font(.caption)
                    .foregroundStyle(V2Theme.tertiary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(width: 206, alignment: .leading)
        .background((isDone ? V2Theme.line : color).opacity(isDone ? 0.16 : 0.09))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(color.opacity(isDone ? 0.16 : 0.28), lineWidth: 1)
        )
        .opacity(isDone ? 0.72 : 1)
    }

    private var symbolName: String {
        switch task.status {
        case .planned:
            "circle"
        case .active:
            "play.circle.fill"
        case .paused:
            "pause.circle.fill"
        case .done:
            "checkmark.circle.fill"
        }
    }

    private var statusText: String {
        switch task.status {
        case .planned:
            "待推进"
        case .active:
            "正在发生"
        case .paused:
            "暂停观察"
        case .done:
            "已完成"
        }
    }
}

private struct V2TreeGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let step: CGFloat = 34
        var x = rect.minX
        while x <= rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
            x += step
        }

        var y = rect.minY
        while y <= rect.maxY {
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += step
        }

        return path
    }
}

private struct V2TimeLensView: View {
    @Binding var scale: V2TaskTimeScale
    let timelineItems: [V2TimelineItem]
    let tasks: [V2TaskNode]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                ForEach(V2TaskTimeScale.allCases) { item in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            scale = item
                        }
                    } label: {
                        Text(item.rawValue)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .foregroundStyle(scale == item ? .white : V2Theme.secondary)
                            .background(scale == item ? V2Theme.blue : V2Theme.panel)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(scale == item ? Color.clear : V2Theme.line, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Array(scale.slots.enumerated()), id: \.offset) { index, slot in
                        V2TimeColumn(
                            title: slot,
                            items: items(for: index),
                            tasks: tasks,
                            isNow: index == currentSlotIndex
                        )
                    }
                }
                .padding(.vertical, 4)
                .padding(.trailing, 18)
            }
        }
    }

    private var currentSlotIndex: Int {
        min(scale.slots.count - 1, max(0, scale.slots.count / 2))
    }

    private func items(for slotIndex: Int) -> [V2TimelineItem] {
        guard !timelineItems.isEmpty else { return [] }
        return timelineItems.enumerated().compactMap { index, item in
            index % scale.slots.count == slotIndex ? item : nil
        }
    }
}

private struct V2TimeColumn: View {
    let title: String
    let items: [V2TimelineItem]
    let tasks: [V2TaskNode]
    let isNow: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 8) {
                Circle()
                    .fill(isNow ? V2Theme.blue : V2Theme.line)
                    .frame(width: 9, height: 9)

                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isNow ? V2Theme.ink : V2Theme.secondary)
                    .lineLimit(1)
            }

            Rectangle()
                .fill(isNow ? V2Theme.blue.opacity(0.45) : V2Theme.line)
                .frame(height: 2)

            VStack(alignment: .leading, spacing: 10) {
                if items.isEmpty {
                    Text("留白")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(V2Theme.tertiary)
                        .frame(maxWidth: .infinity, minHeight: 62, alignment: .center)
                } else {
                    ForEach(items, id: \.id) { item in
                        V2TimeItemView(
                            item: item,
                            task: tasks.first { $0.id == item.taskID }
                        )
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 178, alignment: .topLeading)
        .background(V2Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isNow ? V2Theme.blue.opacity(0.35) : V2Theme.line, lineWidth: 1)
        )
    }
}

private struct V2TimeItemView: View {
    let item: V2TimelineItem
    let task: V2TaskNode?

    var body: some View {
        let color = task.map { V2Theme.goalColor($0.colorName) } ?? V2Theme.secondary

        HStack(alignment: .top, spacing: 9) {
            VStack(spacing: 4) {
                Circle()
                    .fill(item.isDone ? V2Theme.line : color)
                    .frame(width: 10, height: 10)
                Rectangle()
                    .fill(color.opacity(0.18))
                    .frame(width: 2, height: 42)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(item.timeLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
                    .lineLimit(1)

                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(item.isDone ? V2Theme.secondary : V2Theme.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .strikethrough(item.isDone, color: V2Theme.secondary)

                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(V2Theme.tertiary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
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
                color: task.map { V2Theme.goalColor($0.colorName) } ?? V2Theme.secondary
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
                                    .font(.footnote.weight(.semibold))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(visibleGoalIDs.contains(goal.id) ? goal.color : V2Theme.tertiary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background((visibleGoalIDs.contains(goal.id) ? goal.color : V2Theme.line).opacity(0.12))
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
                .stroke(V2Theme.ink.opacity(0.18), style: StrokeStyle(lineWidth: 4, lineCap: .round))

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
        .background(
            LinearGradient(
                colors: [V2Theme.panel, V2Theme.page],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(V2Theme.line, lineWidth: 1)
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
                .font(.caption2.weight(.bold))
                .foregroundStyle(item.color)
                .lineLimit(1)

            Text(item.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(V2Theme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.78)

            Text(item.detail)
                .font(.caption2)
                .foregroundStyle(V2Theme.tertiary)
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
                .foregroundStyle(V2Theme.tertiary)

            Text(title)
                .font(.headline)
                .foregroundStyle(V2Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Text(detail)
                .font(.subheadline)
                .foregroundStyle(V2Theme.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
        .padding(24)
        .background(V2Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(V2Theme.line, lineWidth: 1)
        )
    }
}

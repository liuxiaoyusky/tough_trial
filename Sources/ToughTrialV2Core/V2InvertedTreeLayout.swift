import Foundation

/// Presentation-only forest layout. Coordinates never change task relationships.
public struct V2InvertedTreeLayout: Sendable {
    /// A layout element, deliberately separate from business task nodes.
    public struct OverviewRoot: Sendable {
        public let x: Double
        public let y: Double
        public let width: Double
        public let height: Double
    }

    public struct Entry: Identifiable, Sendable {
        public var id: String { node.id }
        public let node: V2TaskNode
        public let parentID: String?
        public let depth: Int
        public let x: Double
        public let y: Double
        public let width: Double
    }
    public let entries: [Entry]
    public let width: Double
    public let height: Double
    public let nodeHeight: Double
    public let overviewRoot: OverviewRoot?

    public init(roots: [V2TaskNode], expandedIDs: Set<String>, nodeHeight: Double = 96,
                includesOverviewRoot: Bool = false) {
        struct Branch {
            let node: V2TaskNode
            let children: [Branch]
            let width: Double
            let span: Double
        }
        let gap = 12.0
        func measure(_ node: V2TaskNode, depth: Int) -> Branch {
            let children = expandedIDs.contains(node.id) ? node.children.map { measure($0, depth: depth + 1) } : []
            let width = depth == 0 ? 240.0 : (node.children.isEmpty ? 80.0 : 164.0)
            let childrenWidth = children.reduce(0) { $0 + $1.span } + Double(max(0, children.count - 1)) * gap
            return Branch(node: node, children: children, width: width, span: max(width, childrenWidth))
        }
        var entries: [Entry] = []
        let overviewHeight = includesOverviewRoot && !roots.isEmpty ? nodeHeight * 0.5 : 0
        let topOffset = overviewHeight > 0 ? overviewHeight + 24 : 0
        func place(_ branch: Branch, parentID: String?, depth: Int, left: Double) {
            entries.append(Entry(node: branch.node, parentID: parentID, depth: depth,
                                 x: left + (branch.span - branch.width) / 2,
                                 y: 16 + topOffset + Double(depth) * (nodeHeight + 36), width: branch.width))
            let childWidth = branch.children.reduce(0) { $0 + $1.span } + Double(max(0, branch.children.count - 1)) * gap
            var childLeft = left + (branch.span - childWidth) / 2
            for child in branch.children {
                place(child, parentID: branch.node.id, depth: depth + 1, left: childLeft)
                childLeft += child.span + gap
            }
        }
        var left = 16.0
        for root in roots {
            let branch = measure(root, depth: 0)
            place(branch, parentID: nil, depth: 0, left: left)
            left += branch.span + gap
        }
        self.entries = entries
        self.width = roots.isEmpty ? 0 : left - gap + 16
        self.height = (entries.map(\.y).max() ?? 0) + (entries.isEmpty ? 0 : nodeHeight + 16)
        self.nodeHeight = nodeHeight
        overviewRoot = overviewHeight > 0
            ? OverviewRoot(x: (self.width - 160) / 2, y: 16, width: 160, height: overviewHeight)
            : nil
    }
}

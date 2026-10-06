import XCTest
import ToughTrialV2Core

final class InvertedTreeLayoutTests: XCTestCase {
    func node(_ id: String, _ children: [V2TaskNode] = []) -> V2TaskNode {
        V2TaskNode(id: id, title: id, subtitle: "", goal: "", colorName: "teal",
                   status: .planned, spentMinutes: 0, children: children)
    }

    func testBranchesDoNotOverlapAndParentsCenterOverChildren() throws {
        let root = node("r", [node("a", [node("a1"), node("a2")]), node("b", [node("b1"), node("b2")])])
        let layout = V2InvertedTreeLayout(roots: [root, node("other")], expandedIDs: ["r", "a", "b"])
        for depth in 0...2 {
            let row = layout.entries.filter { $0.depth == depth }.sorted { $0.x < $1.x }
            for pair in zip(row, row.dropFirst()) {
                XCTAssertLessThanOrEqual(pair.0.x + pair.0.width + 11, pair.1.x)
            }
        }
        for parent in layout.entries {
            let children = layout.entries.filter { $0.parentID == parent.id }
            if let first = children.first, let last = children.last {
                XCTAssertEqual(parent.x + parent.width / 2,
                               (first.x + first.width / 2 + last.x + last.width / 2) / 2, accuracy: 0.01)
                XCTAssertGreaterThan(first.y, parent.y + layout.nodeHeight)
            }
        }
        let collapsed = V2InvertedTreeLayout(roots: [root], expandedIDs: [])
        XCTAssertEqual(collapsed.entries.map(\.id), ["r"])
        XCTAssertLessThan(collapsed.width, layout.width)
    }

    func testSixLevelsAndEmptyForest() {
        var root = node("5")
        for depth in (0..<5).reversed() { root = node("\(depth)", [root]) }
        let layout = V2InvertedTreeLayout(roots: [root], expandedIDs: Set((0..<6).map(String.init)))
        XCTAssertEqual(layout.entries.count, 6)
        XCTAssertEqual(layout.entries.last?.depth, 5)
        XCTAssertEqual(layout.entries.first!.x + layout.entries.first!.width / 2,
                       layout.entries.last!.x + layout.entries.last!.width / 2, accuracy: 0.01)
        XCTAssertTrue(V2InvertedTreeLayout(roots: [], expandedIDs: []).entries.isEmpty)
    }

    func testOverviewConnectsForestWithoutAddingOrReparentingTasks() throws {
        let roots = [node("one", [node("child")]), node("two")]
        let ordinary = V2InvertedTreeLayout(roots: roots, expandedIDs: ["one"])
        let overview = V2InvertedTreeLayout(roots: roots, expandedIDs: ["one"], includesOverviewRoot: true)
        let root = try XCTUnwrap(overview.overviewRoot)
        XCTAssertEqual(root.x + root.width / 2, overview.width / 2, accuracy: 0.01)
        XCTAssertEqual(overview.entries.map(\.id), ordinary.entries.map(\.id))
        XCTAssertEqual(overview.entries.map(\.parentID), ordinary.entries.map(\.parentID))
        XCTAssertEqual(overview.entries.map(\.depth), ordinary.entries.map(\.depth))
        XCTAssertEqual(overview.entries.map(\.x), ordinary.entries.map(\.x))
        for entry in overview.entries.filter({ $0.parentID == nil }) {
            XCTAssertGreaterThan(entry.y, root.y + root.height)
        }
        XCTAssertNil(ordinary.overviewRoot, "聚焦实际分支时不增加展示根")
        let empty = V2InvertedTreeLayout(roots: [], expandedIDs: [], includesOverviewRoot: true)
        XCTAssertNil(empty.overviewRoot)
        XCTAssertEqual(empty.width, 0)
        XCTAssertEqual(empty.height, 0)
    }
}

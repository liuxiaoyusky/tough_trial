# Frontend Redesign V2 Clean Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a clean V2 SwiftUI prototype for the redesigned `今天`, `任务`, `计划`, and `回想` experience without extending the old SwiftUI implementation.

**Architecture:** Treat the existing Swift files as historical reference only. Add a separate `ToughTrialV2Core` package target for demo state and checks, add a separate `Sources/ToughTrialV2App` app surface, and point the Xcode target at the V2 app source folder. The V2 prototype uses local state and mock AI output only.

**Tech Stack:** Swift 6, SwiftUI, Swift Package Manager, XcodeGen-generated iOS app.

---

## Product Source References

- Spec: `docs/superpowers/specs/2026-05-28-tough-trial-interaction-redesign-design.md`
- Task mockup: `.superpowers/brainstorm/99266-1779956168/content/tasks-main-view-v2.html`
- Plan mockup: `.superpowers/brainstorm/99266-1779956168/content/plan-chat-agent-v2.html`
- Recall mockup: `.superpowers/brainstorm/99266-1779956168/content/recall-three-layouts-v5.html`
- Agent guide: `CLAUDE.md`

## Current Workspace Rule

Run before any edit:

```bash
git status --short
```

The workspace already contains unrelated dirty Swift files and old mockup artifacts. Do not reset, checkout, delete, or reformat those files. V2 should avoid them by creating new files and changing the app target source path.

## V2 File Structure

Package and checks:

- Modify: `Package.swift`
  - Add library product `ToughTrialV2Core`.
  - Add target `ToughTrialV2Core` at `Sources/ToughTrialV2Core`.
  - Add executable target `ToughTrialV2Checks` at `Checks/ToughTrialV2Checks`.
- Create: `Sources/ToughTrialV2Core/V2PrototypeState.swift`
  - Own all V2 demo state, IDs, task tree, timeline, active sessions, plan chat draft, recall references.
- Create: `Checks/ToughTrialV2Checks/main.swift`
  - Check active session lifecycle, quick add, plan draft generation, recall reference insertion, and fullscreen toggle state.

V2 app:

- Modify: `project.yml`
  - Point the iOS target source path to `Sources/ToughTrialV2App`.
  - Depend on package product `ToughTrialV2Core`.
  - Keep the existing bundle id and `Sources/ToughTrialApp/Info.plist`.
- Create: `Sources/ToughTrialV2App/ToughTrialV2App.swift`
  - New `@main` app entry.
- Create: `Sources/ToughTrialV2App/V2AppStore.swift`
  - Observable store wrapping `V2PrototypeState`.
- Create: `Sources/ToughTrialV2App/V2Theme.swift`
  - Modern neutral visual tokens, not the old palette.
- Create: `Sources/ToughTrialV2App/V2Components.swift`
  - Shared buttons, chips, segmented controls, floating action, panels.
- Create: `Sources/ToughTrialV2App/V2RootView.swift`
  - Tab shell for `今天`, `任务`, `回想`; `计划` opens as a standalone full-screen chat agent.
- Create: `Sources/ToughTrialV2App/V2TodayView.swift`
  - Active sessions + flowing today timeline + bottom-right blue capsule plus + Zen entry.
- Create: `Sources/ToughTrialV2App/V2ZenView.swift`
  - Full-screen timer surface linked to an optional task/session.
- Create: `Sources/ToughTrialV2App/V2TasksView.swift`
  - `结构 / 时间 / 鱼骨` main view with switchable lenses.
- Create: `Sources/ToughTrialV2App/V2PlanAgentView.swift`
  - Codex-mobile-like standalone chat agent, no tab bar, structured draft artifact.
- Create: `Sources/ToughTrialV2App/V2RecallView.swift`
  - Date rail + editor + reference window + top-left fullscreen button.

## Out Of Scope

- Editing old `Sources/ToughTrialApp/*.swift`.
- Editing old `Sources/FocusTimelineCore/*.swift`.
- Real LLM API calls.
- SwiftData persistence.
- Apple Reminders, Calendar, notifications, or AlarmKit integration.
- Dreaming background jobs.
- Full graph dragging.

## Task 1: Isolated V2 Core And Checks

**Files:**
- Modify: `Package.swift`
- Create: `Sources/ToughTrialV2Core/V2PrototypeState.swift`
- Create: `Checks/ToughTrialV2Checks/main.swift`

- [ ] **Step 1: Update Package.swift with V2 targets**

Replace `Package.swift` with this complete manifest:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ToughTrial",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "FocusTimelineCore", targets: ["FocusTimelineCore"]),
        .library(name: "ToughTrialV2Core", targets: ["ToughTrialV2Core"])
    ],
    targets: [
        .target(name: "FocusTimelineCore"),
        .target(name: "ToughTrialV2Core"),
        .executableTarget(
            name: "FocusTimelineCoreChecks",
            dependencies: ["FocusTimelineCore"],
            path: "Checks/FocusTimelineCoreChecks"
        ),
        .executableTarget(
            name: "ToughTrialV2Checks",
            dependencies: ["ToughTrialV2Core"],
            path: "Checks/ToughTrialV2Checks"
        )
    ]
)
```

- [ ] **Step 2: Add V2 prototype state**

Create `Sources/ToughTrialV2Core/V2PrototypeState.swift` with:

```swift
import Foundation

public struct V2TaskNode: Identifiable, Sendable, Equatable {
    public enum Status: String, Sendable {
        case planned
        case active
        case paused
        case done
    }

    public let id: UUID
    public var title: String
    public var subtitle: String
    public var goal: String
    public var colorName: String
    public var status: Status
    public var spentMinutes: Int
    public var children: [V2TaskNode]

    public init(
        id: UUID,
        title: String,
        subtitle: String,
        goal: String,
        colorName: String,
        status: Status = .planned,
        spentMinutes: Int = 0,
        children: [V2TaskNode] = []
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.goal = goal
        self.colorName = colorName
        self.status = status
        self.spentMinutes = spentMinutes
        self.children = children
    }
}

public struct V2TimelineItem: Identifiable, Sendable, Equatable {
    public let id: UUID
    public var timeLabel: String
    public var title: String
    public var detail: String
    public var taskID: UUID?
    public var isDone: Bool

    public init(id: UUID, timeLabel: String, title: String, detail: String, taskID: UUID?, isDone: Bool = false) {
        self.id = id
        self.timeLabel = timeLabel
        self.title = title
        self.detail = detail
        self.taskID = taskID
        self.isDone = isDone
    }
}

public struct V2ActiveSession: Identifiable, Sendable, Equatable {
    public enum Status: String, Sendable {
        case running
        case paused
    }

    public let id: UUID
    public var taskID: UUID?
    public var title: String
    public var startedAtLabel: String
    public var currentElapsed: Int
    public var totalElapsed: Int
    public var status: Status

    public init(id: UUID, taskID: UUID?, title: String, startedAtLabel: String, currentElapsed: Int = 0, totalElapsed: Int = 0, status: Status = .running) {
        self.id = id
        self.taskID = taskID
        self.title = title
        self.startedAtLabel = startedAtLabel
        self.currentElapsed = currentElapsed
        self.totalElapsed = totalElapsed
        self.status = status
    }
}

public struct V2PlanMessage: Identifiable, Sendable, Equatable {
    public enum Role: String, Sendable {
        case user
        case agent
    }

    public let id: UUID
    public var role: Role
    public var text: String

    public init(id: UUID, role: Role, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }
}

public struct V2PlanDraft: Sendable, Equatable {
    public var title: String
    public var summary: String
    public var decisions: [String]
    public var scheduleItems: [String]

    public init(title: String, summary: String, decisions: [String], scheduleItems: [String]) {
        self.title = title
        self.summary = summary
        self.decisions = decisions
        self.scheduleItems = scheduleItems
    }
}

public struct V2RecallReference: Identifiable, Sendable, Equatable {
    public enum Kind: String, Sendable {
        case event
        case deviation
        case past
    }

    public let id: UUID
    public var kind: Kind
    public var title: String
    public var detail: String

    public init(id: UUID, kind: Kind, title: String, detail: String) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
    }
}

public struct V2PrototypeState: Sendable, Equatable {
    public enum SampleID {
        public static let writingTask = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
        public static let runningTask = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
        public static let readingTask = UUID(uuidString: "20000000-0000-0000-0000-000000000003")!
        public static let urgentTask = UUID(uuidString: "20000000-0000-0000-0000-000000000004")!
        public static let firstTimeline = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
        public static let secondTimeline = UUID(uuidString: "30000000-0000-0000-0000-000000000002")!
        public static let thirdTimeline = UUID(uuidString: "30000000-0000-0000-0000-000000000003")!
    }

    public var todayDateTitle: String
    public var taskTrees: [V2TaskNode]
    public var timelineItems: [V2TimelineItem]
    public var activeSessions: [V2ActiveSession]
    public var selectedTaskID: UUID?
    public var selectedTaskLens: String
    public var selectedPlanRange: String
    public var planMessages: [V2PlanMessage]
    public var currentPlanDraft: V2PlanDraft?
    public var savedPlanDrafts: [V2PlanDraft]
    public var recallDateLabels: [String]
    public var selectedRecallDate: String
    public var recallDraft: String
    public var recallReferences: [V2RecallReference]
    public var insertedRecallReferenceIDs: [UUID]
    public var isRecallFullscreen: Bool

    public init(
        todayDateTitle: String,
        taskTrees: [V2TaskNode],
        timelineItems: [V2TimelineItem],
        activeSessions: [V2ActiveSession] = [],
        selectedTaskID: UUID?,
        selectedTaskLens: String = "结构",
        selectedPlanRange: String = "今天",
        planMessages: [V2PlanMessage] = [],
        currentPlanDraft: V2PlanDraft? = nil,
        savedPlanDrafts: [V2PlanDraft] = [],
        recallDateLabels: [String],
        selectedRecallDate: String,
        recallDraft: String = "",
        recallReferences: [V2RecallReference],
        insertedRecallReferenceIDs: [UUID] = [],
        isRecallFullscreen: Bool = false
    ) {
        self.todayDateTitle = todayDateTitle
        self.taskTrees = taskTrees
        self.timelineItems = timelineItems
        self.activeSessions = activeSessions
        self.selectedTaskID = selectedTaskID
        self.selectedTaskLens = selectedTaskLens
        self.selectedPlanRange = selectedPlanRange
        self.planMessages = planMessages
        self.currentPlanDraft = currentPlanDraft
        self.savedPlanDrafts = savedPlanDrafts
        self.recallDateLabels = recallDateLabels
        self.selectedRecallDate = selectedRecallDate
        self.recallDraft = recallDraft
        self.recallReferences = recallReferences
        self.insertedRecallReferenceIDs = insertedRecallReferenceIDs
        self.isRecallFullscreen = isRecallFullscreen
    }

    public var selectedTaskTitle: String {
        taskTitle(for: selectedTaskID) ?? "未关联任务"
    }

    public static func sample() -> V2PrototypeState {
        let writingLeaf = V2TaskNode(
            id: SampleID.writingTask,
            title: "写作提纲",
            subtitle: "服务长期表达能力",
            goal: "表达",
            colorName: "blue",
            status: .active,
            spentMinutes: 42
        )
        let readingLeaf = V2TaskNode(
            id: SampleID.readingTask,
            title: "读书 20 页",
            subtitle: "沉淀材料，不追百分比",
            goal: "输入",
            colorName: "green",
            status: .planned
        )
        let runningLeaf = V2TaskNode(
            id: SampleID.runningTask,
            title: "跑步 3 公里",
            subtitle: "本周运动节奏",
            goal: "身体",
            colorName: "orange",
            status: .done,
            spentMinutes: 31
        )

        return V2PrototypeState(
            todayDateTitle: "五月二十九日",
            taskTrees: [
                V2TaskNode(
                    id: UUID(uuidString: "21000000-0000-0000-0000-000000000001")!,
                    title: "表达能力",
                    subtitle: "把输入转成可发表的判断",
                    goal: "表达",
                    colorName: "blue",
                    children: [writingLeaf]
                ),
                V2TaskNode(
                    id: UUID(uuidString: "21000000-0000-0000-0000-000000000002")!,
                    title: "身体节奏",
                    subtitle: "稳定运动和睡眠",
                    goal: "身体",
                    colorName: "orange",
                    children: [runningLeaf]
                ),
                V2TaskNode(
                    id: UUID(uuidString: "21000000-0000-0000-0000-000000000003")!,
                    title: "知识输入",
                    subtitle: "低摩擦累计材料",
                    goal: "输入",
                    colorName: "green",
                    children: [readingLeaf]
                )
            ],
            timelineItems: [
                V2TimelineItem(id: SampleID.firstTimeline, timeLabel: "09:20", title: "跑步 3 公里", detail: "已完成 · 31 分钟", taskID: SampleID.runningTask, isDone: true),
                V2TimelineItem(id: SampleID.secondTimeline, timeLabel: "14:00", title: "写作提纲", detail: "当前最适合推进", taskID: SampleID.writingTask),
                V2TimelineItem(id: SampleID.thirdTimeline, timeLabel: "今晚", title: "读书 20 页", detail: "可以保留为今天的轻任务", taskID: SampleID.readingTask)
            ],
            selectedTaskID: SampleID.writingTask,
            planMessages: [
                V2PlanMessage(id: UUID(uuidString: "50000000-0000-0000-0000-000000000001")!, role: .agent, text: "告诉我你想安排什么。我会先理解意图，再给你一份可保存的草稿。")
            ],
            recallDateLabels: ["今天", "昨天", "5/27", "5/26"],
            selectedRecallDate: "今天",
            recallDraft: "",
            recallReferences: [
                V2RecallReference(id: UUID(uuidString: "60000000-0000-0000-0000-000000000001")!, kind: .event, title: "跑步 3 公里", detail: "09:20 · 31 分钟"),
                V2RecallReference(id: UUID(uuidString: "60000000-0000-0000-0000-000000000002")!, kind: .event, title: "写作提纲", detail: "累计 42 分钟"),
                V2RecallReference(id: UUID(uuidString: "60000000-0000-0000-0000-000000000003")!, kind: .deviation, title: "午后被临时事项打断", detail: "现实维护占用了计划空档"),
                V2RecallReference(id: UUID(uuidString: "60000000-0000-0000-0000-000000000004")!, kind: .past, title: "上周同类反思", detail: "下午安排过密时，写作容易被挤掉")
            ]
        )
    }

    public mutating func startSession(taskID: UUID?, title: String, startedAtLabel: String) {
        activeSessions.append(
            V2ActiveSession(
                id: UUID(),
                taskID: taskID,
                title: title,
                startedAtLabel: startedAtLabel
            )
        )
        selectedTaskID = taskID
    }

    public mutating func toggleSession(_ id: UUID) {
        guard let index = activeSessions.firstIndex(where: { $0.id == id }) else { return }
        activeSessions[index].status = activeSessions[index].status == .running ? .paused : .running
    }

    public mutating func endSession(_ id: UUID, totalElapsed: Int, endLabel: String) {
        guard let index = activeSessions.firstIndex(where: { $0.id == id }) else { return }
        var session = activeSessions.remove(at: index)
        session.totalElapsed = totalElapsed
        timelineItems.append(
            V2TimelineItem(
                id: UUID(),
                timeLabel: endLabel,
                title: session.title,
                detail: "记录用时 \(totalElapsed) 分钟",
                taskID: session.taskID,
                isDone: true
            )
        )
        if let taskID = session.taskID {
            addSpentMinutes(totalElapsed, to: taskID)
        }
    }

    public mutating func quickAddTodayTask(title: String) {
        let taskID = UUID()
        let task = V2TaskNode(
            id: taskID,
            title: title,
            subtitle: "今日临时加入",
            goal: "现实维护",
            colorName: "gray"
        )
        taskTrees.append(task)
        timelineItems.append(
            V2TimelineItem(
                id: UUID(),
                timeLabel: "今天",
                title: title,
                detail: "临时任务 · 可并行",
                taskID: taskID
            )
        )
        selectedTaskID = taskID
    }

    public mutating func sendPlanPrompt(_ prompt: String) {
        planMessages.append(V2PlanMessage(id: UUID(), role: .user, text: prompt))
        currentPlanDraft = V2PlanDraft(
            title: "计划草稿",
            summary: "我先把这句话理解成一个轻量计划，不强迫你补充结构化字段。",
            decisions: [
                "判断是否需要拆解",
                "判断是否需要安排时间",
                "判断它服务长期目标还是现实维护"
            ],
            scheduleItems: [
                "\(selectedPlanRange)：保留一个可执行片段",
                "如果任务过大，再建议拆成下一步"
            ]
        )
        planMessages.append(V2PlanMessage(id: UUID(), role: .agent, text: "我生成了一份草稿。你可以继续补充、保存草稿，或接受安排。"))
    }

    public mutating func saveCurrentPlanDraft() {
        guard let currentPlanDraft else { return }
        savedPlanDrafts.append(currentPlanDraft)
    }

    public mutating func acceptCurrentPlanDraft() {
        guard let currentPlanDraft else { return }
        savedPlanDrafts.append(currentPlanDraft)
        timelineItems.append(
            V2TimelineItem(
                id: UUID(),
                timeLabel: selectedPlanRange,
                title: currentPlanDraft.title,
                detail: currentPlanDraft.summary,
                taskID: nil
            )
        )
        self.currentPlanDraft = nil
    }

    public mutating func insertRecallReference(_ id: UUID) {
        guard let reference = recallReferences.first(where: { $0.id == id }) else { return }
        if !insertedRecallReferenceIDs.contains(id) {
            insertedRecallReferenceIDs.append(id)
        }
        let prefix = recallDraft.isEmpty ? "" : "\n"
        recallDraft += "\(prefix)- \(reference.title)：\(reference.detail)"
    }

    public mutating func applyRecallDraft() {
        let prefix = recallDraft.isEmpty ? "" : "\n\n"
        recallDraft += "\(prefix)今天的重点不是完成了多少，而是哪些时间真正推进了长期目标，哪些时间只是现实维护。"
    }

    public mutating func toggleRecallFullscreen() {
        isRecallFullscreen.toggle()
    }

    public func taskTitle(for id: UUID?) -> String? {
        guard let id else { return nil }
        return flattenTasks().first(where: { $0.id == id })?.title
    }

    public func flattenTasks() -> [V2TaskNode] {
        taskTrees.flatMap { node in [node] + flatten(node.children) }
    }

    private func flatten(_ nodes: [V2TaskNode]) -> [V2TaskNode] {
        nodes.flatMap { node in [node] + flatten(node.children) }
    }

    private mutating func addSpentMinutes(_ minutes: Int, to id: UUID) {
        for index in taskTrees.indices {
            if addSpentMinutes(minutes, to: id, in: &taskTrees[index]) {
                return
            }
        }
    }

    private func addSpentMinutes(_ minutes: Int, to id: UUID, in node: inout V2TaskNode) -> Bool {
        if node.id == id {
            node.spentMinutes += minutes
            return true
        }
        for index in node.children.indices {
            if addSpentMinutes(minutes, to: id, in: &node.children[index]) {
                return true
            }
        }
        return false
    }
}
```

- [ ] **Step 3: Add V2 checks**

Create `Checks/ToughTrialV2Checks/main.swift` with:

```swift
import Foundation
import ToughTrialV2Core

func expect(
    _ condition: @autoclosure () -> Bool,
    _ message: String,
    file: StaticString = #file,
    line: UInt = #line
) {
    if !condition() {
        FileHandle.standardError.write(Data("Check failed: \(message) at \(file):\(line)\n".utf8))
        Foundation.exit(1)
    }
}

func checkActiveSessionLifecycle() {
    var state = V2PrototypeState.sample()

    state.startSession(taskID: V2PrototypeState.SampleID.writingTask, title: "写作提纲", startedAtLabel: "14:00")
    let sessionID = state.activeSessions[0].id
    state.toggleSession(sessionID)
    state.endSession(sessionID, totalElapsed: 25, endLabel: "14:25")

    expect(state.activeSessions.isEmpty, "ending a session should remove it from the active area")
    expect(state.timelineItems.contains { $0.title == "写作提纲" && $0.detail.contains("25") && $0.isDone }, "ending should write a completed time record")
    expect(state.flattenTasks().first(where: { $0.id == V2PrototypeState.SampleID.writingTask })?.spentMinutes == 67, "ending should add time to the linked task")
}

func checkQuickAddCreatesTodayMaintenanceTask() {
    var state = V2PrototypeState.sample()

    state.quickAddTodayTask(title: "查报销到账")

    expect(state.timelineItems.last?.title == "查报销到账", "quick add should append to today's timeline")
    expect(state.timelineItems.last?.detail.contains("可并行") == true, "quick add should not force replacement or empty-slot logic")
    expect(state.selectedTaskTitle == "查报销到账", "quick add should select the new task")
}

func checkPlanPromptCreatesDraftWithoutMutatingTimeline() {
    var state = V2PrototypeState.sample()
    let beforeCount = state.timelineItems.count

    state.sendPlanPrompt("这周想跑 10 公里")

    expect(state.currentPlanDraft?.decisions.contains("判断是否需要拆解") == true, "plan draft should expose planning judgments")
    expect(state.timelineItems.count == beforeCount, "draft generation should not mutate today's timeline before acceptance")
}

func checkAcceptingPlanDraftAddsTimelineItem() {
    var state = V2PrototypeState.sample()

    state.sendPlanPrompt("这周想跑 10 公里")
    state.acceptCurrentPlanDraft()

    expect(state.currentPlanDraft == nil, "accepting should clear current draft")
    expect(state.savedPlanDrafts.count == 1, "accepting should save the draft")
    expect(state.timelineItems.last?.title == "计划草稿", "accepting should add a plan artifact to the timeline")
}

func checkRecallReferenceAndFullscreen() {
    var state = V2PrototypeState.sample()
    let referenceID = state.recallReferences[0].id

    state.insertRecallReference(referenceID)
    state.toggleRecallFullscreen()

    expect(state.recallDraft.contains("跑步 3 公里"), "reference insertion should append evidence text")
    expect(state.insertedRecallReferenceIDs == [referenceID], "inserted references should be tracked once")
    expect(state.isRecallFullscreen, "fullscreen toggle should update state")
}

checkActiveSessionLifecycle()
checkQuickAddCreatesTodayMaintenanceTask()
checkPlanPromptCreatesDraftWithoutMutatingTimeline()
checkAcceptingPlanDraftAddsTimelineItem()
checkRecallReferenceAndFullscreen()

print("ToughTrialV2Checks passed")
```

- [ ] **Step 4: Run V2 checks**

Run:

```bash
swift run ToughTrialV2Checks
```

Expected: prints `ToughTrialV2Checks passed`.

- [ ] **Step 5: Commit Task 1**

Run:

```bash
git add Package.swift Sources/ToughTrialV2Core Checks/ToughTrialV2Checks
git commit -m "feat: add v2 prototype core"
```

## Task 2: V2 App Shell, Theme, And Project Routing

**Files:**
- Modify: `project.yml`
- Create: `Sources/ToughTrialV2App/ToughTrialV2App.swift`
- Create: `Sources/ToughTrialV2App/V2AppStore.swift`
- Create: `Sources/ToughTrialV2App/V2Theme.swift`
- Create: `Sources/ToughTrialV2App/V2Components.swift`
- Create: `Sources/ToughTrialV2App/V2RootView.swift`

- [ ] **Step 1: Route Xcode target to V2 app files**

In `project.yml`, change target sources and dependency to:

```yaml
targets:
  ToughTrial:
    type: application
    platform: iOS
    sources:
      - path: Sources/ToughTrialV2App
    dependencies:
      - package: FocusTimelineCore
        product: ToughTrialV2Core
```

Keep the existing `info.path` pointing to `Sources/ToughTrialApp/Info.plist`.

- [ ] **Step 2: Add V2 app entry**

Create `Sources/ToughTrialV2App/ToughTrialV2App.swift`:

```swift
import SwiftUI

@main
struct ToughTrialV2App: App {
    var body: some Scene {
        WindowGroup {
            V2RootView()
        }
    }
}
```

- [ ] **Step 3: Add store**

Create `Sources/ToughTrialV2App/V2AppStore.swift`:

```swift
import SwiftUI
import ToughTrialV2Core

@MainActor
final class V2AppStore: ObservableObject {
    @Published var state = V2PrototypeState.sample()
    @Published var isPlanPresented = false
    @Published var zenSession: V2ActiveSession?

    func openPlanAgent() {
        isPlanPresented = true
    }

    func closePlanAgent() {
        isPlanPresented = false
    }

    func startZen(taskID: UUID?, title: String) {
        state.startSession(taskID: taskID, title: title, startedAtLabel: "现在")
        zenSession = state.activeSessions.last
    }

    func finishZen() {
        guard let id = zenSession?.id else { return }
        state.endSession(id, totalElapsed: 25, endLabel: "刚刚")
        zenSession = nil
    }

    func closeZen() {
        zenSession = nil
    }
}
```

- [ ] **Step 4: Add theme**

Create `Sources/ToughTrialV2App/V2Theme.swift`:

```swift
import SwiftUI

enum V2Theme {
    static let ink = Color(red: 0.08, green: 0.09, blue: 0.11)
    static let secondary = Color(red: 0.43, green: 0.46, blue: 0.50)
    static let tertiary = Color(red: 0.66, green: 0.69, blue: 0.73)
    static let page = Color(red: 0.94, green: 0.95, blue: 0.97)
    static let panel = Color.white
    static let line = Color(red: 0.84, green: 0.87, blue: 0.91)
    static let blue = Color(red: 0.28, green: 0.40, blue: 0.94)
    static let mint = Color(red: 0.29, green: 0.73, blue: 0.62)
    static let orange = Color(red: 0.93, green: 0.55, blue: 0.24)
    static let violet = Color(red: 0.50, green: 0.39, blue: 0.91)

    static func goalColor(_ name: String) -> Color {
        switch name {
        case "blue": return blue
        case "green": return mint
        case "orange": return orange
        default: return tertiary
        }
    }
}

extension View {
    func v2ScreenBackground() -> some View {
        background(V2Theme.page.ignoresSafeArea())
            .foregroundStyle(V2Theme.ink)
    }
}
```

- [ ] **Step 5: Add reusable components**

Create `Sources/ToughTrialV2App/V2Components.swift` with small SwiftUI components:

```swift
import SwiftUI

struct V2IconButton: View {
    var systemName: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.86), in: Circle())
        }
        .buttonStyle(.plain)
    }
}

struct V2SegmentedPicker: View {
    var items: [String]
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items, id: \.self) { item in
                Button {
                    selection = item
                } label: {
                    Text(item)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(selection == item ? .white : V2Theme.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(selection == item ? V2Theme.ink : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(.white.opacity(0.76), in: Capsule())
    }
}

struct V2FloatingPlusButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 74, height: 58)
                .background(V2Theme.blue, in: Capsule())
                .shadow(color: V2Theme.blue.opacity(0.28), radius: 18, y: 10)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("新增今日任务")
    }
}

struct V2Panel<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(V2Theme.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
```

- [ ] **Step 6: Add V2 root shell**

Create `Sources/ToughTrialV2App/V2RootView.swift`:

```swift
import SwiftUI

struct V2RootView: View {
    @StateObject private var store = V2AppStore()

    var body: some View {
        TabView {
            V2TodayView(store: store)
                .tabItem { Label("今天", systemImage: "checkmark.circle.fill") }

            V2TasksView(store: store)
                .tabItem { Label("任务", systemImage: "square.grid.2x2") }

            Button {
                store.openPlanAgent()
            } label: {
                VStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 42, weight: .medium))
                    Text("打开计划 Agent")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .v2ScreenBackground()
            }
            .tabItem { Label("计划", systemImage: "sparkles") }

            V2RecallView(store: store)
                .tabItem { Label("回想", systemImage: "book.pages") }
        }
        .fullScreenCover(isPresented: $store.isPlanPresented) {
            V2PlanAgentView(store: store)
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { store.zenSession != nil },
                set: { if !$0 { store.closeZen() } }
            )
        ) {
            if let session = store.zenSession {
                V2ZenView(session: session, onFinish: store.finishZen, onClose: store.closeZen)
            }
        }
    }
}

#Preview {
    V2RootView()
}
```

- [ ] **Step 7: Generate project and commit shell**

Run:

```bash
/opt/homebrew/bin/xcodegen generate
```

Expected: succeeds and includes only `Sources/ToughTrialV2App` for the iOS app target.

Commit:

```bash
git add project.yml Sources/ToughTrialV2App
git commit -m "feat: add v2 app shell"
```

## Task 3: V2 Today And Zen Surfaces

**Files:**
- Create: `Sources/ToughTrialV2App/V2TodayView.swift`
- Create: `Sources/ToughTrialV2App/V2ZenView.swift`

- [ ] **Step 1: Implement Today**

Create `V2TodayView` with these required pieces:

- Header with `五月二十九日` and small icon buttons.
- Current active-session area; show only running/paused sessions, never unstarted tasks.
- If no active session exists, show a quiet empty active area.
- Timeline list with current item visually larger than done/future items.
- Task row actions: tap row selects task, play starts a session, leaf button starts Zen.
- Bottom-right blue capsule plus opens a compact quick-add sheet.
- Plus supports long-press and upward-drag affordance text in the sheet, without implementing real voice input.

Use `store.state.startSession`, `store.state.toggleSession`, `store.state.endSession`, `store.state.quickAddTodayTask`, and `store.startZen`.

- [ ] **Step 2: Implement Zen**

Create `V2ZenView` as a full-screen dark timer surface:

- show linked title from `V2ActiveSession.title`
- show `25:00`
- primary button completes and calls `onFinish`
- close button calls `onClose`

- [ ] **Step 3: Build app**

Run:

```bash
/opt/homebrew/bin/xcodegen generate
xcodebuild -project ToughTrial.xcodeproj -scheme ToughTrial -destination 'platform=iOS Simulator,name=iPhone 17' build
```

Expected: app target builds if local simulator exists. If the simulator name is unavailable, run `xcrun simctl list devices available` and use an available iPhone simulator.

- [ ] **Step 4: Commit Today and Zen**

Run:

```bash
git add Sources/ToughTrialV2App/V2TodayView.swift Sources/ToughTrialV2App/V2ZenView.swift
git commit -m "feat: add v2 today execution surface"
```

## Task 4: V2 Tasks Surface

**Files:**
- Create: `Sources/ToughTrialV2App/V2TasksView.swift`

- [ ] **Step 1: Implement switchable lenses**

Create `V2TasksView` with:

- top segmented control: `结构`, `时间`, `鱼骨`
- structure lens:
  - horizontal paging cards
  - each card fills most of the center
  - card content is tree-shaped, not a flat list
  - no total task count and no percentage
- time lens:
  - TickTick-like calendar selector: `年`, `月`, `周`, `3日`, `日`
  - timeline entries are not grouped by long-term goal
- fishbone lens:
  - one horizontal completion axis
  - goal checkboxes toggle visible colored completion nodes
  - different goals use different colors
- bottom-right blue capsule plus

- [ ] **Step 2: Build and commit**

Run:

```bash
xcodebuild -project ToughTrial.xcodeproj -scheme ToughTrial -destination 'platform=iOS Simulator,name=iPhone 17' build
git add Sources/ToughTrialV2App/V2TasksView.swift
git commit -m "feat: add v2 task lenses"
```

## Task 5: V2 Plan Agent

**Files:**
- Create: `Sources/ToughTrialV2App/V2PlanAgentView.swift`

- [ ] **Step 1: Implement standalone chat agent**

Create `V2PlanAgentView` with:

- no bottom tab bar
- top close button and title `计划 Agent`
- Codex-mobile-like message list
- prompt input at the bottom
- range selector: `今天`, `三日`, `本周`, `本月`
- on send, call `store.state.sendPlanPrompt`
- show current draft as an artifact card with:
  - understanding summary
  - decisions list
  - schedule items
  - buttons: `继续聊`, `存草稿`, `接受`
- `存草稿` calls `saveCurrentPlanDraft`
- `接受` calls `acceptCurrentPlanDraft`

- [ ] **Step 2: Build and commit**

Run:

```bash
xcodebuild -project ToughTrial.xcodeproj -scheme ToughTrial -destination 'platform=iOS Simulator,name=iPhone 17' build
git add Sources/ToughTrialV2App/V2PlanAgentView.swift
git commit -m "feat: add v2 plan agent"
```

## Task 6: V2 Recall Surface

**Files:**
- Create: `Sources/ToughTrialV2App/V2RecallView.swift`

- [ ] **Step 1: Implement recall layout**

Create `V2RecallView` with:

- left date rail
- top-left fullscreen button
- main plain editor area, no extra card layer around the editor
- placeholder: `写下今天真正发生了什么...`
- right reference window with tabs/chips: `事件`, `偏差`, `过去`
- reference tap inserts evidence into the editor
- bottom actions: `引用`, `整理草稿`, `保存`
- `整理草稿` calls `applyRecallDraft`
- no top detail card, no summary card, no ratio dashboard

- [ ] **Step 2: Build and commit**

Run:

```bash
xcodebuild -project ToughTrial.xcodeproj -scheme ToughTrial -destination 'platform=iOS Simulator,name=iPhone 17' build
git add Sources/ToughTrialV2App/V2RecallView.swift
git commit -m "feat: add v2 recall editor"
```

## Task 7: Final Verification And Polish

**Files:**
- Review only: `Sources/ToughTrialV2App/*.swift`
- Review only: `Sources/ToughTrialV2Core/V2PrototypeState.swift`
- Review only: `project.yml`
- Review only: `Package.swift`

- [ ] **Step 1: Run V2 checks**

Run:

```bash
swift run ToughTrialV2Checks
```

Expected: `ToughTrialV2Checks passed`.

- [ ] **Step 2: Generate project**

Run:

```bash
/opt/homebrew/bin/xcodegen generate
```

Expected: succeeds.

- [ ] **Step 3: Build iOS app**

Run:

```bash
xcodebuild -project ToughTrial.xcodeproj -scheme ToughTrial -destination 'platform=iOS Simulator,name=iPhone 17' build
```

If `iPhone 17` is unavailable, select an available simulator from:

```bash
xcrun simctl list devices available
```

- [ ] **Step 4: Manual smoke test**

Verify in simulator:

- `今天`: timeline row can start a session.
- `今天`: active session can pause/resume/end.
- `今天`: plus adds a temporary today task.
- `今天`: Zen opens from a task and completion writes time back.
- `任务`: all three lenses show distinct information architecture.
- `计划`: opens full-screen agent, no bottom tab bar, can send prompt and save/accept a draft.
- `回想`: fullscreen button works, references insert into editor, `整理草稿` adds text.

- [ ] **Step 5: Commit final fixes**

If polish or build fixes were required:

```bash
git add Package.swift project.yml Sources/ToughTrialV2Core Checks/ToughTrialV2Checks Sources/ToughTrialV2App
git commit -m "fix: polish v2 frontend prototype"
```

If no fixes were required, do not create an empty commit.

## Self-Review Checklist

- V2 ignores old front-end Swift files by routing the Xcode target to `Sources/ToughTrialV2App`.
- V2 avoids editing old `FocusTimelineCore`; all new prototype state lives in `ToughTrialV2Core`.
- `今天` remains execution-first and excludes analysis/dashboard clutter.
- `任务` is observation/cognition-first with structure/time/fishbone views.
- `计划` is a standalone chat agent with structured draft artifacts and no bottom tab bar.
- `回想` is editor-first, minimal, with user-triggered references and AI draft action.
- Quick add stays lightweight and does not force type selection.
- Mock AI does not mutate timeline until user accepts a draft.

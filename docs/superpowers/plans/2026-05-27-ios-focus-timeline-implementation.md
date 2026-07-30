# iOS Focus Timeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the V1 native iOS foundation for the Focus Timeline app described in `docs/superpowers/specs/2026-05-27-ios-focus-timeline-design.md`.

**Architecture:** Use a Swift Package core for platform-neutral domain rules and tests, plus an XcodeGen-generated iOS SwiftUI app target for the native interface. Keep reminder mapping, task/progress models, planning drafts, AI confirmation models, and export schemas independent from SwiftUI so Android and HarmonyOS clients can reuse the concepts.

**Tech Stack:** Swift 6.3, Swift Package Manager, custom Swift check runner, SwiftUI, SwiftData, UserNotifications, EventKit, AlarmKit guarded by availability, XcodeGen.

---

## Environment Notes

- This local Command Line Tools Swift environment cannot import `XCTest` or Swift `Testing`; use `swift run FocusTimelineCoreChecks` for core verification until full Xcode is selected.
- `xcodegen` is installed at `/opt/homebrew/bin/xcodegen`.
- `xcodebuild` currently requires full Xcode selection, so CI-style simulator builds are blocked until Xcode is installed or selected with `xcode-select`.
- The first implementation commit should establish a tested core package and generated iOS project files without requiring simulator execution.

## File Structure

- `Package.swift` - Swift Package manifest for `FocusTimelineCore` and `FocusTimelineCoreChecks`.
- `Sources/FocusTimelineCore/TaskModels.swift` - task type, priority tier, task status, and task entity.
- `Sources/FocusTimelineCore/ReminderPolicy.swift` - priority-to-reminder mapping and AlarmKit fallback rules.
- `Sources/FocusTimelineCore/TimelineModels.swift` - timeline events, fuzzy time markers, and event source.
- `Sources/FocusTimelineCore/PlanningModels.swift` - planning draft, planned slots, unplaced tasks, and inbox message types.
- `Sources/FocusTimelineCore/ExportModels.swift` - Markdown and CSV export DTOs.
- `Sources/ToughTrialApp/ToughTrialApp.swift` - SwiftUI app entry.
- `Sources/ToughTrialApp/RootView.swift` - initial tab shell with Today, Tasks, Plan, and Recall.
- `Sources/ToughTrialApp/TodayView.swift` - approved Today timeline layout implementation.
- `Sources/ToughTrialApp/TasksView.swift` - approved Tasks list layout implementation.
- `Sources/ToughTrialApp/PlanView.swift` - approved Plan timeline editor layout implementation.
- `Sources/ToughTrialApp/ZenModeView.swift` - approved Zen mode layout implementation.
- `project.yml` - XcodeGen project definition for the iOS app.
- `Checks/FocusTimelineCoreChecks/main.swift` - executable check runner for reminder mapping first, then task/progress, planning draft, and export checks as phases are added.

## Task 1: Core Package And Reminder Policy

**Files:**
- Create: `Package.swift`
- Create: `Sources/FocusTimelineCore/TaskModels.swift`
- Create: `Sources/FocusTimelineCore/ReminderPolicy.swift`
- Create: `Checks/FocusTimelineCoreChecks/main.swift`

- [ ] **Step 1: Write the failing reminder mapping tests**

```swift
import FocusTimelineCore
import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        FileHandle.standardError.write(Data("Check failed: \(message)\n".utf8))
        Foundation.exit(1)
    }
}

let critical = ReminderPolicy.policy(for: .critical, alarmKitAvailable: true)
expect(critical.primaryChannel == .alarmKit, "critical task should use AlarmKit")
expect(critical.fallbackChannel == .localNotificationWithSound, "critical task should fall back to local notification with sound")
expect(critical.requiresScheduledStart, "critical task should require scheduled start")

let criticalFallback = ReminderPolicy.policy(for: .critical, alarmKitAvailable: false)
expect(criticalFallback.primaryChannel == .localNotificationWithSound, "critical task should fall back without AlarmKit")
expect(criticalFallback.fallbackChannel == nil, "critical fallback should not have a second fallback")

let medium = ReminderPolicy.policy(for: .medium, alarmKitAvailable: true)
expect(medium.primaryChannel == .soundNotificationAndVibration, "medium task should use sound, notification, and vibration")

let notifyOnly = ReminderPolicy.policy(for: .notifyOnly, alarmKitAvailable: true)
expect(notifyOnly.primaryChannel == .notificationOnly, "notify-only task should use notification only")

let none = ReminderPolicy.policy(for: .none, alarmKitAvailable: true)
expect(none.primaryChannel == .none, "no-priority task should not notify")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift run FocusTimelineCoreChecks`

Expected: FAIL because `ReminderPolicy` and related types do not exist yet.

- [ ] **Step 3: Add the Swift package and minimal reminder implementation**

Create `Package.swift`:

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
        .library(name: "FocusTimelineCore", targets: ["FocusTimelineCore"])
    ],
    targets: [
        .target(name: "FocusTimelineCore"),
        .executableTarget(
            name: "FocusTimelineCoreChecks",
            dependencies: ["FocusTimelineCore"],
            path: "Checks/FocusTimelineCoreChecks"
        )
    ]
)
```

Create `Sources/FocusTimelineCore/TaskModels.swift`:

```swift
import Foundation

public enum TaskPriorityTier: String, Codable, Sendable, CaseIterable {
    case critical
    case medium
    case notifyOnly
    case none
}
```

Create `Sources/FocusTimelineCore/ReminderPolicy.swift`:

```swift
import Foundation

public enum ReminderChannel: String, Codable, Sendable, Equatable {
    case alarmKit
    case localNotificationWithSound
    case soundNotificationAndVibration
    case notificationOnly
    case none
}

public struct ReminderPolicy: Equatable, Sendable {
    public let primaryChannel: ReminderChannel
    public let fallbackChannel: ReminderChannel?
    public let requiresScheduledStart: Bool

    public static func policy(
        for priority: TaskPriorityTier,
        alarmKitAvailable: Bool
    ) -> ReminderPolicy {
        switch priority {
        case .critical:
            if alarmKitAvailable {
                return ReminderPolicy(
                    primaryChannel: .alarmKit,
                    fallbackChannel: .localNotificationWithSound,
                    requiresScheduledStart: true
                )
            }
            return ReminderPolicy(
                primaryChannel: .localNotificationWithSound,
                fallbackChannel: nil,
                requiresScheduledStart: true
            )
        case .medium:
            return ReminderPolicy(
                primaryChannel: .soundNotificationAndVibration,
                fallbackChannel: nil,
                requiresScheduledStart: false
            )
        case .notifyOnly:
            return ReminderPolicy(
                primaryChannel: .notificationOnly,
                fallbackChannel: nil,
                requiresScheduledStart: false
            )
        case .none:
            return ReminderPolicy(
                primaryChannel: .none,
                fallbackChannel: nil,
                requiresScheduledStart: false
            )
        }
    }
}
```

- [ ] **Step 4: Run tests to verify green**

Run: `swift run FocusTimelineCoreChecks`

Expected: PASS.

- [ ] **Step 5: Run all current tests**

Run: `swift build`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/FocusTimelineCore Checks/FocusTimelineCoreChecks
git commit -m "feat: add focus timeline core reminder policy"
```

## Task 2: Task And Progress Domain

Local test adaptation: because this environment cannot import `XCTest` or Swift `Testing`, implement Task 2 and later verification by adding focused check functions to `Checks/FocusTimelineCoreChecks/main.swift`. The `Tests/FocusTimelineCoreTests/...` paths below document the intended XCTest organization for a full Xcode setup, but this local run should keep using the executable check runner.

**Files:**
- Modify: `Sources/FocusTimelineCore/TaskModels.swift`
- Create: `Tests/FocusTimelineCoreTests/TaskProgressTests.swift`

- [ ] **Step 1: Write failing tests for task progress rules**

```swift
import XCTest
@testable import FocusTimelineCore

final class TaskProgressTests: XCTestCase {
    func testOneTimeTaskCompletesOnce() {
        var task = TaskItem.oneTime(id: UUID(), title: "买耳塞", priority: .notifyOnly)

        task.recordCompletion(amount: nil, at: Date(timeIntervalSince1970: 100))

        XCTAssertEqual(task.status, .completed)
        XCTAssertEqual(task.progress.completedAmount, 1)
        XCTAssertEqual(task.progress.targetAmount, 1)
    }

    func testCumulativeTaskAddsProgressTowardTotal() {
        var task = TaskItem.cumulative(
            id: UUID(),
            title: "读完一本书",
            unit: "页",
            targetAmount: 1000,
            priority: .none
        )

        task.recordCompletion(amount: 30, at: Date(timeIntervalSince1970: 100))
        task.recordCompletion(amount: 20, at: Date(timeIntervalSince1970: 200))

        XCTAssertEqual(task.progress.completedAmount, 50)
        XCTAssertEqual(task.status, .active)
    }

    func testFrequencyTaskCountsCompletionsInPeriod() {
        var task = TaskItem.frequencyGoal(
            id: UUID(),
            title: "本周跑 5 次 3 公里",
            targetCount: 5,
            period: .week,
            priority: .medium
        )

        task.recordCompletion(amount: nil, at: Date(timeIntervalSince1970: 100))
        task.recordCompletion(amount: nil, at: Date(timeIntervalSince1970: 200))

        XCTAssertEqual(task.progress.completedAmount, 2)
        XCTAssertEqual(task.progress.targetAmount, 5)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter TaskProgressTests`

Expected: FAIL because `TaskItem`, `TaskStatus`, `TaskProgress`, and period types are not defined.

- [ ] **Step 3: Implement minimal task model**

Add task kinds, status, progress, factory methods, and `recordCompletion` to `TaskModels.swift`.

- [ ] **Step 4: Run task progress tests**

Run: `swift test --filter TaskProgressTests`

Expected: PASS.

- [ ] **Step 5: Run all tests and commit**

```bash
swift test
git add Sources/FocusTimelineCore/TaskModels.swift Tests/FocusTimelineCoreTests/TaskProgressTests.swift
git commit -m "feat: add task progress domain model"
```

## Task 3: Timeline And Planning Draft Models

**Files:**
- Create: `Sources/FocusTimelineCore/TimelineModels.swift`
- Create: `Sources/FocusTimelineCore/PlanningModels.swift`
- Create: `Tests/FocusTimelineCoreTests/PlanningDraftTests.swift`

- [ ] **Step 1: Write failing planning draft tests**

Test that a planning draft can contain fixed scheduled events, uncertain-time tasks, parallel slots, and unplaced tasks.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter PlanningDraftTests`

Expected: FAIL because planning types do not exist.

- [ ] **Step 3: Implement timeline and planning DTOs**

Implement value types only. Do not add AI service calls in this task.

- [ ] **Step 4: Run tests and commit**

```bash
swift test --filter PlanningDraftTests
swift test
git add Sources/FocusTimelineCore/TimelineModels.swift Sources/FocusTimelineCore/PlanningModels.swift Tests/FocusTimelineCoreTests/PlanningDraftTests.swift
git commit -m "feat: add timeline planning draft models"
```

## Task 4: Export DTOs And Round Trip Tests

**Files:**
- Create: `Sources/FocusTimelineCore/ExportModels.swift`
- Create: `Tests/FocusTimelineCoreTests/ExportRoundTripTests.swift`

- [ ] **Step 1: Write failing export tests**

Test Markdown daily record rendering and CSV row generation for tasks, timeline events, focus blocks, and progress logs.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ExportRoundTripTests`

Expected: FAIL because export models do not exist.

- [ ] **Step 3: Implement export DTOs and renderers**

Implement deterministic Markdown and CSV generation with stable column order.

- [ ] **Step 4: Run tests and commit**

```bash
swift test --filter ExportRoundTripTests
swift test
git add Sources/FocusTimelineCore/ExportModels.swift Tests/FocusTimelineCoreTests/ExportRoundTripTests.swift
git commit -m "feat: add markdown csv export models"
```

## Task 5: iOS Project Scaffold

**Files:**
- Create: `project.yml`
- Create: `Sources/ToughTrialApp/ToughTrialApp.swift`
- Create: `Sources/ToughTrialApp/RootView.swift`

- [ ] **Step 1: Create XcodeGen project definition**

Create `project.yml` with one iOS app target named `ToughTrial` and a dependency on the local `FocusTimelineCore` package.

- [ ] **Step 2: Add minimal SwiftUI app shell**

Create `ToughTrialApp.swift` and `RootView.swift` with Chinese tab labels: `今天`, `任务`, `计划`, `回想`.

- [ ] **Step 3: Generate project**

Run: `xcodegen generate`

Expected: `ToughTrial.xcodeproj` is generated.

- [ ] **Step 4: Verify available checks**

Run: `swift test`

Expected: PASS.

Full iOS simulator build requires full Xcode selection.

- [ ] **Step 5: Commit**

```bash
git add project.yml ToughTrial.xcodeproj Sources/ToughTrialApp
git commit -m "chore: scaffold swiftui ios app"
```

## Task 6: SwiftUI Layouts

**Files:**
- Create: `Sources/ToughTrialApp/TodayView.swift`
- Create: `Sources/ToughTrialApp/TasksView.swift`
- Create: `Sources/ToughTrialApp/PlanView.swift`
- Create: `Sources/ToughTrialApp/ZenModeView.swift`
- Modify: `Sources/ToughTrialApp/RootView.swift`

- [ ] **Step 1: Implement static SwiftUI layouts from approved mockups**

Use the approved HTML files as layout references:

- `.superpowers/brainstorm/51209-1779869812/content/layout-01-today.html`
- `.superpowers/brainstorm/51209-1779869812/content/layout-02-tasks.html`
- `.superpowers/brainstorm/51209-1779869812/content/layout-03-plan-approved.html`
- `.superpowers/brainstorm/51209-1779869812/content/layout-04-zen.html`

- [ ] **Step 2: Wire navigation states**

Today and Tasks can enter focus candidate state. Start opens Zen mode.

- [ ] **Step 3: Verify core tests and project generation**

```bash
swift test
xcodegen generate
```

- [ ] **Step 4: Commit**

```bash
git add Sources/ToughTrialApp project.yml ToughTrial.xcodeproj
git commit -m "feat: add approved swiftui layouts"
```

## Task 7: Reminder And Apple Integration Facades

**Files:**
- Create: `Sources/FocusTimelineCore/AppleIntegrationModels.swift`
- Create: `Tests/FocusTimelineCoreTests/AppleIntegrationTests.swift`

- [ ] **Step 1: Write failing tests for external object mapping**

Test that tasks map to Reminders, scheduled timeline blocks map to Calendar, and critical task starts map to AlarmKit policy.

- [ ] **Step 2: Implement model-only facades**

Keep EventKit, UserNotifications, and AlarmKit calls behind protocols so core behavior remains testable.

- [ ] **Step 3: Run tests and commit**

```bash
swift test --filter AppleIntegrationTests
swift test
git add Sources/FocusTimelineCore/AppleIntegrationModels.swift Tests/FocusTimelineCoreTests/AppleIntegrationTests.swift
git commit -m "feat: add apple integration mapping models"
```

## Task 8: AI Draft And Inbox Models

**Files:**
- Create: `Sources/FocusTimelineCore/AIDraftModels.swift`
- Create: `Tests/FocusTimelineCoreTests/AIDraftTests.swift`

- [ ] **Step 1: Write failing tests for confirmation-first writes**

Test that AI task drafts, planning drafts, memory suggestions, and inbox messages cannot become saved domain records until confirmed.

- [ ] **Step 2: Implement draft models**

Implement local models only. Do not connect a provider SDK in this task.

- [ ] **Step 3: Run tests and commit**

```bash
swift test --filter AIDraftTests
swift test
git add Sources/FocusTimelineCore/AIDraftModels.swift Tests/FocusTimelineCoreTests/AIDraftTests.swift
git commit -m "feat: add ai draft inbox models"
```

## Self-Review Checklist

- Spec coverage: tasks cover scaffold, domain model, progress, timeline, Plan drag/drop data model, reminders, AI draft/inbox, export, and tests.
- V1 boundary: Dreaming analysis and push delivery are not implemented in V1 tasks; inbox message type is included.
- Reminder boundary: AlarmKit is limited to critical task start reminders.
- Platform boundary: Google Calendar and Android/HarmonyOS clients are excluded from V1 implementation.
- Verification: every behavior task starts with a failing executable check and uses `swift run FocusTimelineCoreChecks` in this local environment.

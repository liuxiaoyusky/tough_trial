# Task Structure Markmap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the V2 task structure lens with an iOS-light horizontal Markmap-style task map that matches the approved spec and mockup.

**Architecture:** Keep domain data in `ToughTrialV2Core` and presentation in `ToughTrialV2App`. The first implementation is a prototype view backed by richer sample nodes, not a persistence or AI planning change.

**Tech Stack:** Swift 6, SwiftUI, existing `ToughTrialV2Core` sample state, `ToughTrialV2Checks`, `swift build`.

---

### Task 1: Add Sample Structure Coverage

**Files:**
- Modify: `Checks/ToughTrialV2Checks/main.swift`
- Modify: `Sources/ToughTrialV2Core/V2PrototypeSamples.swift`

- [ ] Add a check that `V2PrototypeState.sample()` exposes a real three-layer task structure with a root, first-level branches, and at least one branch with children.
- [ ] Run `swift run ToughTrialV2Checks` and confirm the new check fails before changing sample data.
- [ ] Update `V2PrototypeSamples.swift` so the task sample can actually drive the approved structure map.
- [ ] Run `swift run ToughTrialV2Checks` and confirm it passes.

### Task 2: Replace Structure Lens UI

**Files:**
- Modify: `Sources/ToughTrialV2App/V2TasksView.swift`

- [ ] Replace the old tree-card structure view with a full-width paper canvas.
- [ ] Render the root context on the left, first-level branches in the middle, and the selected branch's children on the right.
- [ ] Use branch color propagation and lightweight status dots instead of cards, percentages, or dashboard counters.
- [ ] Keep the existing `结构 / 时间 / 鱼骨` segmented navigation and blue add button.

### Task 3: Verify

**Files:**
- Read only unless fixes are needed.

- [ ] Run `swift run ToughTrialV2Checks`.
- [ ] Run `swift build`.
- [ ] If the local Xcode project is available, run an iOS simulator build or explain why it could not be run.

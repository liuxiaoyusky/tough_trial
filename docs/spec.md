# Tough Trial Product Spec

Status: active source-of-truth entrypoint
Last updated: 2026-07-21

## Canonical Design Source

The detailed Chinese product spec remains:

- `docs/superpowers/specs/2026-05-30-tough-trial-interaction-redesign-design-zh.md`

The active visual role system is:

- `docs/design-system.md`

This file is the stable entrypoint for agents. If this file and the detailed
spec appear to conflict, pause and ask the user before changing product
behavior.

## Product Definition

Tough Trial is not a heavy project-management system. It is a light assistant
for seeing tasks, arranging them, executing today, and reflecting from evidence.

The product has four main surfaces:

- `今天`: today's execution manager. It should stay quiet and focused.
- `任务`: a multi-view task cognition layer for goals, task breakdowns,
  execution history, future possibilities, and endpoints.
- `计划`: a chat-first AI planning workspace for a day or longer period.
- `回想`: an evidence-based reflection space grounded in real execution records.

## Current Direction

`今天` should prioritize live execution and a flow timeline. It must not show
long-term category labels, Dreaming recommendations, forced conflict resolution,
or planning analysis during execution.

`任务` should support multiple views. The current structure view direction is a
wide, horizontally scrollable and pinch-zoomable map. Nodes show progress through
a completion signal: leaf nodes are `1` when done and `0` otherwise; parent nodes
average their children. The UI reads that signal and renders green fill.

`计划` should default to low-friction chat. Structured inputs are optional for
complex plans. Planning AI may generate structured drafts, but durable writes
need user confirmation.

`回想` should remain minimal and evidence-first. Analysis belongs here, not in
today's execution flow.

## Explicit Guardrails

- Execution labels such as "long-term goal" or "maintenance task" do not appear
  in `今天`.
- Urgent tasks can be inserted without forced replacement or capacity
  calculation.
- Tasks may be parallel. The system records what happened; it does not decide
  how far a task must be executed.
- AI suggestions and Dreaming outputs are drafts until the user confirms them.
- Do not add heavy project-management mechanics unless the user explicitly asks.

## Implementation Surfaces

- `Sources/ToughTrialV2Core/`: V2 domain models and prototype state.
- `Sources/ToughTrialV2Core/V2Engine.swift`: durable task and execution commands.
- `Sources/ToughTrialV2Core/V2JSONSnapshotStore.swift`: local JSON persistence.
- `Sources/ToughTrialV2App/`: V2 SwiftUI screens.
- `Checks/ToughTrialV2Checks/`: executable checks for V2 behavior.
- `docs/superpowers/specs/`: historical and detailed design specs.
- `docs/superpowers/plans/`: implementation plans.

## Current Verification Ladder

Run these from the repository root:

```bash
swift run ToughTrialV2Checks
swift build
xcodebuild -project ToughTrial.xcodeproj -scheme ToughTrial -destination 'generic/platform=iOS Simulator' build
```

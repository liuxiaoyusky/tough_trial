# Tough Trial Agent Guide

## Source Of Truth

- Edit this file only. `AGENTS.md` must be a symlink to `CLAUDE.md`.
- If `AGENTS.md` becomes a normal file, merge any useful content here and restore
  the symlink with `ln -s CLAUDE.md AGENTS.md`.
- Product design decisions live in `docs/superpowers/specs/`.

## Current Product Direction

Tough Trial is a native SwiftUI iOS prototype for task execution, task cognition,
planning, and reflection. The current redesign source of truth is:

- `docs/superpowers/specs/2026-05-28-tough-trial-interaction-redesign-design.md`

Follow that spec before changing UI or behavior. In short:

- `今天` is only for today's execution. Keep it quiet and focused.
- `任务` is a multi-view layer for goals, tasks, execution history, future
  possibilities, and endpoints.
- `计划` is a chat-first AI planning workspace for a day or longer period.
- `回想` is evidence-based reflection using real execution records.
- Dreaming suggests empty-time arrangements and long-term goal breakdowns, but
  never writes durable data without user confirmation.

## UX Guardrails

- The app is a light assistant, not a heavy project-management system.
- Do not show task category labels during execution on `今天`.
- Do not put Dreaming recommendations into `今天`.
- Do not force conflict resolution, replacement, capacity calculation, or
  single-task execution rules for urgent inserts.
- Put time-ratio and category analysis in `回想`, not in the execution flow.
- Planning AI should default to low-friction chat input and return a structured
  draft. Structured forms are optional for complex plans.
- User intent has priority over architectural neatness. Reduce interaction
  burden whenever there is a tradeoff.

## Repository Shape

- `Package.swift`: Swift package manifest.
- `Sources/FocusTimelineCore/`: platform-neutral domain and demo state.
- `Sources/ToughTrialApp/`: SwiftUI app views.
- `Checks/FocusTimelineCoreChecks/main.swift`: executable core checks.
- `project.yml`: XcodeGen iOS project definition.
- `docs/superpowers/specs/`: approved design specs.
- `docs/superpowers/plans/`: implementation plans.

## Commands

Use these from the repository root:

```bash
swift run FocusTimelineCoreChecks
swift build
/opt/homebrew/bin/xcodegen generate
```

For simulator builds, use the generated Xcode project after full Xcode is
selected. Prior work used `swift run FocusTimelineCoreChecks`, `swift build`,
and then `xcodebuild`/simulator or device verification when available.

## Editing Rules

- Read the relevant spec before making product or UI changes.
- Keep edits surgical. Do not refactor unrelated files.
- Use the existing SwiftUI style unless the spec requires a redesign.
- Keep domain rules in `FocusTimelineCore` where possible; keep SwiftUI views
  focused on presentation and interaction.
- Verify with `swift run FocusTimelineCoreChecks` for core behavior changes and
  `swift build` for general Swift package changes.
- If iOS UI behavior changes, continue to Xcode/simulator/device verification
  when the local environment supports it.

# Tough Trial Agent Guide

## Source Of Truth

- Edit this file only. `AGENTS.md` must be a symlink to `CLAUDE.md`.
- If `AGENTS.md` becomes a normal file, merge any useful content here and restore
  the symlink with `ln -s CLAUDE.md AGENTS.md`.
- Product design decisions start at `docs/spec.md`, which links to detailed
  specs under `docs/superpowers/specs/`.

## Current Product Direction

Tough Trial is a native SwiftUI iOS prototype for task execution, task cognition,
general AI assistance, and reflection. The current product source-of-truth
entrypoint is:

- `docs/spec.md`
- `docs/superpowers/specs/2026-05-30-tough-trial-interaction-redesign-design-zh.md`
- `docs/superpowers/specs/2026-08-17-tough-trial-general-assistant-design-zh.md`

Follow that spec before changing UI or behavior. In short:

- `今天` is only for today's execution. Keep it quiet and focused.
- `任务` is a multi-view layer for goals, tasks, execution history, future
  possibilities, and endpoints.
- `助手` is a general, multi-session chat workspace for conversation, web
  search, personal-data retrieval, and planning artifacts.
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
- The assistant defaults to low-friction chat and automatically selects
  read-only tools. Planning remains a structured artifact, and durable writes
  always require explicit user confirmation.
- Web scope starts with search, read, cite, and user-controlled WKWebView
  browsing. Do not add autonomous web clicking or form submission.
- User intent has priority over architectural neatness. Reduce interaction
  burden whenever there is a tradeoff.

## Repository Shape

- `Package.swift`: Swift package manifest.
- `Sources/ToughTrialV2Core/`: active platform-neutral domain and planning logic.
- `Sources/ToughTrialV2App/`: active SwiftUI app views and App Info.plist.
- `Sources/FocusTimelineCore/`: compatibility domain and demo state.
- `Checks/FocusTimelineCoreChecks/main.swift`: executable core checks.
- `project.yml`: XcodeGen iOS project definition.
- `docs/spec.md`: current product source-of-truth entrypoint.
- `docs/superpowers/specs/`: detailed and historical design specs.
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
- Keep active domain rules in `ToughTrialV2Core` where possible; keep SwiftUI
  views focused on presentation and interaction.
- Verify active behavior with `swift run ToughTrialV2Checks`, compatibility
  behavior with `swift run FocusTimelineCoreChecks`, and general package changes
  with `swift build`.
- If iOS UI behavior changes, continue to Xcode/simulator/device verification
  when the local environment supports it.

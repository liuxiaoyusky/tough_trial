# Tough Trial Agent Guide

## Source Of Truth

- Edit this file only. `AGENTS.md` must be a symlink to `CLAUDE.md`.
- If `AGENTS.md` becomes a normal file, merge any useful content here and restore
  the symlink with `ln -s CLAUDE.md AGENTS.md`.
- Product design decisions start at `docs/spec.md`, which links to detailed
  specs under `docs/superpowers/specs/`.

## Current Product Direction

Tough Trial is a native SwiftUI iOS prototype with a native macOS client,
for task execution, task cognition, general AI assistance, and reflection. The current product source-of-truth
entrypoint is:

- `docs/spec.md`
- `docs/superpowers/specs/2026-05-30-tough-trial-interaction-redesign-design-zh.md`
- `docs/superpowers/specs/2026-08-17-tough-trial-general-assistant-design-zh.md`
- `docs/superpowers/specs/2026-09-07-ai-schedule-and-sync-design-zh.md`
- `docs/superpowers/specs/2026-09-09-unified-capture-and-ledger-design-zh.md`
- `docs/superpowers/specs/2026-09-16-macos-sync-ontology-design-zh.md`

Follow that spec before changing UI or behavior. In short:

- `今天` is only for today's execution. Keep it quiet and focused.
- `任务` is a multi-view layer for goals, tasks, execution history, future
  possibilities, and endpoints.
- `助手` is a general, multi-session chat workspace for conversation, web
  search, personal-data retrieval, and planning artifacts.
- `回想` is evidence-based reflection using real execution records.
- `随手记` uses typed Capture contracts for mixed input, ledger and notes. Ledger
  categories always require human confirmation; new capture/media data is local
  until its separate versioned sync protocol is implemented.
- Dreaming suggests empty-time arrangements and long-term goal breakdowns, but
  never writes durable data without user confirmation.

## UX Guardrails

- Prefer continuous, document-style input over separate fields and target switches. Infer defaults from entry context, keep optional content optional, and use the app theme rather than unstyled system forms. Task input uses the first paragraph as its title and the following paragraphs as its body.

- The app is a light assistant, not a heavy project-management system.
- Do not show task category labels during execution on `今天`.
- Do not put Dreaming recommendations into `今天`.
- Do not force conflict resolution, replacement, capacity calculation, or
  single-task execution rules for urgent inserts.
- Put time-ratio and category analysis in `回想`, not in the execution flow.
- The assistant defaults to low-friction chat. Explicitly requested schedule
  edits apply atomically with visible changes and undo; an optional strict
  setting requires confirmation before applying. Discussion and Dreaming do
  not authorize writes. Follow the 2026-09-07 schedule/sync spec.
- Web scope starts with search, read, cite, and user-controlled WKWebView
  browsing. Do not add autonomous web clicking or form submission.
- User intent has priority over architectural neatness. Reduce interaction
  burden whenever there is a tradeoff.

## Repository Shape

- `Package.swift`: Swift package manifest.
- `Sources/ToughTrialV2Core/`: active platform-neutral domain and planning logic.
- `Sources/ToughTrialV2App/`: active SwiftUI app views and App Info.plist.
- `Sources/ToughTrialMacApp/`: native Mac workspace: today, four task views, capture, finance/statistics, assistant, recall and settings. GitHub sync currently covers tasks/schedule only.
- `Sources/ToughTrialAppShared/`: native task draft, save and undo application service.
- `ontology/` and `Tools/OntologyIndexer/`: curated task capability/code/test map and read-only compiler-parse indexer.
- `Sources/FocusTimelineCore/`: compatibility domain and demo state.
- `Checks/FocusTimelineCoreChecks/main.swift`: executable core checks.
- `project.yml`: XcodeGen iOS project definition.
- `docs/spec.md`: current product source-of-truth entrypoint.
- `docs/superpowers/specs/`: detailed and historical design specs.
- `docs/superpowers/plans/`: implementation plans.

For task editing investigations, start with `Tools/OntologyIndexer/README.md` and
`python3 Tools/OntologyIndexer/ontology.py query '标题修改'`. Build the index if it is
missing or stale. It covers a bounded subset and does not prove runtime causes;
source code and actual test/trace evidence remain authoritative. Do not copy
personal task data into the development ontology.

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

## UI Interaction Acceptance

- For each changed UI, inventory every visible interactive control, including checkbox-like icons. Exercise the actual tap/input, then assert visible feedback and the resulting domain state; existence checks and screenshots alone do not verify interaction.
- Decorative elements must not resemble inactive buttons or checkboxes. Explain disabled states and use accessible labels with adequate tap targets.
- Cover primary, cancel, undo and disabled/empty paths for the changed surface. Report which interactions were actually tested and any remaining gaps.

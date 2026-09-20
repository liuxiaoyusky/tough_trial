# Assistant Context and Memory Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement assigned tasks, with root integration and verification.

**Goal:** Give the assistant durable inspectable context and fix the two real session regressions.
**Architecture:** Typed workspace/memory remain canonical. A derived local archive provides JSONL history, bounded retrieval and compaction. Shared host context and intent guards cover every model/write route.
**Tech Stack:** Swift 6, Foundation, SwiftUI, XCTest.
**Spec:** `docs/superpowers/specs/2026-09-10-assistant-context-memory-design.md`

## Global Constraints

- Preserve unrelated dirty files and existing device data. Workers use isolated worktrees; root alone runs Xcode/device commands.
- No private Codex content is imported. No credentials or private reasoning in app logs. Compact never authorizes business writes.
- Existing schema decoding stays compatible. Raw session messages remain available after compact.

### Task 1: Archive and compaction Core (isolated worker)

Files: new `Sources/ToughTrialV2Core/V2AssistantArchive.swift`, new `Tests/ToughTrialCaptureTests/V2AssistantArchiveTests.swift` only.

- [x] Define Codable archive event, session index and compaction models with source message IDs; implement file storage and optional in-memory mode.
- [x] First write tests for duplicate import, message update, restart, bounded retrieval, compact source retention, safe paths, delete and corrupt-tail handling; run the failing tests.
- [x] Implement sync(workspace), list/search/read, compact(session), loadCompaction and memory Markdown projection; run focused tests.
- [x] Deliver exact public API to root; do not alter workspace/domain schemas.

### Task 2: Host write intent Core (isolated worker)

Files: new `Sources/ToughTrialV2Core/V2AssistantWriteIntent.swift`, new `Tests/ToughTrialCaptureTests/V2AssistantWriteIntentTests.swift` only.

- [x] Tests cover hello after failed schedule, negation/discussion, explicit colloquial writes, split reference, and adjacent successful clarification replies.
- [x] Implement pure decision function accepting current text and bounded preceding messages. Distinguish direct request, clarification answer, and no authority; do not trust model-proposed action text.
- [x] Run tests; root integrates guard into all write paths and keeps failed turns in host authorization context.

### Task 3: Shared typed context and host tools (root)

Files: AgentClient, ScheduleClient, AssistantStore/TurnLoop/Schedule/ToolExecution/Dependencies, AppStoreDynamicTools, new assistant context Core/App adapters and tests.

- [x] Reproduction tests assert referenced task reaches first router request and schedule request; fabricated writes on hello never call backend.
- [x] Add context metadata, fresh selected task resolution, memory selection, local compaction, request manifest Trace and current date/timezone.
- [x] Add bounded memory/session/trace/compact tools and shared archive sync; validate tools against active module catalog.
- [x] Add schedule prompt rules for executable breakdown and today plan creation; preserve existing source and schema validation.

### Task 4: User access, validation and delivery (root)

- [x] Add compact/context/history sheet to assistant session UI; reuse existing memory management.
- [x] Run Core suites and executable checks; App regression on isolated simulator; validate actual archived device sessions on local copies.
- [x] Build normal signed app, install then immediately launch; update QA with exact successful checks and limitations.

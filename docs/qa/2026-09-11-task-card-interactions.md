# Task-card interaction acceptance — 2026-09-11

## Defect

The leading circle was an SF Symbol image, not a Button. Existing UI tests exercised editing/confirmation/undo but omitted a control-shaped decorative element. A new UI test failed before the change because no task checkbox button existed (`/private/tmp/tough-checkbox-red.log`).

## Fix

- Saved tasks use a 44-point checkbox Button with explicit action label and current completion value. A click completes/restores the actual task and its associated plan item using the same domain operations as Today, without an AI call.
- Unsaved/cancelled/undone cards use plain ordinal text; they do not expose fake checkboxes.
- Completion has a durable host receipt. Restoring the most recent unchanged completion restores exact prior values, including across reload, so the original creation can still be undone. Subsequent edits are preserved rather than silently reverted.
- Cards read the current task status; returning from Today refreshes their presentation. Unavailable/archived tasks do not expose a completion action.
- `CLAUDE.md` now requires an inventory of interactive controls and actual tap/input + resulting-state assertions for changed UI. `AGENTS.md` remains its symlink.

## Interaction inventory

| Control | Actual UI exercise | Evidence |
| --- | --- | --- |
| Saved checkbox | Tap complete, inspect completed task in Today, return, tap restore, undo original creation | Passed on simulator and physical iPhone 13 Pro; device test 21.877 s |
| Unsaved checkbox | No checkbox action exists before confirmation | UI assertion passed |
| Edit title / Done | Type a new title, save draft, confirm, find changed title in Today | Passed, including note-input rerun (31.466 s) |
| Edit Cancel | Enter text, cancel, verify text not saved | Passed |
| Schedule toggle | Click the actual right-hand switch, verify 1 → 0 → 1 and date field hide/show | Passed after correcting the test hit point |
| Date field | Tap to open system calendar, capture view, dismiss, cancel editor, assert editor closed | Passed |
| Confirm / Cancel | Confirm creates records; cancel hides confirmation and prevents write | Passed |
| Note input | Type a marker, close editor, assert persisted card text | Passed (`/private/tmp/tough-checkbox-controls-final.log`) |
| Saved adjustment | Open, verify empty Send disabled, Cancel, reopen, type, Send, verify changed note and successful final response | Passed (42.123 s combined editor/date/adjustment flow) |
| Undo | Click after save and after completion/restoration, verify undone state and no checkbox | Passed |

The first switch test hit the middle of the full-row accessibility frame rather than its switch (recorded frame width 370). The adjustment test initially queried a TextView although SwiftUI exposed the input differently. These harness issues were corrected; no existence-only result was accepted as proof of input or action success.

The system calendar intercepts outside touches; its top edge overlaps the navigation bar. The test now taps an observed point below the calendar and asserts the editor actually closes after Cancel. The deterministic model fixture now targets the quoted task ID and returns a final answer after its tool result. Final combined editor/date/adjustment acceptance passed (`/private/tmp/tough-checkbox-adjustment-acceptance.log`). The inventory aggregates successful targeted runs; it does not claim every row passed in one suite invocation. AI responses in these UI tests are synthetic; taps, editors, persistence, and domain changes are real.

Core regression: 217 tests, five opt-in skips, zero failures; ToughTrialV2Checks passed. Includes task + plan completion, round-trip after reload, and preserving later task edits (`/private/tmp/tough-checkbox-core-all.log`).

Physical-device checkbox UI test passed (`/private/tmp/tough-checkbox-device-ui.log`). Version 1.0 (10) was installed and launched normally at 18:48:49. A later build containing corrections only to the synthetic UI-test fixture succeeded; reinstalling it timed out because the device transport was unavailable. The installed version already contains all production checkbox changes. Auxiliary-control acceptance is complete.

Scope: this acceptance covers task cards and their editors. It is not an assertion that every existing app screen has been re-tested. The new project rule applies to future changed interfaces as well.

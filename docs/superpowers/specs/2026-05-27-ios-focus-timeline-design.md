# iOS Focus Timeline V1 Design Spec

Date: 2026-05-27
Status: Approved for implementation

## Summary

V1 is a native iOS app for focus, task progress, day planning, and daily recall. The product is centered on a Chinese-first timeline experience:

- `今天` is the home screen and primary daily timeline.
- `任务` is a searchable list for task tracking and focus entry.
- `计划` is a future-date timeline editor with AI planning.
- `回想` is a writing surface that references the day's completed work.
- `Zen mode` is the minimal focus session screen.

The visual direction combines a calm iOS-native daily interface with a more immersive focus mode. Theme color can shift by time of day or app state, such as morning green for daily planning and a darker copper tone for Zen mode.

## Approved Mockup References

The approved brainstorming mockups are stored under `.superpowers/brainstorm/51209-1779869812/content/`:

- `layout-01-today.html` - approved Today timeline and focus candidate layout.
- `layout-02-tasks.html` - approved Tasks list and focus candidate layout.
- `layout-03-plan-approved.html` - approved Plan timeline editor layout.
- `layout-04-zen.html` - approved Zen mode layout.

These HTML files are concept references only. The production app should implement the same structure and interaction language in SwiftUI.

## Core Screens

### Today

`今天` is the default landing screen. It shows the day's timeline and a top focus candidate card.

Default behavior:

- The top card starts as the default `Next Focus`.
- Tapping a past or future task in the timeline changes the top card to `专注候选`.
- Tapping `开始` enters Zen mode.
- Completing a task outside the Today list appends a completion event to Today so Recall can reference it.
- Stand reminders can appear in the timeline when relevant.

### Tasks

`任务` is a searchable, vertically scrolling list.

Task behavior:

- Tapping a task opens the same focus candidate state used by Today.
- Tapping `开始` enters Zen mode.
- Tasks can be one-time, cumulative, frequency-based, or decomposed long-term goals.
- The list remains useful even for tasks with no reminders or scheduled time.

### Plan

`计划` uses the same timeline language as Today, but for future dates and editable planning.

Plan behavior:

- The main view is a timeline draft for a selected date.
- Events without fixed time show `?` or a blurred time marker.
- The bottom primary action is `AI 规划`.
- AI planning uses priority, estimated duration, memory, and fixed calendar items to reorder the target day's timeline.
- Tasks without duration receive an AI-proposed duration during planning.
- Tasks that do not fit remain below the timeline.
- Users can drag tasks into the timeline, remove tasks from the timeline, reorder events, and place tasks side-by-side when parallel work is acceptable.

AI suggestions and night Dreaming do not occupy the Plan main view. They live in a top-right message inbox and open as pop-out windows.

### Zen Mode

Zen mode keeps the interface minimal:

- Countdown timer.
- Current task title.
- Short stand reminder context when needed.
- Pause and end actions.

If Zen mode is started without a linked task, the task text area shows a short motivational sentence instead of an empty state.

### Recall

`回想` is a daily writing screen connected to the day's timeline.

Recall behavior:

- Shows completed tasks, focus blocks, progress logs, and stand events from the day.
- Users can insert references to those records while writing.
- References support jumping back to the source task, progress record, or focus block.
- V1 prioritizes user-authored recall with references, not automatic full-day summary generation.

## Task Model

V1 supports four task patterns:

- One-time task: complete once.
- Cumulative task: progress accumulates toward a total, such as `50 / 1000 pages`.
- Frequency goal: repeated target within a period, such as `5 runs this week`.
- Decomposed long-term task: a larger goal represented by smaller actionable tasks.

Core task fields:

- Title.
- Notes.
- Task type.
- Priority tier.
- Status.
- Estimated duration.
- Optional scheduled date and time.
- Optional reminder configuration.
- Progress definition.
- Links to timeline events, focus sessions, and external Apple objects.

## Reminder Priority Rules

V1 uses four fixed priority tiers:

- `critical`: most important tasks. Use an AlarmKit alarm before the scheduled start time. If AlarmKit is unavailable or permission is denied, fall back to local notification with sound.
- `medium`: use sound, notification, and vibration.
- `notifyOnly`: use notification only.
- `none`: do not notify. Task exists only in the list.

AlarmKit is only for critical task start reminders in V1. It is not used for every task, every focus session, or every stand reminder.

If a critical task alarm fires and the user does not start the task, the task becomes `未开始`. The app does not automatically reschedule it. The user can drag it manually or tap `AI 规划` to produce a new plan.

## Focus And Stand Behavior

Default focus cycle:

- 25 minutes focus.
- 2 minutes stand.

The one-hour stand reminder is based on app-known activity, not precise body motion detection in V1. The app uses events such as finishing a stand break, ending a focus session, or manually marking activity as the reference point.

Focus and stand reminders use local notification behavior unless a task's priority tier explicitly calls for AlarmKit at task start.

## AI Features

AI is a confirmation-first assistant. It never writes durable user data without confirmation.

V1 AI features:

- Voice or text input can create a structured task draft.
- AI planning can produce a timeline draft for a target date.
- AI can propose memory entries, such as commute time or work hours, but the user must confirm before saving.
- AI suggestions appear in the message inbox and open as pop-out windows.

Deferred to V1.1:

- Real night Dreaming analysis and push delivery.
- Dreaming should analyze recent completions, newly added tasks, preferences, and long-stalled tasks, then propose smaller task breakdowns through the message inbox.

## Memory

Memory stores user-confirmed planning context, such as:

- Usual wake time.
- Usual commute time.
- Common work hours.
- Repeated locations or routines.

V1 does not automatically save memory. AI can propose memory based on evidence, but the user must accept it.

## Apple Integrations

V1 is one-way write with stored external IDs.

- Apple Reminders: task reminders.
- Apple Calendar: scheduled timeline blocks, planned focus blocks, and calendar-like events.
- AlarmKit: critical task start alarms only.
- Local notifications: medium and notify-only task reminders, focus completion, and stand reminders.

V1 does not implement full bidirectional sync or conflict resolution with Apple Reminders or Calendar.

Google Calendar is out of V1 scope.

## Data And Export

The app is local-first with SwiftData as the iOS persistence layer. Data shapes should remain platform-neutral so Android and HarmonyOS clients can reuse the domain model later.

Export format:

- Daily Markdown files for readable Obsidian-style records and recall.
- CSV files for structured tasks, progress events, focus blocks, and timeline events.

V1 should support export and import for these formats when practical, with round-trip tests for representative records.

## Technical Direction

V1 implementation target:

- SwiftUI for native iOS UI.
- SwiftData for local persistence.
- UserNotifications for local notifications.
- EventKit for Apple Reminders and Calendar.
- AlarmKit for critical task start alarms where available, with fallback behavior.

Future platform strategy:

- Keep UI native per platform.
- Keep task, timeline, AI, planning, reminder mapping, and export schemas platform-neutral.

## V1 Boundaries

In scope:

- Native iOS app scaffold.
- Today, Tasks, Plan, Recall, and Zen mode.
- Task/progress domain model.
- Reminder priority mapping.
- Apple one-way write integration boundaries.
- Local-first persistence.
- AI drafts with user confirmation.
- Markdown and CSV export/import foundations.

Out of scope for V1:

- Google Calendar.
- Full Apple bidirectional sync.
- Automatic memory writes.
- Real night Dreaming analysis and push delivery.
- Android and HarmonyOS clients.

## Acceptance Criteria

- The app opens to Today.
- Users can select a timeline task as a focus candidate and enter Zen mode.
- Users can search tasks and start focus from a task candidate state.
- Users can plan a future day with timeline draft semantics and keep unplaced tasks below the timeline.
- Users can map priority tiers to correct reminder behavior.
- AI-generated tasks, plans, memories, and breakdowns require confirmation before saving.
- Daily records can be exported in Markdown and core structured data can be exported in CSV.

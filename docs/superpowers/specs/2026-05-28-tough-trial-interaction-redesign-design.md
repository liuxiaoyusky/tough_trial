# Tough Trial Interaction Redesign Design Spec

Date: 2026-05-28
Status: Approved for agent handoff

## Purpose

This redesign keeps the four main surfaces: `今天`, `任务`, `计划`, and `回想`.
The goal is not to add more control, but to make each surface responsible for a
clear user mindset:

- `今天`: execute today's tasks with minimal distraction.
- `任务`: understand tasks, goals, past execution, future possibilities, and endpoints.
- `计划`: create lightweight plans for a day or longer period, with AI support.
- `回想`: reflect on real execution records and use time analysis as reference.

The product should behave as a light assistant. It helps the user see, arrange,
execute, and reflect, but it should not over-design the user's life or force
extra decisions during execution.

## Core Principles

1. **Execution should stay quiet.** `今天` should not show task classification,
   long-term goal explanations, Dreaming suggestions, or planning analysis.
2. **User action remains primary.** The four main pages are controlled by the
   user's active intent: record, arrange, execute, reflect.
3. **AI suggests, user judges.** AI and Dreaming can propose plans or task
   breakdowns, but nothing becomes durable until the user accepts it.
4. **Input should stay low-friction.** Planning AI defaults to chat-style input.
   Structured input exists as an optional switch when the plan needs more detail.
5. **Facts and intentions stay separate.** Plans describe intent; execution
   records describe what really happened; recall interprets those records later.

## Task Types

The system should support three task categories without forcing those labels into
the execution UI:

- **Goal tasks**: tasks that serve a long-term goal, project, or growth direction.
- **Commitment tasks**: tasks tied to external promises, deadlines, events, or appointments.
- **Maintenance or isolated tasks**: urgent, administrative, or one-off tasks that
  do not directly serve a long-term goal but still need to be handled.

These categories are mainly useful for planning, review, and time-ratio analysis.
They should not add friction when the user is executing today's work.

## Page Responsibilities

### 今天: Today's Task Executor

`今天` only serves today. It should help the user focus on the current task,
today's task list, and the real time spent.

Should include:

- Current task or focus item.
- Today's task list.
- Start, pause, end, and time recording.
- A lightweight way to insert urgent tasks.
- A simple execution timeline of what has happened today.

Should not include:

- Long-term goal explanations.
- Task category labels such as goal, commitment, or maintenance.
- Dreaming recommendations.
- Empty-time arrangement suggestions.
- Forced conflict handling, replacement suggestions, or capacity judgment.

Urgent insertion should be allowed. For the current design stage, do not require
replacement, conflict resolution, or empty-slot calculation. Tasks can be
parallel. How deeply a task is executed is the user's decision; the system only
helps record what happened.

#### First Information Architecture

`今天` should be built around two major surfaces:

1. **Active task area**
2. **Today timeline**

There should be no separate top status dashboard. Do not show daily category
ratios, long-term explanations, or AI recommendations at the top.

##### Active Task Area

The active task area only contains tasks that already have an active or paused
time-recording session. Unstarted tasks do not appear here.

This area can contain multiple active or paused task items, but only one item
should be expanded with detailed controls at a time. Other active items remain
compact.

Each active item should show:

- Task title.
- Status icon for running or paused.
- Current session duration.
- Today's total duration for this task.
- A combined play/pause control.
- An end-session control.
- A `Zen` entry when appropriate.

Status and start/pause behavior should be visually merged. The user should not
have to parse separate state text and separate controls when an icon can do the
job.

Ending a session only ends the current time segment. It does not necessarily
mean the task is complete. Completion is a separate lightweight action on the
timeline item.

For running tasks, use a two-time display inspired by aTimeLogger-style
tracking:

- First time: current session duration.
- Second time: today's total duration for that task.

##### Zen Behavior

Zen is a special full-screen time-recording session, not a separate task model.

- Starting Zen from an active or timeline task links the Zen session to that task.
- Starting Zen from an empty state may first search for and link a task.
- The user may also start Zen without linking any task.
- Manual Zen end or timer completion writes the time segment back to the linked
  task when one exists.
- Ordinary play/pause and Zen both contribute to the same task duration model.
  Zen only changes the interaction surface.

##### Today Timeline

The today task list and execution record should be merged into one modern,
flowing timeline. This timeline can be vertical, horizontal, or another more
interesting visual design, but it must emphasize:

- Current time.
- Current plan.
- Running tasks.
- Paused tasks.
- Completed tasks.
- Future tasks.
- Urgent inserted tasks.

The timeline is responsible for selection, starting, Zen entry, and completion
state. The active task area is responsible for ongoing time recording.

Clicking a timeline task should not automatically move it into the active task
area. Instead, it should expand lightweight timeline actions such as:

- Start.
- Zen.
- Complete.
- View or edit.

Only `Start` or `Zen` creates an active or paused session item.

Completed tasks should remain visible in the timeline with simple visual changes
such as strikethrough, lighter color, smaller scale, reduced opacity, or other
basic status treatment. Running tasks can use color, size, dynamic highlight, or
position to become more prominent. Future tasks should remain readable without
competing with the current task.

The timeline may visually emphasize the current time and nearby planned work,
but it should not judge what the user must do next.

##### Urgent Insert

The urgent insert control should be minimal, similar in spirit to adding a new
item in iPhone Reminders:

- A clean blue button or floating control.
- White plus sign.
- Minimal required fields.

New urgent tasks go directly into today's timeline. Do not require category,
goal, conflict, replacement, or empty-slot decisions at insertion time.

##### Today Interaction Rule

Use this rule as the design anchor:

> The timeline is for choosing, starting, and completing. The active task area is
> for recording and switching. Zen is for immersive timing. Completion state stays
> on the timeline.

### 任务: Multi-View Task Cognition Layer

`任务` is not just a task list. It helps the user see what tasks exist, how they
serve long-term direction, what has happened in the past, what may happen next,
and where the endpoint or next milestone is.

Should include multiple views:

- **Goal tree view**: growth area -> long-term goal -> project or stage -> subtask.
- **Time-scale view**: day, week, month, and year perspectives for past execution
  and future possible plans.
- **Fishbone or decomposition view**: a target goal shown with branches such as
  skills, resources, habits, projects, and executable tasks.
- **Execution history view**: completed actions and real time spent.
- **Path view**: current state, completed nodes, active nodes, stalled nodes, and
  possible next milestones.

Maintenance or isolated tasks should also exist here. They do not need to serve a
long-term goal, but they still need a place in the system.

Dreaming's long-term goal breakdown suggestions should primarily enter through
the task surface or a task-related suggestion inbox.

### 计划: Chat-First AI Planning Workspace

`计划` arranges a day or a longer time range. It can cover today, a future day,
the next few days, a week, a month, or a periodic target such as "run 10 km next
week".

The default AI interaction should be chat-style and low-friction. A user should
be able to type a simple request such as:

- "这周想跑 10 公里"
- "明天安排得轻一点"
- "这几天想推进论文"

The AI should use fixed context when available:

- Current task library.
- Existing plans and commitments.
- Memory about life rhythm, work hours, exercise habits, preferences, and routines.
- Past execution patterns.
- The user's current prompt.

The AI output should be a structured draft first, not a long explanation. It
should show:

- Scheduled day or time range.
- Task or newly proposed subtask.
- Periodic target breakdown.
- Items that were not arranged.
- Optional collapsed rationale: why this arrangement was suggested.

The user can accept, edit parts, continue adjusting with a prompt, or switch to
structured input. Structured input is an optional enhancement for complex
planning, not the default entry cost.

### 回想: Evidence-Based Reflection

`回想` is the reflection surface. It is mainly about today, but it may refer to
past events.

Should include:

- Today's real execution records and time spent.
- References to tasks, focus sessions, inserted urgent tasks, and relevant past events.
- User-authored reflection.
- Time-ratio analysis based on task metadata, such as goal tasks, commitment
  tasks, and maintenance or isolated tasks.
- Plan-vs-actual reference: what was intended and what actually happened.

Should not include:

- Current execution controls.
- Forced task classification during execution.
- Automatic conclusions that the user cannot edit or reject.
- Automatic task or plan mutation.

The analysis is a reference for the user, not a judgment engine.

## Dreaming: Model-Proactive Suggestion Layer

Dreaming is not a fifth main page. It is a model-proactive suggestion layer that
can surface through an inbox, drawer, or contextual entry point.

Dreaming has two approved suggestion types:

1. **Empty-time arrangement suggestions**
   - Input: a plan for a day or period, empty time, existing executable subtasks,
     memory, and current commitments.
   - Output: a suggestion to place an already defined task into an empty time.
   - User actions: accept, ignore, modify time, or defer.

2. **Long-term goal breakdown suggestions**
   - Input: a long-term goal, progress history, stalled goals, and existing subtasks.
   - Output: smaller executable tasks that can keep the goal moving.
   - User actions: accept as tasks, edit and accept, ignore, or defer.

Dreaming can recommend. It must not automatically write to tasks or plans.

## Core Data Relationships

- **Task**: the base material. It may belong to a long-term goal or exist as an
  isolated maintenance task.
- **Plan item**: intended work for a day or period. It may reference a task or
  represent a temporary commitment.
- **Execution record**: what actually happened, including time spent. It may come
  from a plan item or a same-day urgent insertion.
- **Recall entry**: user-authored reflection that references execution records.
- **Dreaming suggestion**: a draft recommendation. It becomes a task or plan item
  only after user confirmation.

Keep these objects separate. Plans should not overwrite execution facts, and
execution records should not be treated as proof that the original plan was
correct.

## First Implementation Bias

When this design is implemented, prefer a focused prototype over a complete
product-management system:

- Preserve the four-tab structure unless there is a strong reason to change it.
- Redesign page content and state flow before adding persistence or real AI calls.
- Keep `今天` minimal and execution-oriented.
- Let `计划` hold most AI planning complexity.
- Let `任务` gain multiple views gradually, starting with goal structure and
  time-scale perspectives.
- Let `回想` be the first place where category analysis appears.

The design is considered successful when a user can feel that:

- Today is for doing.
- Tasks are for understanding the task system.
- Plan is for arranging a day or period with light AI help.
- Recall is for learning from what actually happened.

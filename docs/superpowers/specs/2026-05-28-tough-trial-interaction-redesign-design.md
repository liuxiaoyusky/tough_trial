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

The working mockup reference is:

- `.superpowers/brainstorm/99266-1779956168/content/tasks-main-view-v2.html`

The approved direction is one main task map with multiple switchable lenses, not
several unrelated pages.

#### First Information Architecture

`任务` should be built around three first-version lenses:

1. **结构**
2. **时间**
3. **鱼骨**

The earlier standalone `历史` and `路径` lenses are removed for now. Completed
history should appear as completed nodes inside the structure map or as events
on the fishbone completion axis. Path-like meaning can still emerge from the
tree, but it should not be a separate top-level lens.

##### Structure Lens

The structure lens is the default. It should feel like a task map, not a task
list.

The main screen should show one large card occupying the center of the page. The
user can horizontally swipe between cards. Each card represents a meaningful
task context, such as a growth area, long-term goal, project, or maintenance
group.

Inside each card:

- Content is a tree-like structure, not a vertical list.
- The card canvas can pan vertically and horizontally.
- Nodes represent goals, projects, stages, subtasks, and completed tasks.
- Completed tasks can stay in the tree as light, crossed-out, or otherwise
  visually softened completion nodes.
- Individual tasks should be placed somewhere inside the tree, close to the goal
  or project they serve.
- Maintenance or isolated tasks may have their own card or a clear maintenance
  branch, but they should not be forced to attach to a long-term goal.

Avoid these elements in the structure lens:

- A top-level total task count.
- Percent progress for a long-term goal.
- Dense list rows as the main content.
- A separate history list.

Do not show percent progress because these are infinite-improvement paths, not
finite completion bars. If progress needs to be communicated, use softer signals
such as recent activity, completed nodes, next visible task, or stalled nodes.

##### Time Lens

The time lens should be closer to TickTick-style time management. It should not
classify tasks by their long-term goal.

Supported scales:

- Year.
- Month.
- Week.
- Three-day.
- Day.

This lens is for seeing and temporarily arranging tasks by time. It can include
manual task addition. It should show tasks, reminders, temporary items, and
scheduled work by date or time range without making the user think about the
goal hierarchy.

This lens is different from `计划`: it is a time-based task view inside the task
system. `计划` is the AI-supported planning workspace for generating or revising
plans.

##### Fishbone Lens

Keep the fishbone idea, but make it more artistic and simpler than a complex
diagram. The first version should be a single completion axis.

The fishbone lens should show completed tasks on one time axis:

- One axis only.
- Completed task nodes appear on the axis.
- Different goals use different colors.
- Checkboxes let the user show or hide goals from the axis.
- Maintenance or isolated completions may appear with their own color or neutral
  treatment.

This lens answers: "What has actually accumulated over time?" It should avoid
becoming a full analytics dashboard.

##### Add Button

The add button should be a blue pill or circular control with a white plus sign,
positioned at the bottom-right of the task page.

The plus control is a lightweight capture control, not the deep planning entry by
default:

- Tap: quick add in the current page context.
- Press and hold: voice capture until release.
- Press, hold, and drag upward: locked continuous voice recording, similar in
  spirit to Telegram's voice gesture.

Voice recognition should produce an editable draft before durable data is
written.

Default behavior depends on context:

- In `今天`, quick add creates a today task. If the input includes a time, it can
  become a today-dated plan point; otherwise it stays as a today task.
- In `任务`, quick add creates a task or node in the current structure card or
  current context.
- In `计划`, quick add creates a task or plan item under the current planning
  object.

Deep AI planning should be entered from an expanded task item through an
`AI 计划` button. This keeps fast capture separate from deliberate planning.

Maintenance or isolated tasks should also exist here. They do not need to serve a
long-term goal, but they still need a place in the system.

Dreaming's long-term goal breakdown suggestions should primarily enter through
the task surface or a task-related suggestion inbox.

### 计划: Chat-First AI Planning Workspace

`计划` arranges a day or a longer time range. It can cover today, a future day,
the next few days, a week, a month, or a periodic target such as "run 10 km next
week".

The working mockup reference is:

- `.superpowers/brainstorm/99266-1779956168/content/plan-chat-agent-v2.html`

The approved direction is that `计划` is a standalone chat agent workspace, not a
calendar-like board and not another task view. Because it opens as its own
workspace, it should not keep the bottom tab bar visible inside the page.

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

#### First Information Architecture

`计划` should behave like a Codex-mobile-style planning agent:

- The main page is a conversation workspace.
- The page has a clear title and back/close control, but no bottom tab bar.
- The first screen can show a short agent prompt and a few lightweight example
  prompts.
- The composer stays at the bottom of the agent workspace.
- User input is natural language by default.
- The agent returns an understanding card and structured plan drafts inside the
  conversation.
- Plan drafts are artifacts, not just chat text. They can be accepted, saved as
  drafts, edited, or adjusted through follow-up prompts.
- Saved drafts can remain pending until the user confirms them.

There should be no blue plus button on the `计划` agent home. The plus gesture is
for lightweight capture in pages like `今天` and `任务`; planning is driven by the
agent composer and by `AI 计划` entry points from expanded task items.

#### AI Planning From Expanded Task Items

Deep planning starts from an expanded task item through an `AI 计划` button. It
does not start from the global plus button by default.

When `AI 计划` starts, the model should make several judgments in parallel:

- Whether the item needs decomposition.
- Whether the item needs time planning.
- Whether the item is long-term or short-term.
- Whether the item fits an existing goal.
- Whether the item should stay in isolated or maintenance tasks.
- Whether the item itself is a large goal rather than an executable task.
- Whether the item is periodic.
- Whether the item has an external commitment, deadline, or specific time.
- Whether the item is suitable for today.
- Whether memory is needed for planning.
- Whether there are conflicts worth mentioning without forcing resolution.

The interface should not expose this as a form. The first AI planning screen
should show a lightweight understanding card, for example:

```text
I understand this as:
Type: periodic goal
Belongs to: body / running
Needs: decomposition + time planning
Draft: 3km + 3km + 4km this week

[Generate plan draft] [Make ordinary task] [Change goal]
```

After the user proceeds, AI produces a structured draft:

- Proposed subtasks.
- Proposed dates or time ranges.
- Items not arranged.
- Optional collapsed rationale.
- Save draft.
- Accept.
- Continue adjusting with prompt.

AI planning must support at least two partial modes:

- **Decompose only**: break a large goal into executable tasks without arranging
  time yet.
- **Schedule only**: place an already clear task into a day or period without
  decomposing it.

The model may ask follow-up questions only when essential information is missing.
When asking, it should ask the smallest useful question instead of opening a
large structured form.

### 回想: Evidence-Based Reflection

`回想` is the reflection surface. It is mainly about today, but it may refer to
past events.

The working mockup reference is:

- `.superpowers/brainstorm/99266-1779956168/content/recall-three-layouts-v5.html`

The approved direction is the second layout from that mockup: a diary-like page
with a date rail and a small reference window.

#### First Information Architecture

`回想` should prioritize writing, not analytics.

The first version should include:

- A date rail for switching between recent days.
- A fullscreen or immersive-mode button at the top-left.
- A main reflection editor for the selected date.
- A compact reference window for inserting evidence into the text.
- Actions for `引用`, `整理草稿`, and `保存`.

The main editor should contain only one placeholder sentence, such as:

```text
今天最值得记录的是……
```

Evidence should not be presented as a large dashboard. It should be available
through the reference window or writing tools. The default evidence categories
are:

- **事件**: tasks, focus sessions, Zen sessions, and temporary insertions that
  actually happened.
- **偏差**: event-like differences between plan and reality, such as an unexecuted
  planned task or an unplanned completed task.
- **过去**: previous events the user wants to refer to.

Do not include time-ratio statistics as default writing references. Those can
exist elsewhere in the task system or as optional analysis, but `回想` should not
start with percentages or summary cards.

AI can help only when the user requests it:

- `整理草稿` may generate an editable draft from the selected date and inserted
  evidence.
- AI output must not be auto-saved.
- AI must not automatically modify tasks, plans, or memory.

Should not include:

- Current execution controls.
- Forced task classification during execution.
- Automatic conclusions that the user cannot edit or reject.
- Automatic task or plan mutation.
- Top summary cards, detail cards, or visible time-ratio dashboards by default.

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

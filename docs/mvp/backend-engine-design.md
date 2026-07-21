# 后端 MVP 引擎核心设计

状态：已确认，第一阶段实施中
日期：2026-07-01
输入：

- `docs/mvp/backend-engine-requirements.md`
- 设计体验部阶段输出
- 开发部阶段输出

## 1. 设计总原则

Tough Trial 后端 MVP 先做一个本地核心引擎，而不是继续扩写前端样例状态。

核心结论：

> Task 是材料，Plan 是意图，Execution 是事实，Recall 是解释。

四个页面共享同一套本地核心数据，但每个页面只读取自己的投影数据：

- `今天` 读 `TodayExecutionSnapshot`
- `任务` 读 `TaskCognitionSnapshot`
- `计划` 读 `PlanningWorkspaceSnapshot`
- `回想` 读 `RecallEvidenceSnapshot`

页面不直接读全量对象后自行解释，避免把计划分析、长期目标解释、Dreaming 推荐污染到 `今天`。

## 2. 语义边界

### Task

`Task` 是要做的事、想推进的方向、阶段、子任务、维护事项或孤立事项。

它描述任务材料和结构，不描述真实发生过什么。

### Plan

`Plan` 是打算在某天或某段时间做什么。

它是意图，不是事实。计划项可以引用任务，也可以代表临时承诺。计划失败不等于任务失败，只说明意图和现实不同。

### Execution

`Execution` 是真实发生的时间段。

它是事实来源。可以有关联任务，也可以没有。可以来自普通计时、Zen 或临时插入。多个 execution segment 可以并行。

回想、统计和偏差分析必须优先相信 execution，而不是 plan。

### Recall

`Recall` 是用户事后的解释和反思。

它可以引用任务、计划、执行段，但不能反向篡改事实。AI 可以帮整理草稿，但用户保存前不成为正式回想。

## 3. 页面投影

### TodayExecutionSnapshot

`今天` 可以使用：

- 今天日期下的 `PlanItem`
- 用户明确加入今天的 `Task`
- 今天发生的 `ExecutionSegment`
- 正在进行 / 暂停的未结束 segment
- 今天紧急插入的任务
- Zen 产生的执行段
- 任务标题、基础完成状态、今日累计用时

`今天` 不能展示为主内容：

- 长期目标分类标签
- 目标 / 承诺 / 维护类型说明
- Dreaming 推荐
- 空闲时间安排建议
- 时间比例分析
- 计划偏差分析
- 父目标完成百分比
- 自动冲突解决、容量判断、替换建议

### TaskCognitionSnapshot

`任务` 可以使用：

- 任务上下文
- 任务树投影
- 完成节点
- 维护 / 孤立任务分支
- 完成信号
- 历史执行摘要
- 未来计划引用

它不直接承担今天执行计时，也不把计划草稿当作已生效任务。

### PlanningWorkspaceSnapshot

`计划` 可以使用：

- 用户聊天输入
- AI 计划草稿
- 待确认计划项
- 待确认任务拆解
- 已保存但未接受的草稿
- 已接受计划项

AI 和 Dreaming 只能 propose，用户才 commit。

### RecallEvidenceSnapshot

`回想` 可以使用：

- 某天真实执行段
- 计划项
- 任务引用
- 计划了没做
- 没计划但做了
- 未归属时间段
- 用户保存的回想文本
- AI 整理草稿

回想分析只在回想使用，不回写今天执行流。

## 4. 核心状态

新增真实核心状态，不直接扩写 `V2PrototypeState`：

```swift
struct V2AppSnapshot: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var taskContexts: [V2TaskContext]
    var tasks: [V2Task]
    var planDrafts: [V2PlanDraft]
    var planItems: [V2PlanItem]
    var executionSegments: [V2ExecutionSegment]
    var recallEntries: [V2RecallEntry]
    var dreamingSuggestions: [V2DreamingSuggestion]
}
```

兼容说明：现有 UI prototype 已占用 `V2PlanDraft` 名称，因此持久化层暂用
`V2PlanDraftRecord`。等计划页面迁移到 Engine 后再统一命名，不为命名提前重写
现有 SwiftUI。

现有 `V2PrototypeState` 暂时保留为 UI prototype/sample 的兼容层。新引擎完成后，再逐步让 SwiftUI 从 engine projection 读取数据。

## 5. 模型设计

### V2TaskContext

用于表达长期目标、项目或维护组。

字段建议：

- `id`
- `title`
- `note`
- `colorName`
- `createdAt`
- `updatedAt`
- `archivedAt?`

### V2Task

持久化层采用扁平存储，不存嵌套 children。

字段建议：

- `id`
- `contextID?`
- `parentID?`
- `title`
- `note?`
- `kind: goal / commitment / maintenance / nil`
- `status: notStarted / active / paused / done / archived`
- `createdAt`
- `updatedAt`
- `completedAt?`
- `archivedAt?`

读取任务树时，按 `parentID` 组装 `V2TaskTreeNode`。

### V2ExecutionSegment

执行段是真实事实源。

字段建议：

- `id`
- `taskID?`
- `titleSnapshot`
- `startAt`
- `endAt?`
- `source: normal / zen / urgentInsert`
- `createdFromPlanItemID?`
- `note?`

暂停定义为结束当前 open segment，并把任务状态变为 `paused`。恢复时创建新的 segment。这样每个 segment 都是连续真实时间段。

### V2PlanDraft

字段建议：

- `id`
- `status: draft / accepted / discarded`
- `mode: scheduleOnly / breakdownOnly / mixed`
- `userPrompt`
- `summary`
- `proposedTaskChanges`
- `proposedPlanItems`
- `createdAt`
- `updatedAt`
- `acceptedAt?`

未接受前不能写正式任务或计划项。

### V2PlanItem

字段建议：

- `id`
- `date`
- `startAt?`
- `endAt?`
- `taskID?`
- `title`
- `sourceDraftID?`
- `status: planned / canceled / convertedToExecution`

计划项允许只有日期，没有具体时间。

### V2RecallEntry

字段建议：

- `id`
- `date`
- `text`
- `referencedTaskIDs`
- `referencedSegmentIDs`
- `referencedPlanItemIDs`
- `createdAt`
- `updatedAt`

### V2DreamingSuggestion

字段建议：

- `id`
- `kind: scheduleSuggestion / breakdownSuggestion`
- `status: pending / accepted / discarded`
- `summary`
- `proposedTaskChanges`
- `proposedPlanItems`
- `createdAt`
- `acceptedAt?`

Dreaming suggestion 只能作为草案存在。

## 6. Engine 分层

建议核心分三层：

1. `V2JSONSnapshotStore`
   - 只负责 load / save JSON。
   - 不承担业务规则。
2. `V2Engine`
   - 持有 `V2AppSnapshot`。
   - 执行业务 command。
   - 每个 command 后可触发保存。
3. Query helpers
   - 从 snapshot 生成页面投影。
   - 不修改状态。

## 7. Command API

### Task Commands

- `createTask(title:parentID:contextID:kind:)`
- `updateTask(id:title:note:parentID:contextID:kind:)`
- `completeTask(id:at:)`
- `restoreTask(id:)`
- `archiveTask(id:at:)`
- `addTaskToToday(taskID:date:)`
- `quickInsertTodayTask(title:date:)`

### Execution Commands

- `startExecution(taskID:title:source:at:)`
- `pauseExecution(segmentID:at:)`
- `endExecution(segmentID:at:)`
- `resumeTaskExecution(taskID:at:)`

规则：

- 结束 segment 不等于完成 task。
- 多个 open segment 可以并行存在。
- 未关联任务的 segment 必须保留。

### Plan Commands

- `savePlanDraft(_:)`
- `acceptPlanDraft(id:at:)`
- `discardPlanDraft(id:at:)`

规则：

- `scheduleOnly` 只生成 `PlanItem`，不改任务树。
- `breakdownOnly` 只生成任务结构，不安排时间。
- `mixed` 可以同时生成任务结构和计划项。

### Recall Commands

- `saveRecallEntry(date:text:references:)`
- `updateRecallEntry(id:text:references:)`
- `acceptRecallDraft(...)`

### Dreaming Commands

- `saveDreamingSuggestion(_:)`
- `acceptDreamingSuggestion(id:at:)`
- `discardDreamingSuggestion(id:at:)`

规则：

- AI / Dreaming 不能直接调用 durable command。
- 只有 accepted draft / suggestion 才能生成 durable task / plan / recall。

## 8. Query API

- `todaySnapshot(date:) -> V2TodayExecutionSnapshot`
- `taskTree(contextID:) -> [V2TaskTreeNode]`
- `completionSignal(taskID:) -> Double`
- `taskCognitionSnapshot(contextID:) -> V2TaskCognitionSnapshot`
- `planningWorkspaceSnapshot(range:) -> V2PlanningWorkspaceSnapshot`
- `recallEvidence(date:) -> V2RecallEvidenceSnapshot`
- `executionSegments(on:) -> [V2ExecutionSegment]`
- `spentDuration(taskID:) -> TimeInterval`
- `planDeviation(date:) -> V2PlanDeviation`

## 9. JSON 持久化

第一版使用一个 JSON 文件：

- 路径：`Application Support/ToughTrial/v2-snapshot.json`
- 根对象：`V2AppSnapshot`
- `schemaVersion = 1`

保存策略：

- 每次 action 后原子写入。
- 先写 temp 文件，再 replace。

读取策略：

- 读取失败时保留错误，不静默清空。
- 开发期可以 fallback sample。
- 正式引擎不能假装数据没坏。

未结束执行段恢复：

- `endAt == nil` 的 segment 就是未结束执行段。
- App 重启后直接恢复为 active tray 数据。
- 如果 `taskID` 存在，任务状态应恢复为 `active`。
- 如果 `taskID` 不存在，保留为未归属执行记录，供回想引用。
- 不自动补 `endAt`，因为系统不替用户决定事实结束时间。

## 10. 冻结产品规则

- 父节点完成信号采用递归叶子平均。
- 快速新增任务允许无类型、无目标归属。
- 维护 / 孤立任务是一等任务，不强行挂长期目标。
- 计划项允许只有日期。
- 周期任务 MVP 只展开成多个 `PlanItem`，暂不做 recurrence engine。
- 未关联任务的 Zen / 执行段必须保留。
- 任务完成和计时结束是两件事。
- 计划不证明事实，执行记录才证明事实。
- 回想分析只能引用事实和计划差异，不能污染今天执行流。
- AI / Dreaming / 整理草稿未确认前不能写任务、计划、回想或 memory。

## 11. Checks 分组

### TaskCoreChecks

- 三层任务树稳定读取。
- 创建 / 移动 / 归档。
- 叶子完成信号。
- 递归叶子平均。
- 维护 / 孤立任务不强制挂目标。

### ExecutionChecks

- start 生成 open segment。
- pause / end 写入 `endAt`。
- 两个 open segment 并行存在。
- Zen 有 / 无 taskID 都能保存。
- spent duration 从 segments 计算。

### PlanChecks

- draft 保存不改 task / plan。
- accept 后才生成 PlanItem / Task。
- scheduleOnly 不改任务树。
- breakdownOnly 不生成计划时间。
- 周期输入拆成多个 PlanItem。

### RecallChecks

- 按日期读取 execution evidence。
- 保存并读取 RecallEntry。
- 引用 segment / task / planItem。
- 计划未执行、执行未计划能被列为偏差。
- 回想分析不影响 today 执行流。

### PersistenceChecks

- JSON round trip。
- schemaVersion 存在。
- active segment 重启后仍 open。
- draft 重启后仍 draft。
- corrupt JSON 不覆盖原数据。

## 12. 实施顺序

1. 新增 Codable 核心模型和 `V2AppSnapshot`，保留现有 prototype 模型不动。
2. 新增 `V2Engine`，先实现任务树和 completion signal。
3. 实现 execution segment：start / pause / end / parallel / Zen。
4. 实现 JSON store 和 round-trip checks。
5. 实现 plan draft accept：先支持 scheduleOnly / breakdownOnly。
6. 实现 recall evidence 和 recall entry 保存。
7. 最后再让 SwiftUI 从 engine projection 读数据，逐步替换 `V2PrototypeState.sample()`。

## 13. 主要风险

- 不要把 UI timeline 和真实执行事实混在一起。`ExecutionSegment` 必须成为事实源。
- 不要继续在嵌套 `children` 上做持久化，后续移动 / 归档会很痛。
- 不要让计划草稿接受逻辑过早复杂化。MVP 只接受结构化 proposed changes。
- 不要在重启恢复时自动结束 open segment。系统不替用户补事实。
- 不要让页面直接读全量对象后自行解释。页面应读专属 snapshot。

## 14. 确认与实施状态

- [x] 新增 `V2AppSnapshot + V2Engine + V2JSONSnapshotStore`，保留旧 prototype 状态。
- [x] 任务持久化采用扁平存储，查询时组装树。
- [x] 暂停 = 结束当前 segment；恢复 = 新建 segment。
- [x] 第一轮先做 task + execution + JSON。
- [ ] SwiftUI 切换到 Engine 页面投影。
- [ ] plan + recall durable commands 与查询。

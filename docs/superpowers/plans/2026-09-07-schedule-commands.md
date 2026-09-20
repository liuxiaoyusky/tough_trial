# 原子日程命令与整次撤销实现计划

## 目标

在 `ToughTrialV2Core` 内增加可编码的日程操作提案、一次性原子应用、持久化回执以及按受影响实体安全撤销。操作只允许使用明确的白名单字段，不扩展到 App、AgentClient 或 Markdown 同步。

## 设计边界

- `V2ScheduleProposal` 携带摘要和有序 `V2ScheduleOperation` 列表。
- `V2Engine.applyScheduleProposal(_:requestID:at:calendar:expectedSnapshot:)` 先在候选快照中验证受影响对象的基线并完整执行，最后只调用一次 `commit`。
- `requestID` 持久化并幂等；首次应用生成的 receipt 与结果快照同次保存。
- receipt 保存每个受影响任务/计划项的真实 ID 和完整 before/after；级联归档、父任务 Context 变化也包含后代。
- undo 只比较 receipt 记录的实体，发现实体被后续修改或新增关联会拒绝覆盖；无关的新修改保留。对新建任务/排期若已有执行证据或外部引用，会拒绝产生悬空引用。
- 完成和归档不隐式结束真实执行会话；执行 segment 只在明确被操作时进入 receipt。
- `V2AppSnapshot` 新增 receipt 数组必须通过 `decodeIfPresent` 兼容缺少新字段的旧 JSON，暂不提升 schema 版本。

## 实施顺序

1. 在 `V2EngineModels.swift` 增加扁平 Codable 操作、变更和 receipt 类型，并为旧快照增加兼容解码。
2. 在 `V2ScheduleCommands.swift` 实现白名单字段校验、候选快照应用、级联变更收集、request ID 幂等和 undo。
3. 只在必要处调整 `V2Engine.swift` 的提交入口或错误类型；保持现有生命周期不变。
4. 增加 `ScheduleCommandChecks.swift`，覆盖原子回滚、重复请求和重启、撤销冲突与无关变化、后代归档恢复、旧 JSON、延期保留计划 ID 与执行证据。

## 验证

```bash
swift run ToughTrialV2Checks
swift build
```

开发过程中先让新增检查因缺少接口而失败，再实现至通过；最后检查 diff 只包含本任务允许的 Core、checks 和本计划文件。

## 已知限制

- 当前快照没有跨进程锁或变更日志；本功能只保证单个 `V2JSONSnapshotStore` 的单次原子写入。
- 计划项原有模型没有单独的更新/取消 API，命令引擎需要在 Core 内集中执行其校验。
- 本任务不会接入真实模型、聊天 UI、Markdown、GitHub 或远端运行器。

# Tough Trial Markdown 日程协议 v1

这份协议定义一个由用户直接编辑、也能被 App 和远端运行器安全处理的日程执行文件。它只拥有 `tough-trial:begin owned` 与 `tough-trial:end owned` 两个标记之间的内容；标记外的正文由文档持有者保留，合并时不能静默丢弃。

当前 Core API 是：

```swift
let document = try V2ScheduleMarkdown.decode(markdown)
let markdown = try V2ScheduleMarkdown.encode(document)
let merged = try V2ScheduleMerge.merge(base: base, local: local, remote: remote)
```

## 文件骨架

```markdown
# 这里可以写给人的说明

<!-- tough-trial:begin owned -->
<!-- tough-trial:document id="schedule-main" timezone="Asia/Shanghai" version="1" -->

## 分类
- 个人 <!-- tough-trial:context color="blue" id="context-personal" -->
<!-- tough-trial:context-meta archived=null color="blue" created="2026-09-07T00:00:00.000Z" id="context-personal" updated="2026-09-07T00:00:00.000Z" -->

## 任务
- [ ] 写周报 <!-- tough-trial:task id="task-report" -->
  保留给人的备注，可以继续写多行。
<!-- tough-trial:task-meta archived=null completed=null context="context-personal" created="2026-09-07T00:00:00.000Z" id="task-report" kind="commitment" parent=null sourceKey=null sourceKind=null sourceLocation=null sourceUpdated=null status="notStarted" updated="2026-09-07T00:00:00.000Z" -->

## 排期
- 2026-09-08 09:00–10:00 | 写周报 <!-- tough-trial:plan id="plan-report" -->
<!-- tough-trial:plan-meta id="plan-report" sourceDraft=null status="planned" task="task-report" -->

## 执行记录
- 2026-09-07T01:00:00.000Z → 2026-09-07T01:30:00.000Z | 写周报 <!-- tough-trial:execution id="segment-report" -->
<!-- tough-trial:execution-meta endReason="stopped" id="segment-report" plan="plan-report" session="session-report" source="normal" task="task-report" -->
<!-- tough-trial:end owned -->

## 这里仍然属于用户正文
这段内容不会被协议编码器删除。
```

标题、任务勾选、备注和排期日期/时间是用户可直接编辑的部分。HTML 注释只携带机器需要的稳定身份和不能安全地从标题推断出的细节，不放整份 JSON。任务 `[x]` 表示完成；其他状态使用任务 metadata 的 `status` 保存，例如 `active`、`paused` 和 `archived`。如果用户改了勾选，勾选对“是否完成”具有优先级，编码器下次会把 metadata 规范化为一致状态。

日期和时间使用文档 `timezone` 解释。排期可以写日期、日期加开始时间，或日期加开始和结束时间。执行记录的可见时间使用 ISO 8601；正在进行的记录以 `—` 表示没有结束时间。

## 身份和安全边界

- `document.id` 必须稳定；同一个文件的三方合并要求三份文档 ID 相同。
- 每一类对象的 `id` 必须唯一。任务的 `parent` 与 `context`、排期的 `task`、执行记录的 `task` 和 `plan` 必须引用同一文档中存在的对象。
- 缺少 ID 的新任务、分类、排期或执行行会按可见内容和行序生成确定性 ID；下一次往返会保留这个 ID。已有行如果带 ID，metadata 缺失或 ID 不一致会被当作坏文件拒绝。
- 缺少一行不会表示删除，避免截断文件造成批量删除。任务应使用 `status="archived"` 表达归档，排期应使用 `status="canceled"` 表达取消。
- 重复 ID、未知协议版本、无效日期/时间、断开的引用、循环父子关系和缺失 owned 结束标记都会拒绝导入；拒绝时调用方必须保留原来的本地数据。
- 凭据、Authorization header、模型响应中的密钥和原始音频不属于 Markdown 协议。

## 文字转义

新导出的 document header 声明 `textEncoding="entities-v1"`。该声明只作用于托管记录的标题、备注、请求原文和结果；ID、其他 metadata 和标记外正文保持原义。文字中的 `&`、`<`、`>` 使用 HTML 实体；标题里的换行、首尾空白和文字中的回车使用数字实体，备注继续保持多行 Markdown。读取时只解码一遍，原本写着 `&lt;` 的文字仍保留为 `&lt;`，不会递归解码。

没有声明的旧文件按原义读取；未知的 `textEncoding` 拒绝导入，避免猜测编码而改坏内容。App 与云端运行器应使用同一协议实现。

## 三方合并

`V2ScheduleMerge.merge(base:local:remote:)` 使用共同基线逐字段比较：

- 只有一侧相对基线修改时，自动采用该侧。
- 两侧修改不同对象或同一对象的不同字段时，自动合并。
- 同一字段两侧都修改且值不同，生成 `V2ScheduleConflict`，保留 `base`、`local`、`remote` 三个 JSON primitive 候选；返回的文档暂采用本地候选，调用方不得在 `conflicts` 非空时直接写回。
- 执行记录以稳定 ID 为事实身份。不同 ID 的新记录都追加；已有记录的同字段并发修改仍形成冲突。
- 一侧缺少基线对象时按“未表达删除”处理，保留另一侧/基线对象。显式归档或取消由业务状态表达。
- 标记外正文的并发冲突会在临时结果中同时保留本地和远端正文，并附带 typed conflict，等待后续本地 AI 或用户处理。

该 codec 和 merge 只负责纯 Core 数据，不直接访问文件系统、网络、GitHub 或 AI。App 的文件绑定、GitHub 乐观并发控制、远端 Action 和本地 AI 冲突处理属于后续接线。

## 跨午夜排期

次日结束时间显式添加 `+1d`，例如 `2026-09-07 22:00–00:00+1d | 准备材料`。解码不会把结束时间倒退到当天零点；不存在的夏令时墙上时间拒绝导入。

## 云端请求

可选的 `## 云端请求` 区域保存明确交给云端 AI 的指令。旧文件没有该区域时等价于空请求列表。例：

```markdown
## 云端请求
- [ ] 把准备演示拆成具体步骤 <!-- tough-trial:request id="request-1" -->
  总共最多 2 小时，先不要安排日期。
<!-- tough-trial:request-meta created="2026-09-07T00:00:00.000Z" id="request-1" processed=null status="pending" -->
```

处理后勾选改为 `[x]`，status 改为 `processed` 或 `needsClarification`，processed 写入时间；结果跟在 metadata 后，以 Markdown 引用 `> 结果正文` 显示，多行逐行引用。pending 不允许附带旧结果。勾选与 metadata 状态不一致时拒绝导入。

新请求没有 ID 时补稳定 ID，写回时固定。没有 created 的手写新请求以运行器当前时间解释相对日期；App 创建请求应写真实 created。处理过的请求不能通过改原文或取消勾选重新执行，补充要求使用新 ID。

请求原文、状态、结果作为一个整体合并。如果手机改请求的同时云端完成处理，形成冲突并保留双方版本，不能把旧请求结果套到新原文上。

## 执行事实保护

已存在执行段的身份、关联、标题快照、开始时间与来源不可覆盖；已结束执行段的结束时间与结束原因也不可覆盖。即使只有一方修改，也形成冲突并保留基线事实。基线未结束的执行段允许追加结束事实；备注仍可修改或三方合并。某一端缺少执行行不能绕过上述检查。

## 时间精度

执行记录和 metadata 日期输出到纳秒位，解码避免默认 ISO8601DateFormatter 截断到毫秒。旧本机 JSON 使用 Unix Double 秒，转换到 Date 参考纪元时可能有一个浮点精度单位的差异；合并只容忍这一表示精度范围，保留基线执行事实，避免重启后把自己的文件误判为篡改。超过该范围的执行时间改写仍产生冲突。

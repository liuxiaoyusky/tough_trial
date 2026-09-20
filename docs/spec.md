# Tough Trial Product Spec

Status: active source-of-truth entrypoint
Last updated: 2026-09-20

## Mac 与 Ontology 实施（2026-09-16 已确认）

按 [Mac / 同步 / Ontology 设计](superpowers/specs/2026-09-16-macos-sync-ontology-design-zh.md) 分阶段实施。原生 Mac 共用 Swift 领域核心，本地优先，GitHub 为首个同步渠道；WebDAV/NAS 与托管 E2EE 后续接入。先交付 Mac 任务编辑与第一条可查询业务代码映射，再验收双端同步及其他数据域。

任务页遵循用户最新修订：并排「列表、结构、时间、鱼骨」；列表平铺，结构直接呈现树状关系。此修订优先于下方历史结构入口描述。

Current assistant home redesign: `docs/superpowers/specs/2026-09-11-assistant-home-design.md` supersedes the standalone assistant presentation.

## Canonical Design Source

The canonical detailed product specs are:

- `docs/superpowers/specs/2026-05-30-tough-trial-interaction-redesign-design-zh.md`
- `docs/superpowers/specs/2026-08-17-tough-trial-general-assistant-design-zh.md`
- `docs/superpowers/specs/2026-09-06-realtime-speech-design-zh.md`
- `docs/superpowers/specs/2026-09-07-ai-schedule-and-sync-design-zh.md`
- `docs/superpowers/specs/2026-09-09-unified-capture-and-ledger-design-zh.md`
- `docs/superpowers/specs/2026-09-10-assistant-context-memory-design.md`
- `docs/superpowers/specs/2026-09-14-local-backup-and-sync-design-zh.md`
- `docs/superpowers/specs/2026-09-20-business-card-contacts-design-zh.md`
- `docs/superpowers/specs/2026-09-20-customizable-tabbar-and-more-plugins-design-zh.md`

The 2026-08-17 assistant spec supersedes the older plan-page information
architecture. The planning rules remain active as one assistant capability. The 2026-09-07
schedule/sync spec supersedes mandatory per-write confirmation for explicitly
requested schedule edits: apply with visible changes and undo by default, with
an optional strict confirmation setting.

The active visual role system is:

- `docs/design-system.md`

This file is the stable entrypoint for agents. If this file and the detailed
spec appear to conflict, pause and ask the user before changing product
behavior.

## Product Definition

Tough Trial is not a heavy project-management system. It is a light assistant
for seeing tasks, getting contextual help, executing today, and reflecting from
evidence.

The product has five core surfaces. Additional modules may expose their own
independent surfaces without being merged into these five:

- `今天`: today's execution manager. It should stay quiet and focused.
- `任务`: a multi-view task cognition layer for goals, task breakdowns,
  execution history, future possibilities, and endpoints.
- `助手`: a general, multi-session AI workspace for conversation, web search,
  personal-data retrieval, and planning artifacts.
- `回想`: an evidence-based reflection space grounded in real execution records.
- `随手记`: mixed text, dictation and media capture, with a local ledger and classified notes.

The iPhone bottom navigation is a user-selected shortcut layer rather than a
complete module inventory. It shows 2–5 tabs total; one tab is always `更多插件`,
and the remaining 1–4 tabs are ordered user choices from currently available
modules. Removing a module from the tab bar does not disable it or delete its
data. `我的资料` is the first new independent module using this navigation model.

## 今日执行分区（2026-09-20 用户评审确认）

以 [今日执行队列设计](superpowers/specs/2026-09-20-today-execution-queue.md) 为准：主卡片、执行队列、今日规划；暂停/完成后队首补位，完成任务留在今日规划，显示本段、今日和跨天累计用时。此修订替代旧版今日暂停/结束双入口。

## Current Direction

`今天` should prioritize live execution and a flow timeline. It must not show
long-term category labels, Dreaming recommendations, forced conflict resolution,
or planning analysis during execution.

`任务` should support multiple views. The structure entry shows a compact list
of top-level tasks; standalone tasks open details, while tasks with children open
a wide, horizontally scrollable and pinch-zoomable map with a return-to-list action. Nodes show progress through
a completion signal: leaf nodes are `1` when done and `0` otherwise; parent nodes
average their children. The UI reads that signal and renders green fill.

`助手` should default to unrestricted natural-language chat and automatically
select read-only tools when useful. It supports multiple isolated sessions,
source-linked inline web views, and user/debug trace layers. Planning is one
assistant tool: it may generate structured drafts. Explicitly requested schedule edits apply
with visible changes and undo; strict confirmation is optional.

`回想` should remain minimal, writing-first, and evidence-grounded. Its active
interaction direction is one daily reflection with two equal input modes:
`文字` and `手写`. Switching modes stays on the same page; handwriting is not a
detached modal. Analysis belongs here, not in today's execution flow.

## Explicit Guardrails

- Execution labels such as "long-term goal" or "maintenance task" do not appear
  in `今天`.
- Urgent tasks can be inserted without forced replacement or capacity
  calculation.
- Tasks may be parallel. The system records what happened; it does not decide
  how far a task must be executed.
- Unrequested AI suggestions and Dreaming outputs remain drafts until confirmed.
- User-requested schedule edits apply atomically with visible changes and undo,
  or await confirmation when strict mode is enabled. Read-only tools are automatic.
- External side effects require the user to authorize the destination and scope.
- The first web scope is search, read, cite, and user-controlled browsing. The
  agent does not click, scroll, fill, or submit web pages.
- Do not add heavy project-management mechanics unless the user explicitly asks.

## Implementation Surfaces

- `Sources/ToughTrialV2Core/`: V2 domain models and prototype state.
- `Sources/ToughTrialV2Core/V2Engine.swift`: durable task and execution commands.
- `Sources/ToughTrialV2Core/V2PlanEngine.swift`: durable plan drafts, atomic acceptance, and planning queries.
- `Sources/ToughTrialV2Core/V2RecallEngine.swift`: daily reflection persistence, execution evidence, and conservative plan-deviation queries.
- `Sources/ToughTrialV2Core/V2JSONSnapshotStore.swift`: local JSON persistence.
- `Sources/ToughTrialV2App/`: V2 SwiftUI screens.
- `Checks/ToughTrialV2Checks/`: executable checks for V2 behavior.
- `docs/superpowers/specs/`: historical and detailed design specs.
- `docs/superpowers/plans/`: implementation plans.

## Current Verification Ladder

Run these from the repository root:

```bash
swift run ToughTrialV2Checks
swift build
xcodebuild -project ToughTrial.xcodeproj -scheme ToughTrial -destination 'generic/platform=iOS Simulator' build
```

## 统一随手记与理账（首个本地闭环已实现）

- [设计与数据契约](superpowers/specs/2026-09-09-unified-capture-and-ledger-design-zh.md)
- [实施与验收计划](superpowers/plans/2026-09-09-unified-capture-implementation.md)

新增随手记入口，UI、数据、AI 分层。账单分类始终人工确认；新内容首版本地保存，暂不扩展 schedule.md。

## 快速模型、文件导入与快捷小组件

见 [2026-09-10 设计](superpowers/specs/2026-09-10-fast-model-import-widgets.md) 与 [实现计划](superpowers/plans/2026-09-10-fast-model-import-widgets.md)。外部文件先本机识别和预览，再明确触发整理；快捷入口复用原领域数据。

## 名片扫描与联系人

见 [名片扫描、联系人建立与整理](superpowers/specs/2026-09-20-business-card-contacts-design-zh.md)。入口优先放在随手记；扫描/导入后先生成联系人草稿，用户确认后才写入独立联系人领域。扫描时不要求先选标签或关系类型；后续联系人库提供人物、公司、最近、搜索、重复合并与可选 AI 整理。联系人库另有「我的名片」，用于保存用户自己的一个或多个身份名片，并可直接把选定字段以文字、名片图片或标准 vCard 二维码分享给别人；内部备注、标签和联系记录默认永不外发。首期本地保存，名片原图复用附件库；现有 GitHub 日程同步不自动包含联系人。

## 财务计划、附件与功能插件

见 [设计](superpowers/specs/2026-09-10-finance-attachments-plugins.md) 和 [实施计划](superpowers/plans/2026-09-10-finance-attachments-plugins.md)。确认支付才生成实付流水；预算读取既有账单；插件停用保留数据。


## 插件运行框架与统一契约（全模块接入）

见 [运行框架与统一数据契约设计](superpowers/specs/2026-09-10-plugin-runtime-and-contracts-design-zh.md) 与 [完整实施验收](qa/2026-09-10-complete-module-runtime.md)。现有原生模块统一接入命令登记、依赖门禁、受限查询和生命周期；页面显隐独立于能力开关。助手从当前可用功能及已定义字段生成工具目录，经严格参数校验、来源校验和同一领域规则写入；业务回执与事实原子保存，支持确认、幂等重试、撤销和聊天卡片恢复。分类及付款始终人工确认。通知/日程同步使用持久 outbox；快照 schema 1 升级前保留原始备份。声明式插件 v2 支持权限差异、受限表单、更新/卸载保留内容，继续兼容 v1。原生模块仍随 App 编译，使用既有强类型 Engine 接口；Native envelope 是宿主调用元数据，不是通用 JSON reducer。可执行第三方插件及新领域跨设备同步是后续独立范围。

## 本地优先与多渠道备份（2026-09-14 用户确认）

数据首先保存在本地。当前新增备份渠道只实施 GitHub，预留 WebDAV 与 NAS；统一可校验、可恢复的备份格式，渠道独立于业务数据和后续加密。多渠道备份不等于多个双向同步源。现有 GitHub 日程同步保持原范围，全量财务、笔记、助手资料与附件备份尚未实现。

参见[备份与同步设计](superpowers/specs/2026-09-14-local-backup-and-sync-design-zh.md)、[Obsidian 调研与收费方向](sync/2026-09-14-obsidian-sync-research.md)和[roadmap](roadmap.md)。托管 E2EE、全领域冲突处理、长期历史与选择性同步作为后续收费方向研究；本地使用、导出和基础恢复保留。加密同步不会自动授权云端 AI 读取正文，不能将密钥交给现有远端日程运行器。新的备份格式在完整实现及验收前，不改变 Capture/media 当前仅本地保存的边界。

## 用户反馈体验优化计划（2026-09-11）

见[优化计划](superpowers/plans/2026-09-11-user-feedback-ux-roadmap.md)与[roadmap](roadmap.md)。优先解决任务详情不能编辑及长内容操作困难，再统一语音新增、长输入、记账入口并复验联网能力。A 批次的共用任务编辑、详情操作及跨视图入口已实现，本地验收见[QA](qa/2026-09-11-user-feedback-ux.md)；真机回访待完成。B 已接入共用任务表单、任务听写和助手同页展开，详见[B 批 QA 与截图](qa/2026-09-11-unified-input-b.md)。9 月 12 日按用户反馈将任务输入调整为首段标题、回车后正文的连续文档，移除字段/听写目标切换，并使用应用主题。见[文档式输入验收](qa/2026-09-12-task-document-input.md)。C 的分类与记账、D 的联网反馈修复均已完成本地实现与回归，详见[C 验收](qa/2026-09-12-classification-ledger.md)与[D 验收](qa/2026-09-12-web-feedback.md)。生产搜索客户端已实测；真实模型、自然听写、真实输入法和本轮手机安装仍待验收。

### 2026-09-14 真机反馈续修（已批准实施）

任务详情点击标题、正文或空正文提示即可进入同一窗口的共用文档编辑器，移除独立“编辑”工具栏按钮。保存、取消、分类及撤销继续使用原领域规则。任务页同一行并排提供“列表、结构、时间、鱼骨”四个视图，默认列表。列表平铺全部任务（包括子任务），行点击直接进入详情，不使用层级缩进或列表内二次导航；结构直接展示树状图，支持展开、缩放和任务详情。树状图总览展示所有根任务，即使没有父子关系也可查看。“全部任务”仅为视觉分组，不写入业务数据，不自动创建父子关系；空任务保持明确空态。列表、结构新增均创建根任务，时间视图保留日期上下文。手机反馈任务由用户测试后自行标记完成。按本节更新实现并做真实交互验收。

### 项目内部组件复用方向（用户确认）

用户明确组件组主要服务本项目及后续参与本项目的开发者。采用 SwiftUI 基础交互组件、业务组件组、页面组合三层组织，保持在现有 App target 内。首先让任务新增、已有任务编辑、助手提案编辑共用任务编辑组件；草稿状态按入口对象隔离，提交仍区分正式创建、更新已有对象和修改待确认提案。长文本与语音等真实重复的交互随反馈修复提取，记账保留金额、币种和人工分类确认等领域行为。

组件提供明确的输入/事件、示例预览和测试；页面负责导航及业务接线，Core 继续负责持久化规则。按入口逐步迁移并验收，不以全库重构作为任务编辑修复的前置条件。本轮不建设独立 SDK、对外 Swift Package、通用动态表单框架或新的插件系统。具体组件边界与迁移验收见上述优化计划。

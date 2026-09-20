# AI 日程与同步实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. 各模块在隔离 worktree 实现，主线程验收后集成。

**Goal:** 完成已批准的路线 1–5，让口述经 AI 成为可撤销日程，并通过 Markdown/GitHub 与云端往返同步。

**Architecture:** Core 负责原子命令、回执、文件协议与合并；App 负责模型调用、展示、设置和安全凭据；远端运行器复用协议与验证。任何实际数据写入必须产生可核查结果。

**Tech Stack:** Swift 6、SwiftUI、Foundation、现有 OpenAI-compatible 客户端、GitHub Contents API 与 Actions。

**Spec:** ../specs/2026-09-07-ai-schedule-and-sync-design-zh.md

## Global Constraints

- 用户明确请求的日程操作默认立即执行；严格确认可选。讨论和 Dreaming 不授权写入。
- 语音点完成后才提交；保护已验收的苹果/FunASR 切换。
- 回执与领域修改原子保存，重复 requestID 不重复执行，撤销不覆盖后续事实。
- Markdown 是人工可编辑协议，稳定 ID，坏文件不损坏正常数据。
- Trace 本机、有界、可关闭/查看/导出；不记录凭据或原始音频。
- 私人日程不放公开代码仓库；云端密钥不进入源码、日志或日程文件。
- 每一项分开记录自动检查、实际设备和真实远端验证。

## 1. 原子执行与撤销

Files: `Sources/ToughTrialV2Core/V2ScheduleCommands.swift`, `V2EngineModels.swift`, `Checks/ToughTrialV2Checks/ScheduleCommandChecks.swift`。

Contract: `applyScheduleProposal(_:requestID:at:calendar:) throws -> V2ScheduleReceipt`; `undoScheduleReceipt(id:at:) throws -> V2ScheduleReceipt`。命令先全部校验，单次 commit。receipt 逐实体 before/after，旧 JSON 缺 receipts 解码为空数组。

- [x] 写混合命令后置失败不改变 snapshot/磁盘、相同 requestID 重启幂等、撤销保留无关修改且拒绝相关后续变化的检查。
- [x] 实现新增/修改/排期/延期/取消排期/完成/恢复/归档、父子别名、日期时区验证。
- [x] 检查级联后代恢复及执行事实保持；运行核心 checks 和 Swift build。
- [x] 集成助手操作回执卡、关联任务高亮、撤销和严格模式确认；两条模式模拟器通过，真模型验收仍在第2项。

## 2. 可执行整理与模型工具

Files: `Sources/ToughTrialV2Core/V2ScheduleClient.swift`, `V2AgentClient.swift`, `V2AgentTurnPolicy.swift`; App `V2AssistantDependencies.swift`, `V2AssistantTurnLoop.swift`, `V2AssistantStore.swift`, `V2AppStore.swift` 与消息卡视图。

- [x] 客户端输出采用步骤白名单；将现在日期、时区、已有任务/计划 ID 和相关对话提供给模型。
- [x] 固定样例覆盖“明天下午三点，不，四点”“不要修改其他安排”、无日期的任务树、同名歧义追问和继续修改已有条目；真实 GLM 样本结果见 `docs/sync/glm-coding-pi.md`。
- [x] 请求绑定持久用户消息 ID；取消/切换会话后迟到结果不能写；真实回执才允许宣告成功。
- [x] 在独立模拟器用真实 GLM 经过 App 聊天路由、日程客户端和实际写入验证连续修改、高亮、磁盘重建后的撤销、严格确认与 Trace；2026-09-07 新增联合测试通过，详见阶段验收记录。
- [ ] 真机使用配置好的真实模型运行合成日程，检查真实状态、回执、撤销和重启恢复。

## 3. 使用 Trace

Files: `Sources/ToughTrialV2Core/V2UsageTrace.swift`, `Checks/ToughTrialV2Checks/UsageTraceChecks.swift`; App `V2UsageTraceView.swift`, `V2AssistantView.swift`, `V2AssistantTurnLoop.swift`, `V2AppStore.swift`。

- [x] 事件仅允许固定事件名/来源和 ID、耗时、字数；无任意错误原文或输入原文。
- [x] 持久保存最近 30 天、最多 2000 条；关闭后不新增；损坏文件不自动覆盖。
- [x] 录音、输入、AI 完成/失败/取消、手动修改、提案/应用/撤销、同步调用处接入；语音按会话关联，助手/文件/同步按操作 ID 关联，手动编辑为独立事件。已核对入口接线与真实导出，见收尾核对。
- [x] 菜单提供开关、最近事件、导出预览、主动分享和清空；测试关闭/保留上限/重启/损坏文件。

## 4. Markdown 文件协议

Files: `Sources/ToughTrialV2Core/V2ScheduleMarkdown.swift`, `V2ScheduleMerge.swift`, `Checks/ToughTrialV2Checks/ScheduleMarkdownChecks.swift`, `docs/sync/markdown-protocol.md`; App 文件绑定/快照导入服务。

- [x] 实现带协议版本/文档 ID、任务/计划/执行记录稳定 ID 的人工可编辑格式；原文非托管内容保持。
- [x] 检查标题、勾选、备注、日期人工修改往返；拒绝重复 ID、截断、错误引用，缺行不隐式删除。
- [x] 三方按实体和字段合并；同字段冲突保留双方；执行事实追加并防止覆盖。
- [x] 实现文件选择器/bookmark 与基线/备份；模拟器通过真实临时文件验证读取、助手新增、写回、重新导入和恢复后的重启，另有系统选择器打开/取消检查。
- [ ] 可选外部文件路径：真机验证所选文件提供者、iCloud 下载（如使用）和 security-scoped bookmark 重启授权。此项不是 GitHub 主线的前置条件。

## 5. GitHub 与云端 AI

Files: `Sources/ToughTrialV2Core/V2GitHubScheduleClient.swift`, `V2ScheduleSync.swift`, 对应 checks；App 同步设置/Keychain/状态；`Sources/ToughTrialScheduleRunner/` 运行器、`docs/sync/` 部署说明与工作流模板。

- [x] 用可注入 HTTP transport 检查读取/SHA 条件写入、401/409/离线/重试；只接受指定仓库/分支/文件。
- [x] 持久化共同基线及待上传状态，恢复后先拉取合并，避免重复；界面展示最新结果。
- [x] 本地模型接收具体冲突候选，返回结构化解决值，校验基线版本和执行证据；无法判断的冲突保留。
- [x] 云端拉取待处理请求，用稳定 requestID 去重并调用模型；并发锁+乐观 SHA，避免自触发循环。
- [x] 在用户指定私人仓库用合成日程跑两个独立客户端与真实 Actions/AI 回写；记录实际远端 URL 和结果。客户端为同一台 Mac 上的独立持久实例，不代表两台手机验收。

当前证据：`docs/sync/glm-coding-pi.md` 与 `docs/qa/2026-09-07-ai-schedule-sync-progress.md`。2026-09-07 再查指定仓库 `tough-trial-sync` 为 PRIVATE，GLM Actions `34087032219` 为 completed/success；本轮完整 `ToughTrialV2Checks` 通过。下方是历史推进记录，早期“尚未部署/待指定仓库”已被这些结果取代。真机验收仍保留未勾选。

## 进度与裁决

- 最新收尾结论见 [路线 1–5 验收核对](../../qa/2026-09-07-route-1-5-audit.md)：本机与当前 GLM 云端重复执行验证通过，实际手机模型/文件授权/同步门禁等待设备。下方保留历史推进记录。

- 2026-09-07：产品规格已写入，旧强制确认规则已在入口文档被替代。
- 2026-09-07：现有核心基础检查通过；新增命令和 Markdown 分别隔离实现。
- 同步目的地已异步询问；继续本地代码，实际私人文件发布等待明确目的地。
- GitHub 当前代码仓库公开，因此不复用它存放私人日程。远端尚未部署。

- 2026-09-07：Trace 核心新检查和 Swift build 通过；UI 接线已完成，正在模拟器检查，详见 `docs/qa/2026-09-07-ai-schedule-sync-progress.md`。

- 2026-09-07：Core边界修复c248aee集成后checks通过；24项App单元与2项日程UI通过，签名真机测试包构建通过。实际iPhone当前unavailable，已询问重连；不影响继续Markdown及网络代码。

- 2026-09-07：主线程接管并完成模型客户端、Markdown/语义合并和 remoteRequests 集成；核心、兼容检查、Swift build、iOS Simulator 构建通过。云端运行器与 Actions 模板已具备本机可审查实现，重复处理和 SHA 竞态由注入传输检查通过，尚未进行远端部署。详见阶段验收记录最新一节。

- 2026-09-07：App 文件入口、bookmark、原子导入和 20 次恢复记录已实现；核心、2 项 App 文件往返/保护测试、1 项系统选择器 UI 测试通过，既有 6 项助手日程测试复测通过。真机文件提供者与恢复 UI 全流程尚待验收。

- 2026-09-07：已接入 GitHub 持久基线/SHA/失败与重试状态、前台自动同步、Keychain 配置入口，以及本机助手服务的结构化冲突处理、可选确认、高亮与恢复。核心竞态/离线/重启检查及 App/配置页检查通过，真实服务尚未联调。已重新询问私有仓库目的地；devicectl 实查 iPhone 仍 unavailable。

# AI 日程与同步：阶段验收记录

关联规格：[路线 1–5](../superpowers/specs/2026-09-07-ai-schedule-and-sync-design-zh.md)

## 当前结论

路线 1–5 正在实现，尚未完成。远端尚未部署；真实 AI 日程执行、文件往返与远端冲突合并均需独立证据。

## 已完成的基础检查

2026-09-07 主线程新增 Trace 核心与 App 入口：

- `swift run ToughTrialV2Checks` 通过，含新 `checkUsageTracePersistenceAndBounds`。
- 新检查覆盖：关闭不新增、数量上限、30 天过期、重启恢复、导出、清空、损坏原文件保留与明确清空后的恢复。
- `swift build` 通过。
- iOS Simulator 应用及 UI 测试目标编译通过。
- 已接入提交输入、语音开始/完成/取消/失败、取消后修改转写、助手完成/失败/取消和 App 手动修改。
- 日程提案/应用/撤销以及同步的事件名已经定义，但调用处需随这些模块接入，不算已验收。
- Trace 是固定字段与枚举，默认不含文本正文、原始音频、密钥或供应商错误原文。事件含时间、来源、会话/请求 ID、耗时、字数。

## UI 验证

模拟器：iPhone 17 Pro，iOS 26.5，ID `70658AC9-865F-44BC-8FAE-E8762E4F6824`。

初次 UI 测试定位了两个测试操作问题：Toggle 容器中心不切换开关；系统确认框暴露嵌套的同名按钮。已改为点击开关右侧和明确选择确认按钮首个匹配；第三次运行通过（`TEST SUCCEEDED`）。查看真实事件、关闭记录、导出预览、清空与重开页面保持关闭状态均通过。

测试日志：`/private/tmp/tough-trial-trace-ui-03.log`。尚未作真机新流程验收。

## 并行工作边界

- `.worktrees/schedule-commands`：Core 原子命令、回执、撤销、旧数据兼容。
- `.worktrees/schedule-markdown`：Markdown codec、稳定 ID、三方合并。
- `.worktrees/schedule-client`：结构化模型客户端与固定契约检查。
- 主目录保留已验收语音改动；各子模块完成后先审查再集成。

## 剩余验收

- [ ] 原子命令及撤销集成与真模型执行。
- [ ] 高亮、严格确认可选、迟到结果保护与重启恢复。
- [ ] 真实口述细节/否定/纠正与任务树整理。
- [ ] Trace 新日程/同步事件与真机链路（已有助手/设置模拟器 UI 通过）。
- [ ] Markdown 手工修改往返、绑定、损坏保护与恢复。
- [ ] 私有 GitHub 目的地配置；离线和并发同步。
- [ ] 云端 Actions 与真实模型回写、本地真实 AI 冲突处理。

## 日程执行集成（2026-09-07 后续）

已集成 Core `1650d18` 与边界修复 `c248aee` 的改动，保留独立 worktree 供追踪。主线程审查发现并修复的检查包括 context 基线方向、跨午夜延期、DST 墙上时间、别名撞 ID，以及撤销导致父子 context 不一致。

- 主目录 `swift run ToughTrialV2Checks` 再次通过，日志 `/private/tmp/tough-trial-schedule-core-final.log`。
- 模拟器 5 项新助手日程测试通过：立即执行/撤销保留无关任务、严格模式取消/确认、取消阻止写入、切换会话再返回也阻止迟到写入、待确认卡片重启恢复。
- 原有 19 项助手 Store 测试通过。上述 24 项日志 `/private/tmp/tough-trial-schedule-integration-ios.log`。
- 首次日程 UI 测试发现卡片父层 accessibilityIdentifier 覆盖内部按钮标识。已移除父层标识；重跑 2 项 UI 测试全部通过（默认执行/撤销、严格模式取消再确认），日志 `/private/tmp/tough-trial-schedule-ui-02.log`。
- 真机 `build-for-testing` 成功，日志 `/private/tmp/tough-trial-schedule-device-build.log`，DerivedData `/private/tmp/tough-trial-device-signed`。
- 新 `V2ScheduleDeviceTests.testRealProviderPreservesCorrectionsAndEditsExistingTasks` 已编译；仅显式开启 `TOUGH_TRIAL_REAL_SCHEDULE_TEST=1` 才调用已配置供应商。使用内存中的合成日程，不加载用户日程；覆盖口头三点改四点、延期保留任务和计划 ID、完成/撤销、父子拆解、否定与同名歧义。
- **该真模型测试尚未执行**：`xcrun devicectl list devices` 当前显示 sky/iPhone 13 Pro 为 `unavailable`。已异步请用户重连并解锁，不把模拟器替身当真实模型结果。

现有模型客户端从 `.worktrees/schedule-client` 复制了工作版本用于集成编译，尚待该 worker 最终 commit、契约检查与主线程审查。Markdown/合并 worker 仍在实现，尚未集成。真实 GitHub/云端仍未部署。

## 后续审查与网络接口

- App 接线独立审查发现并修复：严格确认后会话保存失败不能清除错误；待确认卡片正确显示以 `localID` 引用的新任务名称。
- 裁决：聊天保存失败时仍允许撤销已保存到 Core 的操作。卡片状态以 Core receipt 为准，撤销只原子更新领域数据与 receipt；不能因为聊天文件暂时不可写而困住用户。新增“确认成功但聊天保存失败→撤销→恢复存储→重复确认不重建”的专项测试已通过；这一轮共 6 项助手日程测试通过。
- 测试日志 `/private/tmp/tough-trial-schedule-app-02.log` 已确认终态成功，无需重新启动同一轮测试。
- 新增 `V2GitHubScheduleClient` 与假 transport 检查，验证指定分支/中文路径、读取内容及 SHA、带基线 SHA 的写入、409 冲突、无效路径拒绝。`swift run ToughTrialV2Checks` 已通过，日志 `/private/tmp/tough-trial-github-checks.log`。仍没有执行真实 GitHub 写入。
- GitHub Contents API 实现依据官方接口：[repository contents](https://docs.github.com/en/rest/repos/contents)。真实云端部署尚待协议、运行器及目的地完成。

## 模型客户端、Markdown 与云端运行器集成（后续）

并行 worker 因额度限制终止后，主线程在主目录接管；worktree 中旧副本保留作历史，不再视为最终实现。

- 日程客户端移除重复的领域校验，使用无持久存储的 Core 候选状态验证。继续严格拒绝未知命令字段，但忽略供应商外围 metadata；拒绝未完整生成的 finish_reason。补全模型实际收到的操作字段与 JSON 输出示例，修正 scheduleTask 的别名说明。
- 新回归先复现响应 metadata 被拒绝，再验证仅改时长、别名撞 ID、自环层级与截断响应。主目录核心检查通过：`/private/tmp/tough-trial-client-integrated.log`。
- Markdown 与三方合并从 worktree 集成后，新增回归复现并修复次日零点排期丢失日期偏移；格式使用 `00:00+1d`。不存在的 DST 时间拒绝解码。
- 已存在执行事实的单边改写也产生冲突并保留基线，缺行不能绕过校验；基线开放执行段允许追加结束事实。备注仍支持正常三方合并。
- 新 remoteRequests 模型与可编辑 Markdown 请求区域，旧文档 JSON 可兼容加载。请求原文与处理结果整体合并；已处理请求不可沿用 ID 改成新问题。
- `V2ScheduleRemoteProcessor` 经同一 Core 处理明确请求；返回文档同时包含任务变化、状态与结果。`V2ScheduleRemoteRunner` 经 GitHub Contents API 条件写回，409 重新读取请求状态，避免另一端已完成时重复调用 AI。
- `ToughTrialScheduleRunner` 提供 `--example`、`--validate`、`--file` 和 `--github`；独立主机入口限定 macOS / Swift 6，尚未声称支持 Linux。Actions 模板和部署说明位于 `docs/sync/`，尚未激活。
- 完整核心检查通过：`/private/tmp/tough-trial-remote-runner-checks.log`，覆盖旧检查、文件往返、执行事实保护、请求幂等、澄清无写入、并发请求改口、另一端先完成与正常重复运行。
- `swift build` 通过：`/private/tmp/tough-trial-runner-build.log`。CLI 生成合成 Markdown 后验证通过（0 tasks / 1 request）。
- 兼容核心检查通过：`/private/tmp/tough-trial-remote-compatibility.log`。
- iOS Simulator 通用构建通过：`/private/tmp/tough-trial-markdown-ios-build.log`。

本轮没有执行远端写入、真实模型调用或新的真机验收。剩余 App 文件绑定/原子导入与版本恢复、同步状态与离线队列、本地 AI 冲突处理、真实两客户端 GitHub / Actions / 模型验收均未完成。路线 1–5 继续保持进行中。

- 最后复查补上非托管前言尾部空行、请求原文尾部换行的精确保留；新增对应往返用例，全部核心检查再次通过：`/private/tmp/tough-trial-markdown-preservation.log`。

## App 文件绑定、原子导入与恢复（后续）

- 新增 `V2ScheduleDocumentState`，在同一本机快照中保存文档身份、文件基线、bookmark、最近读写时间及最多 20 次前后版本。旧快照缺少该字段时可加载。
- Core 导入先校验/三方合并/保护执行事实，再一次提交领域数据与恢复记录；过期快照、重复 ID、真实冲突与保存失败不部分写入。
- 恢复保留无关后续任务和既有顺序；执行记录、云端请求保持，相关实体后来更改或形成悬空引用时拒绝覆盖。
- 助手菜单新增“日程文件”，接入系统文件选择器和导出面板、security-scoped bookmark 解析、重新读取、合并写回、待写回状态、恢复记录。文件协调和 IO 在后台任务执行，写入前比较刚读到的原始内容。
- 提醒更新按顺序执行，包含恢复前已删除的排期 ID；失败只提示提醒未更新，不伪装成日程没有保存。
- 文件成功/失败产生不含正文的 Trace。无后台自动 GitHub 同步声明。
- 核心导入测试初次暴露 JSON 日期回读与内存值的精度差；“坏文件不改磁盘”改为比较实际前后字节，并单独检查内存不变。进一步新增带亚毫秒执行时间的 Markdown 往返及 JSON 重启后导入回归，定位到 0.119 微秒的表示差，已通过保留日期精度和仅容忍 Unix Double 的 ULP 差异解决。
- 最新完整 Core 检查通过：`/private/tmp/tough-trial-document-final-core-02.log`。覆盖文件编辑复用 ID、bookmark/版本重启、坏文件内存/磁盘不变、过期读取拒绝、真实磁盘保存失败回滚、恢复保留无关任务及顺序、精细执行时间往返及重启导入。
- iOS Simulator 构建通过：`/private/tmp/tough-trial-files-ios-build-02.log`。
- 2 项 App 文件测试与 1 项 UI 测试通过：`/private/tmp/tough-trial-file-app-tests.log`。App 测试使用真实临时文件和 bookmark：文件改标题→导入同一任务→手机新增→写回文件→快照重新加载；另一编辑者写入新字节后旧写入被拒绝。UI 测试打开助手文件入口、系统选择器并取消，返回无错误。
- 最后复测 6 项既有助手日程测试和 2 项 App 文件测试全部通过：`/private/tmp/tough-trial-file-regression-final.log`。

剩余：文件提供者/iCloud/真机授权与恢复 UI 全流程验收；GitHub 配置界面、持久同步状态与离线队列、本地 AI 冲突处理，以及真实模型/两客户端/Actions 远端验收。真实目的地尚未配置，目标继续保持进行中。

## GitHub 同步状态与本机 AI 冲突处理（后续）

- `V2ScheduleSync` 在本机快照中保存 GitHub 目的地、共同基线、SHA、最近同步、失败类别、待重试状态、在途请求 ID 与三份冲突候选。凭据只通过 App Keychain 读取，不进入领域状态。
- 上传前读取最新 SHA 并三方合并；409 重新读取，首次创建的 422 竞态也重读。无变化不写入新版本。上传前检查任务关系及执行事实，避免先破坏远端再被本地校验拒绝。
- 完成网络请求后，将结果再次合并到网络期间产生的本地编辑；较新的本地任务保留并继续待上传。配置变更后，旧请求不能覆盖新目的地。
- 更新 metadata 的时间戳按较新值合并，不阻断真正不同字段的并发编辑。
- GitHub 配置页提供仓库/分支/文件/安全凭据字段、保存配置、同步、最近结果、待同步状态及冲突候选。保存配置本身不联网，首次连接由用户点击。
- `V2ScheduleConflictClient` 使用本机配置的助手服务，只发送具体冲突候选、允许选择和补充要求。响应必须绑定当前冲突 ID、覆盖且仅覆盖已列出的冲突。可以选择候选或合并文字；执行事实不可改写，候选仍经 Core 校验。
- 默认应用后高亮并提供撤销；严格模式显示具体前后内容，确认才写入，取消无写入。澄清只显示问题，支持补充处理要求后再次请求。迟到模型结果在本地文档变化后拒绝写入。
- 冲突处理与恢复版本原子保存，撤销记录带回溯 ID；同步后仍能撤回可恢复的最近一次冲突处理，保留无关后续编辑及执行事实。
- 前台自动同步依赖 scenePhase：首次连接后检查待上传修改（最短 5 秒）、定期拉取（30 秒），失败至少 30 秒后重试。凭据/文档错误、未解决冲突、待确认和已有在途请求停止自动尝试。可关闭；退出前台取消循环，不声明后台常驻。

验证证据：

- 完整核心检查通过：`/private/tmp/tough-trial-sync-final-core.log`；兼容检查通过：`/private/tmp/tough-trial-sync-final-compat.log`。
- 核心覆盖：离线→保存→重启→重试；上传期间新增任务后保留待上传；重复同步不新增版本；真正 SHA 写入竞态后重读合并；不同内容字段与 timestamp 同时变更；旧目的地结果拒绝。
- AI 契约覆盖：供应商外围 metadata、用户补充要求、凭据不在请求正文、仅列出的冲突字段、过期响应、实际应用与撤销、澄清无写入、执行事实候选限制。新增公开冲突构造器后，跨模块检查全部通过，日志 `/private/tmp/tough-trial-sync-conflict-final-core-02.log`。
- iOS Simulator 构建通过：`/private/tmp/tough-trial-conflict-ios-build.log`。
- 最新 4 项 App 测试与 1 项配置页 UI 测试通过：`/private/tmp/tough-trial-auto-sync-app-tests.log`。覆盖默认应用/高亮/撤销、严格预览/取消/应用、澄清保持候选、自动同步首次连接边界与重试间隔；UI 验证安全输入框及无效仓库拒绝且不连接。
- 重新实查：`xcrun devicectl list devices` 显示 iPhone 13 Pro/sky 仍为 unavailable；`gh repo view` 确认当前 liuxiaoyusky/tough_trial 仍是 PUBLIC。没有进行远端写入或真实模型请求。
- 已异步询问真实合成测试的私有仓库目的地，选项为新建 tough-trial-schedule 或用户指定现有私有仓库；尚未收到答复。

剩余真实验收不能由上述替身测试代替：App 完整文件 UI 往返与恢复、真机文件权限/重启、真实模型的自然语言日程与冲突处理、两个独立客户端在真实私有 GitHub 文件同步、Actions 自动拉新/模型回写及重复触发。路线 1–5 尚未完成整体验收，继续保持进行中。

## 文件完整 UI 往返与恢复（后续）

- 增加仅 DEBUG 且显式 UI 测试环境启用的隔离文件夹，使用随机 UUID；准备真实 Markdown、bookmark 和 JSON 快照，不接触个人日程。准备代码只建立初始条件，读写、任务执行和恢复均通过正常 App 界面。
- 新 UI 场景：重新读取电脑修改的标题→通过助手新增任务→合并并写回→重新启动并还原原始本地快照→确认新增任务尚不存在→再次从文件读取并找到新增任务→恢复此前内容→再次启动确认恢复状态持久保存，且界面提示待写回。
- 首次测试失败于导航/查找方式：助手是全屏，关闭文件面板后还需退出助手；任务结构页不是完整列表。修正为正常退出助手，通过今天的全任务搜索核对存在/不存在，不启动执行。文件读写和恢复状态在该轮未报告错误。
- 修正后的完整 UI 场景通过，1 项测试、0 失败，xcodebuild exit 0：`/private/tmp/tough-trial-file-ui-roundtrip-02.log`。结果包：`/private/tmp/tough-trial-apple-sim/Logs/Test/Test-ToughTrial-2026.09.07_11-10-50-+0800.xcresult`。系统选择器打开/取消在首轮独立用例通过，日志 `/private/tmp/tough-trial-file-ui-roundtrip.log`；该首轮整体失败，不列为整套通过。
- 助手在此测试使用确定性响应；文件是真实本机临时文件。此结果证明模拟器界面往返和恢复，不证明真实模型质量、iCloud 或真机文件授权。
- 本轮重新检查设备，iPhone 13 Pro 仍 unavailable；Mac Keychain 未找到该 App 的聊天服务凭据。私有测试仓库目的地仍待用户选择，没有远端写入。

剩余：真机文件提供者/重启授权、真实模型日程与冲突处理、真实私有仓库两个客户端及 Actions 自动回写。路线 1–5 仍未完成整体验收。

## 文件 Trace 操作关联（后续）

- 文件读取/合并将同一个操作 ID 用于 Core 导入记录和 Trace；导出/写回无变更时仍记录独立操作。恢复记录为 `scheduleUndone`，关联被恢复的原变更 ID。成功和失败事件都记录耗时，不增加自由文本字段。
- 先添加 UI 回归并运行，复现原实现把恢复记成 `syncFinished`，日志 `/private/tmp/tough-trial-file-trace-red.log`，exit 65。随后修改事件类型、操作 ID 和耗时接线。
- 新 UI 测试从文件恢复记录读取变更 ID，再实际打开 Trace 导出 JSON，验证读取/恢复两条事件对应同一变更、类型正确、耗时存在，且不包含任务标题及文件名。
- 2 项 App 文件测试与 2 项 UI 测试通过，xcodebuild exit 0：`/private/tmp/tough-trial-file-trace-green.log`。UI 回归同时覆盖 Trace 关闭、导出、清空。结果包：`/private/tmp/tough-trial-apple-sim/Logs/Test/Test-ToughTrial-2026.09.07_11-18-20-+0800.xcresult`。
- 本轮未触发真实模型、远端 GitHub 或 Actions；这些验收仍待设备/凭据和已询问的私有仓库目的地。未将路线 1–5 标记为完成。

## Markdown 原文保真修复（后续）

- 回归复现：任务备注单独包含 `<!-- tough-trial:end owned -->` 时，导出后读回误报重复结束标记；多行标题和内嵌协议注释也需要区分文字与语法。红灯日志 `/private/tmp/tough-trial-markdown-text-red.log`，exit 133。
- 新导出 header 明确声明 `textEncoding="entities-v1"`；仅转义记录标题、备注、请求原文和结果，读取时非递归解码一次。保留旧文件字面实体文本、任务身份、metadata 和外部正文；未知编码拒绝导入。标题在解码后再次验证，避免空白实体绕过空标题限制。
- 核心覆盖：任务/分类/排期/执行记录文字、协议注释、多行标题、CRLF、字面 HTML 实体、请求原文/结果、人工编辑转义标题、旧格式迁移和未知编码拒绝。最新完整 Core 检查通过：`/private/tmp/tough-trial-markdown-text-final-core-03.log`。扩展检查初次因非 throwing autoclosure 的测试写法未编译，修正后通过；不把该编译失败算成业务回归。
- 兼容检查通过：`/private/tmp/tough-trial-markdown-text-compat.log`。最终 `swift build` 通过：`/private/tmp/tough-trial-markdown-text-final-build.log`。运行器 `--example` 输出并通过 `--validate`：`/private/tmp/tough-trial-markdown-text-runner.log`；没有调用模型。
- 新格式的 2 项 App 文件测试与 1 项完整文件 UI 往返/重启/恢复测试通过：`/private/tmp/tough-trial-markdown-text-ios.log`，exit 0。补充解码后空标题校验后，最终构建的 2 项 App 文件测试再次通过：`/private/tmp/tough-trial-markdown-text-final-app.log`，exit 0。实际磁盘测试含协议标记、字面实体与 CRLF 备注。
- 重新检查真实联调条件：iPhone 13 Pro 仍 unavailable；百炼控制台明确显示未登录，进入阿里云登录页后没有可复用的登录会话。保留该登录页供用户继续。私有仓库目的地尚未答复；没有新建仓库、保存云端凭据或进行远端写入。

下一步需要用户确定私有仓库，并恢复真实模型访问（重新登录百炼或连接已配置服务的 iPhone）；真机文件授权仍需连接设备。上述外部条件持续未满足，路线 1–5 不作完成声明。

## 私有同步仓库已确定（后续）

- 用户同意使用私有仓库后，按此前提出的名称创建 `liuxiaoyusky/tough-trial-schedule`，地址：https://github.com/liuxiaoyusky/tough-trial-schedule 。`gh repo view` 实查 `visibility=PRIVATE`、`isEmpty=true`。
- 该仓库用于当前用户的日程同步与合成联调。选择 GitHub 同步的其他用户应指定各自的私有仓库；不共享当前用户的日程数据或凭据。
- 当前仅完成目的地创建，尚未上传日程、部署运行器或配置云端凭据。仓库选择这一阻塞已解除，真实模型访问和真机验收条件仍待恢复。

## 改用用户指定的 tough-trial-sync 并完成初始部署（后续）

- 用户明确提供 https://github.com/liuxiaoyusky/tough-trial-sync 后，将实际联调目的地改为该仓库。部署前实查 PRIVATE、空仓库；部署分支为其默认 `main`，文件为 `schedule.md`。
- 在独立 checkout `.worktrees/schedule-sync-deployment` 准备最小 Swift Package、44 个运行器/Core 源文件、源码摘要 manifest、使用说明和 Actions 工作流。没有上传 App 资源、录音或个人日程；`schedule.md` 来自 `--example`，含 0 个任务、1 个合成待处理请求。
- 独立包本地构建和格式验证通过：`/private/tmp/tough-trial-sync-deploy-build.log`、`/private/tmp/tough-trial-sync-deploy-validate.log`。
- 首个部署提交 `525578244abdf38ff29e9f1020bce5c9665337c5` 已推送至该私有仓库。远端 Contents API 返回的日程 SHA `b4a64b12a6850c9992b0c571661ed24ff7ef1bad` 与本地 Git blob 一致。
- 真实 GitHub Actions 运行 https://github.com/liuxiaoyusky/tough-trial-sync/actions/runs/34081405278 已完成：构建/日程校验成功、配置检查成功、AI 处理步骤 skipped。完整日志保存于 `/private/tmp/tough-trial-sync-bootstrap-actions.log`，watch 终态 exit 0。
- 工作流在缺少模型配置时明确写出待配置摘要，跳过 AI 调用；配置齐全后才处理请求。此次运行后日程 SHA 未变化，不能把 Actions 的 success 解释为 AI 回写成功。
- 仓库目的地和运行器部署已落实。下一步仍需可用模型服务配置，完成真实 AI 回写、两个客户端同步/冲突处理和真机文件授权验收。


## 百炼恢复登录后：真实模型与私有 GitHub 联调（2026-09-07）

- 用户恢复百炼登录；从控制台复用已有 Key，没有创建、重置或删除密钥。已核对业务空间的 OpenAI-compatible 端点。密钥仅用于授权合成联调和 `tough-trial-sync` 的 Actions secret，不进入源码、Markdown 或测试输出。
- 首次真实本机调用约 3.61 秒，首次真实 Actions `34081880264` 处理 1 条请求并回写。但原提示词示例的“保留用户限制”被模型照抄，丢失两小时上限；因此首次通路成功不算语义验收。原始合成结果与日志保留在 `/private/tmp/tough-trial-live-acceptance/actions-first.md`、`actions-first.log`。
- 增加显式 opt-in 的 SwiftPM 真模型 / 真 GitHub 测试 target，默认不联网。qwen-flash 和 qwen-plus 初版测试曾出现分钟换算错误、相对日期错误和同名任务被批量修改；qwen3.5-plus 默认思考的一个请求超过现有 30 秒上限，未被选为本轮配置。保留失败日志，不用后来的通过覆盖失败事实。
- 修改提示词中的占位示例，明确将具体限制写入父任务备注；模型时间接口改为 `startTime: HH:mm`，由严格 ASCII 格式解析换算为 Core startMinute。兼容旧分钟字段，但拒绝双字段冲突。提供确定性的今天/明天/后天日期，明确同名任务没有区分或批量授权时追问。Core、Markdown 字段和用户交互不改。
- `qwen-plus` 最新真实日程 2 项测试通过：三点改口四点、明天改后天五点保持原任务/排期 ID 和半小时时长、完成及撤销、两小时父子拆解、不写入讨论、同名追问、两小时限制往返与已处理请求不再执行。四个可执行请求耗时分别约 2.95 / 3.21 / 1.76 / 3.32 秒，整套约 17.61 秒；日志 `model-plus-final.log`。这些是合成样本结果，不宣称模型对所有表达都可靠。
- 最新 `qwen-plus` 真 GitHub 测试通过，两个独立客户端与独立 JSON 快照读写 `acceptance/two-clients-3bc1bc56-99c0-4304-9fde-846a86e5156a.md`。真实 SHA 并发拒绝、不同字段合并、同字段备注真 AI 合并（保留 3 个示例/配图/最多 2 小时）、整次撤销、重启恢复、注入断网后真实联网重试、重复同步 SHA 不变均通过。最终 SHA `abe36e8d73bfab0a4b1b6115763933567bf0d625`，日志 `github-plus-final.log`。这里是同一台 Mac 上的独立客户端，尚不是两台实机。
- 早一轮精确 Date 相等断言暴露 JSON 快照的 Unix Double 时间精度差异；合并文本、字段和 SHA 均正确。最终测试明确对 createdAt/updatedAt 允许 1 微秒的既有存储精度差，其他字段逐项完全一致；重复同步仍要求真实 SHA 不变。
- Core 完整检查 `core-final.log`、Swift 包构建 `package-build.log`、兼容检查 `compatibility.log` 通过。iOS Simulator 6 项助手日程 + 4 项冲突处理测试通过，日志 `ios-regression.log`，包含默认执行/高亮/撤销和严格确认路径。所有这些日志位于 `/private/tmp/tough-trial-live-acceptance/`。
- 运行器修复与源摘要已在私有仓库提交 `889ca61c54b3ca3511341a1d518bac59ab83e2f3`。真实 push 自动触发 Actions `34082869157`，处理 2 条新请求；通过新请求修复原任务备注，同时创建带“最多 45 分钟、不要联系客户”限制的父任务与两个子任务。原 3 个任务 ID 保持，最终 6 个任务、0 排期、3 条 processed 请求，SHA `225c63f33ae94aafc2df87d6fea3dd10e61f2067`。结果 `actions-fixed.md`，日志 `actions-fixed.log`。
- iPhone 13 Pro 当前仍显示 unavailable；已请求重新连接解锁，继续等待真机文件授权、真实模型设置和实际 App 同步验收。路线 1–5 尚不宣称全部完成。

- 重复触发 Actions `34082950882` 成功：Processed 0 / pending 0 / retries 0，6 个任务与 3 条请求的文件字节完全不变，SHA 仍为 `225c63f33ae94aafc2df87d6fea3dd10e61f2067`。运行列表没有 AI 自身提交产生的新工作流；日志 `actions-repeat.log`。


## 按用户指定切换 GLM-5.3-Flash Coding Plan

- 用户明确要求参照 `earendil-works/pi` 的连接方式。已核对其 commit `9767ba275f3e9a5ee0f5c5342249b629ab1b2282`，使用国内 Coding endpoint、Bearer 鉴权和未选思考强度时的 `thinking: disabled`，适配聊天、计划、日程及冲突四条入口。App GLM 预设与模型列表已更新，语音配置独立。
- 真模型日程 2 项测试、真实 GitHub 冲突处理、聊天回答与 schedule 路由最终复测通过。首次聊天格式错误及后续复测均有记录，不把失败轮次描述为通过。
- 云端已改用 `glm-5.3-flash`，真实 Actions [34087032219](https://github.com/liuxiaoyusky/tough-trial-sync/actions/runs/34087032219) 自动回写通过。新增合成任务保留“最多 15 分钟，不要联网”，最终日程 SHA `4f36cb72860f6caadeed079fa23eab197daa8f8b`。
- Core 全部检查、包构建、兼容检查与最终 11 项 iOS 模拟器回归通过。真机尚未连接，未安装新构建或切换其当前活动配置。详细参数、时延及日志见 [GLM 接入记录](../sync/glm-coding-pi.md)。

## 真实 GLM 与 App 聊天流程联合验收

- 用户当前没有真机，本轮保留真机门禁，使用新建的独立 iPhone 17 Pro / iOS 26.5 模拟器。测试从 `V2AssistantStore.send` 进入，经 `V2AppStore.makeAssistantDependencies` 的真实聊天路由和日程客户端，调用 GLM-5.3-Flash 后由 App 实际写入引擎与磁盘；未启用确定性 UI 测试模型。
- 新增 `V2AssistantLiveScheduleTests`，普通运行默认 skip。测试临时凭据只在隔离模拟器的 tmp 中以 0600 文件提供，读取后立即删除；不写 Keychain、源码或测试安装包。`V2AppStore` 增加可选的内存 AI 设置注入，未提供时沿用正常配置加载。
- 四轮实际请求：新增明天四点周报（保留“三点，不，四点”纠正、三十分钟、核对数字）；省略任务名继续改到后天五点（原任务/排期 ID、时长、备注不变）；标记完成；严格模式新增准备演示及两个子任务（保留两小时限制，不强造日期）。每轮经完整聊天入口的耗时约 4.91 / 12.96 / 14.28 / 3.97 秒。
- 核对实际回执与 App 高亮 ID；从 JSON 重新构造 App/聊天后撤销完成状态；严格提案从磁盘恢复后连续确认两次只产生一次写入；撤销任务树后再次加载磁盘，未留下子任务，未改动无关任务。这里验证的是持久化重建，不是杀进程、系统文件提供者或真机重启。
- 实际导出的 Trace 核对输入/提案/应用/完成的同一操作 ID，以及严格确认/撤销的关联；断言导出不包含本轮凭据和合成备注。
- 本轮真实测试 1 项、0 失败、0 跳过，36.177 秒，xcodebuild exit 0。日志 `/private/tmp/tough-trial-live-app-first.log`，结果包 `/private/tmp/tough-trial-apple-sim/Logs/Test/Test-ToughTrial-2026.09.07_15-17-16-+0800.xcresult`。此前无凭据回归为 11 项通过、1 项正确跳过，日志 `/private/tmp/tough-trial-live-app-regression.log`。测试构建及完整 Core 检查通过，分别见 `tough-trial-live-app-build.log`、`tough-trial-live-app-core.log`。
- 当前结论限于这些合成样本与 App 状态层集成，不替代真实界面点击、语音质量、物理文件授权、两台手机或连续使用验收。跟进项是完整回合的响应耗时，不能以独立日程 API 的较短耗时代表用户等待时间。

## 等待反馈与中断步骤计时修复

- 原加载提示要求消息处于 pending 且 parts 为空，但发送时 `updateTurn` 已插入 Trace part，等待提示因此不显示。现在 pending/streaming 消息持续显示与自身消息 ID 对应的处理阶段；活动阶段只保留在内存中，结束后清空。日程处理分别显示“正在理解你的意思…”和“正在整理日程…”。
- 原失败与取消步骤 duration 固定为 0；现在每个活动步骤保存开始时间，失败/取消按实际间隔记录。新回归用受控时钟分别等待 9 秒取消、7 秒超时，要求耗时准确且任务仍为空。
- 红灯：`/private/tmp/tough-trial-progress-red.log`，两个 App 回归分别复现 0 与 9/7 不符，UI 回归未找到两个阶段提示。首轮 UI 测试的取消文案也与既有 App 不一致，已修正为“操作已取消。”；这与加载提示问题分开处理。xcodebuild exit 65，保留失败证据。
- 绿灯：`/private/tmp/tough-trial-progress-green.log`，31 项 App 测试（助手日程 8、原助手状态 19、冲突 4）和 3 项日程 UI 测试全部通过，exit 0。UI 覆盖默认应用/撤销、严格取消/确认、等待阶段切换与执行前停止。加入截图后补跑通过，日志 `tough-trial-progress-visual.log`；人工检查[等待截图](../assets/schedule-progress/2026-09-07-schedule-waiting.png)，提示与停止按钮清楚可见。
- 真模型测试改用真实时钟，输出已有模型/日程 Trace 的分阶段耗时。首轮 `tough-trial-progress-live.log` 因对重载任务与序列化前内存对象作 Date 精确相等比较而失败；其他内容及流程断言通过。JSON secondsSince1970 的 Double 会带来亚微秒舍入。测试改为分别对照原内存对象和原磁盘对象做完整相等检查，同时核对首次序列化时间差不超过 1 微秒；没有放宽任务内容或后续修改判定。
- 最终真实 GLM 联合测试通过：`/private/tmp/tough-trial-progress-live-final.log`，1 项、0 失败、0 跳过，21.732 秒，exit 0。四轮路由/日程秒数分别为 2.08/2.39、2.55/3.65、2.85/2.96、1.69/3.45；完整回合 4.49、6.21、5.82、5.15 秒。数据说明模型时延有波动，不能将本轮较短时间归因于 UI 修复。结果包 `Test-ToughTrial-2026.09.07_15-28-18-+0800.xcresult` 位于 `/private/tmp/tough-trial-apple-sim/Logs/Test/`。
- 最终测试构建及核心检查通过：`tough-trial-progress-final-build.log`、`tough-trial-progress-core.log`。默认完成后等待提示消失的 UI 断言也在 `tough-trial-progress-live.log` 中独立通过，虽该轮整体因上述日期比较失败。改动未涉及云端运行器，不需要重新部署。
- 真机门禁与路线 1–5 的整体结论不变；没有以模拟器截图或状态重建代替手机文件权限和实际跨设备使用。

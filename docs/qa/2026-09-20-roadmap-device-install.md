# 统一 Roadmap 与 iPhone 安装验收

执行日期：2026-09-20；收尾更新：2026-09-21。设备：已配对 iPhone 13 Pro，iOS 27.0 beta。用户明确要求合并 roadmap、安装测试。

## 文档交付

- `docs/roadmap.md` 统一当前进度、R1–R6 交付顺序、未完成项与验收条件；保留导航 N、资料 C、备份 G 的原编号映射。
- `docs/progress.md` 只保留跳转，README 添加统一入口。
- `docs/roadmap-history-2026-09-20.md` 完整归档合并前 roadmap 和 7 月 progress；历史记录不作为当前结论。
- 纳入最新已确认的重复规则设计，明确尚未实现；修正 Dreaming、Mac、统计和签名状态的历史歧义。
- 新 roadmap、跳转、归档中的相对文件链接检查通过。

## 构建和安装

- `swift run ToughTrialV2Checks`：通过。
- `swift run FocusTimelineCoreChecks`：通过。
- `swift build`：通过。
- iPhone Debug 1.0（14）构建成功，包内版本号核对为 14，`codesign --verify --deep --strict` 通过。
- 用现有有效 Apple Development 签名和覆盖本机的 Xcode 管理配置构建；未改仓库签名配置。
- 23:35 原位安装成功，bundle ID `com.skyliu.toughtrial`；未卸载、未清空数据。
- 首次正常启动被锁屏拒绝；之后设备测试恢复运行。9/21 00:43 不带测试参数正常启动成功（见下方收尾结果）。

## 定向测试范围

- 今天领域：暂停补位/继续新段、完成保留/恢复不启动、跨天累计/今日口径。
- 文档输入组件：使用现有 V2TaskDocumentTests。
- 真机 UI：创建合成任务、空提交禁用、开始/暂停/继续/完成/恢复、队列焦点切换、Zen 返回、理账入口；四任务视图入口。
- 真机 UI：编辑任务、继续编辑/放弃、保存标题与正文、完成/撤销/恢复。
- 将任务编辑用例的旧系统 TabBar 定位改为当前自定义底栏稳定 ID；仅修改测试定位，不改产品行为。

测试状态：9/20 23:38–23:39 已实际运行；9 项状态/组件通过，4 项 UI 失败。用例选择使用现有内存或临时测试数据；不执行写入手机生产任务的持久化测试。未运行真实 AI、自然语音、输入法手工操作、全量同步或分享发送。

已知附件测试 `V2FileAttachmentTests.swift` 访问 fileprivate thumbnail 的编译遗留仍在；本次通过 `EXCLUDED_SOURCE_FILE_NAMES` 排除该文件运行定向测试，不声明全测试套件通过。

## 数据边界

自动审批拒绝了将手机个人任务快照复制到本机临时目录用于安装前后比较的步骤：安装测试授权未明确包含该数据复制。该步骤未执行，也未采用其他路径导出。因此不宣称安装前后完整快照一致；9/14 的 39 条任务比较仅是历史结果。

## 本机证据

- `/private/tmp/tough-roadmap-core-20260920.log`
- `/private/tmp/tough-roadmap-compat-20260920.log`
- `/private/tmp/tough-roadmap-swift-build-20260920.log`
- `/private/tmp/tough-roadmap-device-build-20260920.log`
- `/private/tmp/tough-roadmap-install-20260920.json`
- `/private/tmp/tough-roadmap-launch-20260920.json`
- `/private/tmp/tough-roadmap-device-tests-20260920.log`
- `/private/tmp/tough-roadmap-device-tests-20260920.xcresult`

## 最终结果（2026-09-21 收尾）

| 范围 | 结果 |
| --- | --- |
| V2TaskDocumentTests | 6 项通过：首段标题/正文、空内容、空行/emoji、Windows 换行、光标及听写绑定 |
| V2TodayQueueTests | 3 项通过：暂停补位/继续、完成保留/恢复、跨天/今日用时 |
| 任务编辑 UI | 失败：点击底栏任务后未找到合成根任务；保存/取消/撤销步骤未执行 |
| 四视图 UI | 失败：点击 `root.tab.tasks` 后找不到列表视图按钮；层级快照仍是助手页 |
| 队列焦点/理账 UI | 失败：点击今天后找不到 `today.quickAdd`；后续步骤未执行 |
| 暂停/完成/恢复 UI | 失败：点击今天后找不到 `today.emptyZen.startUnlinked`；后续步骤未执行 |
| 正常启动 | 9/21 00:43 成功：`--terminate-existing` 后不带测试环境参数启动 `com.skyliu.toughtrial` |

Xcode 总体结果为 **TEST FAILED**。4 个 UI 用例均在底栏切页后的前置检查失败，不能声称今天/任务业务交互已在这台手机通过。当前证据不能确定是触控命中、拖拽手势、导航状态或 iOS 27 beta 兼容性原因；该问题已列为统一 roadmap 的下一项。没有借收尾修改生产代码。

额外启动回执：`/private/tmp/tough-roadmap-final-launch-20260921.json`。手机恢复正常 App 使用状态；本轮未关闭用户手机上的反馈任务。自然输入法/语音、真实 AI、多端同步和用户回访继续开放。



## 后续复验

9/21 01:04，同一版本未修改生产代码，9 项状态/组件 + 4 项真机 UI 均通过；详情见 [9/21 复验](2026-09-21-device-regression.md)。本文件保留原失败事实，不以复验覆盖历史。

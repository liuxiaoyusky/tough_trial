# 今天执行队列与真实页面评审

## 本轮范围

按 8768 页面批注落地 iOS 今天：主卡片、运行队列、今日规划；暂停保存本段，继续新建段；完成在一次 commit 内关闭同任务执行段并更新任务/计划完成态。队首补位仅改变关注，不创建执行段。跨天累计按 taskID 汇总，今日用时按本地自然日截断，暂停间隔不计入。自由 Zen 无任务可完成时仍为结束时间段。

核心 `completeTodayItem` 新增显式 `finishExecution` 参数，今天入口传 true；默认 false 保留其他已有调用的行为。没有修改任务结构产品设计，本轮仅更新其真实截图。

## 证据

- `swift run ToughTrialV2Checks`、`swift run FocusTimelineCoreChecks`、`swift build` 通过。
- iOS 模拟器构建通过。
- V2TodayQueueTests 3 项通过：暂停补位/继续新段、完成保留/恢复不启动、跨天累计/今日口径。
- V2TodayQueueUITests 实际点按通过：创建任务、空提交禁用、开始、队列切换、主卡片 Zen/返回、暂停、继续、完成、完成后补位、恢复、空闲态；独立自由 Zen 进入/返回/结束。
- 任务四视图和其他模块入口的点击与截图通过；这部分只验证进入和截图，不宣称对各模块所有业务交互做了回归。
- 单元和页面截图测试结果：`/tmp/tough-today-review-tests-4.xcresult`；其中一个滚动定位用例失败，修正测试使目标完整进入可点击区域后，在 `/tmp/tough-today-review-tests-5.xcresult` 两项相关 UI 测试均通过。
- 首次测试发现旧完成逻辑不结束计时，已修复并通过回归。测试目标已有 `V2FileAttachmentTests.swift` 访问 fileprivate thumbnail 的编译问题，本轮以命令行 `EXCLUDED_SOURCE_FILE_NAMES=V2FileAttachmentTests.swift` 临时排除；未修改附件模块，也不声称全测试套件通过。

## 评审与边界

截图使用 iPhone 17e / iOS 26.5 模拟器和模拟器测试数据。今天截图包含运行、暂停补位、完成、空闲状态。结构页与鱼骨页保留真实画布和布局问题供用户继续评审，不用理想化 SVG 覆盖。

本轮未向真实手机安装，不访问手机私有任务数据。通知/Live Activity 视觉、真实手机手感及大字体专项仍未验证。评审网站是静态截图批注，原生操作的验证证据在上述测试包。

评审服务原来只允许 5 个资料页面 ID 保存批注，现改为随 index 页面清单校验，以支持今天及任务等页。

稳定截图复验通过：`/tmp/tough-today-review-captures.xcresult`，任务四视图及其他模块入口共 2 项；截图等待页面动画结束后导出。8768 结构页批注经过真实 POST 保存、GET 读取与临时条目清理验证。

## Mac 用户验收

2026-09-20：最新 ToughTrialMac Debug 构建通过，打开原生「今天」供用户测试；用户确认「可以，测试完毕」，授权 commit 与 push。iOS 真机安装状态不变。

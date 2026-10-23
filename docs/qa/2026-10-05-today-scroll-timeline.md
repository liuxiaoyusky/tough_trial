# 2026-10-05 · 今日整页滚动与时间线

## 改动与范围

按本轮用户反馈调整原生 SwiftUI：标题、主卡片和今日规划共用一个垂直滚动区；取消独立的「执行中」分区，其他仍在运行的会话并入今日时间线，点按仍可切换主卡片。恢复左侧时间、连续细线和状态节点。没有具体时间的规划显示「今天」，不生成虚构时间。

已完成项留在原来的时间线位置，使用灰色删除线、较小字重和间距、透明背景，默认收起操作，点开才显示「恢复」。完成成功后清除选择，恢复不会自动开启计时。条目的内边距包含在按钮点击区域内，紧凑完成项仍不小于 44 点；右下角新增入口保留。

没有改变并行计时、暂停结束本段、完成任务或自动补位的领域规则。计划提醒仍从今天右上角菜单进入。

## 验证

最新生产布局的 7 项原生交互和 5 项 App 单元验证均通过。它们来自下列独立批次，不声称整个项目全套测试通过。

- iPhone 17 Pro 专用模拟器，iOS 26.5 / 23F77，Xcode 27.0 / 27A266a。Debug 工作区版本 1.0（18），全部使用合成任务，不读取手机个人记录。
- 最新布局的六项原生交互已通过：明确时间/无时间的新增、自由和关联 Zen、Zen 模态隔离、计划提醒设置/取消/撤销/清除、切换主卡片、暂停/完成补位与点开恢复。
- Mac 共用组件构建、`ToughTrialV2Checks`、`FocusTimelineCoreChecks` 和 `swift build` 已通过。Mac 构建不代表 Mac 全交互验收。

| 范围 | 实际结果 | 本机证据 |
| --- | --- | --- |
| 提醒、Zen、时间输入、切换/补位/完成恢复 | 6 项通过；同批长列表坐标断言失败，保留失败批 | `/private/tmp/tough-trial-20261005-today-scroll-final-ui.xcresult`，`final-ui{.log,-summary.json}` |
| 十二条规划的长列表 | 修正测试准备后单项通过；主卡片屏幕坐标已在视口上方、悬浮新增可用、继续编辑/放弃草稿、时间在卡片左侧、完成项更矮且点击区至少 44 点、默认收起恢复、恢复不启动计时均实际断言 | `/private/tmp/tough-trial-20261005-today-scroll-accepted.xcresult`，`accepted{.log,-summary.json}` |
| 当天投影与领域状态 | 5 项通过：其他运行会话保留、主卡片不重复、无关联会话匹配、补位不重开计时段、完成/恢复与跨天累计边界 | `/private/tmp/tough-trial-20261005-today-scroll-final-unit.xcresult`，`final-unit{.log,-summary.json}` |
| 兼容与构建 | Mac 共用 View、两个领域检查和包构建通过 | `final-mac-build.log`、`core.log`、`compatibility.log`、`package-build.log` |

六项 UI 通过批之后只修改了长列表测试准备和滚动定位；生产 SwiftUI/Store 源码未再改变。七个相关源码/测试文件摘要见 `sources.json`，清单 SHA-256 为 `53dc310ca4041f078225d19f16b6718d404c29bb52497801f8bc030dc4d44dee`；这是有限源码清单，不是安装包或干净提交的摘要。

本机日志在 `.runtime/today-scroll-20261005/`。成功与失败批次分别保留，不相加为独立测试数。

## 页面评审包

新增 6 张独立原生图后，Feature Map 对照检查为 50 页、0 个引用错误；`mobile-review` 的清单检查和构建通过。21 个功能条目和历史页面继续保留，不把其余模块顺便标成通过。

390×844 Chromium 实际查看了六个新版入口。隔离的 CLI 评审包实际测试来源信息、点位/画圈、保存后刷新、导出内容与删除；没有写入用户原站点的批注。没有浏览器脚本错误。工具使用已安装的 Node Playwright，Python 环境不含 Playwright；记录见 `review-browser.log` 和 `review-390.png`。这是浏览器尺寸测试，不代替 iPhone Safari。

本地评审入口为 `http://127.0.0.1:8770/#today-current-20261005`。它通过原来的工作台展示原生实图；可复用 CLI 包位于 `outputs/mobile-review-cli/`，不是 App 安装包。本轮不公开发布站点。

## 测试判断与准备记录

- 修复前单项确实复现主卡片停留在列表外：`today-scroll-red.xcresult` 的目标断言失败。
- 首轮重排时，给普通 VStack 添加容器标识覆盖了内部按钮/时间标识；按实际辅助树移除这些容器标识，保留具体控件和滚动区的标识。
- 一批 XCTest 在宿主连接前卡住，未执行用例；终止后只重启 Tough Trial 专用模拟器，保留中断日志及不完整 result bundle，不算通过。
- 三条历史测试仍寻找系统 TabBar，而项目使用自定义底栏；更新到实际的 `root.tab.today`，也验证 Zen 模态下底栏隐藏。
- 八个短条目不足以把主卡片底部完全移到屏幕坐标 0 以上；录屏显示页面确实滚动。长列表用十二项规划，直接断言控件已滚出视口，截图与坐标共同核对，避免只看 `isHittable`。
- 取消已经输入的新增草稿会弹「放弃未保存的修改？」。测试必须操作继续编辑或放弃修改，再等待编辑页关闭；不能绕过确认后在被遮挡的列表上继续滑动。

## 交付边界

原生截图来自生产 View 和测试中的实际操作，单独登记为 10/5 新版本；9/20 旧图及其批注不覆盖。它们可用于评审，不等于用户 iPhone 的安装版已经更新。

截图：[主卡片与统一时间线](assets/2026-10-05-today-scroll/today-current-native-20261005.png)、[滚动到详情](assets/2026-10-05-today-scroll/today-scrolled-native-20261005.png)、[完成项与待办对比](assets/2026-10-05-today-scroll/today-quiet-completed-native-20261005.png)、[暂停补位](assets/2026-10-05-today-scroll/today-paused-native-20261005.png)、[完成后](assets/2026-10-05-today-scroll/today-completed-native-20261005.png)、[空态](assets/2026-10-05-today-scroll/today-empty-native-20261005.png)。

本轮没有归档、导出或上传新的安装包。此前 `/private/tmp/ToughTrial-20261005-18-simulator-retested.xcarchive` 不包含本轮今日布局，已经成为历史候选；以后分发必须按最新源码重新归档。此前 Apple 协议/分发证书阻塞仍未解除。真机滚动、大字体和当前安装版的用户回访仍开放。

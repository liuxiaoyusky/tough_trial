# 2026-10-05 · 计划提醒入口与修复候选

10/5 后续[模拟器复验](2026-10-05-simulator-retest.md)补齐合成相册视频导入 / 播放，发现并修复转录详情返回时的识别方式重置；已重新生成最终候选。本文保留较早提醒候选的原始证据，不把旧归档当作最新上传包。

## 结果

修复「开启计划提醒只有通知提示，没有地方设置时间」：今天右上角 → 计划提醒 → 选择规划 → 设置日期和时间。设置、清除及撤销沿用现有 plan ID，不生成第二条任务。系统拒绝通知时仍保留排期，返回前台重新授权后重建通知。执行中的关联规划、完成/取消/归档任务和过去日期不进入设置列表。

提醒与此前的[文件转录修复](2026-10-04-transcription-file-repair.md)一起生成 Release 1.0（18）候选。Archive 已成功；最终导出仍被 Apple 开发者协议更新阻止，没有成功上传证据，用户手机尚未确认拿到这组修复。

## 实际验证

| 验证 | 结果 / 范围 | 证据 |
| --- | --- | --- |
| 提醒专项 | 11 项通过、0 skip、0 失败：身份、移动/清除/撤销、无效或陈旧编辑不写、执行/完成筛选、断权保留、重新授权、授权等待中撤销、最近 32 条、重启保留、实际系统通知入队 | `/private/tmp/tough-reminders-20261005-candidate18-clean.xcresult`；`.runtime/reminders-20261005/candidate18-clean.log` |
| 提醒原生操作 | 1 项通过：菜单、空态/关闭、创建任务、选择分钟、取消不保存、保存后显示时间、撤销、重新保存、清除、返回今日仍有任务 | 同一构建 18 result bundle；iPhone 17 Pro 模拟器，iOS 26.5 / 23F77，合成数据 |
| 今日队列回归 | 3 项领域 + 1 项 UI 通过：开始、暂停补位、完成/恢复、累计与跨天统计、快速新增 | `/private/tmp/tough-reminders-20261005-serial.xcresult`；此批另含 9 项早期提醒专项 + 1 项提醒 UI，共 14 项通过 |
| 核心和包 | ToughTrialV2Checks、FocusTimelineCoreChecks、swift build 通过 | `.runtime/reminders-20261005/{core-checks,compatibility-checks,package-build}.log` |
| Mac 兼容 | 原生 Mac 构建成功；未在 Mac 操作通知或设置页 | `.runtime/reminders-20261005/mac-build.log` |
| 发布候选 | 主 App 与 LiveActivity 均签名校验通过，版本均为 18；ITSAppUsesNonExemptEncryption=false | `/private/tmp/ToughTrial-20261005-18-reminders.xcarchive`；`.runtime/reminders-20261005/archive18.log` |

实际系统通知测试使用 UNUserNotificationCenter，确认合成请求已进入 pending 队列且触发时间正确；测试结束只取消该测试请求。没有等待锁屏弹出、声音或 Focus 模式展示，不把入队当作真机到点提醒验收。

最终原生画面：[设置时间](assets/2026-10-05-plan-reminders/plan-reminder-time-editor.png)、[保存后](assets/2026-10-05-plan-reminders/plan-reminder-saved.png)、[空态](assets/2026-10-05-plan-reminders/plan-reminders-empty.png)。来自生产 SwiftUI / V2Theme，使用合成任务，不是独立重绘稿。模拟器 Debug 与 Release archive 都使用候选构建号 18，但二进制及平台不同，不宣称是手机实拍。

候选源码清单（185 个 Swift/配置文件）的 SHA-256：`45e4deaa786d06922803789ac186f322403a80dd18edb917e1c3cc6b2d00f94a`，本机清单位于 `.runtime/reminders-20261005/candidate18-sources.json`。此清单对应源码候选，不是发布包摘要或干净 Git commit。

## 交互范围与未完成项

- 实际点按：今天菜单、提醒入口、规划行、日期时间控件的分钟轮、取消、保存、清除、撤销、关闭；另通过今日队列回归。
- 空态已操作；过期时间与陈旧编辑通过领域拒绝测试。日期轮/小时轮、大字/VoiceOver、长规划列表尚未逐一操作。
- 通知拒绝、重新授权与等待授权期间撤销通过注入响应；系统通知入队通过实际 API。打开系统通知设置及系统设置返回的手动流程尚未点按验收。
- 真实中文视频的 Apple 模型识别证据仍是 10/4 的 Mac 合成素材；用户原视频、iPhone 13 Pro 上的识别、真实 FunASR/AI 调用尚未验收。未复制私人 records.json，未调用付费转录服务。

## 测试失败与边界

- 最初测试的 startExecution 参数名不符实际接口，修正测试调用后编译通过。
- 原生 picker 的可选值是 `31`，辅助描述是 `31 minutes`。初次 UI 测试误用描述作为可选值而失败；修正输入后按保存结果验证通过。
- 一次旧测试收尾停滞时过早启动复验，结果包未完整写入；两次运行已结束，不计入通过证据。后续关闭并行、使用干净构建目录完成串行验证。
- 单方法筛选的候选 18 运行出现 XCTest 宿主建立连接前停滞；该批 UI 虽通过，整批结果仍失败。最终使用完整提醒测试类、干净目录运行得到 12 项全部通过，不以未执行的宿主测试作为通过。

## 分发状态

10/5 初次分发检查与最终同包候选导出都返回 `PLA Update available` 与缺少 iOS Distribution 签名证书，退出码均为 70。日志为 `.runtime/reminders-20261005/export-permission-check.log` 和 `export18.log`。Apple 要求账号持有人在开发者账户确认最新协议；未代为接受协议或切换团队。当前没有成功导出的 TestFlight IPA，也没有上传/手机更新完成证据。

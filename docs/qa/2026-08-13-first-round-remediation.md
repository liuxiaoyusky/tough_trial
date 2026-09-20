# Tough Trial 首轮核心 UI 修复验收报告

- 日期：2026-08-13
- 分支：`codex/public-release-ready`
- 修复前报告：`docs/qa/2026-08-13-full-user-ui-acceptance.md`
- 本轮范围：P1-1、P1-2、P1-3、P2-3 最小规则、P2-4
- 结论：**本轮范围通过；完整文字 spec 仍未全部完成**

## 结论摘要

本轮已补齐“看见任务 -> 安排任务 -> 执行今天 -> 回想记录”的核心断点。iPhone 17e 与 iPhone 17 均完成完整 UI 套件，分别为 14/14 通过；六条本轮关键旅程又在两种尺寸各运行一次并保存截图，分别为 6/6 通过。核心检查、兼容检查、Swift Package 构建和 iOS 测试构建均通过。

这份结论只关闭本轮约定的五项 finding。P2-1 状态与控制合并、P2-2 回想整理草稿、P3-1 地图探索提示仍按计划延期，不能据此宣称完整 spec 已交付。

## Finding 结果

| Finding | 结果 | 已验收行为 |
| --- | --- | --- |
| P1-1 结构 / 鱼骨新增 | 通过 | 取消不写入；结构新增到当前根；鱼骨新增为未归类根；创建后连续终止并重启两次仍可检索 |
| P1-2 任务详情 / AI 计划 | 通过 | 节点正文打开详情，展开控件保持独立；计划页携带同一任务上下文；只有 `加入计划` 才产生正式计划项 |
| P1-3 空状态 Zen | 通过 | 可直接开始未关联 Zen，也可搜索已有任务后开始；关闭后会话保留，结束后时间段写入 |
| P2-3 明确时间解析 | 通过 | `15:00`、`下午三点`、`下午三点半`进入对应今天时间点；普通输入保持未定时，不再伪造提交时刻 |
| P2-4 Zen 模态隔离 | 通过 | Zen 中只有一组暂停 / 结束语义；Tab Bar 与底层今天页控件不在辅助功能树中；退出后今天页恢复 |

## 自动化证据

```text
swift run ToughTrialV2Checks       passed
swift run FocusTimelineCoreChecks  passed
swift build                        passed
xcodebuild build-for-testing       passed

iPhone 17e, iOS 26.5, full UI      14/14 passed
iPhone 17,  iOS 26.5, full UI      14/14 passed (independent QA)
iPhone 17e, remediation evidence    6/6 passed
iPhone 17,  remediation evidence    6/6 passed
```

关键结果包：

- `/private/tmp/tough-trial-full-iphone17e.xcresult`
- `/private/tmp/tough-trial-independent-iphone17.xcresult`
- `/private/tmp/tough-trial-remediation-evidence-iphone17e.xcresult`
- `/private/tmp/tough-trial-remediation-evidence-iphone17.xcresult`

六条本轮正式 UI 用例：

1. `testTaskCaptureInStructureAndFishbonePersistsAfterRelaunch`
2. `testTaskDetailOpensContextualPlanAndWritesOnlyOnAccept`
3. `testEmptyTodayZenSupportsUnlinkedAndLinkedSessions`
4. `testTodayQuickAddParsesExplicitTimeAndLeavesPlainInputUntimed`
5. `testZenModalAccessibilityTreeExcludesTodayLayer`
6. `testEndToEndSeeArrangeExecuteRecallAndRelaunch`

## 双尺寸截图

| 状态 | iPhone 17e | iPhone 17 |
| --- | --- | --- |
| 结构新增入口 | [截图](2026-08-13-first-round-remediation/iphone17e/remediation-task-capture-structure.png) | [截图](2026-08-13-first-round-remediation/iphone17/remediation-task-capture-structure.png) |
| 结构新增结果 | [截图](2026-08-13-first-round-remediation/iphone17e/remediation-task-created-structure.png) | [截图](2026-08-13-first-round-remediation/iphone17/remediation-task-created-structure.png) |
| 鱼骨未归类入口 | [截图](2026-08-13-first-round-remediation/iphone17e/remediation-task-capture-fishbone.png) | [截图](2026-08-13-first-round-remediation/iphone17/remediation-task-capture-fishbone.png) |
| 任务详情 | [截图](2026-08-13-first-round-remediation/iphone17e/remediation-task-detail.png) | [截图](2026-08-13-first-round-remediation/iphone17/remediation-task-detail.png) |
| 任务上下文计划 | [截图](2026-08-13-first-round-remediation/iphone17e/remediation-task-plan-context.png) | [截图](2026-08-13-first-round-remediation/iphone17/remediation-task-plan-context.png) |
| 未关联 Zen | [截图](2026-08-13-first-round-remediation/iphone17e/remediation-zen-unlinked.png) | [截图](2026-08-13-first-round-remediation/iphone17/remediation-zen-unlinked.png) |
| 关联任务 Zen | [截图](2026-08-13-first-round-remediation/iphone17e/remediation-zen-linked.png) | [截图](2026-08-13-first-round-remediation/iphone17/remediation-zen-linked.png) |
| 明确时间 / 未定时 | [截图](2026-08-13-first-round-remediation/iphone17e/remediation-today-explicit-and-untimed.png) | [截图](2026-08-13-first-round-remediation/iphone17/remediation-today-explicit-and-untimed.png) |
| Zen 单层模态 | [截图](2026-08-13-first-round-remediation/iphone17e/remediation-zen-modal.png) | [截图](2026-08-13-first-round-remediation/iphone17/remediation-zen-modal.png) |
| 执行到回想已保存 | [截图](2026-08-13-first-round-remediation/iphone17e/remediation-recall-loop-saved.png) | [截图](2026-08-13-first-round-remediation/iphone17/remediation-recall-loop-saved.png) |

截图由生产等价持久化旅程生成，可能含此前自动化创建的测试记录。它们用于核对状态、布局与两种尺寸适配，不是商店宣传素材。

## 保留项与风险

- 延期：P2-1 今天页状态与开始 / 暂停控件合并。
- 延期：P2-2 回想页用户主动触发的 `整理草稿`。
- 延期：P3-1 任务地图横向可探索提示。
- 未验证：真实 OpenAI-compatible 在线服务的超时、错误、重试与供应商兼容性。
- 未验证：VoiceOver 人工走查、超大 Dynamic Type、深色模式、横屏、真机触感和 Apple Pencil。
- Xcode 日志仍有 debugger 版本和模拟器 WebCore / WebKit 重复 accessibility class 警告；本轮测试未出现因此导致的失败或崩溃。

## 验收决定

本轮核心 MVP 修复可以关闭，版本可继续用于内部体验。下一轮应从延期的 P2-1、P2-2、P3-1 中重新冻结范围；发布前仍需真实在线 AI、真机和无障碍专项验收。

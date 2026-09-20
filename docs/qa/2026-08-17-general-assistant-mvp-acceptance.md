# 通用助手 MVP 验收记录

日期：2026-08-17

## 结论

- **本地 MVP 候选：Conditional Pass**
- **代码阻断项：无**
- **人工硬边界：真实供应商联调、WebView 内外滚动手感、系统浏览器跳转**

原 `计划` 页面已经升级为全屏、多 Session 的通用助手。聊天、只读网页与本地
查找、Trace、计划 artifact、显式确认写入、多个内嵌 WebView 和状态恢复已完成。
确定性自动化全部通过，但没有把 fixture 回复当成真实供应商验收，也没有把控件
存在当成真机手势质量。

## 最终自动验证

在 iOS 26.5 `iPhone 17` 模拟器执行：

- `swift run ToughTrialV2Checks`：通过。
- `swift run FocusTimelineCoreChecks`：通过。
- `swift build`：通过。
- `/opt/homebrew/bin/xcodegen generate`：通过，生成后 Git 无差异。
- `xcodebuild build ... CODE_SIGNING_ALLOWED=NO`：通过。
- `ToughTrialV2AppTests`：`19/19` 通过。
- `ToughTrialUITests`：`22/22` 通过，耗时约 8 分 32 秒。
- 浏览器自动操作静态扫描：无 `evaluateJavaScript`、`WKScriptMessageHandler`、
  script-message bridge、模拟点按或表单提交路径。

完整 XCTest 结果：

`~/Library/Developer/Xcode/DerivedData/ToughTrial-deefjtoogisgribpqgvuttdvzxhf/Logs/Test/Test-ToughTrial-2026.08.17_22-16-18-+0800.xcresult`

## 17 条标准映射

| # | 状态 | 证据 |
| --- | --- | --- |
| 1 | passed | `testPrimaryNavigationAndAssistantPresentation` 验证新 Session 直接进入输入与一键入口。 |
| 2 | passed | 同一测试验证聊天、网页、本地资料、计划四个入口；入口只发送示例意图，不保存模式。 |
| 3 | passed | `testAssistantSessionsKeepConversationIsolatedAndSearchable` 验证两个 Session 独立对话、搜索和切回。 |
| 4 | passed | Session UI 测试、workspace round-trip、浏览器 ownership、Provider snapshot 和计划 artifact 测试共同覆盖隔离。 |
| 5 | needs provider confirmation | 确定性多轮循环已覆盖普通回答、网页、本地查找与计划工具；真实模型的选择质量尚未联调。 |
| 6 | passed | `testAssistantRendersTraceSourcesAndFullSessionDetails` 验证搜索回答包含可点按来源。 |
| 7 | passed | `testAssistantSupportsMultipleInlineBrowsers` 验证来源下方展开；实现高度为 `max(180, availableHeight * 0.25)`。 |
| 8 | needs device confirmation | 内外层分别拥有自己的 ScrollView，未实现边界手势转移；实际嵌套滚动手感需真机操作。 |
| 9 | passed | 双 WebView UI 测试验证两个来源同时展开；Controller key 为 `(sessionID, browserID)`。 |
| 10 | needs device confirmation | 同一 WKWebView 在内嵌/全屏间重挂载，URL、历史和滚动状态有持久化与竞态测试；真实滚动后缩放手感仍需人工确认。 |
| 11 | needs device confirmation | 全屏工具栏和 `UIApplication.open` 路径已构建并自动检查，实际离开 App 的系统跳转未自动执行。 |
| 12 | passed | 双 WebView UI 测试在两个网页展开时确认 `assistant.composer` 仍存在。 |
| 13 | passed | Trace 摘要在消息中折叠展示，完整 Trace 在会话详情中展示，UI 测试覆盖两层。 |
| 14 | passed | typed Trace、凭证模式脱敏和 forbidden-field 检查通过；不保存模型内部思维。 |
| 15 | passed | `testTaskDetailOpensContextualAssistantAndWritesOnlyOnAccept` 验证确认前不可见、点击 `加入计划` 后才写入。 |
| 16 | passed | 请求失败、取消、损坏存储、写入失败、重试和冷启动中断恢复均有自动测试，Session 不丢失。 |
| 17 | passed | 无 JavaScript-to-native bridge、脚本执行、模拟点击、表单提交或自动滚动网页能力；只允许用户手势导航。 |

汇总：`13 passed`、`1 needs provider confirmation`、`3 needs device confirmation`、
`0 blocked`。

## 视觉证据

| 状态 | 截图 |
| --- | --- |
| 空 Session | [assistant-empty.png](assets/general-assistant/assistant-empty.png) |
| 多 Session | [assistant-session-list.png](assets/general-assistant/assistant-session-list.png) |
| Trace 与来源 | [assistant-conversation-trace.png](assets/general-assistant/assistant-conversation-trace.png) |
| 计划 artifact | [assistant-plan-artifact.png](assets/general-assistant/assistant-plan-artifact.png) |
| 两个内嵌网页 | [assistant-two-inline-browsers.png](assets/general-assistant/assistant-two-inline-browsers.png) |
| 全屏网页 | [assistant-fullscreen-browser.png](assets/general-assistant/assistant-fullscreen-browser.png) |

## 已处理的独立审查问题

1. WebKit 回调不再替换整份浏览器状态，只合并 URL、历史和滚动位置，避免覆盖
   较新的全屏/展开状态。
2. 删除 Session 会释放对应 WKWebView；内存告警会淘汰已收起实例。
3. Registry 查询已有 Controller 时保持纯读取，避免在 SwiftUI `body` 更新期间发布。
4. 动态网页的滚动恢复改为有限次数重试。
5. 顶层导航显式限制为 `http/https`，`target=_blank` 在当前 WebView 打开。

## 明确边界与剩余风险

- 网页 Cookie、Local Storage 和登录身份使用 App 级 `WKWebsiteDataStore.default()`；
  不同聊天 Session 隔离消息、Trace、URL、滚动和 artifact，但不重复隔离网站账号。
- WebView 内容不获得本地任务、Memory、Keychain 或原生工具权限。
- 首版没有 Agent 自动点击、填写、登录、提交或控制网页的能力。
- 只读网页工具仍保留 MVP 的 DNS rebinding 风险，未实现 DNS 结果固定。
- iOS 26.5 模拟器报告 WebCore/WebKit Accessibility bundle 重复类警告；完整测试
  未因此失败，真机仍需观察。

## 人工门禁

### 真实供应商

使用一个用户确认的有效 Provider 和模型，记录 Provider 标签、模型、时间和结果，
不记录 Key、Header、Cookie 或本地资料内容：

1. Session A 普通聊天。
2. 查询当前网页信息并打开一个来源。
3. Session B 生成计划 artifact。
4. 切回 Session A，确认消息和网页状态未串用。
5. 回到 Session B，点击确认后检查任务/日程仅在此时写入。

### 真机交互

1. 在内嵌网页内部滚动，再从网页外部滚动对话，确认手势不会越界接管。
2. 滚动网页后全屏、缩小，确认 URL、回退和位置保持。
3. 点击系统浏览器按钮，确认 Safari 正确打开且 App 不追踪后续浏览。

完成这两组人工门禁后，本地 MVP 可以从 `Conditional Pass` 更新为 `Pass`。

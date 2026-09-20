# 助手输入与视觉更新

用户要求：听写切换移出右上角更多菜单；FunASR 改为录完后转写；助手页面与其他主页面风格一致。

## 本轮交付

- 输入区常驻听写方式菜单和语音设置按钮，可直接选择苹果原生/FunASR，选择持续保存；更多菜单移除重复语音入口。
- FunASR 使用官方非实时 HTTP 接口，整段 WAV/Base64 上传并关闭 SSE。模型标识仍为 `fun-asr-realtime`，但 App 录音期间不发请求，也不展示实时转写。点完成后才上传和调用助手。
- 本机内存暂存单段录音，显示时长，5 分钟停录等用户提交；失败可重试同一段音频，取消/离开/后台清理暂存，迟到结果不能提交。密钥更新后重试读取当前设置。
- 助手复用 V2Theme：左对齐标题、暖色背景、圆角按钮/快捷卡片、输入区和消息样式；保留全屏导航和实际日程行为。

## 检查与边界

- 2 项 HTTP/WAV/响应解码检查通过；新增检查先验证缺少实现时失败，再实现至通过。日志 `/private/tmp/tough-trial-recorded-{red,green}.log`。
- 3 项录后转写生命周期 + 9 项苹果识别检查通过，覆盖录音零上传、一次完成一次提交、失败重试、取消迟到结果、时长上限与苹果路径隔离。日志 `/private/tmp/tough-trial-recorded-ios-final.log`。
- 最终 5 项 UI 回归通过：四页视觉基线、输入区直接切换/设置与重开恢复、日程执行撤销、等待取消、严格确认。日志 `/private/tmp/tough-trial-assistant-style-after.log`；结果包 `/private/tmp/tough-trial-recorded-sim/Logs/Test/Test-ToughTrial-2026.09.08_11-02-35-+0800.xcresult`。
- `swift run ToughTrialV2Checks` 通过，日志 `/private/tmp/tough-trial-recorded-core.log`。最终签名真机测试包构建结果见 `/private/tmp/tough-trial-assistant-final-device-build.log`。
- 已人工查看今天/助手的新旧模拟器截图。手机本轮 unavailable，**尚未安装此更新、验证真实麦克风或用实际百炼 Key 调用新 HTTP 接口**。本轮通过的是请求协议、受控生命周期、编译和模拟器 UI，不能当成真实服务质量验收。

## 截图

[更新后的助手](../assets/assistant-style/2026-09-08-assistant.png) · [对话状态](../assets/assistant-style/2026-09-08-conversation.png) · [更新前](../assets/assistant-style/2026-09-08-before.png)

接口：[FunASR 非实时 HTTP](https://help.aliyun.com/zh/model-studio/non-real-time-speech-recognition-for-fun-asr-realtime)，[5 分钟音频规格](https://help.aliyun.com/zh/model-studio/asr-model)。

## 追加：持续对话与 Thinking 状态

用户追问持续聊天、Thinking 等后续状态；本次补齐助手正文层次、真实 activity 处理卡、折叠执行记录、引用来源及内嵌网页、计划草稿、错误/取消状态与会话列表的容器样式。零步骤记录不再占据处理页面；有步骤的记录依然可展开。没有增加模型内部思维展示或虚构进度。

- 7 项 UI 回归通过（多轮会话与搜索/隔离、来源和步骤展开、失败、双网页、日程执行撤销、处理中取消、严格确认）。日志 `/private/tmp/tough-trial-conversation-style.log`，结果包 `Test-ToughTrial-2026.09.08_15-23-30-+0800.xcresult`。
- 计划草稿编辑与双网页在最终圆角改动后补验 2 项通过，日志 `/private/tmp/tough-trial-conversation-artifacts.log`，结果包 `Test-ToughTrial-2026.09.08_15-25-44-+0800.xcresult`。
- 隐藏零步骤提示后补验处理中/停止 1 项通过，日志 `/private/tmp/tough-trial-thinking-final.log`，结果包 `Test-ToughTrial-2026.09.08_15-26-43-+0800.xcresult`。
- 上述结果包均位于 `/private/tmp/tough-trial-recorded-sim/Logs/Test/`。人工检查模拟器截图；测试使用确定性回复/延迟/失败样例，证明界面与交互，不证明真实模型质量或时延。本次追加未装真机。

| 状态 | 模拟器截图 |
| --- | --- |
| 多轮聊天 | [查看](../assets/assistant-style/2026-09-08-assistant-multiturn.png) |
| Thinking | [查看](../assets/assistant-style/2026-09-08-assistant-thinking.png) |
| 整理日程中 | [查看](../assets/assistant-style/2026-09-08-schedule-progress.png) |
| 执行记录展开 | [查看](../assets/assistant-style/2026-09-08-assistant-conversation-trace.png) |
| 引用来源 | [查看](../assets/assistant-style/2026-09-08-assistant-sources.png) |
| 内嵌网页 | [查看](../assets/assistant-style/2026-09-08-assistant-two-inline-browsers.png) |
| 计划草稿 | [查看](../assets/assistant-style/2026-09-08-assistant-plan-artifact.png) |
| 日程结果 | [查看](../assets/assistant-style/2026-09-08-assistant-schedule-result.png) |
| 严格确认 | [查看](../assets/assistant-style/2026-09-08-assistant-confirmation.png) |
| 请求失败 | [查看](../assets/assistant-style/2026-09-08-assistant-error.png) |
| 已停止 | [查看](../assets/assistant-style/2026-09-08-assistant-cancelled.png) |

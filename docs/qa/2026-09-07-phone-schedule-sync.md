# iPhone 日程与 GitHub 同步验收

设备：用户的 iPhone 13 Pro（sky），2026-09-07 晚间重新连接。当前签名构建已安装；文字服务使用已授权的 GLM-5.3 Flash Coding Plan。本文的 GitHub 测试不使用 Files/iCloud 授权。

## 已通过

1. **真实 GLM 的 App 日程链路**：`V2AssistantLiveScheduleTests` 在实际手机上运行，1 项通过、0 失败、0 跳过，19.682 秒。经过实际助手 Store、路由客户端、日程客户端和持久化引擎，覆盖连续改期、稳定任务/排期身份、回执、高亮、撤销、严格确认、重复确认及 Trace。此项重建 JSON Store，尚不代表实际退出 App 后重新打开。
2. **手机与 Mac 并发修改同一私有 Markdown**：`V2PhoneMacSyncTests` 与独立的 `scripts/phone_mac_sync_editor.py` 实际往返 GitHub，1 项通过、0 失败、0 跳过，14.532 秒。手机增加“两小时上限”，Mac 改标题并增加“必须配图”；手机调用真实 GLM 处理备注冲突，严格确认之前不写入，确认后保留 3 个示例/配图/两小时要求。撤销恢复冲突前任务，重建 Store 后可再次处理；注入一次断网失败后重载并通过真实网络重试。最终两条合成任务，重复同步不改变 SHA，Mac 下载文件字节与 SHA 一致。
3. **实际模型配置保存**：通过一次性配置将用户已选择的 GLM 服务保存到手机 App 的正常设置与钥匙串，并重新加载检查服务、模型和凭据。凭据不写入测试源码、安装包、xctestrun 或日志；设备临时配置读取后删除，本机副本也已删除，随后设备 tmp 列表确认无配置文件。

私有合成文件：[phone-mac 验收 Markdown](https://github.com/liuxiaoyusky/tough-trial-sync/blob/main/acceptance/phone-mac-42577130-fb37-46cb-adb0-1c872250c722.md)。最终 SHA：`b2e880fc707b86a0bfe09a42f540580dcd9a599d`。测试使用独立临时引擎；没有将手机原有数据替换为测试数据，也没有把正常 App 绑定到该合成文件。仓库主文件 `schedule.md` 不受此轮写入影响。

## 证据

- 构建：`/private/tmp/tough-trial-device-current-build.log`、`/private/tmp/tough-trial-phone-sync-build.log`，均 `TEST BUILD SUCCEEDED`。
- 真实 GLM：`/private/tmp/tough-trial-device-live-chat.log`；结果包 `~/Library/Developer/Xcode/DerivedData/ToughTrial-fbwddmjfiuwudqgegxzoaoteesxn/Logs/Test/Test-ToughTrial-2026.09.07_20-21-37-+0800.xcresult`。
- 手机同步：`/private/tmp/tough-trial-phone-mac-device.log`；结果包 `~/Library/Developer/Xcode/DerivedData/ToughTrial-gdyefeilbmkhyvfqulsrqctwfjkg/Logs/Test/Test-ToughTrial-2026.09.07_20-29-29-+0800.xcresult`。
- Mac 修改与下载：`/private/tmp/tough-trial-phone-mac-editor.log`、`/private/tmp/tough-trial-phone-mac-42577130/result.json`；后者记录初始、Mac 修改、手机最终三个 SHA 和下载校验结果。

## 继续验证

- 真实手机界面新增、实际进程退出/重开、列表和回执、严格确认与撤销。
- 固定测试语音经手机麦克风输入，点击完成后交给真实 GLM 执行并撤销；这只验证该样本的链路，不代替自然口述质量验收。
- 外部文件/iCloud/bookmark 属于可选路径，单独保留待验收，不作为 GitHub 主线前置条件。

20:32 界面测试首次启动遇到系统锁屏；解锁后运行，在任务页查找新任务标题的 UI 断言失败，完整重启场景未通过。实际已生成的专用任务于 21:22 使用原始回执撤销，检查其他任务完全不变。不能把这轮记为完整界面通过。

## 21:22：修复用户实际发现的无可用回复

用户询问“帮我看看我今天还有什么任务”时，手机会话显示本地查询成功，下一次模型调用报 `操作包含不适用的字段`，最终显示通用错误标题“没有收到可用回复”。这不是语音未转写，也不是缺少模型凭据。

- 复现：只读回答携带残留 query/url、本地查询携带说明文字时，旧解析器即使已识别明确 action 仍整条拒绝。新增合成回归样本在旧代码报同样错误，日志 `/private/tmp/tough-trial-readonly-fields-red.log`。
- 修复：answer 只取 text、local_search 只取 query；多余字段不触发其他工具。空必要字段、未知 action、无效结构继续拒绝，schedule 写入仍要求不适用字段为空。完整 `ToughTrialV2Checks` 通过，日志 `/private/tmp/tough-trial-readonly-fields-green.log`。
- 真机：修复版签名构建并安装；实际 UI 输入用户原句，模型→本地查询→模型回答成功，5.153 秒，返回正常文字且没有写入回执。导出的手机会话再次确认最后回复 complete、trace succeeded。
- 苹果入口：真实手机打开“助手 → … → 语音输入”，可选苹果原生并显示准备中文模型，不要求百炼 Key，截图已人工查看。检查时原设置为 FunASR，测试后恢复原选择；此项验证入口与切换，没有重新测试苹果麦克风识别质量。
- 本轮 1 项回执清理 + 1 项只读查询/苹果切换 UI 测试通过，0 失败、0 跳过。日志 `/private/tmp/tough-trial-readonly-phone-acceptance.log`；结果包 `~/Library/Developer/Xcode/DerivedData/ToughTrial-hjjlcovyihqapjfwbimydpoavarf/Logs/Test/Test-ToughTrial-2026.09.07_21-22-18-+0800.xcresult`。本次通过不替代上面的完整日程重启失败记录。

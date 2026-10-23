# 2026-10-05 · 提醒与视频转录模拟器复验

## 结果

实际测试了原生 iOS App 的提醒设置、今日队列、相册视频导入、原文件播放及转录失败后的交互。发现并修复了「选苹果原生 → 查看原文件 → 返回」时识别方式跳回全局默认云端的问题。现在选择只在详情首次建立时初始化，返回页面不会覆盖用户当前选择；仍不提前改写已有逐字稿的来源。

苹果模型在此模拟器不可用，真实识别测试明确跳过；不能据此关闭用户原视频或 iPhone 13 Pro 的识别反馈。没有调用 FunASR/AI 服务，也没有读取个人转录库。

## 环境与实际结果

- iPhone 17 Pro 模拟器 `104D4750-9D7F-4665-A982-C272AEFD3EC1`，iOS 26.5 / 23F77，Xcode 27.0 / 27A266a。只操作本项目模拟器，未重启其他项目设备。
- Debug 候选版本 1.0（18）。使用合成任务、静音 WAV 和约 8 秒的合成中文 MP4；不是用户视频或手机实拍。

| 验证 | 实际结果 | 本机证据 |
| --- | --- | --- |
| 提醒 / 今日 / 转录合批，新增返回修复之前 | 39 项：38 通过、0 失败、1 跳过。含提醒 11 单元 + 1 UI、今日 3 单元 + 8 UI、转录 13 单元通过 + 1 模型跳过 + 2 UI | `/private/tmp/tough-trial-20261005-simulator-reboot.xcresult`；`.runtime/simulator-20261005/{reboot.log,summary.json}` |
| 返回时识别方式重置，修复前回归 | 单项实际到达返回断言并失败，确认本地选择被覆盖 | `/private/tmp/tough-trial-20261005-provider-return-red-isolated.xcresult`；`provider-return-red-isolated.log` |
| 修复后转录专项 | 16 项：15 通过、0 失败、1 模型跳过。包含新的返回选择断言、完整视频音轨读取、文件保留、重试 / 取消保存边界、摘要及逐字稿编辑、删除取消 / 确认 | `/private/tmp/tough-trial-20261005-provider-return-fixed.xcresult`；`provider-return-fixed{.log,-summary.json}` |
| Mac 共用 View | 原生 Mac 构建通过；未宣称 Mac 全交互验收 | `.runtime/simulator-20261005/mac-provider-return-build.log` |

两批成功结果有重叠，不相加为独立测试总数。返回修复只改 `V2TranscriptionDetailView`，提醒源码没有再变。今日 UI 类包含部分任务视图用例；这些有限操作不等于整套任务模块通过当前人工验收。

## 已操作的交互

- 提醒：菜单入口、空态关闭、快速新增规划、提醒行、分钟轮、取消不写入、保存及权限允许、撤销、再保存、清除、返回今日仍保留任务。真实 UNUserNotificationCenter 测试确认请求入队和时间；没有等待锁屏到点通知。
- 转录：库中记录、苹果方式选择、开始 / 继续入口、明确模型不可用反馈、全文与原文件、录音播放 / 暂停、返回后方式仍选苹果、摘要取消 / 保存、逐字稿保存、删除取消 / 确认和空库。
- 另在原生界面手动通过系统 PhotosPicker 选中合成 MP4，实际导入并进入「相册视频」详情。明确选择苹果后开始，显示模型不可用；打开原视频，播放进度实际到达 `0:08`，返回时观察到原重置故障。后续自动回归用同一个详情返回路径验证修复。未把播放进度当作已试听音频或已成功识别。
- 视频专项走生产 `importMedia → 音轨 M4A → PCM`，确认读取完整、音频非空、末尾不再额外读取出错、原 MP4 保留。真实模型测试由 `SpeechTranscriber.isAvailable == false` 明确跳过，不把没有文字当成功。

原生截图：[提醒时间](assets/2026-10-05-simulator/plan-reminder-time-editor.png)、[保存后](assets/2026-10-05-simulator/plan-reminder-saved.png)、[失败与重试](assets/2026-10-05-simulator/transcription-readable-retry.png)、[原文件](assets/2026-10-05-simulator/transcription-original-retained.png)、[视频播放器](assets/2026-10-05-simulator/photo-video-original-player.png)。[返回方式重置](assets/2026-10-05-simulator/photo-video-return-provider-reset.png)是修复前故障证据；修复后选择状态通过 XCTest 实际断言。

## 测试准备失败记录

- 最早一次合批停在 XCTest 宿主连接前；中断并重启本项目模拟器后，用独立干净构建目录完成 39 项。中断批不算通过。
- 首次新增返回测试未找到测试草稿，在准备步骤失败，未到达返回断言；保留 `provider-return-red.xcresult` 和日志。失败后 `simctl diagnose` 长时间收集，结束本次诊断子进程后才启动下一批。
- UI helper 显式先结束手工启动的 App 再以 fixture 环境启动。随后隔离单项确实到达返回断言并失败，修复后同一路径通过。最初草稿缺失原因尚未单独证实，不将它解释为业务记录丢失。
- 后续关闭额外失败诊断收集，不关闭断言或跳过回归。没有重叠运行多个测试进程。

## 候选、分发与未完成项

最终源码清单为 185 个 Swift / 配置文件，SHA-256 `4910533764a523669e9dc8fe8724a196ea8d8006770ad93bbdf96169a478b9f6`，算法和逐文件摘要见 `.runtime/simulator-20261005/candidate18-retested-sources.json`。它是源码候选摘要，不是安装包摘要或干净 Git commit。

最终 Release archive 已按该源码重新生成成功，路径 `/private/tmp/ToughTrial-20261005-18-simulator-retested.xcarchive`，日志 `.runtime/simulator-20261005/archive18-retested.log`。主 App / LiveActivity 均为 1.0（18），严格签名校验通过；主 App 的 ITSAppUsesNonExemptEncryption=false。归档后再次比对 185 个源码摘要，未变化。此前提醒归档不含本次返回修复，不应继续作为最新候选上传。

后续同日按用户反馈修改了今日整页滚动、统一时间线和完成项呈现。上述归档不含这些后续布局，保留为当时的转录/提醒候选；当前源码的今日验证见 [整页滚动 QA](2026-10-05-today-scroll-timeline.md)。后续分发需要重新归档，不能继续把上述 archive 当作当前工作区的最新安装包。

本轮未重复导出或上传：上一次实际导出仍是 `PLA Update available` 和缺少 iOS Distribution 签名证书，见[提醒候选分发记录](2026-10-05-plan-reminders-repair.md)。等待账号持有人处理 Apple 协议，没有手机更新成功证据。

仍需真机：用户原视频 / 苹果模型识别、长视频及锁屏后台、真实 FunASR/AI、到点提醒与系统设置往返。日期 / 小时轮、大字 / VoiceOver、真实文件选择器及搜索也未在这轮逐项操作。10/4 的 Mac 合成中文真实模型结果保留在[原转录 QA](2026-10-04-transcription-file-repair.md)，不替代 iPhone 验收。

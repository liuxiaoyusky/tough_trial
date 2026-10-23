# 2026-10-04 · 转录文件故障修复

## 结论与范围

用户在 iPhone 13 Pro / Tough Trial 1.0（17）反馈：相册视频 Apple 转录无文字，FunASR 等待后显示 Operation Interrupted；标题及分段控件对比度不足。本轮修复文件读取、苹果文件识别、断点/取消与文字保留，并验证原生界面。用户原视频和私人转录库未读取，FunASR/AI 付费服务未调用；不能据此断言用户原视频或云端生产服务已经验收。

## 可复现的实际故障

旧 PCM 读取器依赖再次读到 0 帧来判定 EOF。合成 48 kHz 双声道 WAV 在当前系统读到末尾后再次读取，抛 Foundation._GenericObjCError.nilError，最后一段未返回。短于 5 分钟的文件可能因此在第一次服务请求前失败。修复版按 framePosition/length 判断末尾，读取实际剩余帧并排空转换器；同一素材完整返回 9 段（探针用 1 秒分段），尾段 10,516 bytes。探针日志位于 `.runtime/transcription-20261004/pcm-{old,fixed}-probe.log`，均为合成素材，不含用户媒体。

Apple 旧配置在 Mac 合成素材上也可返回文字，因此不把 fastResults 或结果消费顺序当作已证实的原故障原因。文件路径现使用文件转录 preset、模型兼容格式、按需读取的 AnalyzerInput 序列和明确的 finalize；原音频/视频保留。AVAudioFile 打开/长度计算移出主线程，取消保留已保存文字，已删除的记录不会被最终结果重新创建。

## 行为修复

- 切换提供方不会先清空原逐字稿/摘要；新文字实际识别出来后才替换。
- 云端无文字的片段可以继续下一段；全空结果下一次仍从头重试。已有文字时，空前缀后失败不会抹掉它。
- 云端取消后迟到的响应不能写回；取消并删除不会恢复记录或媒体文件。
- 提取音轨、准备模型与识别分别显示实际阶段；暂停使用明确中文反馈，错误日志仅记录阶段、domain/code。
- 固定浅色纸张界面使用可读字体/颜色；新相册导入使用“相册视频”标题。未迁移或删除现有个人记录。

## 实际执行证据

| 验证 | 结果 | 证据 |
| --- | --- | --- |
| macOS 转录专项 | 13 项通过、0 失败；含真实苹果模型识别合成中文 MP4、保存分段与保留原件 | `/private/tmp/tough-transcription-20261004-mac-final.xcresult`；`.runtime/transcription-20261004/mac-final.log` |
| iOS 语音/转录单元回归 | 29 项通过；1 项真实模型测试因未传素材而明确 skip；0 失败 | `/private/tmp/tough-transcription-20261004-ios-final.xcresult` |
| iOS 原生交互 | 2 项通过：识别不可用反馈/重试入口、原录音播放/暂停；摘要取消/保存、逐字稿保存、删除取消/确认与空库 | 同一 iOS result bundle；模拟器 iOS 26.5，测试时系统深色外观 |
| 最终按钮颜色 | 单项操作回归通过，截图更新；主要交互逻辑与上一轮相同 | `/private/tmp/tough-transcription-20261004-ios-color.xcresult` |
| 核心基线 | ToughTrialV2Checks 通过 | `.runtime/transcription-20261004/core-checks.log` |
| 真机实际识别 | 独立诊断 App 编译成功，iPhone 13 Pro 锁屏阻止启动；没有识别通过证据 | `.runtime/transcription-20261004/device-model-2.log` |

原生截图：[失败与重试](assets/2026-10-04-transcription/transcription-readable-retry.png)、[原文件播放](assets/2026-10-04-transcription/transcription-original-retained.png)、[详情与删除取消](assets/2026-10-04-transcription/transcription-readable-detail.png)。截图使用测试记录；模拟器不支持 SpeechTranscriber，展示的是明确不可用反馈，不是实际中文识别成功画面。最后按钮配色改动后的重试与原文件截图已重新生成。

## 可见操作清单

| 页面 / 控件 | 本轮实际操作与限制 |
| --- | --- |
| 更多插件入口、库中记录、返回 | 点按进入详情/全文并返回，通过 |
| 识别方式、开始/继续 | 点按 Apple 与开始，模拟器不可用反馈/重试入口可见；FunASR 切换和真实服务待真机验证 |
| 处理中进度、暂停 | 阶段通过真实 Mac 模型；取消、迟到结果、断点的保存边界通过专项；本轮未在真机点按处理中暂停 |
| 摘要编辑、取消、保存 | 输入变更后取消保持原值；保存显示新值，通过 |
| 逐字稿编辑、保存 | 输入变更后保存显示同一文本，通过；该编辑器取消按钮未单独操作 |
| 播放/暂停原录音 | 实际点按，按钮反馈切换，通过；视频播放器/分段时间戳跳转未单独操作 |
| 菜单、删除、确认取消、确认删除 | 取消保持记录；确认删除返回空库，通过。弹出模式取消用外部点击；单元测试核对媒体删除 |
| 打开语音设置、重新生成摘要 | 控件存在；未点按 AI 请求或更改用户设置 |
| 文件/相册导入、搜索、搜索清除 | UI 入口存在；测试直接用真实合成文件走生产 importMedia；系统选择器、真实相册、搜索本轮未操作 |

这组界面没有撤销控件，删除前提供明确确认；无文件/无结果及删除后的空库状态已经覆盖。处理中的提供方禁用状态、模型下载暂停和云端无密钥反馈仍属后续运行验收。

## 测试边界与失败尝试

- 云端分段/重试/取消用注入的测试响应验证，覆盖实际 PCM 读取和本地保存，没有替代服务生产验收。
- Mac 实际模型测试必须通过 TEST_RUNNER_TOUGH_TRIAL_TRANSCRIPTION_TEST_MEDIA 传入 `/private/tmp` 的合成素材。直接设置普通环境变量没有传入 XCTest（明确 skip）；从 Documents 仓库路径复制测试素材的运行曾超时，移到临时目录后完整通过。不能把这些测试设置问题当成业务识别通过。
- UI 早期失败分别为错误标签缺失 identifier、测试错误地删掉逐字稿首空格，以及原生弹出确认用外部点击取消而无取消按钮。按实际控件/保存文本核对后通过。
- Apple 取消瞬间尚未发布/未最终确认的文字不承诺完整保留；保存后的最终片段保留。未专项测量超长视频、后台/锁屏、模型下载中断、真实相册权限与时间戳点击。
- 私人 records.json 的复制被自动审批拒绝，因可能包含逐字稿、摘要、文件名。已询问授权，未重试或绕过。

## TestFlight 修复版

本轮沿用用户此前对应用二进制及符号上传的明确授权（见 9/30 分发记录），准备 1.0（18）。Release archive 成功，主 App / LiveActivity 的版本均为 1.0（18），主 Bundle ID 为 com.skyliu.toughtrial；合规标记已在最终 archive 内确认。

- 最终 Archive：`/private/tmp/ToughTrial-20261004-18-final.xcarchive`。
- Archive 日志：`.runtime/transcription-20261004/archive-18-final.log`，明确 ARCHIVE SUCCEEDED、退出码 0。
- App Store Connect 导出失败：`.runtime/transcription-20261004/export-18.log`，退出码 70，包含 `No signing certificate "iOS Distribution" found` 与 `Unable to process request - PLA Update available`。
- 当前没有成功导出的 TestFlight IPA，也没有上传成功证据。不得表述为已经发布 18 号构建。
- 已请账号持有人在 Apple 开发者网站处理待接受协议。未代替用户接受协议、切换签名团队或绕过 Apple 限制。协议处理后需重新导出、验证签名和上传，并记录 Apple 返回结果。
- 手机仍确认的安装版本为 1.0（17）；独立诊断测试因锁屏未启动。

当前代码的 CryptoKit 使用仅为 SHA256 内容指纹，传输与凭据使用系统 URLSession/Keychain，没有引入自行实现的加密或端到端同步。[Apple 导出合规说明](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations) 将这类系统加密列为通常可豁免文档的情形；构建声明 ITSAppUsesNonExemptEncryption=false。后续实现端到端加密时必须重新核对该声明。

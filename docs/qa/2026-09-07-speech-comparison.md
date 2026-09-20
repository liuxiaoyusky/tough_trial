# 苹果原生与 FunASR：iPhone 真机对比

2026-09-07。**两种方式均已完成真实麦克风 → 点完成 → 真实 AI 回复；苹果实时输出配置已修正并验证。** 仅使用一条 9.809 秒中文合成录音，不能代表自然口述、方言或长录音的整体准确率。

## 同音频直接输入

测试在 iPhone 13 Pro（iOS 27.0 beta）运行，输入为同一条 macOS Tingting AIFF：

> 这是一段语音测试。我刚才说的是三点，现在改成四点。不要修改任何日程。请只回复测试成功。

直接输入绕开扬声器和麦克风，分别使用真实苹果 SpeechTranscriber 和真实百炼 fun-asr-realtime；苹果走应用实际使用的格式转换器和实时模型配置，FunASR 走应用真实会话控制器与 WebSocket。两边按录音时长节奏分块输入；计时含设备调度开销，FunASR 首字通过 100 ms 采样观察。以下是最终回归中的单次测量，不含云端建连或首次模型下载。

| 指标 | 苹果原生实时模式 | FunASR 实时版 |
| --- | --- | --- |
| 首次出现转写 | 1.140 秒 | 0.528 秒 |
| 输入结束到最终稿 | 0.095 秒 | 0.410 秒 |
| 输入到最终稿总时长 | 10.507 秒 | 10.695 秒 |
| 三点、四点、不要修改任何日程 | 全部保留 | 全部保留 |
| 请只回复 | “请之回复” | “请知回复” |

苹果全文：这是一段语音测试我刚才说的是三点，现在改成 4点不要修改任何日程请之回复测试成功

FunASR 全文：这是一段语音测试，我刚才说的是3点，现在改成4点，不要修改任何日程，请知回复测试成功。

苹果通过文件接口一次处理整段录音耗时 0.513 秒。该数值不是实时首字延迟，也不代表 100 秒录音性能。

## 修正的实时行为

原配置仅开启 volatileResults，同一音频的首字约在 10.503 秒、接近收尾时才出现。开启 fastResults 后，两次直接输入观测为 1.118 / 1.140 秒，收尾为 0.072 / 0.095 秒。

[苹果 fastResults 文档](https://developer.apple.com/documentation/speech/speechtranscriber/reportingoption/fastresults)说明它使用更短的上下文窗口来降低延迟，可能降低准确性。因此已增加真机固定录音测试，确认完成前出字，且保留关键数字、否定和结束句；不将快速模式描述为更准确。

## 真实麦克风与 AI

同一文件通过 MacBook 扬声器播放，手机真实录音，两次最终测试保持 Mac 音量 48.75%。距离和环境噪声未标定，不能用于严格的准确率排名。

| 指标 | 苹果 | FunASR |
| --- | --- | --- |
| 点完成到录音 UI 退出 | 1.627 秒 | 1.591 秒 |
| 点完成到 AI 回复出现 | 2.747 秒 | 2.718 秒 |
| 时间、改口、否定关键内容 | 保留 | 保留 |
| AI 最终回复 | 测试成功 | 测试成功 |

上述时长包含 UI 自动化点击与观察开销，不是纯 ASR 或纯模型响应时长。FunASR 这轮还出现固定音频外的文字，无法区分是环境人声还是误识别，未用于准确率结论。

低音量（18.75%）首轮收音失败：苹果无文字、FunASR 仅零碎文字；该失败保留在原始结果包中。由于同时改了苹果实时输出选项并提高播放音量，不能单独归因于其中一个因素。

## 验收与复现

- 真机最终回归 **19 项通过，0 失败、0 跳过**：2 项真实文件识别、9 项苹果生命周期与路由测试、8 项 FunASR 回归。
- 两种最终麦克风 UI 测试分别通过（1 + 1 项），已人工检查苹果成功截图。
- 最终应用已安装到原 bundle com.skyliu.toughtrial，现有聊天和密钥保留，识别方式可在助手右上角“⋯ → 语音输入”切换。
- 本轮未改动任务数据结构或日程规则；测试聊天按现有会话规则保存。
- 手机临时 Documents/speech-test.aiff 由测试结束清理，并用 devicectl 验证 0 个匹配文件。
- 测试结束时 Mac 已被外部操作调到音量 0 / 静音，保留该最新状态，未覆盖回测试前的 18.75%。

结果根目录：/private/tmp/tough-trial-device-setup/

- speech-final-acceptance.xcresult：最终 19 项真机回归；同名 log 包含 APPLE_FILE_RESULT / FUNASR_FILE_RESULT。
- apple-physical-02.xcresult：苹果麦克风到 AI。
- cloud-physical-02.xcresult：FunASR 麦克风到 AI。
- file-comparison-01.xcresult：原始长上下文配置基线。
- apple-fast-file-01.xcresult：实时选项验证。
- apple-physical-01.xcresult / cloud-physical-01.xcresult：保留首次收音失败证据。

复现固定音频测试：把同一 AIFF 拷贝到应用 Documents/speech-test.aiff；在测试 Runner 设置 TOUGH_TRIAL_APPLE_FILE_TEST=1，只运行 V2AppleSpeechDeviceTests。默认不设置时跳过真实服务测试。类级 tearDown 会删除该测试文件。真实麦克风测试使用现有 TOUGH_TRIAL_DEVICE_SPEECH 和 TOUGH_TRIAL_DEVICE_SPEECH_PROVIDER 开关。

## 剩余范围

自然口述、口音、嘈杂环境、专有名词、长段任务拆解和 100 秒录音仍需更广泛样本验证。当前证据支持两种方式均可试用，不能支持“苹果一定更准”的结论。

![苹果真实录音到 AI 回复](../assets/realtime-speech/apple-physical-assistant-reply.png)

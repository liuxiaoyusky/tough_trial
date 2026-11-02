# 开发与构建

本页面向开发者；只想使用 App，请看 [下载与上手](../README.md)。

## 环境

- macOS、完整 Xcode 与 Swift 6；新系统功能需要支持相应 SDK 的 Xcode。
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)。
- 部署下限：iOS 17、macOS 14。Mac 首发发布范围为 Apple Silicon。
- 真机安装、苹果上传及公开 Mac 包分别需要适用的签名和分发资格；仓库不包含发布凭据。

## 本地检查

从仓库根目录运行：

```bash
swift run ToughTrialV2Checks
swift run FocusTimelineCoreChecks
swift test
swift build
```

生成 Xcode 工程并构建模拟器版本：

```bash
xcodegen generate
xcodebuild \
  -project ToughTrial.xcodeproj \
  -scheme ToughTrial \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

以上为开发命令，不代表商店版本已经验收或发布。使用 AI Dev Workbench 的开发会话须按项目规则通过 `execution run` 留痕，再校验回执。

## 代码与发布

- 产品入口：[产品规格](spec.md)；进度：[Roadmap](roadmap.md)。
- 共享业务逻辑：`Sources/ToughTrialV2Core/`；任务应用服务：`Sources/ToughTrialAppShared/`。
- 手机界面：`Sources/ToughTrialV2App/`；Mac 工作台：`Sources/ToughTrialMacApp/`。
- 频道规则与本轮核验：[稳定版和 Preview](release/2026-11-02-channels.md)。

发布使用冻结的源码、版本号、功能清单和可核验的包摘要。不要从混有其他开发内容的工作区直接上传。不要提交个人任务、录音、原始转录、Token、签名私钥或运行日志。

发布前运行敏感信息检查，并人工复核截图及发布附件：

```bash
node Tools/check-sensitive-info.mjs
```

许可证为 [Apache 2.0](../LICENSE)。

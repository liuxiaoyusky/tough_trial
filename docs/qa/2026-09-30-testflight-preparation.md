# 2026-09-30 · TestFlight 分发准备

## 当前结论

Tough Trial 1.0（17）已于 2026-09-30 18:28（香港时间）成功上传 App Store Connect。Apple 返回 `Upload succeeded` 和 `Uploaded package is processing`，命令退出码为 0。应用记录标识为 `6817721911`。随后用户完成合规问卷和内部测试群组；19:05 截图显示一个构建版本、一个测试员且邀请已发出，19:16 用户确认在 iPhone 安装并打开。分发闭环完成，页面视觉验收未通过。

本次使用既有 archive，没有修改产品代码或 Bundle ID。重复规则仍是设计稿，不因本次打包成为已实现功能。

## 本机证据

- 工具：Xcode 27.0（27A266a）。
- Archive：`/private/tmp/ToughTrial-20260930.xcarchive`。
- 导出包：`/private/tmp/tough-testflight-20260930/export/ToughTrial.ipa`。
- 版本：1.0（17）；主 Bundle ID：`com.skyliu.toughtrial`；Team：`KH5Y8F5247`。
- IPA 大小：10,180,631 bytes。
- SHA-256：`220887f276451d530cc4b9680b3593d0cd9de84c1913b2e2ad32b3f9f6693789`。
- 导出日志：`/private/tmp/tough-testflight-20260930/export-auto-signing.log`，结果为 `EXPORT SUCCEEDED`。
- 导出方法：`app-store-connect`；`destination=export`；自动签名并允许 provisioning 更新。
- 主 App 和扩展均由 `Apple Distribution: xiaoyu liu (KH5Y8F5247)` 签名；`codesign --verify --strict` 分别通过，IPA ZIP 校验通过。
- 两个 embedded profile 都有明确 application identifier，`get-task-allow=false`，无设备列表、无全设备授权；到期日为 2027-09-23。
- 签名来自 Xcode 自动分发流程。本机 `security find-identity` 仍只列出开发身份，不能把它作为分发包签名失败的结论。
- 账号纠正：网页先前预填的邮箱不应作为开发者账号依据。已从分发日志中的账号/团队关联及 Xcode 偏好设置核对实际签名账号；团队为 `xiaoyu liu / KH5Y8F5247`，`isFreeProvisioningTeam=false`。网页已切换到该账号，具体邮箱不写入仓库。
- 包内有 AppIcon、麦克风/语音用途文案和 PrivacyInfo。上传流程已成功；加密合规状态及 Apple 后续处理结果尚未确认。

## 分发过程记录（历史阻塞已解除）

1. 用户已针对应用二进制及崩溃排查符号向 Apple App Store Connect 的上传明确回复“允许”，上传授权已取得，不应重复请求。
2. 最初上传失败已解除：用户在手机完成应用记录后重试成功。新日志为 `/private/tmp/tough-testflight-20260930/upload-after-app-record.log`，明确包含 `Upload succeeded`、`Uploaded ToughTrial`、`EXPORT SUCCEEDED`。期间 store configuration 仍出现账号提供方警告，但未阻止此次实际上传；旧失败不再作为当前上传阻塞。
3. 用户已明确允许使用已有 Apple 账号自动填充登录和创建应用记录，不应重复请求该授权。实际检查发现 Bitwarden 密码库锁定，需要主密码或通行密钥；其通行密钥窗口仅提供手机/平板与 USB 安全密钥，没有可直接使用的本机凭据。取消提示后已返回 Apple 登录页。Apple 页面直接通行密钥尝试亦未完成登录。未读取、显示或复制密码。应用记录创建及命令行上传均已完成；浏览器仍未登录，处理/合规状态及测试组配置当前需用户在手机确认，或在 Mac 完成登录后由助手继续。
4. 应用记录已被上传流程识别，Apple ID 为 `6817721911`，Bundle ID 为 `com.skyliu.toughtrial`。管理入口：`https://appstoreconnect.apple.com/apps/6817721911/testflight/ios`。待确认 Apple 处理/合规状态与测试人员配置；电脑网页未登录，已请用户查看手机上的版本状态。
5. 最终分发验收：用户在 iPhone TestFlight 中安装并启动，19:16 的反馈及随手记截图构成证据。上文处理与测试配置的待确认事项已随本次实际安装关闭。

## 新增视觉反馈：开放

- 用户认为安装版与之前版本及评审设计不一致。截图中随手记标题为白色，白色卡片里的“想到什么，就记下来。”不可见，分段文字和底栏对比度不足。
- 对照 `outputs/contacts-design-review/assets/capture-native.png`：页面结构与文案相同，旧原生截图的两个标题为黑色；语音提供方旧截图为阿里云 FunASR，用户截图为苹果原生，这是所选提供方不同，不能据此认定是另一个 App 版本。
- 编译日志确认 archive 包含当前 `ToughTrialV2App.swift`、`V2RootView.swift` 和 `V2CaptureView.swift`。入口 Release 直接使用 `V2RootView`，没有发现第三套发布界面入口。
- 代码线索：`V2Theme` 背景固定浅色，Capture 标题/编辑正文使用系统默认前景色，底栏使用系统 secondary/material，App 未指定外观。深色系统外观与固定浅色背景混用是待运行验证的假设；尚未证明用户当前系统设置，尚未修复。
- 评审站同时包含原生截图和静态设计稿；重复规则仍未实现，不能将所有评审图视为已交付界面。后续需按模块核对实际版本与获确认设计，验证浅色/深色系统环境下的可读性。

iCloud 里的 `ToughTrial-1.0-17-iPhone.ipa` 是此前的开发签名包，与本次 TestFlight 分发包不同；保存文件不代表远程安装完成。

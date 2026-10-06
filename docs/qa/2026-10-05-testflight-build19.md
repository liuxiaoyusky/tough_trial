# 2026-10-05 · iPhone 1.0（19）分发记录

## 当前结果

用户要求更新手机版本。已从最新工作区生成 1.0（19）Release 归档，发布预检、产品版本核对和归档签名校验通过。包含本轮今日布局、任务三组列表，以及此前计划提醒入口和视频转录修复。

**1.0（19）已于 2026-10-05 19:32（香港时间）成功上传 App Store Connect。** 用户处理新版协议并回复 `done` 后，重新导出和上传均退出 0；Apple 返回 `Upload succeeded`、`Uploaded package is processing` 和 `EXPORT SUCCEEDED`。应用记录标识为 `6817721911`。

Apple 处理完成、内部测试群组可用和用户实际安装仍待确认。电脑浏览器实际检查重定向到 App Store Connect 登录页，未取得远端构建状态；没有把上传返回的处理中写成已经可安装。手机最近确认的安装版本仍为 1.0（17）。

首次导出退出码为 70，Apple 返回 `PLA Update available`，同时报告无法取得 iOS Distribution 签名证书。该历史日志保留；本轮协议阻塞已经解除。Apple 官方说明未接受新版协议会暂停自动签名和 TestFlight 等资源，见[访问问题说明](https://developer.apple.com/help/account/access/resolving-access-issues)。

## 候选来源与归档核对

- 主 App：`com.skyliu.toughtrial`；Live Activity：`com.skyliu.toughtrial.LiveActivity`。两个产品版本均为 1.0（19）。
- 归档：`/private/tmp/ToughTrial-20261005-19.xcarchive`；Xcode 返回 `ARCHIVE SUCCEEDED`。
- 编译来源：工作区产品源码与资源共 191 个文件，清单保存在被忽略的 `.runtime/testflight-20261005-build19/candidate19-sources.json`。归档前后逐文件 SHA-256 一致；清单摘要为 `2cf2ed23f9cbe4cdcb8f2f137becdb209ef7aa6f7dc9473e4155a90058eaba86`。这是一份工作区清单，不冒充已提交的 Git 版本。
- 主可执行文件 SHA-256：`f3f6bc427a9da409dabee5436bafbc7cf2fb7ae6cf1a9772d3182564929e839c`。
- `codesign --verify --deep --strict` 通过；PrivacyInfo.xcprivacy 与 Live Activity 扩展存在；`ITSAppUsesNonExemptEncryption=false`。
- 导出仍使用原团队和自动签名，不更换 App 标识或签名团队，也不把开发归档当作可下载即安装的安装包。

## 分发包与上传

- 分发 IPA：`/private/tmp/tough-testflight-20261005-19/export-after-agreement/ToughTrial.ipa`；10,329,397 bytes。
- 分发 IPA SHA-256：`b75f5f5dbe3bf2df91f82693823cefdb37ec71b98a38ea19bb2c8a1620ed0fc2`；ZIP 全部条目校验通过。
- 主 App / Live Activity 扩展版本均为 1.0（19），均由原团队 `KH5Y8F5247` 的 Apple Distribution 签名；逐产品严格验签与主包递归验签通过。
- 两个包的签名 entitlement 与 embedded profile 均为 `get-task-allow=false`；profile 无设备列表、无全设备授权，application identifier 与包标识一致，到期日为 2027-09-23。
- 使用同一归档执行 `destination=upload`，`manageAppVersionAndBuildNumber=false`。源清单和归档二进制在重试前核对匹配，上传后工作区产品清单仍无漂移；没有复用旧的 18 号归档。
- 管理入口：[TestFlight 构建](https://appstoreconnect.apple.com/apps/6817721911/testflight/ios)。本轮未变更测试群组、测试员、App Store 上架信息或提交公开审核。

## 本轮检查范围

`Tools/release-preflight.sh` 的八步全部通过：敏感信息检查、App Store 元数据、隐私清单、当前/兼容 Core 检查、Swift 包构建、Xcode 项目生成、iPhone Release 构建和产物检查。

首次预检发现 `Tools/FeatureCLI/README.md` 和 `docs/qa/2026-10-02-workbench-project-audit.md` 的个人电脑绝对路径。仅将这些示例改成 `$HOME` / `~` 路径后重跑通过，没有放宽扫描规则。本轮唯一产品配置改动为构建号 19，没有修改功能实现。

沿用同一功能源码的已完成交互证据：[今日滚动与时间线](2026-10-05-today-scroll-timeline.md)、[任务三组列表](2026-10-05-task-list-groups.md)、[提醒与转录模拟器复验](2026-10-05-simulator-retest.md)。这些原生截图来源仍为各 QA 标注的 Debug 18，不重标为 Release 19 的实拍。本轮没有新增真机交互结果；自然输入、大字体、到点通知、原视频识别与真实云服务仍待用户回访。

## 执行回执

原始日志和导出配置均保存在被忽略的 `.runtime/testflight-20261005-build19/`，不提交账号日志、证书或 provisioning profile。

| 回执 | SHA-256 / 结果 |
| --- | --- |
| `preflight.log` | `36079208eb4791bceac8a0f7e45d0b4a966ea58887f632dd83438dcd0a98b54c`；退出码 0 |
| `archive19.log` | `da678787daccdee0346a1875765ed0e108e3f4b4a83e5c10cc1c5237c29d7fca`；退出码 0 |
| `archive19-verification.json` | 记录版本、产品标识、源码匹配与主可执行文件摘要 |
| `export19.log` | `07edff2280d9b5d564484c31187c703f579d3f40ee1d1f3db98b58aa62050aa5`；退出码 70 |
| `export19-after-agreement.log` | `e1b1a8f625b19f205d8c224e2a90bbac5cb07669784fe8517f6181d5e5e50a12`；退出码 0 |
| `ipa19-verification.json` | 分发包摘要、版本、签名、entitlement 与 profile 校验 |
| `upload19.log` | `ab7e07de7d68d10fdba295e7b6bada2d4ef0bb9fadbdddca1efb5b29eda1cc4d`；退出码 0 |
| `upload19-receipt.json` | 上传成功时间、候选摘要与 Apple 返回的处理中状态；可安装与真机验收未确认 |

导出与上传已经完成；后续仍需分别记录 Apple 处理完成、测试群组可用和用户实际安装。不能把上传成功写成手机已经更新或全部功能已验收。

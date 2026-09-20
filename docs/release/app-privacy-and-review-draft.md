# App Privacy 与审核提交草稿

## 适用发行基线

以下答案仅适用于同时满足这些条件的首发构建：

1. 使用 `V2DeterministicPlanningClient`，不调用远端 AI；
2. 没有 Tough Trial 账号、开发者后端、广告、分析或第三方崩溃 SDK；
3. 私人快照、Feishu/Obsidian 地址、token 和密钥均未进入构建；
4. 语音识别由系统框架处理，开发者不接收音频或转写内容。

任一条件变化后，本文件失效，必须重新完成隐私审计。

## App Store Connect App Privacy 草案

- 建议候选答案：`No, we do not collect data from this app`
- 理由：任务、计划、执行、回想和手写内容只在设备处理；开发者没有接收这些数据的
  服务器。Apple 官方说明，仅在设备处理且不发送到服务器的数据不属于开发者“收集”的
  数据；Apple 自有框架或服务独立收集的数据不由开发者代为申报。
- 最终状态：**待发布者确认并在 App Store Connect 发布**。

不能把“没有开发者收集”写成“所有信息绝不离开设备”。在不支持本地语音识别的环境中，
Apple 的语音识别服务可能处理音频。

## 审核备注草案

机器可录入版本位于 `app-store-metadata.zh-Hans.json` 的 `reviewNotes`。

审核人员不需要账号、私人快照、外部数据源或 API key。建议从空数据新增第一条任务，
依次体验今天执行、任务结构、计划草稿和回想。语音与通知权限只在用户主动触发对应功能
时请求，拒绝后仍可完成核心流程。

## 截图清单

最终截图必须来自与上传 Build 一致的 Release 候选，不使用网页示意图。

- [ ] 今天：当前任务与当天时间线，避免出现私人内容。
- [ ] 专注计时：与示例任务关联的 Zen 界面。
- [ ] 任务：结构图的目标与拆解，文字和连线不重叠。
- [ ] 计划：自然语言输入与结构化草稿。
- [ ] 回想：编辑状态与可引用的当天证据。

若首发保留 iPad：

- [ ] 完成 iPad 布局与四方向验收。
- [ ] 生成符合当前 App Store Connect 要求的 13 英寸 iPad 截图。

若首发仅 iPhone：

- [ ] 在工程中移除 iPad 设备族后重新构建、安装并生成截图。

## 发布者必须确认

- [ ] App 名称 `Tough Trial` 是否作为最终商店名称。
- [ ] 首发仅 iPhone，还是同时支持 iPad。
- [ ] 首发是否固定本地基础规划。
- [ ] 公开支持邮箱与必要的法定联系方式。
- [ ] 隐私政策中的发布者名称和生效日期。
- [ ] App Privacy、出口合规、年龄分级和内容权利回答。
- [ ] 最终截图、审核备注和 App Review 提交动作。

## 官方依据

- App 信息字段：
  <https://developer.apple.com/help/app-store-connect/reference/app-information/app-information>
- 平台版本字段：
  <https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information>
- App Privacy：
  <https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/>
- 提交审核：
  <https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app>

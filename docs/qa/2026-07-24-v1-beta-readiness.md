# V1 Beta 验收记录

日期：2026-07-24

## 结论

- **本地 Beta 候选：Conditional Pass**
- **TestFlight 交付：Blocked**

Phase 0 到 Phase 6 的本地产品闭环已经集成；Phase 7 的自动回归、双尺寸
模拟器操作与视觉检查、Release 设备构建和应用图标检查已完成。在这些已执行
门禁中没有确认的 P0/P1 缺陷；未执行的真机手势与外部能力仍单独列出。

TestFlight 仍被 Apple 签名环境阻塞。该结论只代表外部交付尚未完成，不影响
本地代码与模拟器候选的验收结果。

## 已通过

### 核心与构建

- `swift run ToughTrialV2Checks`
- `swift build`
- 包含 Live Activity 扩展的通用 iOS Simulator 构建
- `iphoneos` Release 无签名构建
- Release App 内包含 `Assets.car`、AppIcon 产物和嵌入的 Live Activity 扩展

核心检查覆盖计划草稿确认、跨页面执行证据、损坏 JSON 恢复、记忆版本、
Dreaming 门槛与原生能力相关状态规则。自动检查通过不替代下述视觉与真机门禁。

### UI 自动回归

同一组 4 个 UI 测试在以下设备分别通过：

- iPhone 17 Pro
- iPhone 17e

覆盖：

1. `今天 / 任务 / 计划 / 回想` 主导航与计划页全屏行为。
2. 蓝色加号只在用户提交后创建任务，打开编辑界面本身不写入。
3. 任务地图默认展开，可点按收起/恢复，并可使用缩小控件。
4. 四个主页面均可启动并生成视觉附件。

UI 测试使用纯内存 Engine 与固定三层任务夹具，不读取或写入用户持久数据。
任务标题每次唯一，提交前后分别断言，避免模拟器残留造成假阳性。

### 视觉检查

两种尺寸的四个主页面均已人工检查，未发现文字截断、控件重叠或越界：

| 页面 | iPhone 17 Pro | iPhone 17e |
| --- | --- | --- |
| 今天 | [截图](2026-07-24-v1-beta/iphone-17-pro-today.png) | [截图](2026-07-24-v1-beta/iphone-17e-today.png) |
| 任务 | [截图](2026-07-24-v1-beta/iphone-17-pro-tasks.png) | [截图](2026-07-24-v1-beta/iphone-17e-tasks.png) |
| 计划 | [截图](2026-07-24-v1-beta/iphone-17-pro-plan.png) | [截图](2026-07-24-v1-beta/iphone-17e-plan.png) |
| 回想 | [截图](2026-07-24-v1-beta/iphone-17-pro-recall.png) | [截图](2026-07-24-v1-beta/iphone-17e-recall.png) |

## 本轮发现并修复

1. `今天` 的 SwiftUI 长按手势会吞掉蓝色加号的普通点按。改为原生
   `UIControl` 后，点按、长按和上拖锁定分别处理，并由 UI 测试回归。
2. 孤立目标会在任务结构画布中同时作为根节点和自身分支绘制，造成文字与线条
   重叠。孤立根节点现在只绘制一次。
3. Live Activity 共享属性在 Swift Package 的 macOS 构建中缺少平台保护，
   已补齐可用性边界并通过 Swift 与 iOS 构建。
4. UI 测试最初复用了模拟器持久数据，视觉附件包含旧测试任务。现在测试使用
   纯内存夹具，快速新增标题也保持唯一。
5. 任务地图节点缺少稳定的可访问名称。根、分支、明细和叶子已补充语义，
   分支与明细同时暴露展开状态。

## 尚未通过

### TestFlight

临时自动签名 Archive 失败，Xcode 返回：

- `No Account for Team "6RR4Q68Q8R"`
- 主 App `com.xiaoyuliu.ToughTrial` 没有 provisioning profile
- 扩展 `com.xiaoyuliu.ToughTrial.LiveActivity` 没有 provisioning profile

本机可见 Apple Development 证书，但没有可用的 Apple Distribution 身份。
需要先在 Xcode 的 Accounts 中登录或刷新该 Team，并为主 App 与扩展启用签名，
之后重新执行 Archive。当前没有声称已经上传 TestFlight。

### 外部与真机门禁

- 真实 AI 请求：客户端与严格结构化输出契约已完成，但尚未使用真实 API 凭据联调。
- 通知：尚未在真机验证权限弹窗、计划提醒到达和拒绝后的状态。
- Live Activity：尚未在真机验证锁屏、灵动岛与深链返回。
- 语音：尚未验证真实麦克风授权、识别质量和长按上拖手感。
- PencilKit：模拟器可构建，尚未用 Apple Pencil 验证书写、缩放与持久化手感。
- 可访问性：关键入口已有可访问名称并通过自动点击，但尚未完成 VoiceOver、
  Dynamic Type 和“减弱动态效果”的独立人工检查。
- 任务地图：点按收起/恢复与缩小控件已有自动回归；横向/纵向拖动、双指缩放和
  多根节点左右切换仍需人工手势验收。
- 连续使用、能耗与数据安全：尚未进行多日真机测试。

## 下一门禁

1. 在 Xcode Accounts 中恢复 `6RR4Q68Q8R` Team 的有效登录。
2. 为主 App 和 Live Activity 扩展生成或刷新签名配置。
3. 在真机完成通知、Live Activity、语音和 PencilKit 检查。
4. 配置开发用 AI 凭据，验证一次成功响应、一次 schema 失败和一次网络失败。
5. Archive、上传 TestFlight，并记录安装后的独立验收结果。

## 独立 QA

独立只读审查结论为 **Conditional Pass**。审查提出的测试假阳性、任务地图
收起/展开缺少回归、节点可访问语义不足和完成状态过度声明已在本轮处理。
语音组合手势、地图拖动/双指缩放、真机原生能力与签名分发仍明确保留为
未验证边界。

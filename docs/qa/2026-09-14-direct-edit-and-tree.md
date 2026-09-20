# 真机反馈续修：直接编辑与树状图总览

日期：2026-09-14。

## 反馈与改动

- 用户记录“点击修改而不是多一个 button”：任务详情移除独立编辑按钮，标题、正文及空正文提示均可点按进入同一窗口的共用文档编辑器，自动请求键盘焦点。内容仍为首段标题、后续正文，保留原保存、取消、分类与撤销规则。
- 用户记录“列表有了，树状图没了？”：读取手机快照发现 39 条任务均没有父级，原界面只对有子任务的根任务开放树图。结构页现在始终显示“列表 / 树状图”入口；总览展示全部根任务，无需先建立父子关系。“全部任务”是只读视觉分组，不是业务任务，不参与新建时的父级绑定。
- 保留原单目标树图和缩放控件；修改只涉及页面、共用编辑器初始焦点和对应 UI 测试。未扩展为网页客户端，也未改 GitHub 备份范围。

## 验证

- `swift run ToughTrialV2Checks`：通过。
- `swift run FocusTimelineCoreChecks`：通过。
- `swift build`：通过。
- 第一组 iPhone 17e 模拟器测试 2 项通过：无层级/空任务切换、节点详情、点击标题/正文/空正文、自动键盘、保存、取消、撤销、三项缩放按钮、总览新增入口与原层级任务的编辑/完成/撤销。
- 第二组分类、文档输入和大字体长内容回归：6 项通过。两组合计 8 项实际 UI 测试通过。
- 正常设备包 1.0（12）构建与签名校验通过，已原位安装到 iPhone 13 Pro。更新前后 39 条任务逐字段一致，完整业务快照亦一致。首次正常启动被锁屏拒绝；22:18 重试后正常启动成功，不带测试参数，启动后再次读取核对 39 条任务逐字段一致。

UI 测试采用模拟器数据；没有在真实手机上运行会新增或编辑任务的测试。真实手机交互手感、语音与真实输入法不以模拟器通过替代。

## 证据

- [树状图总览截图](assets/2026-09-14-direct-edit/flat-task-tree.png)（模拟器合成任务）。
- `/private/tmp/tough-direct-edit-tests.log`：第一组 UI 测试。
- `/private/tmp/tough-direct-edit-regression.log`：第二组 UI 回归。
- `/private/tmp/tough-direct-edit-core.log`、`/private/tmp/tough-direct-edit-compat.log`、`/private/tmp/tough-direct-edit-package.log`：核心与包检查。
- `/private/tmp/tough-direct-edit-device.log`：设备构建。
- `/private/tmp/tough-direct-edit-phone-before.json`：安装前本机临时快照，不纳入仓库。

第一次在受限环境运行 Swift / 签名校验因缓存或信任服务不可访问而失败，获得系统访问后重新运行通过；不属于产品测试失败。

安装证据：`/private/tmp/tough-direct-edit-install.json`；启动记录：`/private/tmp/tough-direct-edit-launch.json`；安装后临时快照：`/private/tmp/tough-direct-edit-phone-after.json`。原始手机快照不纳入仓库。

正常启动成功：`/private/tmp/tough-direct-edit-launch-retry.json`；启动后数据核对：`/private/tmp/tough-direct-edit-phone-after-launch.json`。

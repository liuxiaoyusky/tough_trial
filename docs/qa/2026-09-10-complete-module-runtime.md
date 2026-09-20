# 全模块运行时、动态 AI 工具与插件 v2 验收

## 交付范围

当前任务：现有原生模块迁移、AI 动态工具目录、声明式插件包 v2、安装到用户连接的 iPhone 13 Pro。

保留现有日程 Markdown 同步协议；Capture、Finance、附件及扩展字段仍为本地数据，新领域同步另行实现。

## 需要验证的用户流程

- 模块启停与页面显隐分离；隐藏全部页面后管理和已启用助手仍可访问。
- Capture 停用后，独立理账和订阅页面仍可工作；Ledger 停用后 Finance/Budget 暂停。
- 手动、AI 和插件写入符合相同领域校验；AI 不能伪造身份、分类确认或支付确认。
- 当前工具目录跟随模块和授权变化；迟到工具、ASR、OCR、导入与浏览器回调不越过停用。
- 原文保存与整理分步；重复调用和回复展示失败不会重复业务写入。
- 扩展字段类型固定、值受约束；停用字段和卸载插件保留历史资料。
- 提醒与同步请求随业务提交进入 outbox；失败重试只运行副作用，不能再次记账。
- 从 snapshot schema 1 升级前保留原文件备份；未来 schema 拒绝覆盖。
- 插件 v1 继续兼容；v2 安装/更新检查权限差异，卸载保留内容。

## 验证记录

2026-09-10：三项实现已交付，正常使用版 **1.0 (2)** 已安装到连接的 iPhone 13 Pro，安装成功后再次查询设备应用列表核对版本。独立构建目录未包含 XCTest 测试组件。

本轮已完成签名真机测试。2026-09-10 16:50（香港时间）解锁后重新安装独立目录构建的正常使用版，并立即启动，CoreDevice 返回 `success`。此前锁屏导致的最终启动核验已完成。

## 实现和审计边界

- 71 个原生命令描述、19 个有界查询描述；静态扫描 45 个业务提交 command ID，无未登记 ID。其余参数化 ID 由领域白名单与回归验证。
- 原生 Swift 模块仍是随 App 编译的受信任代码；已有强类型 Engine 方法保留兼容，内部统一经过登记/门禁/事务。Native envelope 校验调用方、版本、摘要和 generation，参数与业务幂等由对应强类型入口负责，不把元数据 envelope 宣称成通用 JSON 执行协议。
- AI 14 个内置工具加已启用扩展字段工具。第三方声明式包只通过受限表单保存标准 Capture，无付款或任意代码执行权限。
- AI 工具回执保存在 snapshot.toolOperations，和事实原子提交；Usage Trace 仅诊断元数据。付款、分类及排期撤销复用领域撤销校验，防止执行引用或后续修改被覆盖。
- UI 共享 LedgerList、CaptureNoteCard；AI Others 笔记在收纳中心及独立笔记页可见，原文从业务回执恢复。
- 工具网络名称按供应商兼容字符及长度规则映射，内部命名空间不变；拒绝未知名称及单次多工具写入。参考 [OpenAI FunctionDefinition](https://github.com/openai/openai-node/blob/main/src/resources/shared.ts)。

## 本轮验证结果

| 验证 | 结果 | 证据 |
| --- | --- | --- |
| 最终 Swift 全量测试 | 149 项：145 通过、4 项按环境跳过、0 失败 | `/private/tmp/tough-complete-core-release.log` |
| 活跃和兼容 Core 检查、Swift build | 均通过 | `tough-complete-v2-final.log`、`tough-complete-compat-final.log`、`tough-complete-swift-build.log`（均在 `/private/tmp`） |
| 全量模拟器 App 测试 | 108 项：101 通过、6 跳过；Keychain 一项因无签名 entitlement 失败，随后签名真机补测通过 | `/private/tmp/tough-complete-final-simulator.log` |
| 完整模拟器 UI 流程 | 7/7 通过：模块启停、独立理账、附件、AI 任务及付款 | 同上 |
| 签名真机 App + UI | 15/15 App、2/2 UI 通过，含 Keychain、插件与聊天恢复；此轮早于最后四项插件边界修复 | `/private/tmp/tough-complete-device-tests.log` |
| 最后插件边界修复回归 | 15/15 模拟器 App 测试通过，包括 4 项新增回归；额外真机补测因再次锁屏取消，未计为通过 | `/private/tmp/tough-complete-package-final-simulator.log` |
| 正常使用版签名构建 | BUILD SUCCEEDED，1.0 (2) | `/private/tmp/tough-complete-device-final-build.log` |
| 真机安装及版本核对 | 安装成功，设备返回 `com.skyliu.toughtrial` / 1.0 / 2 | `/private/tmp/tough-complete-install.json`、`/private/tmp/tough-complete-installed-app.json` |
| 最终正常启动 | 16:50 正常版重新安装后立即启动成功，未传入测试参数 | `/private/tmp/tough-complete-launch.json` |

最终回归覆盖：实际写入/重载重试/保存失败/冲突撤销/字段更新/来源金额币种日期校验。新增用例先复现日期数字被当成缺失金额的错误，再验证修复。插件复查发现的授权基线污染、v1/v2 ID 冲突覆盖、授权计数溢出均已修复并回归；旧表单链接在停用、重新启用和升级后仍需有效宿主授权。

真机 UI 使用隔离的测试数据和确定性模型响应，证明工具到实际领域数据、确认、撤销及展示链路；本轮未将其作为线上模型理解质量或新领域云同步验收。测试未执行真实付款。

## 真机截图

- [任务执行与撤销入口](assets/2026-09-10-complete-runtime/iphone-task-applied.png)
- [任务撤销后的回执](assets/2026-09-10-complete-runtime/iphone-task-undone.png)
- [付款前人工确认](assets/2026-09-10-complete-runtime/iphone-payment-confirmation.png)
- [付款记录已执行](assets/2026-09-10-complete-runtime/iphone-payment-applied.png)

截图来自上述签名真机 UI 运行，已目视检查任务执行和付款确认画面。原始结果：`/private/tmp/tough-trial-recorded-device/Logs/Test/Test-ToughTrial-2026.09.10_16-19-02-+0800.xcresult`。

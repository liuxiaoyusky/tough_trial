# 插件运行时与统一命令：第一批实施

> 执行方式：主线程集成；隔离 worktree 并行实现 Core 注册表与 Finance 命令。

**目标：** 页面显隐与功能开关分离；手动、快捷入口、AI、同步在写入前执行同一能力检查；异步结果不能越过停用；订阅与还款成为 typed command / receipt 的首个接入模块。

**架构：** Core 中的纯依赖解析 + 运行代次；App PluginStore 持久化偏好并桥接 UI。Engine 的事务边界执行模块权限检查，跨域 Capture 额外检查目标域。Finance dispatcher 使用已有原子 reducer 与支付 receipt，不新增第二份业务状态。

**技术：** Swift 6、SwiftUI、UserDefaults、现有 JSON snapshot / XCTest。

**设计：** [运行时设计](../specs/2026-09-10-plugin-runtime-and-contracts-design-zh.md)。本批不宣称完成动态字段、全部 AI 工具目录、声明包 v2、云同步协议或通用持久化 outbox。

## 分工与接口

| 所有者 | 文件 | 输出 |
| --- | --- | --- |
| runtime_core / 隔离 worktree | V2ModuleRuntime.swift、对应 Core tests | 模块描述、偏好迁移、有效状态、generation ticket |
| finance_contracts / 隔离 worktree | V2FinanceCommands.swift、对应 Core tests | typed commands、host context、receipt 投影、受限 draft |
| 主线程 | App PluginStore / UI / 生命周期接线、Engine 事务授权、集成测试、文档 | 统一可用性检查、停用与重开保护、实际 UI |

## 执行与验收

1. 注册表与迁移：未知 ID / 缺失依赖 / 环阻止执行；Capture 关闭不隐式暂停已启用 Finance；旧版本隐式暂停状态保留为迁移待恢复。验证 Core 单测。
2. 页面与能力：五个页面独立显隐；隐藏仍允许授权执行；停用显示原因，数据保留；管理入口始终可达。验证偏好重启测试、模拟器 UI。
3. 事务与生命周期：Engine 调用不得绕过停用；AI、同步请求获取 ticket 并在等待后校验；通知安排避免在停用后复活。验证停用、重开、旧响应拒绝、原子性回归。
4. Finance 接入：所有财务表单经 dispatcher；支付人工确认、重复请求幂等、撤销版本冲突；重启重建支付 receipt。验证 Core + App 集成和既有 UI。
5. 集成：swift test（相关 Core）、ToughTrialV2Checks、FocusTimelineCoreChecks、swift build；Xcode App tests 与 simulator UI 顺序执行。主线程独占模拟器 / 真机。

## 验收边界

- 不把模拟器测试写成真机验收；不把 typed Finance pilot 写成所有模块已迁移。
- Trace 是可选诊断；关闭 Trace 不删除支付、Capture、日程 receipt，不破坏撤销。
- 保留现有未提交工作。仅复制子代理拥有的新文件，逐项检查其测试结果。

# 全模块迁移、动态工具目录、声明式插件 v2

设计依据：`docs/superpowers/specs/2026-09-10-plugin-runtime-and-contracts-design-zh.md`。

目标：完成现有原生模块的统一契约和生命周期接入；助手使用启用模块生成的工具目录；支持 v1/v2 插件安装、更新、卸载与权限差异；通过回归并安装到已连接的 iPhone。

## 分工与边界

| 任务 | 文件所有者 | 验收 |
| --- | --- | --- |
| 1 原生命令和查询迁移 | Core worker：Engine / 各领域 Engine、ModuleRuntime、新 NativeContracts 与对应测试 | 每个业务提交有注册命令；受限查询；停用与迟到拒绝；手动记账不依赖 Capture |
| 2 声明包 v2 | Package worker：PluginManifest、新 PluginPackage、PluginStore、PluginsView、插件测试与示例 | v1 保留；v2 严格解析、权限差异、原子更新、卸载保留记录、受限表单执行 |
| 3 动态 AI 目录 | AI worker：AgentClient / Models / Policy、AssistantStore / Dependencies / TurnLoop / 卡片、新 ToolContracts / ToolExecution 与测试 | 目录随模块变化；typed 参数校验；宿主确认和持久幂等回执；高亮撤销；迟到工具拒绝 |
| 4 生命周期与集成 | 主线程：AppStore、RootView、新持久化 outbox、通知/同步接线、跨模块验收、文档 | 停用清理自身作业；提交后副作用可重试；已有历史可读；真机安装与启动 |

写入代理使用隔离 worktree，基于当前未提交工作副本，只交付自己拥有的文件。主线程独占 Xcode、模拟器和真机。任何接口依赖通过文字协议先对齐，不互相覆盖文件。

命令 ID 使用 `core.<domain>.<verb>`。原生 typed Engine 方法保留为兼容外观，在同一提交边界经过已注册命令检查。AI 与第三方入口只拿受限客户端；模型参数不能包含宿主身份、确认、稳定 ID 或文件路径。已有领域回执继续作为事实来源。

## 验证顺序

1. 各 worker 的 Core 定向测试，主线程审查所有者 diff。
2. 全 Core tests、ToughTrialV2Checks、FocusTimelineCoreChecks、swift build。
3. Xcode App 集成测试和模拟器 UI 测试，验证现有任务 UI 与 Finance 操作。
4. 签名真机构建、安装到连接的 iPhone 13 Pro，启动并核验版本。
5. 更新 roadmap、插件格式说明与 QA，区分实测和未覆盖项。

当前独立日程 Markdown 同步协议保持兼容；新领域跨设备同步、任意可执行第三方代码与插件市场属于独立后续范围。

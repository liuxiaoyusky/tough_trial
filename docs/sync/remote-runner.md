# 云端日程运行器

状态：已部署至用户指定的私有 tough-trial-sync 仓库，真实 GLM Coding Plan 调用、GitHub Actions 自动回写和两个独立持久客户端联调已通过；iPhone 文件授权与端到端同步仍待真机验收。

运行器只读取 `## 云端请求` 中的 pending 请求，调用配置的真实 AI，再经 Core 原子命令校验。任务变化、处理结果、请求状态必须在同一次文件写入中保存。处理后再运行不会重复调用 AI。需要补充信息时写入 needsClarification 和具体问题，不擅自写任务；用户回答时建立新请求 ID。

## 本地检查与独立主机

要求 macOS 14+、Swift 6。本阶段 CLI 使用 macOS 文件协调，不声称已支持 Linux。

```sh
swift build --product ToughTrialScheduleRunner
.build/debug/ToughTrialScheduleRunner --example > /tmp/schedule-example.md
.build/debug/ToughTrialScheduleRunner --validate /tmp/schedule-example.md
```

使用服务环境配置 `SCHEDULE_AI_ENDPOINT`（完整 HTTPS chat/completions 地址）、`SCHEDULE_AI_MODEL`、`SCHEDULE_AI_API_KEY`。凭据通过主机的秘密管理或进程环境传入，不写入日程、命令参数或 Git。

```sh
.build/debug/ToughTrialScheduleRunner --file /path/to/schedule.md
```

文件模式在 AI 返回后，通过 NSFileCoordinator 再读取并比较原始文件，然后原子写回。若文件已变化，停止而不覆盖；再次运行重新读取。文件协调要求其他写入者也遵守协调机制，因此多主机正式同步使用下面的 GitHub SHA 模式。

## GitHub 模式

除 AI 配置外，设置：

| 环境变量 | 值 |
| --- | --- |
| SCHEDULE_REPOSITORY | owner/repository |
| SCHEDULE_BRANCH | 指定的分支名 |
| SCHEDULE_PATH | 仓库内 Markdown 相对路径 |
| SCHEDULE_GITHUB_TOKEN | 具有该仓库 Contents 读写权限的凭据 |

```sh
.build/debug/ToughTrialScheduleRunner --github
```

每处理一条请求都重新读取远端 Markdown 与 SHA，用刚读取的 SHA 提交。409 冲突最多重新读取三次；如果另一运行器已处理同一请求，不再调用模型。网络响应丢失后再次启动也先读取状态，不盲目重发旧写入。每轮最多处理 100 条；达到上限仍有待处理请求时返回失败，保留已写入结果，下一轮继续。

此模式通过 GitHub API 读取最新内容，不依赖主机 checkout 是否及时 git pull。独立主机可由服务管理器重复执行该命令；本仓库尚未安装任何主机定时服务。

## GitHub Actions 入口

模板：[schedule-ai.workflow.yml](schedule-ai.workflow.yml)。当前已部署到用户指定的私有仓库 [tough-trial-sync](https://github.com/liuxiaoyusky/tough-trial-sync) 的 `.github/workflows/schedule-ai.yml`；主 App 代码仓库只保留模板。

选定的日程仓库需要同时包含 `Package.swift` 和运行器所依赖的 `Sources`。部署时把模板安装到该仓库 `.github/workflows/schedule-ai.yml`，设置上述两个 AI repository variables 与 API key secret。默认监听 `schedule.md`，使用其他路径时同时修改触发路径、校验命令路径与 SCHEDULE_PATH。手机上传该文件后触发处理，也可手动启动。

工作流先构建运行器并校验日程格式。模型配置不齐时，AI 步骤跳过，并在运行摘要中说明仍待配置；构建/校验成功不代表 AI 已处理日程。配置齐全后，工作流才调用真实模型并写回。

同分支任务排队、不取消正在处理的任务；写入仍受 SHA 保护。模板使用仓库 GITHUB_TOKEN；它产生的普通 push 不会再触发同类工作流，持久请求状态另提供业务层幂等保护。官方依据：[触发工作流](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow)、[Contents API](https://docs.github.com/en/rest/repos/contents)。checkout 使用已验证的 v6 commit，参见[官方仓库](https://github.com/actions/checkout)。

当前联调目的地是 `liuxiaoyusky/tough-trial-sync` / `main` / `schedule.md`。当前云端模型为 `glm-5.3-flash`（GLM Coding Plan 国内端点），端点和密钥已分别保存在 repository variables / secret。真实 Actions 自动处理合成请求并回写已经通过；先完成真机合成文件验收，再接入个人日程。

## 可复跑的真实联调检查

主项目新增 `Tests/ToughTrialScheduleLiveTests`。默认跳过外部调用；仅在环境中显式启用：

- `TOUGH_TRIAL_REAL_SCHEDULE_TEST=1`：使用上述 AI 配置，检查真实日程新增/改口/延期/完成/撤销/拆解/否定和歧义。
- `TOUGH_TRIAL_REAL_GITHUB_TEST=1`：还需上述 GitHub 配置。在指定仓库创建唯一 `acceptance/two-clients-<UUID>.md`，两个独立 JSON 状态和 API 客户端读写同一个合成文件。会产生真实提交，测试文件保留用于核验。

```sh
swift test --filter ToughTrialScheduleLiveTests
```

GitHub 场景包括真实旧 SHA 拒绝、不同字段合并、真 AI 处理同字段备注及撤销、重启后重试和重复同步 SHA 不变。离线阶段通过传输层注入断网错误，恢复后使用真实 GitHub；不声称做过物理断网或两台实际手机测试。模型质量结论限于本轮合成样本。详细失败与通过记录见 [进度证据](../qa/2026-09-07-ai-schedule-sync-progress.md)。

GLM 接入参数及 pi 源码核对见 [GLM Coding Plan 接入记录](glm-coding-pi.md)。

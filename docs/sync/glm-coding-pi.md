# GLM Coding Plan 接入：参照 pi

2026-09-07 用户指定文字模型使用 GLM-5.3-Flash Coding Plan，并明确参考 earendil-works/pi 的接入实现。语音识别仍由独立的苹果 / FunASR 配置控制。

## 已核对的上游

仓库：https://github.com/earendil-works/pi

本次核对 commit：`9767ba275f3e9a5ee0f5c5342249b629ab1b2282`。

- `packages/ai/src/providers/zai-coding-cn.ts`：国内端点 `https://open.bigmodel.cn/api/coding/paas/v4`，环境变量 `ZAI_CODING_CN_API_KEY`。
- `packages/ai/src/providers/zai.ts`：国际端点 `https://api.z.ai/api/coding/paas/v4`，环境变量 `ZAI_API_KEY`。
- `packages/ai/src/api/openai-completions.ts`：OpenAI Chat Completions、Bearer key；未指定 reasoningEffort 时，ZAI 使用 `thinking: {type: "disabled"}`。
- `packages/ai/scripts/generate-models.ts`：`processZaiModels` 声明 `openai-completions`、`supportsDeveloperRole: false`、`thinkingFormat: zai`；模型列表来源于 models.dev。未安装或执行 pi 的依赖。

## 本项目配置

当前接入国内端点，完整请求地址为 `https://open.bigmodel.cn/api/coding/paas/v4/chat/completions`，模型 `glm-5.3-flash`。

`V2OpenAIRequestCompatibility` 为两个准确的 Coding 端点和 GLM-5.3/Flash 添加关闭思考参数。它由聊天动作入口、计划草稿、日程命令、冲突处理共用。其他服务、普通 GLM API 和相似域名不会被附加这个供应商字段。

App 的 GLM Coding Plan 预设默认模型及可选列表已更新，仍通过 Keychain 保存凭据。不会修改已有手机的活动配置；切换到该模型和安装新构建需要设备可用。云端通过 repository variables / secret 配置。

## 本轮验证

日志目录：`/private/tmp/tough-trial-glm-pi/`。

- `live-schedule.log`：2 项真模型日程测试通过，约 29.64 秒。新增并保留口头改正/备注、延期保持原 ID 与时长、完成和撤销、两小时父子拆解、否定与同名追问均通过。四个执行请求约 4.38 / 2.77 / 6.77 / 7.47 秒。
- `live-routing-conflict.log`：真实 GitHub 双客户端冲突测试通过，约 14.24 秒，最终合成文件为 `acceptance/two-clients-9183b1b0-7f2a-49f4-8306-92ff480bc2ce.md`，SHA `4fa29d0bd0ace7fa469354b25a00b2a5fca69789`。覆盖具体备注合并、撤销、断网错误注入/重启后真实联网重试和重复同步 SHA 不变。
- 同一日志的首次聊天入口测试出现 `操作 JSON 无法解析`，该轮整体失败。补诊断输出后复跑通过；随后为动作结构补充全部字段为字符串和明确示例，最终 `agent-final.log` 的真实回答与 schedule 路由通过。未取得首次错误的原始输出，因此不宣称已证实其具体字段原因或消除所有偶发格式错误。
- `core-final.log`：核心完整检查通过，新增 Coding 国内/国际端点、普通 API/相似域名不注入、正确 Bearer 与凭据不进入正文的检查。
- `build.log`、`compat.log`：包构建与兼容检查通过。`ios.log`：11 项 iOS Simulator 服务配置/助手日程/冲突回归通过。

结论限于本轮合成样本。日程整理未显示比此前 qwen-plus 更快；本次按用户指定选择 GLM-5.3-Flash。


## 云端最终验收

- 已将 `tough-trial-sync` 的 `SCHEDULE_AI_ENDPOINT`、`SCHEDULE_AI_MODEL` 和 `SCHEDULE_AI_API_KEY` 切换到用户授权的国内 GLM Coding Plan 配置；Key 通过 secret 输入，不进入 Git 或输出。
- 部署提交：`fcd10bc52046b1c20be13afaaedddcc423c5986a`。新增同一参数适配器后，运行器快照共 45 个源文件。
- [真实自动运行 34087032219](https://github.com/liuxiaoyusky/tough-trial-sync/actions/runs/34087032219) 成功，Processed 1 / pending 0 / retries 0。新任务“GLM 接入验证”的备注为“最多 15 分钟，不要联网”，未新增排期。最终 7 个合成任务、4 条 processed 请求，日程 SHA `4f36cb72860f6caadeed079fa23eab197daa8f8b`；日志 `actions.log`、文件 `actions-result.md`。
- 最新 `ios-final.log`：11 项配置/助手日程/冲突回归通过。iPhone 13 Pro 仍 unavailable，未将此构建安装到真机，也未修改手机上当前活动的模型配置。

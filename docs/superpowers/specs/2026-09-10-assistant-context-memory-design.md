# 助手上下文、记忆、会话日志与 Compact

用户授权：复用 Codex 的 memory / session log / trace / compact 思路，在 App 内落地，并解决引用任务丢失与闲聊误触发日程写入。

## 本机观察

2026-09-10 只读核验 Codex：`memories/memory_summary.md` 是入口，`MEMORY.md` 为主题索引及来源指针；`sessions/YYYY/MM/DD/rollout-*.jsonl` 追加保存 session_meta、turn_context、response_item、event_msg、compacted 等事件。会话索引为 `session_index.jsonl`；SQLite 保存线程、历史投影和运行日志索引。此次仅检查字段结构，不复制其他项目正文、凭据或内部推理。复用数据职责与追溯方式，不声称重建 Codex 私有运行时。

## App 结构

- 既有 `v2-memory.json`、`v2-agent-workspace.json` 和业务 snapshot 继续作为事实来源，保持老版本读取兼容。
- 新增 `assistant-context/`：`memory/MEMORY.md` 与摘要入口为结构化记忆的可读投影；`sessions/<sessionID>.jsonl` 为会话事件日志；`session-index.json` 为可重建索引；`compact/<sessionID>.json` 保存压缩摘要、覆盖消息 ID 和版本。
- 日志记录公开聊天文字、工具回执和上下文清单，不保存录音、附件二进制、认证头、API key 或模型内部推理。Trace 保持元数据记录，并加入引用 ID、请求用途、compact 版本、记忆条数和请求字符规模。
- 原始会话不因 compact 删除。压缩为有来源 ID 的结构化摘录，保留近期消息；引用、当前输入和宿主授权单独传递，不依赖摘要。AI 可按需检索原文。无需为维护上下文额外调用远端模型。
- 首次打开导入现有会话；重复导入幂等。显式删除会话时同时删除其日志与 compact。辅助存储失败不能把已经提交的业务操作误报失败，向用户说明并在下次加载修复投影。

## 统一请求上下文

聊天模型、排期模型和动态工具均接收宿主构造的 typed context：当前引用任务（按真实 ID 刷新，保留缺失状态）、适用记忆、压缩摘要、当前时间和时区。模型只读取上下文，不通过上下文获得写入授权。引用任务始终优先于对听写标题的模糊猜测。

明确要求“拆分当前引用任务”时，让 AI 给出可执行子步骤；不反问用户自己拆分。真实缺失的课程内容或截止日期才澄清，不虚构课程标题。明确“今天”的新增需写入当天计划项，复用既有今日 UI。

## 内置能力

通过当前模块目录提供有界 `searchMemory`、`searchSessions`、`readSession`、`readTrace` 和 `compact`。提供会话页面的上下文管理入口，可查看引用、记忆与 compact 状态，手动压缩和回看原始日志。长期记忆编辑沿用现有 typed MemoryEngine 与人工管理入口，不从摘要自动写成永久事实。

## 写入意图边界

本轮明确请求才授权写入；仅紧邻且未失败的澄清问题允许简短确认继承上轮意图。`hello`、问候、纯讨论、错误反馈不能继承历史任务授权。宿主在调用排期模型之前及应用其 proposal 之前校验；动态写入使用同一判定。Compact 和记忆不能改变授权。

## 验收

1. 引用任务只存于 session.sourceTask，第一条消息仅说“帮我拆分”，聊天和排期请求仍包含准确引用；听写错字不影响引用 ID。
2. 先有写入/报错，再输入 hello，恶意或误判的模型 proposal 不产生任何业务写入。
3. 明确“排到今天”及有效澄清回答仍工作；“今天创建任务”不能只留下未排期任务。
4. 老会话导入后可搜索/读取，重启不重复日志；compact 后原始消息可取回，引用与当前输入仍在模型请求。
5. AI 可通过真实宿主工具读取 memory/session/trace，模块停用后不可调用；Trace 足以定位引用是否进入每一次模型请求。
6. Core、App 和模拟器验证后构建正常 iPhone 版本，安装与启动分别记录结果。

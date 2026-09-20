# C 批次：任务分类与轻量记账

承接用户批准的 docs/superpowers/plans/2026-09-11-user-feedback-ux-roadmap.md C 批次。先改相关规格，再实现；不做 D 联网或 E 真机回访的替代声明。

约束：用户只需填写必要信息，任务首段标题/回车正文保持不变。今天不展示类别。复用现有领域对象、来源、回执、门禁和撤销；每个草稿隔离。人工确认账单分类，未知金额/币种/日期不猜测。所有 UI 使用 V2Theme，真实点按后查领域状态。保留已有代码，不重构无关模块。

### Task 1: 任务详情的可选分类

在现有 V2Task.Kind 语义基础上提供人工分类：目标/承诺/维护/未分类。contextID 属于结构上下文，变更会联动子树；parentID 为父子关系，排期为另一对象；不得把分类等同于重设 context，不新建 taxonomy 或误用 ledger category。
先更新任务规格。只在已有任务详情/编辑提供轻量可选入口，不给新增文档加必填项。优先在已有任务文档编辑器的额外区域使用默认收起的分类选择，沿同一保存/取消草稿；或者在详情提供主题一致的独立可选分类浮层，择其更少点击且边界清楚者。本批只允许改 kind，不提供分组迁移或重设父任务。
提交更新原 ID，保护旧基线冲突，保留父 ID/执行证据/状态/累计用时及排期；提供既有回执撤销。仅改变分类应可保存，取消保持原值。可清除 kind 回到未分类，停用任务模块按原门禁。
负责文件：V2TasksView.swift、V2AppStoreTaskEditing.swift、Components/Tasks/ 下必要文件、V2TaskEditingTests.swift 与新 V2TaskClassificationUITests.swift、任务设计规格。Core 优先新增 V2TaskClassification.swift，只改当前任务 kind/updatedAt，使用既有回执表达并安全撤销；不复用会重写后代上下文/updatedAt 的通用 updateTask。不要改 ledger/capture、README、roadmap、project.yml 或生成项目。
先跑失败行为测试，再实现；交付 App 层领域测试（保留未编辑数据/取消不写/清空分类/过期基线/撤销）与实际点按 UI 测试代码。自行跑 App build-for-testing 可用 generic iOS Simulator；禁止启动/操作模拟器，UI 统一由主线程串行执行。报告修改文件、命令/日志、缺口，最后在本工作区提交本任务改动。

### Task 2: 记账入口与原文整理确认

先更新 capture/ledger 规格。随手记“理账”改为清楚的“记账”，一步可见，现有独立账本标题一致；不增第六 Tab，不新建账本。现有 ledger 模块隐藏/停用继续尊重。
让“记一笔”默认是一处自然语言输入（不强制标题/正文分栏），可用共用 V2MultilineInput + V2DictationControl，纸色背景与蓝色动作。一键整理只生成待核对提案，不能在这个专用流程自动写账；原随手记的混合输入免确认设置行为不因本批改动而悄悄改变。金额等固定字段只在整理结果或必要的手动补充时显示，保持一条流程与原草稿。语音完成回填，用户可改口/补充后整理；仍允许 AI 不可用时手动记录。
整理结果可核对/修改金额、币种、收支、日期、描述和分类建议。缺字段明示，币种未知没有配置默认就要求补充；消费日期可未指定，不能把记录日当消费日。已选分类由用户显式确认保存；可拒绝建议留未分类。不能将不相关混合任务/灵感自动保存为账单，保留原文供回看。多笔逐项确认、重复点击幂等、失败重试、取消/返回不丢原文、已保存状态和撤销可发现。
复用 CaptureEntry/Batch/Candidate/Receipt/LedgerEntry 及分类引擎；需要校正候选时新增最小强类型领域命令，保留来源修订和人工校正记录，金额/分类提交尽量原子且不得重复流水。不要靠 UI 手工拼模型 JSON、重建另外的数据存储或修改全局 strict 设置。
验收样本：'午饭花了三十八，不对，是三十五，昨天的'：受控提案 amount=35、日期依据可见、没有币种则补充；另测多笔、缺金额、未知币种、失败重试、分类改选/拒绝、重复确认、撤销和重启。测试 client 的确定性提案只验证接线，不能宣称真实 AI 已识别。真实 AI 调用由主线程可选单独验证。
负责文件：V2CaptureView.swift、V2LedgerView.swift、V2CaptureStore.swift 或其新 extension、新 Components/Ledger/、Core V2CaptureEngine.swift 或新 LedgerConfirmation.swift、V2CaptureUITestClient.swift 的独立显式测试分支、新 Ledger App/Core/UI 测试、capture/ledger 设计规格。不要改任务相关文件、基础 Input 组件、README、roadmap、project.yml 或生成项目；需基础输入变更先反馈。
在独立 worktree 实现，先失败测试再实现，跑定向 swift Core 测试。不得启动模拟器/改主工作区，不派子代理；主线程串行 UI 验收。报告完整文件列表、API/行为、命令与日志、缺口，并只提交本任务代码。

## 本批交付状态（2026-09-12）

任务分类、专用记账输入与核对保存已实现，通过 Core、App 和两种尺寸模拟器定向回归。审查发现的分类命令标识、候选状态边界及旧待补充回执残留已修复；详见 [验收记录](../../qa/2026-09-12-classification-ledger.md)。真实 AI、自然语音和真机回访仍开放，不关闭 D/E。

# 随手记与理账实现计划

Goal: 建立原始输入 → 标准提案 → 校验/确认 → 正式数据 → 来源和撤销的本地闭环。
Architecture: SwiftUI 仅调用类型化 Store；Core 拥有 Capture schema、领域命令和回执；独立 AI Client 只产出候选。
Tech Stack: Swift 6 / SwiftUI / Codable / 现有 V2Engine snapshot / PhotosUI / PencilKit。
Spec: ../specs/2026-09-09-unified-capture-and-ledger-design-zh.md
Global constraints: 不覆盖现有任务/回想；分类强制确认；新内容暂不进入 schedule.md；不重置用户数据；不把模拟测试当真实 API 验收。

- [x] 1. `V2CaptureModels.swift`、`V2CaptureEngine.swift`：来源修订、提案、账单、笔记、分类、回执及快照兼容；测试来源失效、金额/币种、重复提取、追加保护、撤销冲突。
- [x] 2. `V2CaptureClient.swift`：从同一契约生成提示与严格字段校验；注入 transport 测试异常 JSON、未知字段、HTTP 失败；沿用当前文字模型配置。
- [x] 3. `V2CaptureStore.swift`、`V2CaptureView.swift`：统一输入、整理结果、账单/Others/灵感读取、确认分类、合并预览及撤销；复用任务命令和回想数据。
- [x] 4. 媒体资产保存、图片/手写录入与来源预览；语音沿用 Apple/FunASR 选择；不支持识别的媒体明确待识别。
- [x] 5. Trace 衔接：默认无原文元数据，保留业务回执；根来源、批次、模型、校验、保存/呈现可关联。
- [x] 6. Swift package/Core 检查、iOS build、针对闭环的 simulator UI 测试与截图；更新规格/QA，明确未完成的同步与真实 API 验收。

本计划交付首个本地闭环。完整设计中的全库 AI 批量改类、扩展字段注册、新协议同步等后续能力单列在 `docs/qa/2026-09-09-unified-capture.md`，没有并入已完成状态。

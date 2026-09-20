# 项目内部组件

组件随 App 编译，按实际复用需求分组。页面负责导航和业务接线，Core 保留保存规则。

## Tasks / V2TaskEditor

今天、任务结构/鱼骨/时间新增、快捷待办、已有任务详情及助手待确认提案共用文档式输入、空标题校验、保存失败提示及未保存取消确认。用户在一处连续书写：第一段是标题，回车后是可选正文。每次展示独立草稿；取消不发出保存事件。助手已保存任务的“调整”保持指令输入语义。提案编辑上下文与浮层由助手页面持有，消息卡片仅发出编辑事件，避免列表回收重建草稿。

输入：`V2TaskEditorMode.create(location:identifier:)`、`.edit(taskID:)`、`.quick` 或 `.proposal`，以及初始 `title/note`。额外日期字段通过 ViewBuilder 组合，`additionalDirty` 将日期变更纳入未保存确认。
事件：`onSave(title, note) -> String?` 返回错误说明时保留草稿；返回 nil 前调用方应确认实际成功并处理导航。`onCancel()` 由用户明确取消触发。组件不持有 App Store、不调用 AI、不自动提交。

```swift
NavigationStack {
    V2TaskEditor(mode: .create(location: "结构 / 新建根任务"), onSave: { title, note in
        guard store.createTaskFromTasks(title: title, note: note, parentTaskID: nil) else {
            return store.errorMessage ?? "保存失败，请重试。"
        }
        isPresented = false
        return nil
    }, onCancel: { isPresented = false })
}
```

已有任务的页面先保存当前 `V2Task` 为编辑基线，调用 `store.editTask(original, title:note:)`。对象在编辑期间变更时拒绝覆盖。保存/完成回执可通过 `undoTaskChange` 撤销，后续修改冲突时不会被覆盖。

预览见组件文件末尾。交互验证见 `V2TaskEditorUITests`，领域接线见 `V2TaskEditingTests`；实际测试状态以 QA 文档为准。


## Tasks / V2TaskFields

`V2TaskFields` 组合单个 `V2TaskDocumentInput`，以原生 UITextView 管理连续文本和 UTF-16 选区。首段使用应用的圆角粗标题，正文使用标准正文样式，无字段卡片或目标切换。`V2TaskDocumentContent` 负责与既有 title/note 的拆分/拼接；未修改旧草稿时保留原字段，不重解释旧多行标题。中文 marked text 期间不替换文本、选区或样式；录音时暂停编辑与保存。

| 入口 | 去向与提交 |
| --- | --- |
| 今天 | `quickAddTodayTask(title:note:)` 原子创建任务和当天安排 |
| 任务结构 | `createTaskFromTasks` 保留当前父 ID，默认不排期 |
| 任务鱼骨/快捷待办 | 默认不排期；快捷入口仍使用原 Capture/任务保存规则 |
| 任务时间 | `quickAddScheduledTask(title:note:on:)` 保留选中日期 |
| 已有任务 | `editTask` 更新稳定 ID，对过期基线拒绝覆盖 |
| 助手待确认提案 | `editPendingTask` 的既有接线只更新提案，明确确认后才落库 |

## Input / V2DictationControl

接收 `text: Binding<String>`、`isActive: Binding<Bool>`、可选 `selection: Binding<NSRange>`、`ownerModuleID` 和 `identifierPrefix`。文档入口自动使用开始时的光标或选区；识别修订替换同一段，保留原文后缀。取消恢复录音前全文与选区。未传 selection 的旧调用仍沿用末尾追加规则。主界面只有语音动作与设置，服务选择在设置页；不自动创建任务或发送请求。录音期间禁止编辑和保存，离开或后台取消，系统权限弹窗不取消。

组件是项目内部源码，无单独 package、注册中心或持久化模型。录音服务和权限失败用真实生命周期加可注入音频边界验证；模拟器测试不能代替自然语音和真机输入法验收。

## Input / V2MultilineInput

接收文本 Binding、占位文字、最小/最大高度、可用状态和可选焦点 Binding，使用原生 TextEditor 保留光标、选择及系统输入法行为。短输入按行数估算增高，达到上限后内部滚动。助手展开与收起只改变高度，同一份会话草稿、引用、发送和排队继续由原 Store 管理。“收起键盘”通过组件传入的 FocusState Binding 结束焦点，便于切换页面；组件没有传入焦点时使用局部 FocusState。

```swift
V2MultilineInput(text: $draft, placeholder: "输入内容", minHeight: 44,
                 maxHeight: 140, accessibilityIdentifier: "example.composer")
```

任务听写完成只回填草稿，用户可修改后保存。助手沿用已确认的交互：点语音“完成”将内容交给 AI，保留原发送和排队流程。助手不套用任务表单的提交规则。


## Tasks / V2TaskClassificationFields

任务分类继续使用现有 `V2Task.Kind`，选择“目标／承诺／维护／未分类”。分类是已有任务编辑器里的可选内容；新建任务仍只需输入一行。所属上下文与父任务属于结构关系，不能以分类的名义改写。`V2TaskClassificationFields(kind:identifierPrefix:)` 只绑定页面持有的分类草稿；通过 `V2TaskEditor` 的附加内容组合，并将分类变更传入 `additionalDirty`。保存调用 `store.editTask(original, title:note:classification:)`，将正文和类型一次保存；清空使用 `V2TaskClassification(kind: nil)`。分类保存保留稳定 ID、后代、排期和执行记录，撤销检查当前值，不能覆盖后续修改。

```swift
V2TaskClassificationFields(kind: $draftKind,
                           identifierPrefix: "tasks.editor.classification")
```

## Ledger / V2CaptureLedgerForm

记账复用 Input 组件，原文、整理候选和正式流水仍由现有 Capture 领域管理。专用记账输入只整理到待核对结果，确认保存才创建流水；混合随手记仍保留原来的确认设置。缺少金额或币种时提示补充，日期可以不填；账单类别始终由用户确认。任务分类与账单分类的类型和提交规则保持独立。

`V2CaptureLedgerForm(store:)` 放在 `Components/Ledger/`，由随手记记账分段、独立记账页和快捷 URL 共用。`ledgerDraft`、来源 ID 和 `activeLedgerBatchID` 与混合随手记草稿分离；关闭表单取消整理并保留本次原话，“再记一笔”开始独立来源。输入组件只回填文字，`organizeLedger(text:)` 只生成待核对结果，`confirmLedgerCandidate` 原子保存用户当前修改。

核对卡片按 batch ID 隔离编辑状态。原提案不变，`effectiveCandidate(for:)` 提供人工修正后的值，`corrections` 带候选 ID 记录变更。金额、币种、收支缺失时不能保存；消费日期可以留空。账单先保存为 Others，类别建议经单独人工确认后生效，仍沿用同一回执撤销。

```swift
.sheet(isPresented: $isAddingLedger) {
    V2CaptureLedgerForm(store: captureStore)
}
```

定向验证：`V2LedgerReviewUITests`、`V2LedgerCaptureStoreTests`、`V2LedgerConfirmationTests` 和 `V2LedgerConfirmationBoundaryTests`。真实语音与 AI 识别不以受控 fixture 代替，实际验收状态见 [C 批次验收](../../../docs/qa/2026-09-12-classification-ledger.md)。

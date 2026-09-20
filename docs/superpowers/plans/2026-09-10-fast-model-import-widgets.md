# 实现与验收计划

Goal: 更快的默认文字模型；外部资料先本机识别再整理；三个低摩擦主屏幕快捷入口。
Spec: ../specs/2026-09-10-fast-model-import-widgets.md
Stack: SwiftUI / Core Codable / WidgetKit / FoundationXML / zlib（XLSX）。
约束：不迁走已选账号，不覆盖草稿，不导入即自动写账单，不把fixture测试视为真实外部样本验收。

- [x] 模型预设与兼容请求：修改V2AIProviderSettings/View、V2OpenAIRequestCompatibility；测试默认、旧profile、endpoint及reasoning_split。
- [x] 只读文件识别Core：独立worker交付Parser/XLSX与fixture测试，主线程检查支持边界与限额。
- [x] 导入来源/幂等/历史Core：V2ExternalImportEngine，snapshot向后兼容；失败原子保存，去重与来源测试。
- [x] 导入页面：识别与选择预览、保存待整理、单条或所选内容整理，接入随手记现有结果展示；记录元数据Trace。
- [x] 小组件：独立worker交付Widget；主线程实现可测试deep link路由、冷/热启动与草稿保护、记账/任务/notes表单。
- [x] Swift/Core检查、iOS构建和针对导入/快捷路由的UI测试、真机可用时安装，记录未验证的真实样本/账号质量。

验收记录：../../qa/2026-09-10-fast-model-import-widgets.md。完成代码、自动化测试与真机安装；真实 MoneyThings 导出和主屏幕实际添加点击组件仍列为人工验收边界，未冒称完成。

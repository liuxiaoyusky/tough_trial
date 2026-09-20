# 快速模型、文件导入与快捷小组件

用户授权改进，默认假设：本地模型指应用中配置的模型；桌面指现有 iOS 产品主屏幕。若用户进一步明确离线或 macOS 独立应用，调整对应范围。

1. AI：新用户默认 GLM Coding Plan / glm-5.3-flash，保留已保存服务和凭据；增加 MiniMax-M2.7-highspeed 独立预设及同服务内快速推荐入口，不冒充设备端离线推理。GLM现有关闭thinking策略保留，MiniMax启用reasoning_split避免正文混入思考内容，仍按Core契约校验。
2. 导入：本机文件选择 → 确定性格式识别/逐条预览（不联网）→ 用户选择记录 → 保存来源 → 主动整理，复用Capture AI和领域命令、分类确认与撤销。支持标准ICS、CSV/TSV、TXT/Markdown/JSON和XLSX；各厂商通过导出文件适配，不假称账号连接。保留时区/全日/重复规则/取消、币种/金额/收支原始语义；未知字段保留，不能让AI补出默认事实。重复文件按内容hash+记录ID幂等，导入历史在snapshot中持久化，新增字段可向后兼容。
3. 小组件：中号三入口（记账/待办/随手记），小号各单入口；WidgetKit只打开固定deep link，不显示私密内容、不在小组件内伪造文本框。记账打开金额描述表单；待办打开标题备注快速保存到原任务引擎；notes打开新随手记，原文先保存，可稍后整理。当前编辑内容先保存，正在录音/整理时暂存快捷入口，避免覆盖输入。

边界：真实MoneyThings导出样本尚未提供，基于通用表格结构支持并展示完整列，不保证所有历史私有备份格式。ICS复杂重复事件不盲目展开，保留规则并标记需要核对。AI不应把循环描述擅自摊成一次事件。

来源核验（2026-09-10）：
- MiniMax OpenAI兼容与reasoning_split https://platform.minimaxi.com/docs/api-reference/text-openai-api
- MoneyThings官方App Store更新记录包含XLSX导出 https://apps.apple.com/cn/app/moneythings-%E8%AE%B0%E8%B4%A6/id1549694221
- Apple WidgetKit链接限制 https://developer.apple.com/documentation/widgetkit/creating-a-widget-extension
- Google日历ICS导出 https://support.google.com/calendar/answer/37111?hl=en-gb

交互补充：忙碌期间保留最近一次快捷入口选择（再次点击视为改变目标），不排队弹出多个空表单；导入保存/整理按钮固定在页面底部。重复/例外/取消事件、缺 DTSTART 或未知 TZID 的记录在数据层禁止创建 task，可留在收纳中心。

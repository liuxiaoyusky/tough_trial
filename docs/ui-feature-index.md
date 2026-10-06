# UI 与 Feature Map 对照

由 `python3 Tools/FeatureCLI/review_links.py --write-index` 从 `docs/feature-map.json` 生成。不要手改。

图片来源和功能实现状态是两层信息；关联正确不代表已通过视觉或交互验收。评审服务运行于 8770 时可点击下列入口。

| Feature | App 入口 | 评审页面 | 图像来源 | 版本 / 日期 | 验收说明 |
| --- | --- | --- | --- | --- | --- |
| `ui.capture` | 随手记 | [capture-testflight-17](http://127.0.0.1:8770/#capture-testflight-17) | device | 2026-09-30 · 用户 iPhone 13 Pro · TestFlight 1.0（17） | 安装启动已确认；标题、底栏对比度反馈待修复。 |
| `ui.capture` | 随手记 | [capture-design](http://127.0.0.1:8770/#capture-design) | design | 静态设计示意 · 非安装包产物 | 设计参考；不构成原生验收。功能实现状态另见本组说明。 |
| `ui.capture` | 随手记 | [capture](http://127.0.0.1:8770/#capture) | simulator | 2026-09-20 · iPhone 17e 模拟器 · 构建号未锁定 | 历史模拟器截图，合成数据；具体交互范围见原 QA，当前真机未复验。 |
| `ui.today` | 今天 | [today-completion-clear-20261005](http://127.0.0.1:8770/#today-completion-clear-20261005) | simulator | 2026-10-05 · iPhone 13 Pro · iOS 26.5 · 1.0（21）Debug 开发预览 · 系统 dark / App 明确 light · 合成数据 · 未分发 | 完成项紧凑弱化，明确已完成，保留时间线、累计和右下角新增；对应实际交互见本轮 QA，真机人工验收待。 |
| `ui.today` | 今天 | [today](http://127.0.0.1:8770/#today) | simulator | 2026-09-20 · iPhone 17e 模拟器 · 构建号未锁定 | 历史模拟器截图，合成数据；具体交互范围见原 QA，当前真机未复验。 |
| `ui.today` | 今天 | [today-paused](http://127.0.0.1:8770/#today-paused) | simulator | 2026-09-20 · iPhone 17e 模拟器 · 构建号未锁定 | 历史模拟器截图，合成数据；具体交互范围见原 QA，当前真机未复验。 |
| `ui.today` | 今天 | [today-completed](http://127.0.0.1:8770/#today-completed) | simulator | 2026-09-20 · iPhone 17e 模拟器 · 构建号未锁定 | 历史模拟器截图，合成数据；具体交互范围见原 QA，当前真机未复验。 |
| `ui.today` | 今天 | [today-empty](http://127.0.0.1:8770/#today-empty) | simulator | 2026-09-20 · iPhone 17e 模拟器 · 构建号未锁定 | 历史模拟器截图，合成数据；具体交互范围见原 QA，当前真机未复验。 |
| `ui.today` | 今天 | [today-current-20261005](http://127.0.0.1:8770/#today-current-20261005) | simulator | 2026-10-05 · iPhone 17 Pro · iOS 26.5 · 1.0（18）Debug 工作区；合成任务 | 生产 SwiftUI 实际操作截图；7 项 UI + 5 项 App 单元限定范围通过，详见今日滚动 QA。当前 iPhone 安装版和大字体未复验。 |
| `ui.today` | 今天 | [today-scrolled-20261005](http://127.0.0.1:8770/#today-scrolled-20261005) | simulator | 2026-10-05 · iPhone 17 Pro · iOS 26.5 · 1.0（18）Debug 工作区；合成任务 | 生产 SwiftUI 实际操作截图；7 项 UI + 5 项 App 单元限定范围通过，详见今日滚动 QA。当前 iPhone 安装版和大字体未复验。 |
| `ui.today` | 今天 | [today-quiet-completed-20261005](http://127.0.0.1:8770/#today-quiet-completed-20261005) | simulator | 2026-10-05 · iPhone 17 Pro · iOS 26.5 · 1.0（18）Debug 工作区；合成任务 | 生产 SwiftUI 实际操作截图；7 项 UI + 5 项 App 单元限定范围通过，详见今日滚动 QA。当前 iPhone 安装版和大字体未复验。 |
| `ui.today` | 今天 | [today-paused-20261005](http://127.0.0.1:8770/#today-paused-20261005) | simulator | 2026-10-05 · iPhone 17 Pro · iOS 26.5 · 1.0（18）Debug 工作区；合成任务 | 生产 SwiftUI 实际操作截图；7 项 UI + 5 项 App 单元限定范围通过，详见今日滚动 QA。当前 iPhone 安装版和大字体未复验。 |
| `ui.today` | 今天 | [today-completed-20261005](http://127.0.0.1:8770/#today-completed-20261005) | simulator | 2026-10-05 · iPhone 17 Pro · iOS 26.5 · 1.0（18）Debug 工作区；合成任务 | 生产 SwiftUI 实际操作截图；7 项 UI + 5 项 App 单元限定范围通过，详见今日滚动 QA。当前 iPhone 安装版和大字体未复验。 |
| `ui.today` | 今天 | [today-empty-20261005](http://127.0.0.1:8770/#today-empty-20261005) | simulator | 2026-10-05 · iPhone 17 Pro · iOS 26.5 · 1.0（18）Debug 工作区；合成任务 | 生产 SwiftUI 实际操作截图；7 项 UI + 5 项 App 单元限定范围通过，详见今日滚动 QA。当前 iPhone 安装版和大字体未复验。 |
| `ui.tasks.list` | 任务 → 列表 | [device-tasks-list](http://127.0.0.1:8770/#device-tasks-list) | device | 2026-09-21 · iPhone 13 Pro · 1.0（14）历史截图 | 历史设备证据；不代表当前 1.0（17）视觉验收通过。 |
| `ui.tasks.list` | 任务 → 列表 | [tasks-list](http://127.0.0.1:8770/#tasks-list) | simulator | 2026-09-20 · iPhone 17e 模拟器 · 构建号未锁定 | 历史模拟器截图，合成数据；具体交互范围见原 QA，当前真机未复验。 |
| `ui.tasks.list` | 任务 → 列表 | [tasks-list-current-20261005](http://127.0.0.1:8770/#tasks-list-current-20261005) | simulator | 2026-10-05 · iPhone 17 Pro · iOS 26.5 · 1.0（18）Debug 工作区；合成任务 | 生产 SwiftUI 实际新建、开始、暂停和完成后截图；2 iOS UI 与 8 App 单元限定范围通过，详见任务分组 QA。真机和大字体未复验。 |
| `ui.tasks.list` | 任务 → 列表 | [tasks-list-design-foundation-20261005](http://127.0.0.1:8770/#tasks-list-design-foundation-20261005) | simulator | 2026-10-05 · iPhone 13 Pro · iOS 26.5 · 1.0（20）Debug 开发预览；合成任务；系统深色、任务页明确浅色；未分发 | 生产 SwiftUI 实际操作截图；4 项浅色 UI 与最终源码 2 项系统深色复验通过，详见设计 QA。不替代真机或全 App 无障碍验收。 |
| `ui.tasks.list` | 任务 → 列表 | [tasks-list-design-foundation-empty-20261005](http://127.0.0.1:8770/#tasks-list-design-foundation-empty-20261005) | simulator | 2026-10-05 · iPhone 13 Pro · iOS 26.5 · 1.0（20）Debug 开发预览；合成任务；系统深色、任务页明确浅色；未分发 | 生产 SwiftUI 实际操作截图；4 项浅色 UI 与最终源码 2 项系统深色复验通过，详见设计 QA。不替代真机或全 App 无障碍验收。 |
| `ui.tasks.list` | 任务 → 列表 | [tasks-list-design-foundation-large-text-20261005](http://127.0.0.1:8770/#tasks-list-design-foundation-large-text-20261005) | simulator | 2026-10-05 · iPhone 13 Pro · iOS 26.5 · 1.0（20）Debug 开发预览；合成任务；系统深色、任务页明确浅色；未分发 | 生产 SwiftUI 实际操作截图；4 项浅色 UI 与最终源码 2 项系统深色复验通过，详见设计 QA。不替代真机或全 App 无障碍验收。 |
| `ui.tasks.structure` | 任务 → 结构 | [structure-mindmap-tree-20261006](http://127.0.0.1:8770/#structure-mindmap-tree-20261006) | simulator | 2026-10-06 · iPhone 13 Pro · iOS 26.5 · 1.0（23）Debug · 生产 SwiftUI / 合成数据 · light · 未分发 | 彩色分支、细曲线与连接节点；紧凑浅底节点，从同一个未分类展示根展开；原生操作范围见 10/6 阶段 QA，审美人工评审与真机待。 |
| `ui.tasks.structure` | 任务 → 结构 | [structure-mindmap-completed-20261006](http://127.0.0.1:8770/#structure-mindmap-completed-20261006) | simulator | 2026-10-06 · iPhone 13 Pro · iOS 26.5 · 1.0（23）Debug · 生产 SwiftUI / 合成数据 · light · 未分发 | 完成父节点和叶节点保留勾选、已完成和删除线，颜色退为中性；原生操作范围见 10/6 阶段 QA，审美人工评审与真机待。 |
| `ui.tasks.structure` | 任务 → 结构 | [structure-mindmap-selected-20261006](http://127.0.0.1:8770/#structure-mindmap-selected-20261006) | simulator | 2026-10-06 · iPhone 13 Pro · iOS 26.5 · 1.0（23）Debug · 生产 SwiftUI / 合成数据 · light · 未分发 | 选中保持清晰蓝色边界；查看、聚焦和关闭操作沿用原生界面；原生操作范围见 10/6 阶段 QA，审美人工评审与真机待。 |
| `ui.tasks.structure` | 任务 → 结构 | [structure-mindmap-forest-20261006](http://127.0.0.1:8770/#structure-mindmap-forest-20261006) | simulator | 2026-10-06 · iPhone 13 Pro · iOS 26.5 · 1.0（23）Debug · 生产 SwiftUI / 合成数据 · light · 未分发 | 多个实际顶层任务从单一未分类展示根展开；宽树可横向拖动；原生操作范围见 10/6 阶段 QA，审美人工评审与真机待。 |
| `ui.tasks.structure` | 任务 → 结构 | [structure-light-tree-20261005](http://127.0.0.1:8770/#structure-light-tree-20261005) | simulator | 2026-10-05 · iPhone 13 Pro · iOS 26.5 · 1.0（22）Debug · 生产 SwiftUI / 合成数据 · light · 未分发 | 文字节点与细曲线，常态无卡片；共用未分类根，展开控件与标题并排；具体原生操作范围见本轮 QA，人工审美与真机待。 用户反馈要求彩色节点，10/6 已由 23 号替代。 |
| `ui.tasks.structure` | 任务 → 结构 | [structure-light-completed-20261005](http://127.0.0.1:8770/#structure-light-completed-20261005) | simulator | 2026-10-05 · iPhone 13 Pro · iOS 26.5 · 1.0（22）Debug · 生产 SwiftUI / 合成数据 · light · 未分发 | 完成父节点和叶节点保留勾选、已完成与删除线，次级文字保持可读；具体原生操作范围见本轮 QA，人工审美与真机待。 用户反馈要求彩色节点，10/6 已由 23 号替代。 |
| `ui.tasks.structure` | 任务 → 结构 | [structure-light-selected-20261005](http://127.0.0.1:8770/#structure-light-selected-20261005) | simulator | 2026-10-05 · iPhone 13 Pro · iOS 26.5 · 1.0（22）Debug · 生产 SwiftUI / 合成数据 · light · 未分发 | 只有当前选中节点出现淡蓝底；下方查看任务、聚焦与关闭仍使用原生操作；具体原生操作范围见本轮 QA，人工审美与真机待。 用户反馈要求彩色节点，10/6 已由 23 号替代。 |
| `ui.tasks.structure` | 任务 → 结构 | [structure-light-forest-20261005](http://127.0.0.1:8770/#structure-light-forest-20261005) | simulator | 2026-10-05 · iPhone 13 Pro · iOS 26.5 · 1.0（22）Debug · 生产 SwiftUI / 合成数据 · light · 未分发 | 多个顶层任务从同一个展示根延伸；宽树仍可横向查看，不压缩文字强塞首屏；具体原生操作范围见本轮 QA，人工审美与真机待。 用户反馈要求彩色节点，10/6 已由 23 号替代。 |
| `ui.tasks.structure` | 任务 → 结构 | [structure-common-root-20261005](http://127.0.0.1:8770/#structure-common-root-20261005) | simulator | 2026-10-05 · iPhone 13 Pro · iOS 26.5 · 1.0（21）Debug 开发预览 · 系统 dark / App 明确 light · 合成数据 · 未分发 | 结构直接显示倒树；多个顶层任务从单一展示根延伸，宽树仍需横向拖动；对应实际交互见本轮 QA，真机人工验收待。 |
| `ui.tasks.structure` | 任务 → 结构 | [structure-completed-20261005](http://127.0.0.1:8770/#structure-completed-20261005) | simulator | 2026-10-05 · iPhone 13 Pro · iOS 26.5 · 1.0（21）Debug 开发预览 · 系统 dark / App 明确 light · 合成数据 · 未分发 | 完成父节点和叶节点均以文字、勾选、删除线与中性表面表示；对应实际交互见本轮 QA，真机人工验收待。 |
| `ui.tasks.structure` | 任务 → 结构 | [structure-focus-20261005](http://127.0.0.1:8770/#structure-focus-20261005) | simulator | 2026-10-05 · iPhone 13 Pro · iOS 26.5 · 1.0（21）Debug 开发预览 · 系统 dark / App 明确 light · 合成数据 · 未分发 | 聚焦真实分支，返回上一级；展示根不充当业务节点；对应实际交互见本轮 QA，真机人工验收待。 |
| `ui.tasks.structure` | 任务 → 结构 | [structure-empty-20261005](http://127.0.0.1:8770/#structure-empty-20261005) | simulator | 2026-10-05 · iPhone 13 Pro · iOS 26.5 · 1.0（21）Debug 开发预览 · 系统 dark / App 明确 light · 合成数据 · 未分发 | 没有任务时不创建假根；右下角新增仍是实际入口；对应实际交互见本轮 QA，真机人工验收待。 |
| `ui.tasks.structure` | 任务 → 结构 | [native-inverted-overview](http://127.0.0.1:8770/#native-inverted-overview) | simulator | 2026-09-21 · iPhone 17e 模拟器 · 构建号未锁定 | 历史模拟器截图，合成数据；具体交互范围见原 QA，当前真机未复验。 |
| `ui.tasks.structure` | 任务 → 结构 | [native-inverted-selection](http://127.0.0.1:8770/#native-inverted-selection) | simulator | 2026-09-21 · iPhone 17e 模拟器 · 构建号未锁定 | 历史模拟器截图，合成数据；具体交互范围见原 QA，当前真机未复验。 |
| `ui.tasks.structure` | 任务 → 结构 | [native-inverted-focus](http://127.0.0.1:8770/#native-inverted-focus) | simulator | 2026-09-21 · iPhone 17e 模拟器 · 构建号未锁定 | 历史模拟器截图，合成数据；具体交互范围见原 QA，当前真机未复验。 |
| `ui.tasks.structure` | 任务 → 结构 | [native-inverted-six](http://127.0.0.1:8770/#native-inverted-six) | simulator | 2026-09-21 · iPhone 17e 模拟器 · 构建号未锁定 | 历史模拟器截图，合成数据；具体交互范围见原 QA，当前真机未复验。 |
| `ui.tasks.structure` | 任务 → 结构 | [native-directory-mode](http://127.0.0.1:8770/#native-directory-mode) | simulator | 2026-09-21 · iPhone 17e 模拟器 · 构建号未锁定 | 历史模拟器截图，合成数据；具体交互范围见原 QA，当前真机未复验。 |
| `ui.tasks.structure` | 任务 → 结构 | [inverted-tree-overview](http://127.0.0.1:8770/#inverted-tree-overview) | design | 静态设计示意 · 非安装包产物 | 设计参考；不构成原生验收。功能实现状态另见本组说明。 |
| `ui.tasks.structure` | 任务 → 结构 | [inverted-tree-focus](http://127.0.0.1:8770/#inverted-tree-focus) | design | 静态设计示意 · 非安装包产物 | 设计参考；不构成原生验收。功能实现状态另见本组说明。 |
| `ui.tasks.structure` | 任务 → 结构 | [six-level-expanded](http://127.0.0.1:8770/#six-level-expanded) | simulator | 2026-09-21 · iPhone 17e 模拟器 · 构建号未锁定 | 历史模拟器截图，合成数据；具体交互范围见原 QA，当前真机未复验。 |
| `ui.tasks.structure` | 任务 → 结构 | [six-level-default](http://127.0.0.1:8770/#six-level-default) | simulator | 2026-09-21 · iPhone 17e 模拟器 · 构建号未锁定 | 历史模拟器截图，合成数据；具体交互范围见原 QA，当前真机未复验。 |
| `ui.tasks.structure` | 任务 → 结构 | [six-level-scrolled](http://127.0.0.1:8770/#six-level-scrolled) | simulator | 2026-09-21 · iPhone 17e 模拟器 · 构建号未锁定 | 历史模拟器截图，合成数据；具体交互范围见原 QA，当前真机未复验。 |
| `ui.tasks.structure` | 任务 → 结构 | [compact-tasks-structure](http://127.0.0.1:8770/#compact-tasks-structure) | simulator | 2026-09-21 · iPhone 17e 模拟器 · 构建号未锁定 | 历史模拟器截图，合成数据；具体交互范围见原 QA，当前真机未复验。 |
| `ui.tasks.structure` | 任务 → 结构 | [device-tasks-structure](http://127.0.0.1:8770/#device-tasks-structure) | device | 2026-09-21 · iPhone 13 Pro · 1.0（14）历史截图 | 历史设备证据；不代表当前 1.0（17）视觉验收通过。 |
| `ui.tasks.structure` | 任务 → 结构 | [tasks-structure](http://127.0.0.1:8770/#tasks-structure) | simulator | 2026-09-20 · iPhone 17e 模拟器 · 构建号未锁定 | 历史模拟器截图，合成数据；具体交互范围见原 QA，当前真机未复验。 |
| `ui.tasks.time` | 任务 → 时间 | [device-tasks-time](http://127.0.0.1:8770/#device-tasks-time) | device | 2026-09-21 · iPhone 13 Pro · 1.0（14）历史截图 | 历史设备证据；不代表当前 1.0（17）视觉验收通过。 |
| `ui.tasks.time` | 任务 → 时间 | [tasks-time](http://127.0.0.1:8770/#tasks-time) | simulator | 2026-09-20 · iPhone 17e 模拟器 · 构建号未锁定 | 历史模拟器截图，合成数据；具体交互范围见原 QA，当前真机未复验。 |
| `ui.tasks.fishbone` | 任务 → 鱼骨 | [device-tasks-fishbone](http://127.0.0.1:8770/#device-tasks-fishbone) | device | 2026-09-21 · iPhone 13 Pro · 1.0（14）历史截图 | 历史设备证据；不代表当前 1.0（17）视觉验收通过。 |
| `ui.tasks.fishbone` | 任务 → 鱼骨 | [tasks-fishbone](http://127.0.0.1:8770/#tasks-fishbone) | simulator | 2026-09-20 · iPhone 17e 模拟器 · 构建号未锁定 | 历史模拟器截图，合成数据；具体交互范围见原 QA，当前真机未复验。 |
| `ui.assistant` | 助手 | [assistant](http://127.0.0.1:8770/#assistant) | simulator | 2026-09-20 · iPhone 17e 模拟器 · 构建号未锁定 | 历史模拟器截图，合成数据；具体交互范围见原 QA，当前真机未复验。 |
| `ui.recall` | 更多插件 → 回想（可设为底栏快捷入口） | [recall](http://127.0.0.1:8770/#recall) | simulator | 2026-09-20 · iPhone 17e 模拟器 · 构建号未锁定 | 历史模拟器截图，合成数据；具体交互范围见原 QA，当前真机未复验。 |
| `ui.finance` | 更多插件 → 财务 | [finance](http://127.0.0.1:8770/#finance) | simulator | 2026-09-20 · iPhone 17e 模拟器 · 构建号未锁定 | 历史模拟器截图，合成数据；具体交互范围见原 QA，当前真机未复验。 |
| `ui.navigation` | 更多插件 | [more-plugins-paper-20261005](http://127.0.0.1:8770/#more-plugins-paper-20261005) | simulator | 2026-10-05 · iPhone 13 Pro · iOS 26.5 · 1.0（21）Debug 开发预览 · 系统 dark / App 明确 light · 合成数据 · 未分发 | 统一纸白、可读标题和中性模块图标；底栏按真实拖拽调整为今天、转录、更多插件、任务；对应实际交互见本轮 QA，真机人工验收待。 |
| `ui.navigation` | 更多插件 | [navigation-editor-paper-20261005](http://127.0.0.1:8770/#navigation-editor-paper-20261005) | simulator | 2026-10-05 · iPhone 13 Pro · iOS 26.5 · 1.0（21）Debug 开发预览 · 系统 dark / App 明确 light · 合成数据 · 未分发 | 同一纸白配色；真实添加 / 移除和数量限制说明；对应实际交互见本轮 QA，真机人工验收待。 |
| `ui.navigation` | 更多插件 | [navigation-editor-minimum-20261005](http://127.0.0.1:8770/#navigation-editor-minimum-20261005) | simulator | 2026-10-05 · iPhone 13 Pro · iOS 26.5 · 1.0（21）Debug 开发预览 · 系统 dark / App 明确 light · 合成数据 · 未分发 | 2 个入口的原生禁用状态：保留今天与更多插件；对应实际交互见本轮 QA，真机人工验收待。 |
| `ui.navigation` | 更多插件 | [more-plugins](http://127.0.0.1:8770/#more-plugins) | simulator | 2026-09-20 · iPhone 17e 模拟器 · 构建号未锁定 | 历史模拟器截图，合成数据；具体交互范围见原 QA，当前真机未复验。 |
| `ui.profile` | 更多插件 → 我的资料 | [my-home](http://127.0.0.1:8770/#my-home) | simulator | 2026-09-20 · iPhone 17e 模拟器 · 构建号未锁定 | 历史模拟器截图，合成数据；具体交互范围见原 QA，当前真机未复验。 |
| `ui.profile` | 更多插件 → 我的资料 | [qr-share](http://127.0.0.1:8770/#qr-share) | simulator | 2026-09-20 · iPhone 17e 模拟器 · 构建号未锁定 | 历史模拟器截图，合成数据；具体交互范围见原 QA，当前真机未复验。 |
| `ui.profile` | 更多插件 → 我的资料 | [share-info](http://127.0.0.1:8770/#share-info) | design | 静态设计示意 · 非安装包产物 | 设计参考；不构成原生验收。功能实现状态另见本组说明。 |
| `ui.profile` | 更多插件 → 我的资料 | [social-qr](http://127.0.0.1:8770/#social-qr) | design | 静态设计示意 · 非安装包产物 | 设计参考；不构成原生验收。功能实现状态另见本组说明。 |
| `ui.profile` | 更多插件 → 我的资料 | [edit-profile](http://127.0.0.1:8770/#edit-profile) | design | 静态设计示意 · 非安装包产物 | 设计参考；不构成原生验收。功能实现状态另见本组说明。 |
| `ui.habits` | 设计入口：今天 / 任务 → 时间 | [habit-today](http://127.0.0.1:8770/#habit-today) | design | 静态设计示意 · 非安装包产物 | 设计参考；不构成原生验收。对应功能仍未实现。 |
| `ui.habits` | 设计入口：今天 / 任务 → 时间 | [habit-rules](http://127.0.0.1:8770/#habit-rules) | design | 静态设计示意 · 非安装包产物 | 设计参考；不构成原生验收。对应功能仍未实现。 |
| `ui.habits` | 设计入口：今天 / 任务 → 时间 | [habit-edit](http://127.0.0.1:8770/#habit-edit) | design | 静态设计示意 · 非安装包产物 | 设计参考；不构成原生验收。对应功能仍未实现。 |
| `ui.habits` | 设计入口：今天 / 任务 → 时间 | [habit-actual](http://127.0.0.1:8770/#habit-actual) | design | 静态设计示意 · 非安装包产物 | 设计参考；不构成原生验收。对应功能仍未实现。 |
| `ui.habits` | 设计入口：今天 / 任务 → 时间 | [habit-transit](http://127.0.0.1:8770/#habit-transit) | design | 静态设计示意 · 非安装包产物 | 设计参考；不构成原生验收。对应功能仍未实现。 |
| `ui.habits` | 设计入口：今天 / 任务 → 时间 | [habit-reading](http://127.0.0.1:8770/#habit-reading) | design | 静态设计示意 · 非安装包产物 | 设计参考；不构成原生验收。对应功能仍未实现。 |
| `ui.habits` | 设计入口：今天 / 任务 → 时间 | [habit-result](http://127.0.0.1:8770/#habit-result) | design | 静态设计示意 · 非安装包产物 | 设计参考；不构成原生验收。对应功能仍未实现。 |
| `ui.habits` | 设计入口：今天 / 任务 → 时间 | [habit-generation](http://127.0.0.1:8770/#habit-generation) | design | 静态设计示意 · 非安装包产物 | 设计参考；不构成原生验收。对应功能仍未实现。 |
| `ui.habits` | 设计入口：今天 / 任务 → 时间 | [habit-calendar](http://127.0.0.1:8770/#habit-calendar) | design | 静态设计示意 · 非安装包产物 | 设计参考；不构成原生验收。对应功能仍未实现。 |

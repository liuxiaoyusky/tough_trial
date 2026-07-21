# Tough Trial V2 视觉设计系统

状态：采用方案 2「微暖纸白」作为第一版视觉基线
更新日期：2026-07-20

## 设计原则

- 颜色表达职责，不表达页面。四个主页面共享同一套语义角色。
- 中性色保持轻微暖意，但不做成手账、羊皮纸或单一米色主题。
- 蓝色只表达主要操作与当前选择；任务状态与目标分支使用独立色组。
- 执行状态不依赖文字标签之外的单一颜色，图标、文案和状态必须共同成立。
- 页面代码优先引用语义角色，避免直接写 RGB、Hex 或按页面命名的颜色。

## 颜色角色

### 中性表面与文字

| Role | 当前值 | 用途 |
| --- | --- | --- |
| `canvas` | `#FAF9F5` | App 主画布；微暖、安静，不参与状态表达 |
| `surface` | `#FFFFFF` | 普通内容表面 |
| `surfaceRaised` | `#FFFEFC` | 当前任务、浮层等轻抬升表面 |
| `surfaceMuted` | `#F4F2EE` | 次级按钮、输入区、弱强调区域 |
| `outline` | `#E2E0DC` | 分隔线与低对比边界 |
| `textPrimary` | `#0E0F12` | 主要内容与高优先级标题 |
| `textSecondary` | `#575C69` | 说明、时间与次级信息 |
| `textTertiary` | `#94969E` | 已完成内容、占位和弱化信息 |
| `textInverse` | `#FFFFFF` | 深色或彩色背景上的文字 |

### 操作角色

| Role | 当前值 | 用途 |
| --- | --- | --- |
| `primary` | `#0E63E6` | 主要操作、当前时间、当前选择 |
| `onPrimary` | `#FFFFFF` | `primary` 背景上的内容 |
| `primaryContainer` | `#E8F2FF` | 低强调主要操作背景 |
| `onPrimaryContainer` | `#0A57D1` | `primaryContainer` 上的内容 |

### 任务状态角色

| Role | 当前值 | 用途 |
| --- | --- | --- |
| `taskActive` | `#08A380` | 正在进行 |
| `taskActiveContainer` | `#E8F7F2` | 正在进行的弱背景 |
| `taskPaused` | `#F56314` | 已暂停 |
| `taskPausedContainer` | `#FFF0DB` | 已暂停的弱背景 |
| `taskComplete` | `#339E6E` | 已完成事实 |
| `taskCompleteContainer` | `#E8F7ED` | 完成信号的弱背景 |
| `taskIncomplete` | `#F58278` | 尚未完成或孤立插入；不是错误 |
| `taskIncompleteContainer` | `#FFF2F0` | 未完成信号的弱背景 |
| `destructive` | `#D12E33` | 删除等不可逆动作，不用于普通未完成状态 |

### 目标分支角色

`goalBlue`、`goalTeal`、`goalOrange`、`goalViolet` 只用于区分目标或树状结构分支。它们不能表达任务是否进行中、暂停或完成。

## 字体角色

字体沿用 iOS 系统字体；页面只选择角色，不自行组合字号和字重。

| Role | 当前映射 | 用途 |
| --- | --- | --- |
| `displayLarge` | 38 / Black / Rounded | 页面级主标题，如“今天” |
| `displayMedium` | 30 / Black / Rounded | 与分段控件同排的紧凑页面标题，如“任务” |
| `headlineLarge` | 34 / Black / Rounded | 空状态核心提示 |
| `headlineMedium` | 25 / Black / Rounded | 当前任务标题 |
| `headlineSmall` | 22 / Bold / Rounded | 结构图根节点等紧凑强调标题 |
| `titleLarge` | 20 / Bold / Rounded | 区块标题与展开任务 |
| `titleMedium` | 16 / Semibold | 普通任务标题、紧凑控件 |
| `bodyMedium` | 15 / Regular | 正文说明 |
| `bodySmall` | 13 / Medium | 时间线细节 |
| `labelLarge` | 15 / Semibold | 日期与较强标签 |
| `labelMedium` | 13 / Semibold | 状态、时间和操作标签 |
| `labelSmall` | 11 / Semibold | 胶囊内的最小标签 |
| `timerLarge` | 38 / Black / Rounded / Monospaced | 当前计时 |
| `timerSmall` | 15 / Bold / Monospaced | 总时长与紧凑计时 |

## 页面应用规则

- `今天`：画布、中性表面、主要操作色和任务状态色；不出现目标分支色。
- `任务 / 结构`：结构图直接使用页面画布，不包进可见卡片；连线和节点边框使用目标分支色，节点填充只读取完成信号，绿色表示已完成部分，浅红表示未完成部分。
- `任务 / 结构`：默认视口呈现根节点、全部一级分支和当前分支的关键下一级；更深内容通过聚焦、收起/展开、横向拖动和缩放进入，不把整棵树压缩到首屏。
- `任务 / 时间`：只表达时间位置与完成状态，不按长期目标重新分组或着色。
- `任务 / 时间`：年、月、周、三日、日共用连续日历画布；周视图允许任务并排重叠，三日和日提供更高可读性。
- `任务 / 鱼骨`：目标分支色用于筛选与区分同一完成时间轴上的目标来源。
- `计划`：主要操作色负责对话动作，草稿和确认状态使用中性表面层级。
- `回想`：事实记录以中性色为主，只在证据定位和分析引用时使用强调色。

## 当前迁移范围

- `V2Theme.ColorRole` 与 `V2Theme.TypeRole` 是代码中的角色源。
- `V2TodayView` 已迁移为第一块样板页面。
- `V2TasksView` 已迁移，并保留结构、时间、鱼骨三个既定视角及原有交互逻辑。
- 旧别名暂时保留，保证计划和回想页面不因视觉系统落地而发生无意变化；后续逐页设计确认后再迁移。

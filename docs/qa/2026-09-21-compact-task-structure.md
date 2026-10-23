# 结构图紧凑布局评审与验收

日期：2026-09-21。用户确认原真机结构图连线过长、空白过多、信息量少、整体过宽，并同意修正标题截断与首屏位置。

## 实现

- 移除固定 940 × 650 最小画布和 224 点列间距；“全部任务”移到轻量工具栏，不占关系列。
- 保留树关系，采用纵向预序排列、每层 24 点缩进、短折线；画布随可见节点和视口计算。
- 默认展开前两层实际任务的父节点，并保留所选深层任务的祖先路径；多根任务不创建额外业务根。
- 标题最多两行，不缩小成极小文字；任务详情、展开/收起独立操作，触控区域至少 52 点高（最小 0.85 缩放后仍约 44 点）。
- 保留状态圆点的完成信号、任务编辑入口、新增入口、滚动和双指缩放；工具栏缩放按钮 44 点，边界禁用；重置恢复默认比例与左上位置。
- 只修改结构展示与相关测试；列表、时间、鱼骨及领域模型未更改。清除被新布局取代的旧焦点/宽画布/下划线样式代码。

## 验证

| 项目 | 结果 |
| --- | --- |
| 旧版回归 | iPhone 17e 模拟器失败：深层节点无法点击，首屏层级不可达，证明新用例能检出原问题 |
| 第一轮新布局 UI | 通过：三级首屏、完整节点边界、小缩进、收起/展开、详情返回、缩放/重置、新增空提交禁用与取消 |
| 补充回归 | 最终 3 项全部通过：空态/多根任务/编辑保存取消撤销、四视图、缩放边界和双指缩放 |
| 核心、兼容、Swift 包 | `ToughTrialV2Checks`、`FocusTimelineCoreChecks`、`swift build` 均通过 |
| Mac | 共享结构页所在客户端构建通过；未另做 Mac 交互验收 |
| iPhone 构建/安装 | 1.0（15）构建成功、签名验证通过，01:55 最终代码原位安装成功 |
| iPhone 启动/交互 | 手机锁屏：旧版真机基线未执行，01:56 最终版本正常启动同样被 Locked 拒绝；用户解锁后仍需真机复验 |

第一轮截图可在同一首屏看到 7 个合成任务和三层关系，原真机截图只有根附近少量信息。前后设备分别为 iPhone 17e 模拟器与 iPhone 13 Pro 真机，均为 390 点宽，不能宣称同设备像素级对比。

本轮所有测试用合成数据，未复制个人任务快照、未修改手机反馈任务。已知附件测试的 fileprivate thumbnail 编译遗留仍通过命令行排除，不宣称全套测试通过。自然输入法、VoiceOver、深层大数据和长期稳定性不在本轮通过范围。

## 本机证据

- `/private/tmp/tough-compact-sim-red-20260921.log` 与同名 xcresult：旧布局失败。
- `/private/tmp/tough-compact-sim-green-20260921.log` 与同名 xcresult：初轮通过。
- `/private/tmp/tough-compact-final-sim-20260921.log`：补充回归构建服务停滞，无活动编译子进程，已中止。
- `/private/tmp/tough-compact-final-retry-20260921.log` 与同名 xcresult：使用已编译测试包重试。
- `/private/tmp/tough-compact-core-20260921.log`、`tough-compact-compat-20260921.log`、`tough-compact-package-20260921.log`。
- `/private/tmp/tough-compact-mac-20260921.log`、`tough-compact-device-build-20260921.log`。
- `/private/tmp/tough-compact-install-20260921.json`、`tough-compact-launch-20260921.json`。

补充回归发现并修正两个展示问题：外层 accessibilityIdentifier 覆盖了工具栏/画布标识；少量根任务在双向 ScrollView 中垂直居中。去掉覆盖标识、让内容填满视口并靠左上排列。最终 Mac 与 iPhone 构建均通过，签名严格验证通过。

测试调度在编译结束后停滞；直接测试同样停滞，重启本任务模拟器后恢复执行。中止日志保留，不计作用例通过。

最终验收证据：`/private/tmp/tough-compact-reboot-20260921.log` 与同名 xcresult，3 tests / 0 failures（81.598 秒）。截图导出至 `/private/tmp/tough-compact-final-shots-20260921/`；评审截图已保存为 `outputs/contacts-design-review/assets/tasks-structure-compact-simulator-20260921.png`。

最终构建/安装证据：`/private/tmp/tough-compact-device-final-20260921.log`、`tough-compact-mac-final-20260921.log`、`tough-compact-install-final-20260921.json`、`tough-compact-launch-final-20260921.json`。

[查看新版评审页](http://127.0.0.1:8768/#compact-tasks-structure)。原图保留；新版为模拟器截图，用户尚未反馈此版视觉体验。

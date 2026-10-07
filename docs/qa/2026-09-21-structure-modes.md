# 目录与倒树双模式验收

2026-09-21。用户确认保留目录模式并实现倒树总览、聚焦提案。

## 实现范围

- 结构页增加目录/倒树切换，默认目录，在当前任务页会话内保留模式选择；没有新增数据关系或同步格式。
- 目录保持原有紧凑树、节点直达详情、缩放、展开收起。
- 倒树按可见子树宽度分配空间，根在上、分支向下；多个根并列展示。短折线不穿过节点；溢出可横向或纵向滚动，支持按钮和双指缩放。
- 点击倒树节点显示标题/父任务及操作面板，查看任务复用原生详情；可关闭面板。长标题受卡片宽度限制最多两行，选中面板/详情用于读完整内容，不缩小文字硬塞。
- 聚焦分支、叶节点聚焦所属分支、返回上一级；无可聚焦父分支或已经处于该分支时，显示明确禁用提示。
- 展开收起重排周围节点，并依据原节点相对视口位置调整滚动；复位恢复当前子树比例和起始位置。该锚定在视口边缘受滚动边界约束，不保证任何树形都零位移。
- 新增根任务不会重新展开用户已经收起的其他根。

## 验证

- 先运行倒树 UI 用例失败：旧版没有模式切换入口。核心布局测试先因缺少布局类型失败。
- 核心几何测试 2 项通过：同层节点不重叠、规则树父子居中、收起减少空间、六层单链与空森林。
- 首轮 UI 3 项通过：目录现有控制、目录六层自动让位、倒树模式/详情/聚焦/返回/展开收起/缩放/新建取消。
- 补充 UI 2 项通过：目录空态、多根任务、编辑保存/取消/撤销；倒树六层逐层展开与滚动、深层详情、聚焦/返回、面板关闭、缩放上界、两模式空态。
- 最终倒树 2 项复验通过（46.361 秒）：明确禁用提示、多根横向滚动与选中面板截图。
- `ToughTrialV2Checks`、`FocusTimelineCoreChecks`、`swift build` 均通过。

测试均使用合成任务，不复制个人任务快照。已知 `V2FileAttachmentTests.swift` 的 fileprivate thumbnail 编译问题仍通过命令行排除，不宣称全套测试通过。大字体、VoiceOver、每层高分支数压力与长期稳定性未做专项验收。Mac 验收范围以构建为准。

## 证据

- `/private/tmp/tough-inverted-red-20260921.log` 与同名 xcresult。
- `/private/tmp/tough-inverted-core-red-20260921.log`、`tough-inverted-core-green-20260921.log`。
- `/private/tmp/tough-inverted-green-20260921.log` 与同名 xcresult：3 项，59.198 秒。
- `/private/tmp/tough-inverted-deep-20260921.log` 与同名 xcresult：2 项，57.888 秒。
- `/private/tmp/tough-modes-final-20260921.log` 与同名 xcresult。
- `/private/tmp/tough-modes-core-20260921.log`、`tough-modes-compat-20260921.log`、`tough-modes-package-20260921.log`。

最终 iPhone 和 Mac 构建通过，iPhone 安装包严格签名验证通过。实际评审截图位于 `outputs/contacts-design-review/assets/inverted-tree-native-*-20260921.png`；目录截图为 `directory-mode-native-20260921.png`。

## 真机补验

02:26，1.0（16）签名验证、原位安装与正常启动成功。首轮 3 项测试未通过：点击结构后仍停留在列表，目标节点/模式入口不可达。AX 记录显示未选中结构按钮只有 26 × 15.7 点，而设计 frame 高度为 44 点。已给标签完整 frame 增加 contentShape(Rectangle)，并在用例加入点击区域高度断言。修正后高度断言通过，但原机复验仍未进入结构页。不将此问题直接等同于此前其他底栏失败。

首轮证据：`/private/tmp/tough-modes-phone-20260921.log` 与同名 xcresult；失败 AX 在 `/private/tmp/tough-modes-phone-evidence-20260921/80785511-514E-4F9A-8DDC-D02C321DE1BA.txt`。

随后检查第二轮失败录屏，确认手机画中画视频覆盖顶部视图切换区域，点击被系统浮窗拦截。此遮挡是本轮无法切页的直接证据，44 点点击区域修正不能消除浮窗。已请用户暂时移开画中画，再继续真机验收；未将两轮失败算作功能通过。第二轮证据为 `/private/tmp/tough-modes-phone-fix-20260921.log` 与同名 xcresult，截图仅留本机临时诊断目录，未放入评审站。

02:31 通过 `--terminate-existing` 结束测试会话，不带测试环境变量正常启动成功。最终 Mac 构建通过（`/private/tmp/tough-modes-mac-hitarea-20260921.log`）。评审站原生页面切换与临时批注保存、读回、清理通过；原设计图与历史批注保留。

最终点击区域修正后的模拟器再次通过目录编辑/取消/撤销与完整倒树操作 2 项（57.349 秒），证据 `/private/tmp/tough-modes-hitarea-sim-20260921.log` 与同名 xcresult。

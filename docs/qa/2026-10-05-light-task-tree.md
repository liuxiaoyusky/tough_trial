# 2026-10-05 · 轻树评审

用户认为原倒树卡片过重、不像树。本轮沿用 design-foundation 的灰度层级、边界减法和可读状态，先更新 spec 与既有 design-system，再修改生产 SwiftUI。

## 改动

- 移除常态节点卡片、描边、展示根底块，以透明文字节点和细 Bézier 曲线表达关系。
- 根 / 分支使用 titleMedium，叶节点 bodyMedium；不以随机色块或大圆角表达节点。
- 节点基础高度从 96 降至 64 点，标题和展开计数 / 箭头并排；字号仍随系统缩放。点击区与视觉符号独立，选择与展开分别保留至少 44 点且不重叠。
- 只有当前选择使用弱蓝底；完成继续显示勾选、已完成、删除线和可读的次级文字。
- 保留单一未分类展示根、真实任务父子关系、独立展开、聚焦 / 返回、缩放 / 复位和右下角新增。未改 Core 布局、任务模型、领域命令或 Mac 页面。

## 验证记录

开发构建 **1.0（22）Debug / iPhone 13 Pro / iOS 26.5**，合成数据与系统 light，生产 View；未归档或分发。此次图片使用新 ID，21 号和更早图 / 批注保留。

- swift test --filter InvertedTreeLayoutTests、swift run ToughTrialV2Checks、swift run FocusTimelineCoreChecks、swift build 均退出 0。
- `/private/tmp/tough-trial-20261005-light-task-tree.xcresult`：3 个限定原生交互用例通过，0 失败。实际验证单 / 多根、展示根不打开详情、默认缩放下选择 / 展开区域至少 44 点且不重叠、两个分支、详情、聚焦 / 逐级返回、缩放 / 捏合 / 上下限禁用 / 复位、六层纵横拖动、空态、取消空输入新增，以及完成叶节点恢复 / 撤销与完成父节点。
- 总览、选中、完成、多根 4 张新评审图从通过的原生操作附件逐字节拷贝，1170×2532 像素不修图。源附件、图像摘要和结果包登记在 `.runtime/light-task-tree-20261005/screenshots.json`；聚焦、六层与空态的原始附件另保留在该目录 attachments。
- 选择与展开点击区分离断言通过，不因缩小视觉符号缩小命中区。UI 测试不替代审美认可；当前样式待用户评审。

## 范围

本轮不声称真机、完整大字体、VoiceOver、当前 TestFlight 或 R1 发布验收已通过。宽树仍横向拖动，长标题两行预览，全文从详情查看。

本机评审：[轻树总览](http://127.0.0.1:8770/#structure-light-tree-20261005)、[完成状态](http://127.0.0.1:8770/#structure-light-completed-20261005)、[选中 / 详情](http://127.0.0.1:8770/#structure-light-selected-20261005)、[多根](http://127.0.0.1:8770/#structure-light-forest-20261005)。

评审验证：当前 66 页 / 21 个功能，4 张新图正确关联 ui.tasks.structure。独立 390×844 Chromium 会话核对真实图片摘要和 22 号来源，实际点批注、画圈、取消未保存、保存、刷新、导出与删除本次测试批注通过；0 页面错误，旧用户批注未改。未在 iPhone Safari 或远程网站复验。

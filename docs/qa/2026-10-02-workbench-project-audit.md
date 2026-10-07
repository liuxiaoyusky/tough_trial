# 2026-10-02 · 工作台功能与交付状态核对

本轮处理用户“开发散碎、需要明确关注点”的请求。使用
`~/Documents/github/ai-dev-workbench/skills/ai-dev-workbench/SKILL.md`
及工作台 0.2.0，核对本项目 Spec、roadmap、源码与历史 QA；只调整功能索引和进度说明。
当前状态与下一轮目标只维护在 [roadmap](../roadmap.md)。本记录是本次审计证据，不另立进度表。

## 已完成的整理

- 唯一地图仍为 `docs/feature-map.json`，从 13 条补至 21 条；新增统计、Mac、日程同步、全量备份、联系人、转录、评审 CLI 和模块框架。按登记范围分为 15 个已有实现基线、3 个部分实现、3 个仅设计；这些数量不是人工验收完成率。
- 稳定项目 ID 改为 `tough-trial`，显示名保留为 `title: Tough Trial`，与工作台和共享项目 root 对齐。历史调用记录保持原状。
- 每条 `delivery` 分开记录实现、历史技术证据和待完成人工验收；保留原 Spec/QA 来源。没有将截图、源码或本次地图检查写成 App 运行通过。
- 初始引用检查发现 13 项旧摘要，对应 `docs/spec.md` 和桌面评审 `index.html` 两个文件。读完整 Spec、查看桌面页面及相关 Git 差异后更新这些引用；本轮修改的 FeatureCLI README 另更新 2 项引用。其他既有 evidence 摘要保留，不全量重算掩盖变更。
- 补正统计状态：9/16 的 5 项基础统计测试已有通过记录；标签/分类钻取/趋势图和当前真机体验仍开放。
- 补正同步范围：9/7 真机 iPhone 测试 Engine 与独立 Mac 脚本真实 GitHub 往返通过；当时手机完整 UI 退出/重启失败。它不等于当前正常 iPhone App + 原生 Mac UI 的双端验收。
- 将独立转录纳入清单：已有源码接线，未找到专项测试/运行 QA；本次未核实它是否包含在已安装构建中。
- 已刷新 `docs/ui-feature-index.md` 和 `mobile-review-project.json`，并构建本地 `outputs/mobile-review-cli`。44 张图的页面 ID、Feature ID、图片路径、kind、provenance 与整理前一致；没有换图或挪动旧批注。手机 Site 未重新发布。

## 工作台与 Ontology 边界

共享库登记项目 `tough-trial`，root 为当前仓库。仅新增以下来源记录，未新增运行时关系或迁移整张本地图谱：

- `tough-trial:evidence.review-links-source.20261002`：`source` 类，固定现有检查脚本摘要。
- `tough-trial:tool.review-links`：`CodeModule`，表示本地关联检查入口。

共享库 validator 通过。`ui.review-links` 新增 `validate-links-readonly`，沿用已有脚本默认只读模式；旧写索引操作保留。其他历史裸 Ontology ID 仍引用仓库局部图谱，不宣称所有功能均已接入受管执行。

本地 `ontology.py check` 返回过期：`Sources/ToughTrialMacApp/MacAppModel.swift` 增加转录侧栏。已查看差异，工具拒绝旧行号，未静默重建或把旧索引当当前调用证据。当前局部模型为 44 节点、38 关系；全量语义调用图、运行 trace 和根因排序仍未实现。

## 本次真实检查

| 检查 | 结果 / 限定范围 |
| --- | --- |
| 工作台 Feature Map check | 159 项引用 current；仅本地引用一致 |
| FeatureCLI 工具测试 | 6 项通过；正常、过期、漏页/重复/错图、未知实体及越界 |
| 评审关联检查及重新生成索引 | 44 页、0 映射错误；不验证 App 控件 |
| mobile-review check/build | 44 图、12 个有画面的 UI 功能；没有新 App 渲染/重拍 |
| 受管任务 plan/create/run 预览/apply | 一次实际只读运行，completed、exit 0，无重试 |
| evidence show / task status / history | 终态及原生回执 consistent；technical passed，human pending |

运行 ID：

- task：`task_1b6861b690fedd759714c973`
- candidate：`candidate_16aa7ab4036a544e6e3e95dbaf3f8e29aad83490caa996a38937c88bb23c687d`
- workbench run：`wb_run_39291a19e631102169f5638a`
- native run：`run_7505e53603e4f63fdc251b9c1cac06b7`
- trace：`bb3e4242b942822709e6665810616a6b`；仅本地调用传播，`cross_service_verified=false`。

request、数据库和原生回执位于被忽略的 `.runtime/workbench` / `.runtime/feature-cli`。工作台只固定该功能的登记来源；未登记文件不在候选版本保证内，不能据此说整个仓库已验证。

回查命令（仓库根执行）：

```sh
WORKBENCH="$HOME/Documents/github/ai-dev-workbench/skills/ai-dev-workbench/scripts/workbench.py"
python3 -B "$WORKBENCH" --state-dir "$PWD/.runtime/workbench" evidence show --run wb_run_39291a19e631102169f5638a
python3 -B "$WORKBENCH" --state-dir "$PWD/.runtime/workbench" task status --task task_1b6861b690fedd759714c973
```

## 产品状态没有被此次检查关闭

最近由用户确认安装的是 TestFlight 1.0（17），但当前工程默认构建号仍为 10；9/30 使用既有 archive。工作区和已发布包不能自动视为同一候选。下一次交付需明确源码、OS/设备、构建号和画面来源。

TestFlight 17 随手记可读性反馈仍开放；附件 `thumbnail` 的 `fileprivate` 声明与跨文件测试调用仍存在，源码及历史 QA 指向测试编译阻塞。本次未执行 Xcode/App 全套测试，未以新的失败或通过代替历史记录。

自然输入/语音、真实模型搜索引用、当前原生双端同步、用户 Safari 体验、重复规则、联系人和全量备份的缺口均保留。此轮完成的是审计、收束与索引接入；没有修改原生 App、手机数据、发布新构建、commit 或 push。

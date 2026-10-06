# Feature Map 与开发工作台

当前统一使用 `$ai-dev-workbench`。`docs/feature-map.json` 是唯一功能地图；
`docs/roadmap.md` 是当前状态和交付顺序入口。`docs/ui-feature-index.md` 和
`mobile-review-project.json` 是评审投影，不是另一份进度表。

地图的稳定项目 ID 为 `tough-trial`；`title` 保留显示名。`delivery` 扩展记录
实现范围、历史技术验证和人工验收缺口，状态来源仍指向 roadmap 与原 QA。
没有画面的功能使用 `code` 扩展登记源码定位，不虚构截图或完整调用图。
`ontology_refs` 的历史裸 ID 指向仓库内图谱；它们尚未迁移为共享实体，不能
把工作台查询地图成功当作共享 Ontology 全模块接入。当前受管检查只接入
`ui.review-links / validate-links-readonly`，共享实体是
`tough-trial:tool.review-links`，仅有源码证据。

```sh
WORKBENCH="$HOME/Documents/github/ai-dev-workbench/skills/ai-dev-workbench/scripts/workbench.py"
python3 -B "$WORKBENCH" tool feature-map --root "$PWD" --map docs/feature-map.json list
python3 -B "$WORKBENCH" tool feature-map --root "$PWD" --map docs/feature-map.json check
python3 -B "$WORKBENCH" --state-dir "$PWD/.runtime/workbench" project inspect --project tough-trial
```

受管检查的 request、task 和运行回执保存在被忽略的 `.runtime/workbench`；
技术检查通过不代表产品效果或用户验收通过。来源改变后检查差异、重新登记，
不要沿用旧 task 或只改哈希消除告警。

## UI 差异排查

初始排查登记 `ui.capture`，操作 `inspect-baseline`。需求继续以 `docs/spec.md`、
`docs/design-system.md` 为准，用户反馈和验收结论继续写入现有 TestFlight QA；
不建立第二份业务 Spec 或 Ontology。关联扩展时已确认现有图谱的
`code.capture.save` 可定位原文保存；它是关联入口，不代表覆盖全部 UI 或调用链。

以下原生调用也经工作台入口转发（Python 3.11+）：

```sh
python3 -B "$WORKBENCH" tool feature-map --root "$PWD" --map docs/feature-map.json search 随手记
python3 -B "$WORKBENCH" tool feature-cli --root "$PWD" --map docs/feature-map.json doctor ui.capture --operation inspect-baseline
python3 -B "$WORKBENCH" tool feature-cli --root "$PWD" --map docs/feature-map.json plan ui.capture --operation inspect-baseline --param baseline=outputs/contacts-design-review/assets/capture-native.png
python3 -B "$WORKBENCH" tool feature-cli --root "$PWD" --map docs/feature-map.json run ui.capture --operation inspect-baseline --param baseline=outputs/contacts-design-review/assets/capture-native.png --task-id ui-parity-20260930 --artifact .runtime/ui-audit/capture.json --apply
```

执行只读取源码、PNG 元数据和 Git 历史/状态，写本机诊断报告及 CLI 调用记录，
不操作设备、不改 App、不上传。报告是当前位置索引，不能证明线上包一致、视觉一致
或深浅色假设成立。当前地图中的评审素材已逐项纳入仓库，原生新增图使用 `docs/qa/assets/` 的单份原图及 `outputs/` 相对链接；额外本机输出仍忽略。缺失时明确阻塞，
不能用占位截图替换。来源变化时先核对差异，再维护当前功能的 evidence 哈希。

正常输入是现有 `capture-native.png`；失败输入可用 `docs/spec.md`（不是 PNG），
应返回退出码 2 且不覆盖成功报告。运行后用 CLI 的 `status`、`evidence`、`verify`
和 `history --task-id ui-parity-20260930` 回查；失败调用也应有完整记录。

## 画面与功能的双向关联

唯一事实入口是 `docs/feature-map.json` 的 `ui` 扩展：

- `route`：产品内入口；`code`：当前源码路径和符号（导航定位，不是已解析调用关系）。
- `implementation_status`：功能实现状态，与截图类型分别记录。
- `review_pages`：稳定页面 ID、图片路径、`design/simulator/device` 类型、来源/版本、验收说明及评审 hash 路由。

所有现有评审页面必须有唯一对应 Feature，文件必须存在，页面 ID 与图片名必须一致。
`ui.review-links / validate-links` 执行这项检查，并生成 `docs/ui-feature-index.md`；
评审服务从 `/api/features` 动态读取同一地图，引用变化显示 `needs_review`。
校验只证明关联完整；设计稿、历史模拟器截图、当前真机截图均不自动赋予“验收通过”。
不存在对应实现的重复规则明确保持设计态，不生成虚假的代码绑定。

```sh
python3 Tools/FeatureCLI/review_links.py --write-index
python3 -m unittest discover -s Tools/FeatureCLI -p 'test_*.py'
REVIEW_PORT=8770 python3 outputs/contacts-design-review/server.py
```

当前地图引用的图片与概念稿随仓库提供，全新克隆可以直接校验 / 生成手机评审包；派生输出、个人批注、原始运行日志和额外本机素材不提交。
云端站不会随本地修改自动更新。批注继续使用原页面 ID，不改变旧坐标。

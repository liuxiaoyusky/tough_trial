# 2026-09-30 · 画面与 Feature Map 关联

## 范围与事实来源

- `docs/feature-map.json` 是唯一关联源，`ui` 扩展覆盖 44 个现有/新增评审画面、12 个产品功能。
- 另有 `ui.review-links / validate-links` 开发校验入口。设计和验收规则仍引用原 Spec、QA 与 Ontology，不另建业务规则。
- 新增随手记历史 SVG 与用户提供的 1.0（17）实机反馈图，和旧原生截图归入 `ui.capture`。保留旧页面 ID、图片和批注坐标。
- `docs/ui-feature-index.md` 是工具生成的反向索引；网站 `/api/features` 每次读取同一地图并检查本地引用。

## 已执行验证

- Feature Map `check`：112 个引用均 current。此结果仅证明本地文件引用一致。
- `python3 -m unittest discover -s Tools/FeatureCLI -p 'test_*.py'`：6 项通过，覆盖正常映射、旧图变化提示、漏页、重复映射、图片错配、未知 Ontology 和越界路径（其中正常与旧图变化合并在同一用例）。
- Feature CLI doctor、plan、run、verify 均实际调用。运行 ID：`run_143b4dc0099a3e0e5662e4e844374004`，task：`ui-feature-links-20260930`；终态 completed，证据 consistent。
- 浏览器实际操作：筛选随手记、从当前实机画面切到历史示意图及旧原生截图、展开源码/验收来源；重复规划筛选后明确显示仅设计。
- 创建一条专用测试批注、保存、刷新读回、删除并确认列表恢复 0 条。没有删除用户批注。
- 网站运行于 `http://127.0.0.1:8770/`。Codex 内置浏览器控制不可用，使用本机浏览器完成交互验收。

## 边界

本轮未修改原生 App，未重新发布 TestFlight，未修复之前的视觉差异。
历史截图的构建号没有证据时明确标记未锁定，不将时间或文件名推断成安装版本。
重复规则无已实现代码绑定；源码位置是定位线索，不等于已解析调用图或运行根因。
云端手机评审站未自动更新；当前交付为本机评审站与仓库关联数据。

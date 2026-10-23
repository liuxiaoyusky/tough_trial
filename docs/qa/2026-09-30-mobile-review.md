# 手机评审工作台 · 2026-09-30

范围：纯前端画面展示、画圈/点位批注、本浏览器保存与 JSON 导入导出。复用 Feature Map 的 44 张原图（29 张原生截图、15 张概念稿）；没有改原生 SwiftUI 页面，没有上传新 TestFlight 包。

## 实际验证

- `node --test Tools/MobileReview/test_annotations.mjs`：5 项通过。覆盖序列化轨迹、图片 revision 隔离、合并去重/保留较新修改、拒绝跨图 ID 冲突、错误项目/非法坐标。
- `python3 -m unittest discover -s Tools/FeatureCLI -p 'test_*.py'`：6 项通过。
- `node --check Tools/MobileReview/web/review.js` 与 `git diff --check` 通过。
- CUA 浏览器 390×844：DOM 宽度 390，无页面横向溢出；原图按宽度展示，不通过重绘改变 App 外观。
- 实际拖画（导出轨迹含 9 个坐标点）→填写→保存→刷新→读回；编辑保存、已处理、重新打开均通过。
- 导出按钮生成 `tough-trial-review-2026-09-30.json`，实际检查版本摘要、文字与轨迹；通过文件选择器重新导入，仍为 1 条并显示合并成功。
- 撤销圈画、取消未保存草稿、点位打开输入框（无轨迹时撤销禁用）、放大/适应、前后翻页通过。
- 功能过滤到重复规划 + 原生画面显示空态；切换概念稿显示 9 页；选择概念页并查看来源，明确标记业务未实现、原生一致性待验证。
- 实际删除本次唯一测试批注，结果为本项目 0 条、导出禁用；旧桌面 feedback.json 未修改。
- 修复同页 hash 深链接切换不更新视图的问题；实际依次跳转随手记 TestFlight 与今天，页面标题均正确。浏览器临时手机尺寸设置已恢复。

截图：[手机尺寸评审与测试轨迹](assets/2026-09-30-mobile-review/phone-review.jpg)。截图中的红线为验证用轨迹，已从测试浏览器删除。

## 交付与限制

- 源码：`Tools/MobileReview/`。构建导出：`outputs/contacts-design-review/mobile/`。旧桌面评审保留。
- 本地：`http://127.0.0.1:8770/mobile/`，手机远程不能用本机回环地址。
- 原有私有 Site 已更新，保留原受众，不扩展公开访问。网址：`https://tough-trial-review-20260929.sky-liu-xiji.chatgpt.site`。版本 2、源码 `9a26fdf5ece6ea6abd67ce285606e19abf1063ce`、发布 `appgdep_6abd08c946e48191a6da7a865feec0d9`；官方状态于 2026-09-30T13:05:19Z 确认为 succeeded。首次调用传输断开后通过版本与发布状态恢复确认，未重复发布。网站画面仍是各自注明版本的历史证据，未重拍所有模块。
- 以上是桌面浏览器模拟手机尺寸的实际操作，不是 iPhone Safari 真机测试；Safari 触控、键盘遮挡及系统分享仍需用户手机确认。
- 批注只保存在当前浏览器；不能自动进入 Codex 或另一台设备。用户导出后发回对话，或在另一端导入。不支持实时多标签页冲突处理。
- 已有概念稿未转换成 SwiftUI 渲染图。新视觉定稿走同一生产组件/主题，现有 TestFlight 17 视觉差异仍开放。
- App 内操作反馈和 TestFlight 聚合已列入低优先级 roadmap，本次不开发。

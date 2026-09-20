# 回想双模式验收

## 已验证

- 回想页初次进入不自动弹出键盘。
- 点按文字纸面后立即进入输入状态。
- 文字与手写在同一张纸内切换，不打开独立页面。
- 切换到手写再返回文字时，文字草稿仍然保留。
- 只有手写、没有文字的回想可以完成并持久化。
- 旧版回想数据缺少 `hasHandwriting` 字段时仍可读取。

## 证据

- `text-mode.png`：文字模式初始状态。
- `handwriting-mode.png`：同页手写模式与紧凑工具条。
- Core checks：`swift run --disable-sandbox ToughTrialV2Checks`
- Swift build：`swift build --disable-sandbox`
- iOS UI tests：6 passed，0 failed。

## 尚未验证

- 真机 Apple Pencil 的压感、悬停和手掌防误触体验。

# 手机画面评审

## 通用 CLI（1.0.0）

已提供 `cli.py`，Python 3.10+ 标准库即可运行，不依赖 Tough Trial、Node 或 Xcode。全局命令 `mobile-review` 与全局 skill `$mobile-review` 共用此实现。

```sh
mobile-review --help
mobile-review check --manifest mobile-review-project.json
mobile-review build --manifest mobile-review-project.json --output outputs/mobile-review-cli
mobile-review serve --directory outputs/mobile-review-cli --port 8771
```

完整创建项目、Feature Map 适配及批注导入命令见 [CLI 格式](../../skills/mobile-review/references/cli.md)。仓库直接调用可将 `mobile-review` 换成 `python3 Tools/MobileReview/cli.py`。`mobile-review-project.json` 是从 Feature Map 生成的本机快照，已忽略，不重复提交。克隆后先导出再构建：

```sh
python3 Tools/MobileReview/cli.py from-feature-map --root . --map docs/feature-map.json --id tough-trial --title "Tough Trial · 手机页面评审" --output mobile-review-project.json
python3 Tools/MobileReview/cli.py check --manifest mobile-review-project.json
python3 Tools/MobileReview/cli.py build --manifest mobile-review-project.json --output outputs/mobile-review-cli
```

映射改动后重新导出；不维护第二份事实源。

`package_skill.py` 将 CLI 与 web 资源复制进 `skills/mobile-review/scripts/`，生成自包含的 skill（scripts 是忽略的生成物）；克隆后或修改 CLI/web 后先重新打包，再同步全局安装，避免两个实现分叉。全局位置是 `~/.codex/skills/mobile-review`，命令软链接是 `~/.local/bin/mobile-review`。

验证：`python3 -m unittest discover -s Tools/MobileReview -p 'test_cli.py'`；浏览器批注契约继续用下方 Node 测试。本次 CLI 不带远程部署或登录能力，运行 serve 不会改变先前手机站。

## 既有 Tough Trial 导出脚本

纯静态前端；读取 Feature Map 派生的 review.json 和原始图片。没有上传端点、API token 或 App 运行日志采集。图中控件不可操作。

```sh
python3 Tools/MobileReview/build.py --output outputs/contacts-design-review/mobile
node --test Tools/MobileReview/test_annotations.mjs
REVIEW_PORT=8770 python3 outputs/contacts-design-review/server.py
```

本机打开 `http://127.0.0.1:8770/mobile/`；手机远程使用同一包的私有托管网址。生成目录必须重新导出后才能反映 Feature Map 更新。发布只打包 web 文件、派生 manifest 与映射中的图片，不能发布项目根目录、个人业务数据或凭据。

## 视觉一致性

- 原生画面默认优先；保持原图，不用 CSS/SVG 重绘 App 截图。
- 原图来源、日期、版本从 Feature Map 读取。历史图不代表当前代码；未知构建号不猜测。
- 概念稿明确标记未经原生一致性验证；未来定稿由生产 SwiftUI View / V2Theme 在目标 iOS 渲染，用合成数据隔离业务。评审通过后继续复用同一 View，不能另做一套。
- 当前只建设评审载体，未重拍所有界面，未修复 TestFlight 17 的原生视觉问题。

## 批注与版本

- localStorage key 为 `native-review:tough-trial:v1`。保存局限于同一来源、同一浏览器；不声称云同步或离线缓存完整站点。
- 点位与自由圈画使用 0–1 原图坐标；图片 SHA-256 作为 revision，导出素材也以摘要命名。缩放不改变坐标；新图片不能接收旧 revision 的标记。
- 导出 JSON 含项目、功能、页面、原图摘要、来源、文字、轨迹与处理状态；iPhone 支持时调用系统分享，否则下载。
- 导入先完整验证再合并；不同项目拒绝，同 ID 跨图片拒绝，较旧修改不能覆盖较新批注。未知历史图片的批注保留在历史列表及导出包里。
- 本机旧版 `/api/feedback` 数据不覆盖、不自动迁移；桌面原评审页继续可用。跨手机/电脑传递本阶段通过导出/导入，AI 不会自动看到浏览器里的意见。
- 清除浏览器网站数据会清除批注；及时导出。没有实施可靠多标签页实时合并。

## 后续

App 内真实操作反馈、TestFlight 反馈聚合与独立评审 App 都延后。GitHub 远程授权导入、多用户云同步和通用项目选择器尚未实现；本阶段从已有仓库导出单个项目。

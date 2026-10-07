# 命令与文件

下面命令均在目标项目根目录运行；若未安装命令，将 `mobile-review` 替换为 `python3 <skill目录>/scripts/mobile-review.py`。

```sh
mobile-review init --id my-app --title '我的 App'
mobile-review add --id today --feature ui.today --title 今天 --image screenshots/today.png --kind simulator --provenance '2026-10-01 · iPhone 模拟器 · build 18'
mobile-review check
mobile-review build --output outputs/review
mobile-review serve --directory outputs/review --port 8771
```

`init` 不覆盖已有文件。图片必须在清单所在目录或其子目录，不能通过 `..` 或软链接越界。先将项目有权使用的图片放入该目录。`add` 不替换同 ID 页面；更新已有页时显式编辑清单，构建重新计算图片摘要。

默认清单 `review-project.json`；可用 `--manifest` 指定。最小格式：

```json
{
  "schema": 1,
  "project": "my-app",
  "title": "我的 App",
  "pages": [{
    "id": "today",
    "feature_id": "ui.today",
    "title": "今天",
    "image": "screenshots/today.png",
    "kind": "simulator",
    "provenance": "iPhone 模拟器 · 构建号未知"
  }]
}
```

kind：`design` 概念稿、`native-preview` 原生设计预览、`simulator` 模拟器实图、`device` 手机真机实图、`desktop` 桌面实图、`web` 网页实图。支持 PNG/JPEG/WebP/SVG；SVG 和截图必须来自可信项目资源。

页面可选字段：`feature_title`、`route`、`implementation_status`、`verification`；`code:[{"path":"Sources/Today.swift","symbol":"TodayView"}]`；`acceptance:[{"source":"docs/qa/today.md","expected":"暂停后保存本段"}]`。这些引用只供定位，不能证明根因或运行正确。

## 已有 Feature Map

```sh
mobile-review from-feature-map --root . --map docs/feature-map.json --id my-app --title '我的 App' --output review-project.json
```

适配 `features[].ui.review_pages[]`：页面字段同上，功能 ID 和标题来自外层 feature；ui.code/route/implementation_status 与 feature.acceptance 会一并带入。输出清单应位于全部图片的共同祖先目录，且不覆盖旧清单。它不会联网克隆仓库；读取本地已有仓库。

## 收回手机批注

```sh
mobile-review import-feedback --review outputs/review/review.json --file ~/Downloads/my-app-review.json
mobile-review feedback --review outputs/review/review.json --markdown review-feedback.md
```

反馈库默认 `.mobile-review/feedback.json`，可用 `--store` 指定。库不进入 build 输出。JSON 报告包含 `image_status: current|historical`，历史画面不能按当前坐标实施修改。导入拒绝错误项目、重复 ID、非法坐标和同 ID 跨图冲突，不覆盖较新的意见。

## 运行和发布

`serve` 前台运行，Ctrl-C 停止；端口占用会非零退出，不杀其他服务。`--port 0` 可自动选空闲端口并返回实际端口。`--host 0.0.0.0` 仅用于已授权的局域网共享。

build 输出只包含前端、review.json、已登记图片及工具所有权清单。已有非工具目录或夹带未登记文件时拒绝更新，避免把凭据或源码当成站点发布。工具生成的历史图片保留，新的图按摘要追加。发布用该输出目录；托管与认证由部署工具处理。

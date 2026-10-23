# 手机评审 CLI 与 skill

- CLI 1.0.0：init、add、from-feature-map、check、build、serve、import-feedback、feedback；统一 JSON 结果与非零错误退出。
- Python 3.10+ 标准库，前端资源自包含。全局入口 `~/.local/bin/mobile-review` 指向 `~/.codex/skills/mobile-review/scripts/mobile-review.py`。
- skill 源：`skills/mobile-review/SKILL.md`；已打包 CLI/web 并安装全局。不依赖当前项目绝对路径，不包含用户截图/批注、凭据或业务数据。
- 6 项独立临时项目集成测试通过：脱离 Tough Trial 构建、重建、图片换版/保留旧图、拒绝非工具目录/夹带文件、拒绝重复初始化与越界软链接、反馈合并/报告/冲突保留。
- 5 项前端批注测试通过；JS 语法检查通过；skill 官方 quick_validate 通过；git diff --check 通过。
- 实际从 `/private/tmp` 运行全局 CLI，返回版本 1.0.0、44 图引用检查通过。实际适配本项目 Feature Map 得到 44 图、12 功能，并构建成功。
- serve 于 127.0.0.1:8771 启动，首页、review.json、JS/MJS HTTP 200，工具清单与目录外文件 HTTP 404。手机远程不能直接使用该回环地址。
- 本轮不更新已发布手机 Site，不变更原生 App。不声称 CLI 检查等于视觉或交互验收；浏览器圈画验收延用 9/30 记录，本次新增测试重点是 CLI 输入/输出和反馈安全合并。

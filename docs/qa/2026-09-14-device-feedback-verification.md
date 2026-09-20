# 用户反馈修复版真机验收

日期：2026-09-14；设备：sky / iPhone 13 Pro；版本：1.0（11）。

## 已确认

- 用户告知已连接后，CoreDevice 返回 `available (paired)`。
- 主项目 Sources、Tests、Checks、Package.swift 和 project.yml 与先前通过本地验收的隔离工作区逐文件哈希一致。
- 从主项目独立构建目录生成 Debug 正常使用版，构建时指定 `CURRENT_PROJECT_VERSION=11`；包内版本核对为 11，签名验证通过。
- 09:57 原位安装成功，09:58 不带测试参数的启动成功；没有卸载应用或清空数据。
- 安装内容为 A–D 已完成的体验修复。9 月 13 日新增的财务统计页仍待设计与开发，不在本包内。

## 本轮验证

| 检查 | 结果 |
| --- | --- |
| 文档输入组件 | 6 项设备 XCTest 通过：首段拆分、正文保留、换行、空内容、光标回调及听写文本绑定。属于组件测试，不等于真实 IME 或自然语音操作通过。 |
| 生产搜索客户端 | 绕过模型在手机上直接查询 Swift 官方文档，返回 3 个来源，约 1.45 秒；测试通过。 |
| 真实模型联网会话 | 手机已有 MiniMax / MiniMax-M2.7-highspeed 可用配置；两次基线合成查询均未执行网页搜索、没有来源卡片，用例失败。未修改任务、排期与账本的断言通过。 |
| 最小提示实验 | 明确 JSON 网页动作调用格式后，一次进入网页动作但失败，另一次仍在其他工具间循环至上限；未达到稳定验收标准，实验改动已撤回。保留诊断日志，不将其作为交付修复。 |

真实联网使用已有服务配置、合成查询与内存领域数据；一次性标记授权运行，不输出或复制密钥，不把测试查询保存为用户任务或账单。独立搜索通过说明手机当时能够访问搜索服务；模型为何未稳定使用网页动作仍待进一步定位，不能将上述失败笼统归因为手机断网。

本轮没有保留生产源码变更。最终恢复安装独立构建的正常使用版，不带测试参数启动；唯一新增测试为一次性授权的手机生产搜索探测。

自然中文输入法、60 秒自然语音、原反馈用户完整操作与回访仍待完成。设备测试与安装成功不能替代这些体验验收。

## 证据

- 构建：`/private/tmp/tough-ux-e-device-build-20260914.log`
- 安装：`/private/tmp/tough-ux-e-install-20260914.json`
- 首次启动：`/private/tmp/tough-ux-e-launch-20260914.json`
- 设备定向测试：`/private/tmp/tough-ux-e-tests-20260914.log` 与同名 `.xcresult`
- 真实模型诊断：`/private/tmp/tough-ux-e-web-diagnostic-20260914.log`
- 提示实验：`/private/tmp/tough-ux-e-web-fix1-20260914.log`、`/private/tmp/tough-ux-e-web-network-20260914.log`
- 独立生产搜索：`/private/tmp/tough-ux-e-transport-20260914.log` 与同名 `.xcresult`
- 测试后正常安装、启动及版本核对：`/private/tmp/tough-ux-e-final-install-20260914.json`、`/private/tmp/tough-ux-e-final-launch-20260914.json`、`/private/tmp/tough-ux-e-final-version-20260914.json`

这些日志为本机临时证据。历史 9 月 12 日 QA 中“手机不可连接、尚未安装”的描述属于当时状态，本记录追加本轮进展，不改写历史事实。

# Assistant Home Implementation Plan

**Goal:** 实施用户批准的助手主页路线图 P0–P5。
**Architecture:** 保留 SwiftUI + typed Core；主页/消息主线程集成，模型配置与 Compact 隔离工作区实现，集成后统一验证。
**Spec:** docs/superpowers/specs/2026-09-11-assistant-home-design.md

- [x] P0 引用契约、草稿持久化、长输入编辑和消息操作；验证引用序列化和重启草稿。
- [x] P1 Root Tab 默认助手、来源跳转、统一消息布局；模拟器长输入/Tab/消息 UI。
- [x] P2 服务/模型/thinking 有效配置及界面；能力映射和切换回归。
- [x] P3 通用语义路由、补充队列和连续工具回合；问候/否定/混合工具回归。
- [x] P4 Compact 无收益处理与指标；原文保留、实际发送缩减验证。
- [x] P5 本地部分：Core/App/UI 验证、审阅、正常签名包，更新 QA。
- [x] P5 安装：1.0 (5) 真机安装与启动成功。
- [ ] P5 外部体验：真实服务自然多轮与真机完整交互验收；结果分开记录。

保留当前未提交工作，不整体提交或重置；worker 只返回指定文件。测试失败先查根因，设备不可用不伪称验收。

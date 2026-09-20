# 财务、附件与插件实施计划

Goal: 用户能添加带附件的订阅及待付款提醒，确认支付后联动真实花费/预算，并按需启停或加载功能。
Architecture: Core typed models + engine atomic commands; SwiftUI Store and shared attachment presentation; local notifications; bounded declarative manifests.

1. 独立工作区 finance Core：新增 V2FinanceModels/Engine 与测试。主线程负责 snapshot 字段及页面/通知集成。
2. 独立工作区附件组件：新增共享 picker/thumbnail/QuickLook，主线程接入随手记与订阅页，统一原件保存。
3. 主线程功能manifest、启停持久化与入口；加载第三方声明式表单保存到Capture。
4. 财务UI：总览、编辑/详情/支付/撤销、预算、跳转和提醒；共用既有ledger。
5. 核心与App/UI验收、Xcode构建和可用真机安装，记录实际验收边界。

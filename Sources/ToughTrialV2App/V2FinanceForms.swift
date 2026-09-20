import SwiftUI
import ToughTrialV2Core

private enum FinanceDate {
    static func formatter(_ zone: String = TimeZone.current.identifier) -> DateFormatter {
        let value = DateFormatter(); value.locale = Locale(identifier: "en_US_POSIX")
        value.calendar = Calendar(identifier: .gregorian); value.timeZone = TimeZone(identifier: zone)
        value.dateFormat = "yyyy-MM-dd"; return value
    }
}

struct V2FinancePlanEditor: View {
    @ObservedObject var captureStore: V2CaptureStore
    @Environment(\.dismiss) private var dismiss
    @State private var plan: V2FinancePlan
    @State private var date: Date
    private let existing: V2FinancePlan?
    init(captureStore: V2CaptureStore, existing: V2FinancePlan? = nil) {
        self.captureStore = captureStore; self.existing = existing
        let value = existing ?? .init(title: "", kind: .subscription, amount: "", currency: "CNY",
            dueDate: FinanceDate.formatter().string(from: Date()), recurrence: .monthly)
        _plan = State(initialValue: value)
        _date = State(initialValue: FinanceDate.formatter(value.timeZoneIdentifier).date(from: value.dueDate) ?? Date())
    }
    var body: some View {
        NavigationStack {
            Form {
                if existing == nil {
                    Section("快捷填写") {
                        HStack {
                            Button("ChatGPT") { plan.title = "ChatGPT"; plan.link = "https://chatgpt.com/"; plan.currency = "USD" }
                            Spacer()
                            Button("GLM") { plan.title = "GLM"; plan.link = "https://open.bigmodel.cn/"; plan.currency = "CNY" }
                        }.buttonStyle(.borderless)
                        Text("金额按你的实际账单填写。可以随时修改。 ").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("账单") {
                    TextField("名称", text: $plan.title).accessibilityIdentifier("finance.title")
                    Picker("类型", selection: $plan.kind) { ForEach(V2FinancePlanKind.allCases, id: \.self) { Text($0.label).tag($0) } }
                        .onChange(of: plan.kind) { _, kind in plan.direction = kind.defaultDirection }
                    TextField("金额", text: $plan.amount).v2KeyboardType(.decimalPad).accessibilityIdentifier("finance.amount")
                    TextField("币种（CNY / USD / HKD）", text: $plan.currency).v2Autocapitalization(.characters).autocorrectionDisabled()
                    Picker("记入流水为", selection: $plan.direction) {
                        Text("支出").tag(V2LedgerDirection.expense); Text("收入").tag(V2LedgerDirection.income); Text("转账").tag(V2LedgerDirection.transfer)
                    }
                    DatePicker("到期日期", selection: $date, displayedComponents: .date)
                    Picker("重复", selection: $plan.recurrence) {
                        Text("仅一次").tag(V2FinanceRecurrence.once); Text("每月").tag(V2FinanceRecurrence.monthly); Text("每年").tag(V2FinanceRecurrence.yearly)
                    }
                }
                Section("提醒与跳转") {
                    Toggle("到期提醒", isOn: $plan.reminderEnabled)
                    if plan.reminderEnabled { Stepper("提前 \(plan.reminderDays) 天", value: $plan.reminderDays, in: 0...365) }
                    TextField("应用链接或网页地址", text: $plan.link).v2KeyboardType(.URL).v2Autocapitalization(.never).autocorrectionDisabled()
                    TextField("提醒 / 沟通话术", text: $plan.prompt, axis: .vertical).lineLimit(3...6)
                    Button("填写话术示例") {
                        switch plan.kind {
                        case .loan: plan.prompt = "你好，我们约定的还款日期快到了。方便确认一下金额与转账方式吗？如需调整时间，我们可以提前沟通。"
                        case .rent: plan.prompt = "你好，本期房租准备支付，请确认收款信息与金额，支付后我会保留凭证。"
                        case .creditCard: plan.prompt = "核对本期账单、还款金额与截止日期，付款后确认到账。"
                        default: plan.prompt = "检查本期费用和使用情况，确认是否继续订阅，并保存付款凭证。"
                        }
                    }
                    Text("保存后，返回列表开启通知权限。话术可复制后自行发送。 ").font(.caption).foregroundStyle(.secondary)
                }
                if V2PluginStore.shared.enabled("attachments") {
                    Section("附件") {
                        ForEach(plan.attachmentIDs, id: \.self) { id in
                            if let asset = captureStore.state.assets.first(where: { $0.id == id }) {
                                V2AttachmentTile(asset: asset, store: captureStore.assets)
                                Button("移除此附件", role: .destructive) { plan.attachmentIDs.removeAll { $0 == id } }
                            }
                        }
                        V2FileAttachmentPicker(ownerModuleID: "core.finance") { files in
                            captureStore.performFinance(operationID: plan.id) {
                                try V2PluginStore.shared.require(["finance", "attachments"])
                                guard plan.attachmentIDs.count + files.count <= 20 else { throw V2FinanceError.invalidPlan("最多保存 20 个附件") }
                                var ids = plan.attachmentIDs
                                for file in files {
                                    let ext = file.storageExtension
                                    let asset = try captureStore.appStore.engine.saveCaptureAsset(file.data, kind: file.kind,
                                        fileExtension: ext.isEmpty ? "bin" : ext, store: captureStore.assets, originalFileName: file.fileName)
                                    ids.append(asset.id)
                                }
                                plan.attachmentIDs = ids
                            }
                        }
                    }
                }
                if let issue = captureStore.issue { Text(issue).foregroundStyle(.red) }
            }
            .navigationTitle(existing == nil ? "添加订阅或账单" : "编辑计划")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        captureStore.performFinance(operationID: plan.id) {
                            plan.dueDate = FinanceDate.formatter(plan.timeZoneIdentifier).string(from: date)
                            if plan.dueDate != existing?.dueDate || plan.recurrence != existing?.recurrence {
                                var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: plan.timeZoneIdentifier) ?? .current
                                plan.anchorDay = calendar.component(.day, from: date); plan.anchorMonth = calendar.component(.month, from: date)
                            }
                            _ = try captureStore.executeFinance(.savePlan(plan, expectedRevision: existing?.revision))
                        }
                        if captureStore.issue == nil { dismiss() }
                    }.accessibilityIdentifier("finance.save")
                }
            }
        }
    }
}

struct V2FinanceDetail: View {
    @ObservedObject var captureStore: V2CaptureStore
    let planID: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var editing: V2FinancePlan?
    @State private var paying: V2FinancePlan?
    @State private var feedback: String?
    private var plan: V2FinancePlan? { captureStore.state.finance?.plans.first { $0.id == planID } }
    var body: some View {
        List {
            if let plan {
                Section {
                    Text(plan.title).font(.title.bold())
                    Text("\(plan.currency) \(plan.amount)").font(.largeTitle).monospacedDigit()
                    Text("\(plan.kind.label) · \(plan.dueDate) · \(plan.recurrence == .monthly ? "每月" : plan.recurrence == .yearly ? "每年" : "仅一次")")
                    if plan.isActive {
                        Button("确认已支付并记账", systemImage: "checkmark.circle") { paying = plan }.accessibilityIdentifier("finance.pay")
                    }
                    if !plan.link.isEmpty, let url = URL(string: plan.link) {
                        Button("打开对应应用 / 网页", systemImage: "arrow.up.forward.app") {
                            guard V2PluginStore.shared.enabled("finance") else { feedback = "订阅与还款已停用"; return }
                            openURL(url) { accepted in if !accepted { feedback = "无法打开该链接，请检查应用是否已安装，或编辑为网页地址。" } }
                        }
                    }
                    Button("编辑") { editing = plan }
                    Button(plan.isActive ? "暂停提醒" : "恢复计划") {
                        captureStore.performFinance(operationID: planID) { _ = try captureStore.executeFinance(.setPlanActive(id: plan.id, isActive: !plan.isActive, expectedRevision: plan.revision)) }
                    }
                }
                if !plan.prompt.isEmpty {
                    Section("提醒话术") {
                        Text(plan.prompt).textSelection(.enabled)
                        Button("复制话术", systemImage: "doc.on.doc") { V2Platform.copy(plan.prompt); feedback = "话术已复制" }
                    }
                }
                if !plan.attachmentIDs.isEmpty {
                    Section("附件") {
                        ForEach(plan.attachmentIDs, id: \.self) { id in
                            if let asset = captureStore.state.assets.first(where: { $0.id == id }) { V2AttachmentTile(asset: asset, store: captureStore.assets) }
                        }
                    }
                }
                Section("支付记录") {
                    ForEach((captureStore.state.finance?.payments ?? []).filter { $0.planID == planID }.reversed()) { payment in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(payment.dueDate) · \(payment.currency) \(payment.amount)")
                            if payment.status == .undone { Text("已撤销").foregroundStyle(.secondary) }
                            else {
                                Text("已写入流水 · 可在理账中核对分类").font(.caption).foregroundStyle(.secondary)
                                Button("撤销这次记账") {
                                    captureStore.performFinance(operationID: payment.id) { _ = try captureStore.executeFinance(.undoPayment(id: payment.id)) }
                                    if captureStore.issue == nil { feedback = "已撤销，计划和预算已恢复。" }
                                }.accessibilityIdentifier("finance.undo")
                            }
                        }
                    }
                }
            }
            if let feedback { Text(feedback).foregroundStyle(V2Theme.blue).accessibilityIdentifier("finance.feedback") }
            if let issue = captureStore.issue { Text(issue).foregroundStyle(.red) }
        }
        .navigationTitle("计划详情").v2InlineNavigationTitle()
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        .v2Sheet(item: $editing) { V2FinancePlanEditor(captureStore: captureStore, existing: $0) }
        .confirmationDialog("确认已在外部完成支付？", isPresented: Binding(get: { paying != nil }, set: { if !$0 { paying = nil } }), titleVisibility: .visible) {
            if let paying {
                Button("已支付，记入流水") {
                    captureStore.performFinance(operationID: planID) { _ = try captureStore.executeFinance(.markPaid(id: paying.id, expectedRevision: paying.revision, expectedDueDate: paying.dueDate), confirmedPayment: true) }
                    if captureStore.issue == nil { feedback = "已记入流水，预算已更新。可以在下方撤销。" }
                    self.paying = nil
                }
            }
        } message: { Text("这里只记录已完成的支付，不会发起扣款。") }
        .task(id: captureStore.state.finance?.plans) { await V2FinanceNotifications.shared.refresh(captureStore.state.finance?.plans ?? []) }
    }
}

struct V2BudgetEditor: View {
    @ObservedObject var captureStore: V2CaptureStore
    var existing: V2Budget? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var budgetID = UUID().uuidString
    @State private var amount = ""
    @State private var currency = "CNY"
    @State private var month = Date()
    @State private var category = ""
    var body: some View {
        NavigationStack {
            Form {
                TextField("预算金额", text: $amount).v2KeyboardType(.decimalPad).accessibilityIdentifier("budget.amount")
                TextField("币种", text: $currency).v2Autocapitalization(.characters).autocorrectionDisabled()
                DatePicker("选择预算月份", selection: $month, displayedComponents: .date)
                Picker("范围", selection: $category) {
                    Text("全部支出").tag("")
                    ForEach(captureStore.state.categories.filter { $0.mergedIntoID == nil }) { Text($0.name).tag($0.id) }
                }
                Text("选择任意日期，统计该自然月的实际支出。不同币种分别计算。 ").font(.caption).foregroundStyle(.secondary)
                if let existing {
                    Button("删除预算", role: .destructive) {
                        captureStore.performFinance(operationID: existing.id) { _ = try captureStore.executeFinance(.removeBudget(id: existing.id)) }
                        if captureStore.issue == nil { dismiss() }
                    }
                }
                if let issue = captureStore.issue { Text(issue).foregroundStyle(.red) }
            }.navigationTitle("月度预算")
            .onAppear {
                if let existing { amount = existing.amount; currency = existing.currency; category = existing.categoryID ?? ""; month = FinanceDate.formatter().date(from: existing.month + "-01") ?? Date() }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        captureStore.performFinance(operationID: existing?.id ?? budgetID) {
                            let budget = V2Budget(id: existing?.id ?? budgetID, currency: currency, amount: amount,
                                month: String(FinanceDate.formatter().string(from: month).prefix(7)), categoryID: category.isEmpty ? nil : category)
                            _ = try captureStore.executeFinance(.saveBudget(budget, expectedRevision: existing?.revision))
                        }
                        if captureStore.issue == nil { dismiss() }
                    }.accessibilityIdentifier("budget.save")
                }
            }
        }
    }
}

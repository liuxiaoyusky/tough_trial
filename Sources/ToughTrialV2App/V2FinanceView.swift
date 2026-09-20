import SwiftUI
import ToughTrialV2Core

struct V2FinanceView: View {
    @ObservedObject var captureStore: V2CaptureStore
    var initialPlanID: String? = nil
    @ObservedObject private var plugins = V2PluginStore.shared
    @ObservedObject private var notifications = V2FinanceNotifications.shared
    @State private var creating = false
    @State private var budgetForm = false
    @State private var selection: V2FinancePlan?
    @State private var editingBudget: V2Budget?
    private var finance: V2FinanceState { captureStore.state.finance ?? .init() }
    var body: some View {
        List {
            if plugins.enabled("finance") {
                Section {
                    HStack { Text("订阅与还款").font(.title2.bold()); Spacer(); Button("添加", systemImage: "plus") { creating = true }.accessibilityIdentifier("finance.add") }
                    Text("ChatGPT、GLM、房租或还款，记下日期，提前提醒。确认已支付后才记入流水。")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button("开启 / 更新提醒", systemImage: "bell.badge") {
                        Task { await notifications.refresh(finance.plans, requestPermission: true) }
                    }
                    Text(notifications.status).font(.caption).foregroundStyle(.secondary)
                }
                Section("待处理") {
                    let active = finance.plans.filter(\.isActive).sorted { $0.dueDate < $1.dueDate }
                    if active.isEmpty { Text("还没有订阅或待付款。") }
                    ForEach(active) { plan in planRow(plan) }
                }
                let inactive = finance.plans.filter { !$0.isActive }
                if !inactive.isEmpty { Section("已暂停 / 已完成") { ForEach(inactive) { plan in planRow(plan) } } }
            }
            if plugins.enabled("budget") {
                Section {
                    HStack { Text("月度预算").font(.headline); Spacer(); Button("新增预算") { budgetForm = true }.accessibilityIdentifier("budget.add") }
                    Text("只统计同币种实际支出，转账与未支付计划不占用预算。")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(finance.budgets) { budget in
                        Button { editingBudget = budget } label: { budgetRow(budget) }.buttonStyle(.plain)
                    }
                }
            }
            if let issue = captureStore.issue { Text(issue).foregroundStyle(.red) }
        }
        .scrollContentBackground(.hidden).background(V2Theme.page)
        .navigationTitle("理账计划").v2InlineNavigationTitle()
        .v2Sheet(isPresented: $creating) { V2FinancePlanEditor(captureStore: captureStore) }
        .v2Sheet(item: $selection) { plan in NavigationStack { V2FinanceDetail(captureStore: captureStore, planID: plan.id) } }
        .v2Sheet(isPresented: $budgetForm) { V2BudgetEditor(captureStore: captureStore) }
        .v2Sheet(item: $editingBudget) { budget in V2BudgetEditor(captureStore: captureStore, existing: budget) }
        .onAppear {
            captureStore.refresh()
            if let initialPlanID { selection = finance.plans.first { $0.id == initialPlanID } }
        }
        .task(id: finance.plans) { await notifications.refresh(finance.plans) }
    }
    private func planRow(_ plan: V2FinancePlan) -> some View {
        Button { selection = plan } label: {
            HStack(alignment: .top) {
                Image(systemName: plan.kind == .subscription ? "repeat.circle.fill" : "calendar.badge.clock").foregroundStyle(V2Theme.blue).font(.title2)
                VStack(alignment: .leading, spacing: 5) {
                    Text(plan.title).font(.headline)
                    Text("\(plan.kind.label) · \(plan.dueDate)").font(.caption).foregroundStyle(.secondary)
                    if !plan.attachmentIDs.isEmpty { Label("\(plan.attachmentIDs.count) 个附件", systemImage: "paperclip").font(.caption) }
                }
                Spacer()
                Text("\(plan.currency) \(plan.amount)").monospacedDigit()
            }.foregroundStyle(V2Theme.ink).padding(.vertical, 4)
        }.listRowBackground(captureStore.lastFinanceReceipt?.changedIDs.contains(plan.id) == true ? V2Theme.blue.opacity(0.08) : Color.clear)
        .accessibilityIdentifier("finance.plan.\(plan.title)")
    }
    @ViewBuilder private func budgetRow(_ budget: V2Budget) -> some View {
        let progress = captureStore.appStore.engine.budgetProgress(for: budget)
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text(budget.month).font(.headline); Spacer(); Text(budget.currency + " " + budget.amount) }
            Text(budget.categoryID.flatMap { id in captureStore.state.categories.first { $0.id == id }?.name } ?? "全部支出").font(.caption).foregroundStyle(.secondary)
            ProgressView(value: min(1, max(0, NSDecimalNumber(decimal: progress.spent / max(progress.budgetAmount, 1)).doubleValue)))
                .tint(progress.remaining < 0 ? V2Theme.orange : V2Theme.blue)
            Text("已花 \(NSDecimalNumber(decimal: progress.spent).stringValue) · \(progress.remaining < 0 ? "超支" : "剩余") \(NSDecimalNumber(decimal: abs(progress.remaining)).stringValue)")
                .font(.subheadline).accessibilityIdentifier("budget.progress")
        }.padding(.vertical, 6)
    }
}

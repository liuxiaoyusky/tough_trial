import SwiftUI
import ToughTrialV2Core

/// Both entry points render the same ledger projection and row components.
struct V2LedgerList: View {
    @ObservedObject var store: V2CaptureStore
    @ObservedObject private var plugins = V2PluginStore.shared
    let onAdd: () -> Void
    let onCategory: (V2LedgerEntry) -> Void
    let onSource: (String) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("记账").font(.title2.bold()); Spacer(); Button("记一笔", systemImage: "plus") { onAdd() } }
            NavigationLink {
                V2LedgerStatisticsView(store: store)
            } label: {
                Label("收支统计", systemImage: "chart.bar.xaxis")
                    .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                    .background(V2Theme.panel, in: RoundedRectangle(cornerRadius: 14))
            }.accessibilityIdentifier("ledger.statistics.open")
            if plugins.enabled("finance") || plugins.enabled("budget") {
                NavigationLink { V2FinanceView(captureStore: store) } label: {
                    Label("订阅、还款与预算", systemImage: "calendar.badge.clock").frame(maxWidth: .infinity, alignment: .leading).padding(14)
                        .background(V2Theme.panel, in: RoundedRectangle(cornerRadius: 14))
                }.accessibilityIdentifier("finance.open")
            }
            ForEach(Array(store.state.totals(direction: .expense).keys.sorted()), id: \.self) { currency in
                Text("支出 · \(currency) \(NSDecimalNumber(decimal: store.state.totals(direction: .expense)[currency]!).stringValue)")
                    .font(.title3.bold().monospacedDigit())
            }
            if store.state.ledger.isEmpty { Text("先说一段原文，整理后核对；也可以手动补充字段。").foregroundStyle(V2Theme.secondary) }
            ForEach(store.state.ledger.reversed()) { entry in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(entry.text).font(.headline); Spacer()
                        Text("\(entry.currency) \(entry.amount)").font(.headline.monospacedDigit())
                    }
                    HStack {
                        Text(entry.direction == .expense ? "支出" : entry.direction == .income ? "收入" : "转账")
                        Text(store.state.categories.first { $0.id == entry.categoryID }?.name ?? "Others")
                        if let day = entry.localDate { Text(day) }
                    }.font(.caption).foregroundStyle(V2Theme.secondary)
                    HStack {
                        Button(entry.categoryID == "others" ? "确认分类" : "调整分类") { onCategory(entry) }
                        Spacer()
                        if store.state.receipts.contains(where: { $0.id == entry.receiptID }) { Button("查看原文") { onSource(entry.receiptID) } }
                    }.font(.subheadline)
                }.padding(16).background(V2Theme.panel, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }
}

struct V2LedgerView: View {
    @StateObject private var store: V2CaptureStore
    @State private var adding = false
    @State private var category: V2LedgerEntry?
    @State private var sourceText: String?

    init(appStore: V2AppStore) {
        _store = StateObject(wrappedValue: V2CaptureStore(appStore: appStore))
    }
    init(store: V2CaptureStore) {
        _store = StateObject(wrappedValue: store)
    }
    var body: some View {
        ScrollView {
            V2LedgerList(store: store, onAdd: { adding = true }, onCategory: { category = $0 }, onSource: { id in
                let receipt = store.state.receipts.first { $0.id == id }
                let batch = store.state.batches.first { $0.id == receipt?.batchID }
                sourceText = store.state.entries.first { $0.id == batch?.proposal.captureID && $0.revision == batch?.proposal.sourceRevision }?.text
            }).padding(20)
            if let issue = store.issue { Text(issue).foregroundStyle(.red).padding() }
        }
        .background(V2Theme.page).navigationTitle("记账")
        .onAppear { store.refresh() }
        .v2Sheet(isPresented: $adding) { V2CaptureLedgerForm(store: store) }
        .v2Sheet(item: $category) { V2CaptureCategorySheet(store: store, entry: $0) }
        .v2Sheet(isPresented: Binding(get: { sourceText != nil }, set: { if !$0 { sourceText = nil } })) {
            NavigationStack {
                ScrollView { Text(sourceText ?? "").textSelection(.enabled).padding() }
                    .navigationTitle("原始记录")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { sourceText = nil } } }
            }
        }
    }
}

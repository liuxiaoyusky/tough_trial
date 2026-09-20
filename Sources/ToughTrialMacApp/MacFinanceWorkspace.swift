import SwiftUI

struct MacFinanceWorkspace: View {
    @ObservedObject var store: V2CaptureStore
    @ObservedObject private var plugins = V2PluginStore.shared
    @State private var page = "统计"

    private var pages: [String] {
        (plugins.enabled("ledger") ? ["统计", "账单"] : []) +
        ((plugins.enabled("finance") || plugins.enabled("budget")) ? ["计划与预算"] : [])
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("理账视图", selection: $page) {
                ForEach(pages, id: \.self) { Text($0).tag($0) }
            }.pickerStyle(.segmented).frame(maxWidth: 420).padding(20)
                .accessibilityIdentifier("mac.finance.sections")
            NavigationStack {
                switch page {
                case "统计": V2LedgerStatisticsView(store: store)
                case "账单": V2LedgerView(store: store)
                default: V2FinanceView(captureStore: store)
                }
            }.id(page)
        }
        .onAppear { reconcile() }
        .onChange(of: pages) { _, _ in reconcile() }
    }

    private func reconcile() {
        if !pages.contains(page) { page = pages.first ?? "计划与预算" }
    }
}

import SwiftUI
import ToughTrialV2Core

struct V2CaptureCategoriesView: View {
    @ObservedObject var store: V2CaptureStore
    @State private var name = ""
    @State private var parentID = ""
    @State private var sourceID = ""
    @State private var targetID = ""
    @State private var preview: MergePreview?
    private struct MergePreview: Identifiable {
        let id = UUID()
        let sourceID: String
        let targetID: String
        let revision: Int
        let summary: String
    }
    private var categories: [V2LedgerCategory] { store.state.categories.filter { $0.id != "others" && $0.mergedIntoID == nil } }
    var body: some View {
        Form {
            Section("现有分类") {
                Text("Others · 系统收纳，不可合并删除").foregroundStyle(.secondary)
                ForEach(categories) { category in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(category.name)
                            if let parentID = category.parentID, let parent = categories.first(where: { $0.id == parentID }) {
                                Text("属于 \(parent.name)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text("\(store.state.ledger.filter { $0.categoryID == category.id }.count) 笔").foregroundStyle(.secondary)
                    }
                }
            }
            Section("新建或细分") {
                TextField("分类名称", text: $name)
                Picker("上级分类", selection: $parentID) {
                    Text("独立分类").tag("")
                    ForEach(categories) { Text($0.name).tag($0.id) }
                }
                Button("确认创建分类") {
                    store.createCategory(name: name, parentID: parentID.isEmpty ? nil : parentID)
                    if store.issue == nil { name = "" }
                }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Section("合并分类") {
                Picker("将此分类", selection: $sourceID) {
                    Text("选择分类").tag(""); ForEach(categories) { Text($0.name).tag($0.id) }
                }
                Picker("合并到", selection: $targetID) {
                    Text("选择分类").tag(""); ForEach(categories.filter { $0.id != sourceID }) { Text($0.name).tag($0.id) }
                }
                Button("查看合并预览") {
                    let rows = store.state.ledger.filter { $0.categoryID == sourceID }
                    let totals = Dictionary(grouping: rows, by: \.currency).keys.sorted().map { currency in
                        let values = rows.filter { $0.currency == currency }
                        return V2LedgerDirection.allCases.compactMap { direction -> String? in
                            let selected = values.filter { $0.direction == direction }
                            guard !selected.isEmpty else { return nil }
                            let sum = selected.reduce(Decimal(0)) { $0 + (Decimal(string: $1.amount, locale: Locale(identifier: "en_US_POSIX")) ?? 0) }
                            return "\(direction == .expense ? "支出" : direction == .income ? "收入" : "转账") \(currency) \(NSDecimalNumber(decimal: sum).stringValue)"
                        }.joined(separator: "；")
                    }.joined(separator: "\n")
                    let from = categories.first { $0.id == sourceID }?.name ?? ""
                    let to = categories.first { $0.id == targetID }?.name ?? ""
                    preview = .init(sourceID: sourceID, targetID: targetID, revision: store.state.taxonomyRevision,
                        summary: "\(from) → \(to)\n影响 \(rows.count) 笔账单。\n\(totals)\n子分类会随之移入。金额与币种不变。")
                }.disabled(sourceID.isEmpty || targetID.isEmpty || sourceID == targetID)
            }
            if let last = store.state.categoryReceipts.last, !last.undone {
                Section {
                    Button("撤销上一次分类调整") { store.undoCategory(last.id) }
                    Text("如果之后又有相关修改，会先拦截，不覆盖新内容。").font(.caption).foregroundStyle(.secondary)
                }
            }
        }.navigationTitle("账单分类")
            .alert(item: $preview) { value in
                Alert(title: Text("确认合并分类？"), message: Text(value.summary),
                      primaryButton: .default(Text("确认合并")) {
                        store.mergeCategories(sourceID: value.sourceID, targetID: value.targetID, revision: value.revision)
                        sourceID = ""; targetID = ""
                      }, secondaryButton: .cancel(Text("取消")))
            }
    }
}

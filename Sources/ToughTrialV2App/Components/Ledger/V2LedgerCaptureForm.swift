import SwiftUI
import ToughTrialV2Core
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// The dedicated ledger entry keeps its natural-language draft separate from
/// the mixed capture composer. Organizing stages a proposal; only the review
/// card's single confirmation action creates a ledger row.
struct V2CaptureLedgerForm: View {
    @ObservedObject var store: V2CaptureStore
    @State private var amount = ""
    @State private var currency = ""
    @State private var direction = V2LedgerDirection.expense
    @State private var localDate = ""
    @State private var dictationActive = false
    @State private var manualFields = false
    @FocusState private var inputFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private var canSaveManual: Bool {
        V2CaptureContract.validAmount(amount)
            && V2CaptureContract.currencies.contains(currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())
            && !store.ledgerDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("记一笔").font(V2Theme.TypeRole.titleLarge)
                    Text("写下或说出这笔收支，整理后核对保存。")
                        .font(.subheadline).foregroundStyle(V2Theme.secondary)

                    V2MultilineInput(
                        text: $store.ledgerDraft,
                        placeholder: "例如：午饭花了 35 元，昨天的",
                        minHeight: 132,
                        maxHeight: 280,
                        accessibilityIdentifier: "ledger.input",
                        isEnabled: !store.isOrganizing && !dictationActive,
                        focus: $inputFocused
                    )
                    .padding(12)
                    .background(V2Theme.panel, in: RoundedRectangle(cornerRadius: 16))

                    V2DictationControl(
                        text: $store.ledgerDraft,
                        isActive: $dictationActive,
                        ownerModuleID: "core.ledger",
                        identifierPrefix: "ledger.dictation"
                    )

                    if !manualFields {
                        Button("手动补充") { manualFields = true }
                            .font(.subheadline)
                            .accessibilityIdentifier("ledger.manualFields")
                    }

                    if manualFields { manualEntryFields }

                    HStack(spacing: 12) {
                        if store.isOrganizing {
                            ProgressView()
                            Button("停止整理") { store.cancel() }
                                .accessibilityIdentifier("ledger.organize.cancel")
                        } else {
                            Button("一键整理", systemImage: "sparkles") {
                                dismissKeyboard()
                                store.organizeLedger(text: store.ledgerDraft)
                            }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("ledger.organize")
                            .disabled(!store.canOrganizeLedger || dictationActive || store.ledgerDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        if manualFields {
                            Button("直接保存") {
                                dismissKeyboard()
                                store.saveManualLedger(
                                    amount: amount,
                                    text: store.ledgerDraft,
                                    currency: currency,
                                    direction: direction,
                                    localDate: optionalDate
                                )
                                if store.issue == nil { dismiss() }
                            }
                            .accessibilityIdentifier("ledger.save")
                            .disabled(!canSaveManual || store.isOrganizing || dictationActive)
                        }
                    }

                    if !store.canOrganizeLedger {
                        Text("开启随手记和助手后可用一键整理，也可以手动补充后保存。")
                            .font(.caption).foregroundStyle(V2Theme.secondary)
                    }
                    if let issue = store.issue {
                        Text(issue).font(.caption).foregroundStyle(V2Theme.orange)
                            .accessibilityIdentifier("ledger.error")
                    }
                    if let message = store.message {
                        Text(message).font(.caption).foregroundStyle(V2Theme.secondary)
                    }
                    if let batch = store.activeLedgerBatch {
                        if sourceMatchesDraft(batch) {
                            V2LedgerProposalList(store: store, batch: batch)
                                .id(batch.id)
                                .disabled(dictationActive || store.isOrganizing)
                        } else {
                            Text("原话已修改，请重新整理后核对。")
                                .font(.subheadline).foregroundStyle(V2Theme.secondary)
                        }
                        if hasSavedLedger(in: batch) {
                            Button("再记一笔", systemImage: "plus") { startAnotherEntry() }
                                .buttonStyle(.borderedProminent)
                                .accessibilityIdentifier("ledger.new")
                        }
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier("ledger.scroll")
            .background(V2Theme.page)
            .navigationTitle("记账")
            .v2InlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismissKeyboard()
                        store.cancel()
                        dismiss()
                    }
                        .accessibilityIdentifier("ledger.cancel")
                }
                #if os(iOS)
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("收起键盘") { dismissKeyboard() }
                        .accessibilityIdentifier("ledger.dismissKeyboard")
                }
                #endif
            }
            .onAppear {
                if !store.canOrganizeLedger { manualFields = true }
            }
            .onDisappear {
                if store.isOrganizing { store.cancel() }
            }
        }
    }

    private var optionalDate: String? {
        let value = localDate.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func sourceMatchesDraft(_ batch: V2CaptureBatch) -> Bool {
        store.state.entries.first {
            $0.id == batch.proposal.captureID && $0.revision == batch.proposal.sourceRevision
        }?.text == store.ledgerDraft
    }

    private func hasSavedLedger(in batch: V2CaptureBatch) -> Bool {
        batch.proposal.items.contains { item in
            store.receipt(for: item, batch: batch)?.ledgerAfter != nil
        }
    }

    private func startAnotherEntry() {
        dismissKeyboard()
        store.startNewLedgerEntry()
        amount = ""
        currency = ""
        direction = .expense
        localDate = ""
        manualFields = !store.canOrganizeLedger
    }

    private var manualEntryFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("手动补充").font(.subheadline.bold())
            TextField("金额", text: $amount)
                .v2KeyboardType(.decimalPad)
                .accessibilityIdentifier("ledger.amount")
            TextField("币种（CNY / USD / HKD）", text: $currency)
                .v2Autocapitalization(.characters)
                .autocorrectionDisabled()
                .accessibilityIdentifier("ledger.currency")
            Picker("收支", selection: $direction) {
                Text("支出").tag(V2LedgerDirection.expense)
                Text("收入").tag(V2LedgerDirection.income)
                Text("转账").tag(V2LedgerDirection.transfer)
            }
            .accessibilityIdentifier("ledger.direction")
            TextField("消费日期（可选，yyyy-MM-dd）", text: $localDate)
                .accessibilityIdentifier("ledger.localDate")
            Text("分类会先保留为 Others，确认分类后才会更新。日期留空时不会用记录日代替。")
                .font(.caption).foregroundStyle(V2Theme.tertiary)
        }
        .padding(16)
        .background(V2Theme.panel, in: RoundedRectangle(cornerRadius: 16))
        .disabled(store.isOrganizing || dictationActive)
    }

    private func dismissKeyboard() {
        inputFocused = false
        V2Platform.endEditing()
    }
}

private struct V2LedgerProposalList: View {
    @ObservedObject var store: V2CaptureStore
    let batch: V2CaptureBatch

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("核对账单").font(.headline)
            Text("先核对每笔账单，点保存后才会记入账本。")
                .font(.caption).foregroundStyle(V2Theme.secondary)
            ForEach(batch.proposal.items) { original in
                if let item = batch.effectiveCandidate(for: original.id) {
                    V2LedgerProposalEditor(store: store, batch: batch, item: item)
                }
            }
        }
        .padding(16)
        .background(V2Theme.panel.opacity(0.7), in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct V2LedgerProposalEditor: View {
    @ObservedObject var store: V2CaptureStore
    let batch: V2CaptureBatch
    let item: V2CaptureCandidate
    @State private var kind: V2CaptureKind
    @State private var text: String
    @State private var amount: String
    @State private var currency: String
    @State private var direction: V2LedgerDirection?
    @State private var localDate: String
    @State private var categoryName: String
    @State private var categoryEntry: V2LedgerEntry?
    @FocusState private var textFocused: Bool

    init(store: V2CaptureStore, batch: V2CaptureBatch, item: V2CaptureCandidate) {
        self.store = store
        self.batch = batch
        self.item = item
        _kind = State(initialValue: item.kind)
        _text = State(initialValue: item.payload.text)
        _amount = State(initialValue: item.payload.amount ?? "")
        _currency = State(initialValue: item.payload.currency ?? "")
        _direction = State(initialValue: item.payload.direction)
        _localDate = State(initialValue: item.payload.localDate ?? "")
        _categoryName = State(initialValue: item.payload.categoryName ?? "")
    }

    private var receipt: V2CaptureReceipt? { store.receipt(for: item, batch: batch) }
    private var ledger: V2LedgerEntry? {
        guard let targetID = receipt?.targetID else { return nil }
        return store.state.ledger.first { $0.id == targetID }
    }
    private var isTerminal: Bool {
        receipt?.status == .rejected || receipt?.status == .undone
    }
    private var validDraft: Bool {
        kind == .ledger
            && V2CaptureContract.validAmount(amount.trimmingCharacters(in: .whitespacesAndNewlines))
            && V2CaptureContract.currencies.contains(currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())
            && direction != nil
            && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(kind == .ledger ? "账单" : item.kind.label).font(.subheadline.bold())
                Spacer()
                Text(receipt?.status.label ?? "待核对")
                    .font(.caption)
                    .foregroundStyle(receipt?.status == .needsConfirmation ? V2Theme.mint : V2Theme.orange)
            }

            if kind == .ledger {
                V2MultilineInput(
                    text: $text,
                    placeholder: "描述",
                    minHeight: 56,
                    maxHeight: 150,
                    accessibilityIdentifier: "ledger.proposal.\(item.id).description",
                    isEnabled: ledger == nil && !isTerminal && !store.isOrganizing,
                    focus: $textFocused
                )
                .padding(8)
                .background(V2Theme.panel, in: RoundedRectangle(cornerRadius: 10))
                HStack(spacing: 10) {
                    TextField("金额", text: $amount)
                        .v2KeyboardType(.decimalPad)
                        .disabled(ledger != nil || isTerminal || store.isOrganizing)
                        .accessibilityIdentifier("ledger.proposal.\(item.id).amount")
                    TextField("币种", text: $currency)
                        .v2Autocapitalization(.characters)
                        .autocorrectionDisabled()
                        .disabled(ledger != nil || isTerminal || store.isOrganizing)
                        .accessibilityIdentifier("ledger.proposal.\(item.id).currency")
                }
                Picker("收支", selection: $direction) {
                    Text("请选择").tag(nil as V2LedgerDirection?)
                    Text("支出").tag(V2LedgerDirection.expense as V2LedgerDirection?)
                    Text("收入").tag(V2LedgerDirection.income as V2LedgerDirection?)
                    Text("转账").tag(V2LedgerDirection.transfer as V2LedgerDirection?)
                }
                .disabled(ledger != nil || isTerminal || store.isOrganizing)
                .accessibilityIdentifier("ledger.proposal.\(item.id).direction")
                TextField("消费日期（可选，yyyy-MM-dd）", text: $localDate)
                    .disabled(ledger != nil || isTerminal || store.isOrganizing)
                    .accessibilityIdentifier("ledger.proposal.\(item.id).localDate")
                TextField("分类建议（可选）", text: $categoryName)
                    .disabled(ledger != nil || isTerminal || store.isOrganizing)
                    .accessibilityIdentifier("ledger.proposal.\(item.id).categoryName")
                Text("保存账单时暂不分类，之后可再确认。")
                    .font(.caption).foregroundStyle(V2Theme.secondary)
                Text("先保存为未分类，保存后可确认或调整分类。")
                    .font(.caption).foregroundStyle(V2Theme.secondary)
                missingFields
            } else {
                Text(item.payload.text).textSelection(.enabled)
                Text("这段内容会保留在原话中，不会自动成为账单。")
                    .font(.caption).foregroundStyle(V2Theme.secondary)
                if item.kind == .other && !isTerminal {
                    Button("补充字段，转为账单") { kind = .ledger }
                        .disabled(store.isOrganizing)
                        .accessibilityIdentifier("ledger.proposal.\(item.id).convert")
                }
            }

            Text("原话依据：\(item.evidence.map(\.quote).joined(separator: "；"))")
                .font(.caption2).foregroundStyle(V2Theme.secondary)
                .textSelection(.enabled)

            if kind == .ledger {
                HStack {
                    Spacer()
                    if let ledger {
                        Button(ledger.categoryID == "others" ? "确认分类" : "调整分类") { categoryEntry = ledger }
                            .accessibilityIdentifier("ledger.proposal.\(item.id).category")
                        Button("撤销") { if let receipt { store.undo(receipt) } }
                            .accessibilityIdentifier("ledger.proposal.\(item.id).undo")
                    } else if !isTerminal {
                        Button("保存账单") {
                            textFocused = false
                            V2Platform.endEditing()
                            store.confirmLedgerCandidate(
                                item,
                                batch: batch,
                                draft: .init(
                                    kind: kind,
                                    text: text,
                                    amount: amount.isEmpty ? nil : amount,
                                    currency: currency.isEmpty ? nil : currency,
                                    direction: direction,
                                    localDate: localDate.isEmpty ? nil : localDate,
                                    categoryName: categoryName.isEmpty ? nil : categoryName
                                )
                            )
                        }
                        .disabled(!validDraft || store.isOrganizing)
                        .accessibilityIdentifier("ledger.proposal.\(item.id).confirm")
                    }
                }
            } else if receipt?.status == .rejected {
                Text("已保留原话，未保存账单。").font(.caption).foregroundStyle(V2Theme.secondary)
            }
            if let issue = store.issue {
                Text(issue).font(.caption).foregroundStyle(V2Theme.orange)
                    .accessibilityIdentifier("ledger.proposal.\(item.id).error")
            }
            if let error = receipt?.error {
                Text(error.localizedDescription).font(.caption).foregroundStyle(V2Theme.orange)
            }
        }
        .padding(14)
        .background(V2Theme.page, in: RoundedRectangle(cornerRadius: 14))
        .v2Sheet(item: $categoryEntry) { entry in
            V2CaptureCategorySheet(store: store, entry: entry)
        }
    }

    @ViewBuilder
    private var missingFields: some View {
        VStack(alignment: .leading, spacing: 4) {
            if amount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("待补充金额").foregroundStyle(V2Theme.orange)
            }
            if currency.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("待补充币种").foregroundStyle(V2Theme.orange)
            }
            if direction == nil {
                Text("待补充收支方向").foregroundStyle(V2Theme.orange)
            }
        }
        .font(.caption)
    }
}

#Preview("记账 · 空白") {
    V2CaptureLedgerForm(store: V2CaptureStore(appStore: V2AppStore(engine: V2Engine())))
}

#Preview("记账 · 原话") {
    let store = V2CaptureStore(appStore: V2AppStore(engine: V2Engine()))
    store.ledgerDraft = "午饭花了三十八，不对，是三十五，昨天的"
    return V2CaptureLedgerForm(store: store)
}

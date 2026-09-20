import SwiftUI
import ToughTrialV2Core

struct V2NotesView: View {
    @StateObject private var store: V2CaptureStore
    init(appStore: V2AppStore) { _store = StateObject(wrappedValue: V2CaptureStore(appStore: appStore)) }
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                if store.state.notes.isEmpty {
                    ContentUnavailableView("还没有笔记", systemImage: "note.text", description: Text("在助手里记录灵感或想法，整理后的内容会出现在这里。"))
                }
                ForEach(store.state.notes.reversed()) { note in
                    V2CaptureNoteCard(note: note, source: store.noteSource(receiptID: note.receiptID))
                }
            }.padding(20)
        }.background(V2Theme.page).navigationTitle("笔记与灵感").onAppear { store.refresh() }
    }
}

struct V2CaptureNoteCard: View {
    let note: V2CaptureNote
    let source: String?
    var openSource: (() -> Void)? = nil
    @State private var showsSource = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(note.kind.label).font(.caption).foregroundStyle(V2Theme.blue)
            if let title = note.title { Text(title).font(.headline) }
            Text(note.text)
            if source != nil || openSource != nil {
                Button("查看原文") {
                    if let openSource { openSource() } else { showsSource = true }
                }.font(.caption)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(V2Theme.panel, in: RoundedRectangle(cornerRadius: 16))
            .v2Sheet(isPresented: $showsSource) {
                NavigationStack {
                    ScrollView { Text(source ?? "").textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(20) }
                        .navigationTitle("输入原文")
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showsSource = false } } }
                }
            }
    }
}

extension V2CaptureStore {
    func noteSource(receiptID: String) -> String? {
        if let operation = appStore.engine.snapshot.toolOperations.first(where: { $0.id == receiptID }) {
            return operation.result.submittedText
        }
        guard let receipt = state.receipts.first(where: { $0.id == receiptID }),
              let batch = state.batches.first(where: { $0.id == receipt.batchID }) else { return nil }
        return state.entries.first { $0.id == batch.proposal.captureID && $0.revision == batch.proposal.sourceRevision }?.text
    }
}

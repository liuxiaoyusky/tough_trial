import SwiftUI
import ToughTrialV2Core
import ToughTrialAppShared

struct MacTaskOptions: View {
    @ObservedObject var workspace: V2TaskWorkspace
    @ObservedObject var store: V2AppStore
    @State private var date = Date()
    @State private var showsDate = false
    @State private var receiptID: String?
    @State private var feedback: String?

    var body: some View {
        if let task = workspace.draft?.original {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Menu {
                        Button("未分类") { classify(nil) }
                        Button("目标") { classify(.goal) }
                        Button("承诺") { classify(.commitment) }
                        Button("维护") { classify(.maintenance) }
                    } label: { Label(kindTitle(task.kind), systemImage: "tag") }
                    Menu {
                        Button("根任务") { move(nil) }
                        ForEach(workspace.tasks.filter { $0.id != task.id && $0.status != .done }) { parent in
                            Button(parent.title) { move(parent.id) }
                        }
                    } label: { Label("归属", systemImage: "point.3.connected.trianglepath.dotted") }
                    Button("安排日期", systemImage: "calendar") { showsDate.toggle() }
                }.controlSize(.small)
                if showsDate {
                    HStack {
                        DatePicker("日期", selection: $date, displayedComponents: .date).labelsHidden()
                        Button("加入安排") { schedule() }.buttonStyle(.borderedProminent)
                        Button("取消") { showsDate = false }
                    }
                }
                if let feedback {
                    HStack {
                        Text(feedback).font(.caption).foregroundStyle(V2Theme.secondary)
                        if let receiptID {
                            Button("撤销") {
                                guard !workspace.hasChanges else { self.feedback = "请先保存正文，再撤销。"; return }
                                if store.undoTaskChange(receiptID: receiptID) {
                                    workspace.discardDraft(); self.receiptID = nil; self.feedback = "已撤销"
                                } else { self.feedback = store.errorMessage }
                            }.font(.caption)
                        }
                    }
                }
            }.padding(.horizontal, 24).padding(.bottom, 12)
                .onChange(of: task.id) { _, _ in feedback = nil; receiptID = nil; showsDate = false }
        }
    }
    private func current() -> V2Task? {
        guard !workspace.hasChanges || workspace.save(), let id = workspace.selectedID else { return nil }
        return store.engine.snapshot.tasks.first { $0.id == id }
    }
    private func classify(_ kind: V2Task.Kind?) {
        guard let task = current() else { return }
        if let receipt = store.editTask(task, title: task.title, note: task.note, classification: .init(kind: kind)) {
            finished(receipt, message: "分类已保存")
        } else { feedback = store.errorMessage }
    }
    private func move(_ parentID: String?) {
        guard let task = current() else { return }
        apply(.init(kind: .updateTask, targetID: task.id, parentID: parentID, clearParent: parentID == nil), message: "归属已更新")
    }
    private func schedule() {
        guard let task = current() else { return }
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        apply(.init(kind: .scheduleTask, targetID: task.id, day: formatter.string(from: date)), message: "已加入所选日期")
        if receiptID != nil { showsDate = false }
    }
    private func apply(_ operation: V2ScheduleOperation, message: String) {
        do {
            let receipt = try store.engine.applyScheduleProposal(.init(summary: message, operations: [operation]), requestID: "mac-manual:" + UUID().uuidString,
                calendar: store.calendar, expectedSnapshot: store.engine.snapshot)
            store.refreshProjection(at: Date()); store.refreshScheduleReminders(receipt, at: Date())
            finished(receipt, message: message)
        } catch { receiptID = nil; feedback = error.localizedDescription }
    }
    private func finished(_ receipt: V2ScheduleReceipt, message: String) {
        receiptID = receipt.changes.isEmpty ? nil : receipt.id
        workspace.discardDraft(); feedback = message
    }
    private func kindTitle(_ kind: V2Task.Kind?) -> String {
        switch kind { case .goal: "目标"; case .commitment: "承诺"; case .maintenance: "维护"; case nil: "分类" }
    }
}

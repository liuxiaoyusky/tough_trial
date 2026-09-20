import SwiftUI

struct V2QuickTaskForm: View {
    @ObservedObject var store: V2CaptureStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            V2TaskEditor(mode: .quick, onSave: { title, note in
                store.saveQuickTask(title: title, note: note)
                if let issue = store.issue { return issue }
                dismiss()
                return nil
            }, onCancel: { dismiss() })
        }
        .presentationDetents([.large])
    }
}

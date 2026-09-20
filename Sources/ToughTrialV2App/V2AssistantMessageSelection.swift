import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

struct V2AssistantMessageSelection: View {
    let text: String
    let onQuote: (String) -> Void
    @State private var selection = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            SelectableMessage(text: text, selection: $selection).padding(16)
                .navigationTitle("选择文字")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(selection.isEmpty ? "引用全文" : "引用选中内容") { onQuote(selection.isEmpty ? text : selection) }
                    }
                }
        }
    }
}

#if os(iOS)
private struct SelectableMessage: UIViewRepresentable {
    let text: String
    @Binding var selection: String
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false; view.isSelectable = true
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.backgroundColor = .clear; view.delegate = context.coordinator
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        if view.text != text { view.text = text }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: SelectableMessage
        init(_ parent: SelectableMessage) { self.parent = parent }
        func textViewDidChangeSelection(_ textView: UITextView) {
            let range = textView.selectedRange
            let text = textView.text as NSString
            parent.selection = range.length > 0 && NSMaxRange(range) <= text.length ? text.substring(with: range) : ""
        }
    }
}

#else
struct SelectableMessage: NSViewRepresentable {
    let text: String
    @Binding var selection: String
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let view = scroll.documentView as! NSTextView
        view.isEditable = false; view.isSelectable = true
        view.font = .systemFont(ofSize: 16); view.delegate = context.coordinator
        view.string = text
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) { context.coordinator.parent = self }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SelectableMessage
        init(_ parent: SelectableMessage) { self.parent = parent }
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.selection = (view.string as NSString).substring(with: view.selectedRange())
        }
    }
}
#endif

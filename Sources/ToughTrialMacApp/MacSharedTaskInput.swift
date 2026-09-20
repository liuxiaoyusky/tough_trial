import AppKit
import SwiftUI

/// Shared task forms use the same continuous document editor on the desktop.
struct V2TaskDocumentInput: NSViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange
    @Binding var isFocused: Bool
    let isEnabled: Bool
    let identifier: String
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let view = scroll.documentView as! NSTextView
        view.isRichText = false; view.allowsUndo = true
        view.drawsBackground = false; scroll.drawsBackground = false
        view.textContainerInset = NSSize(width: 2, height: 12)
        view.delegate = context.coordinator
        view.string = text
        view.setAccessibilityIdentifier(identifier)
        view.setAccessibilityLabel("任务内容，第一段为标题，回车后写正文")
        context.coordinator.style(view)
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let c = context.coordinator; c.parent = self
        guard let view = scroll.documentView as? NSTextView, !view.hasMarkedText() else { return }
        c.updating = true
        defer { c.updating = false }
        view.isEditable = isEnabled
        if view.string != text { view.string = text; c.style(view) }
        let length = (view.string as NSString).length
        let location = min(selection.location, length)
        let range = NSRange(location: location, length: min(selection.length, length - location))
        if view.selectedRange() != range { view.setSelectedRange(range); view.scrollRangeToVisible(range) }
        if isFocused && isEnabled && !c.focused {
            c.focused = true
            DispatchQueue.main.async { [weak view] in view?.window?.makeFirstResponder(view) }
        } else if !isFocused && c.focused { c.focused = false; view.window?.makeFirstResponder(nil) }
    }
    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: V2TaskDocumentInput
        var updating = false
        var focused = false
        init(_ parent: V2TaskDocumentInput) { self.parent = parent }
        func textDidBeginEditing(_ note: Notification) { focused = true; if !updating { parent.isFocused = true } }
        func textDidEndEditing(_ note: Notification) { focused = false; if !updating { parent.isFocused = false } }
        func textDidChange(_ note: Notification) {
            guard !updating, let view = note.object as? NSTextView else { return }
            // Do not publish incomplete IME composition into autosaving SwiftUI forms.
            guard !view.hasMarkedText() else { return }
            parent.text = view.string; parent.selection = view.selectedRange(); style(view)
        }
        func textViewDidChangeSelection(_ note: Notification) {
            guard !updating, let view = note.object as? NSTextView, !view.hasMarkedText() else { return }
            parent.text = view.string; parent.selection = view.selectedRange()
        }
        func style(_ view: NSTextView) {
            guard let storage = view.textStorage else { return }
            let prior = updating; updating = true; defer { updating = prior }
            let selection = view.selectedRange()
            let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 6; paragraph.paragraphSpacing = 14
            let body: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 17), .foregroundColor: NSColor(V2Theme.ink), .paragraphStyle: paragraph]
            storage.beginEditing(); storage.setAttributes(body, range: NSRange(location: 0, length: storage.length))
            let title = (view.string as NSString).paragraphRange(for: NSRange(location: 0, length: 0))
            if title.length > 0 { storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 28, weight: .bold), range: title) }
            storage.endEditing(); view.setSelectedRange(selection); view.typingAttributes = body
        }
    }
}

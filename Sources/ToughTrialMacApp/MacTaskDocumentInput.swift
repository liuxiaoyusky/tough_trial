import SwiftUI
import AppKit

/// A single native text surface retains IME composition, selection and text undo across paragraphs.
struct MacTaskDocumentInput: NSViewRepresentable {
    var text: String
    var onChange: (String, Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let editor = TaskTextView(frame: .zero)
        editor.isRichText = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainerInset = NSSize(width: 22, height: 24)
        editor.drawsBackground = false
        editor.insertionPointColor = NSColor(V2Theme.blue)
        editor.allowsUndo = true
        editor.delegate = context.coordinator
        editor.setAccessibilityIdentifier("mac.tasks.document")
        editor.setAccessibilityLabel("任务内容，第一段为标题，回车后写正文")
        editor.string = text
        editor.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        context.coordinator.style(editor)
        scroll.documentView = editor
        return scroll
    }

    final class TaskTextView: NSTextView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.makeFirstResponder(self)
        }
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? NSTextView, !editor.hasMarkedText() else { return }
        if editor.string != text {
            let selection = editor.selectedRange()
            editor.string = text
            editor.setSelectedRange(NSRange(location: min(selection.location, (text as NSString).length), length: 0))
            editor.undoManager?.removeAllActions()
            context.coordinator.style(editor)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MacTaskDocumentInput
        init(parent: MacTaskDocumentInput) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            let composing = editor.hasMarkedText()
            parent.onChange(editor.string, composing)
            if !composing { style(editor) }
        }
        func style(_ editor: NSTextView) {
            guard let storage = editor.textStorage else { return }
            let selection = editor.selectedRange()
            let full = NSRange(location: 0, length: storage.length)
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 6
            paragraph.paragraphSpacing = 12
            storage.beginEditing()
            storage.setAttributes([.font: NSFont.systemFont(ofSize: 17), .foregroundColor: NSColor(V2Theme.ink),
                                   .paragraphStyle: paragraph], range: full)
            if storage.length > 0 {
                let title = (editor.string as NSString).paragraphRange(for: NSRange(location: 0, length: 0))
                storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 28, weight: .bold), range: title)
            }
            storage.endEditing()
            editor.setSelectedRange(selection)
            // New paragraphs should not inherit the title font while the user types.
            editor.typingAttributes = [.font: NSFont.systemFont(ofSize: selection.location == 0 ? 28 : 17),
                                       .foregroundColor: NSColor(V2Theme.ink), .paragraphStyle: paragraph]
        }
    }
}

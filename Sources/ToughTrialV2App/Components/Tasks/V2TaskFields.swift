import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif
import ToughTrialV2Core

/// One document surface; the first paragraph is the task title, the rest is body text.
struct V2TaskFields: View {
    @Binding var text: String
    @Binding var selection: NSRange
    @Binding var isFocused: Bool
    let isEnabled: Bool
    let identifierPrefix: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    Text("写下要做的事").font(V2Theme.TypeRole.displayMedium)
                    Text("回车继续写内容").font(.body)
                }
                .foregroundStyle(V2Theme.tertiary)
                .padding(.top, 12).allowsHitTesting(false)
            }
            V2TaskDocumentInput(text: $text, selection: $selection, isFocused: $isFocused,
                                isEnabled: isEnabled, identifier: identifierPrefix + ".document")
        }
    }
}

/// UITextView retains a single caret, native selection, marked text, and text undo across paragraphs.
#if os(iOS)
struct V2TaskDocumentInput: UIViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange
    @Binding var isFocused: Bool
    let isEnabled: Bool
    let identifier: String

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.tintColor = UIColor(V2Theme.blue)
        view.textContainerInset = UIEdgeInsets(top: 12, left: 0, bottom: 24, right: 0)
        view.textContainer.lineFragmentPadding = 0
        view.alwaysBounceVertical = true
        view.keyboardDismissMode = .interactive
        view.adjustsFontForContentSizeCategory = true
        view.accessibilityIdentifier = identifier
        view.accessibilityLabel = "任务内容，第一段为标题，回车后写正文"
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.applyingUpdate = true
        defer { coordinator.applyingUpdate = false }
        coordinator.applyBindings(to: view)
        view.isEditable = isEnabled
        let focusChanged = coordinator.synchronizedFocus != isFocused
        coordinator.synchronizedFocus = isFocused
        if focusChanged && isFocused && isEnabled && !view.isFirstResponder {
            DispatchQueue.main.async { [weak view, weak coordinator] in
                guard let view, coordinator?.parent.isFocused == true,
                      coordinator?.parent.isEnabled == true, view.window != nil else { return }
                view.becomeFirstResponder()
            }
        } else if ((focusChanged && !isFocused) || !isEnabled) && view.isFirstResponder {
            view.resignFirstResponder()
        }
    }

    static func dismantleUIView(_ view: UITextView, coordinator: Coordinator) {
        view.delegate = nil
        view.resignFirstResponder()
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: V2TaskDocumentInput
        var applyingUpdate = false
        var synchronizedFocus: Bool?
        private var synchronizedText: String?
        private var synchronizedSelection: NSRange?
        private var styledContentSize: UIContentSizeCategory?
        init(parent: V2TaskDocumentInput) { self.parent = parent }

        func applyBindings(to view: UITextView) {
            // Only external changes (for example dictation) may replace native editing state.
            // Composition belongs to the system IME until it commits.
            guard view.markedTextRange == nil else { return }
            let wasApplying = applyingUpdate
            applyingUpdate = true
            defer { applyingUpdate = wasApplying }
            let changed = synchronizedText != parent.text
            if changed {
                if view.text != parent.text { view.text = parent.text }
                synchronizedText = parent.text
            }
            if synchronizedSelection != parent.selection {
                let length = (view.text as NSString).length
                let start = min(parent.selection.location, length)
                view.selectedRange = NSRange(location: start, length: min(parent.selection.length, length - start))
                synchronizedSelection = parent.selection
            }
            if changed || styledContentSize != view.traitCollection.preferredContentSizeCategory { style(view) }
            if changed { view.scrollRangeToVisible(view.selectedRange) }
        }

        private func publishNativeState(_ view: UITextView) {
            synchronizedText = view.text
            synchronizedSelection = view.selectedRange
            // UIKit may notify selection before text. Publish both in this order so an
            // intervening SwiftUI update cannot restore the previous document.
            parent.text = view.text
            parent.selection = view.selectedRange
        }

        func textViewDidBeginEditing(_ view: UITextView) {
            synchronizedFocus = true
            if !applyingUpdate { parent.isFocused = true }
        }
        func textViewDidEndEditing(_ view: UITextView) {
            synchronizedFocus = false
            if !applyingUpdate { parent.isFocused = false }
        }
        func textViewDidChange(_ view: UITextView) {
            guard !applyingUpdate else { return }
            publishNativeState(view)
            if view.markedTextRange == nil { style(view) }
            view.scrollRangeToVisible(view.selectedRange)
        }
        func textViewDidChangeSelection(_ view: UITextView) {
            guard !applyingUpdate, view.markedTextRange == nil else { return }
            publishNativeState(view)
        }

        func style(_ view: UITextView) {
            guard view.markedTextRange == nil else { return }
            let wasApplying = applyingUpdate
            applyingUpdate = true
            defer { applyingUpdate = wasApplying }
            let selected = view.selectedRange
            let text = view.text as NSString
            var end = 0, contentsEnd = 0
            text.getParagraphStart(nil, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: 0, length: 0))
            let base = UIFont.systemFont(ofSize: 30, weight: .black)
            let rounded = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
            let titleFont = UIFontMetrics(forTextStyle: .title1).scaledFont(for: UIFont(descriptor: rounded, size: 30), compatibleWith: view.traitCollection)
            let bodyFont = UIFont.preferredFont(forTextStyle: .body, compatibleWith: view.traitCollection)
            let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 6; paragraph.paragraphSpacing = 10
            let titleParagraph = NSMutableParagraphStyle(); titleParagraph.lineSpacing = 4; titleParagraph.paragraphSpacing = 18
            let body: [NSAttributedString.Key: Any] = [.font: bodyFont, .foregroundColor: UIColor(V2Theme.ink), .paragraphStyle: paragraph]
            let title: [NSAttributedString.Key: Any] = [.font: titleFont, .foregroundColor: UIColor(V2Theme.ink), .paragraphStyle: titleParagraph]
            view.textStorage.beginEditing()
            view.textStorage.addAttributes(body, range: NSRange(location: 0, length: text.length))
            view.textStorage.addAttributes(title, range: NSRange(location: 0, length: end))
            view.textStorage.endEditing()
            view.selectedRange = selected
            view.typingAttributes = selected.location <= contentsEnd ? title : body
            styledContentSize = view.traitCollection.preferredContentSizeCategory
        }
    }
}

#endif

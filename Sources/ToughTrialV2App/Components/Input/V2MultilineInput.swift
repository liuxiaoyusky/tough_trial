import SwiftUI

/// A bounded multiline editor that grows with short drafts and scrolls internally for long drafts.
/// The component owns no draft persistence or submission behavior; callers provide the binding.
struct V2MultilineInput: View {
    @Binding var text: String
    let placeholder: String
    let minHeight: CGFloat
    let maxHeight: CGFloat
    let accessibilityIdentifier: String
    var isEnabled: Bool = true
    var focus: FocusState<Bool>.Binding? = nil
    @FocusState private var localFocus: Bool

    private var resolvedHeight: CGFloat {
        let lowerBound = min(minHeight, maxHeight)
        let upperBound = max(minHeight, maxHeight)
        let estimatedLines = text.split(separator: "\n", omittingEmptySubsequences: false).reduce(0) { total, line in
            total + max(1, Int(ceil(Double(line.count) / 32)))
        }
        let contentHeight = CGFloat(max(1, estimatedLines)) * 22 + 16
        return min(upperBound, max(lowerBound, contentHeight))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .foregroundStyle(V2Theme.tertiary)
                    .padding(.top, 8)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $text)
                .focused(focus ?? $localFocus)
                .scrollContentBackground(.hidden)
                .frame(height: resolvedHeight)
                .disabled(!isEnabled)
                .accessibilityIdentifier(accessibilityIdentifier)
        }
        .frame(height: resolvedHeight)
        .font(.body)
        .foregroundStyle(V2Theme.ink)
        .tint(V2Theme.blue)
        .scrollDismissesKeyboard(.interactively)
    }
}

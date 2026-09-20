import SwiftUI

private struct V2ScheduleHighlightKey: EnvironmentKey {
    static let defaultValue: Set<String> = []
}

extension EnvironmentValues {
    var scheduleHighlightedIDs: Set<String> {
        get { self[V2ScheduleHighlightKey.self] }
        set { self[V2ScheduleHighlightKey.self] = newValue }
    }
}

struct V2ScheduleHighlight: ViewModifier {
    @Environment(\.scheduleHighlightedIDs) private var highlightedIDs
    let ids: [String?]

    func body(content: Content) -> some View {
        let highlighted = ids.compactMap { $0 }.contains { highlightedIDs.contains($0) }
        content
            .background(RoundedRectangle(cornerRadius: 8).fill(V2Theme.blue.opacity(highlighted ? 0.09 : 0)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(V2Theme.blue.opacity(highlighted ? 0.4 : 0)))
            .accessibilityHint(highlighted ? "助手刚刚修改，可在对话中撤销" : "")
    }
}

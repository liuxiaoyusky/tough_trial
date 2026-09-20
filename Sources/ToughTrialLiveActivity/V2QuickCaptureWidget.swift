import SwiftUI
import WidgetKit

/// Fixed-entry widgets that hand off to the app's unified capture composer.
///
/// A widget stays deliberately small: it offers a launch point, while the app
/// owns text editing, voice input, AI extraction, and confirmation.
struct V2QuickCaptureWidget: Widget {
    enum Variant: Equatable {
        case medium
        case ledger
        case task
        case note

        var kind: String {
            switch self {
            case .medium: "com.skyliu.toughtrial.quick-capture"
            case .ledger: "com.skyliu.toughtrial.quick-capture.ledger"
            case .task: "com.skyliu.toughtrial.quick-capture.task"
            case .note: "com.skyliu.toughtrial.quick-capture.note"
            }
        }

        var title: String {
            switch self {
            case .medium: "快速记录"
            case .ledger: "快速记账"
            case .task: "快速待办"
            case .note: "随手记"
            }
        }

        var subtitle: String {
            switch self {
            case .medium: "把想法交给 Tough Trial 整理"
            case .ledger: "记下金额和描述"
            case .task: "记下要做的事"
            case .note: "留下今天的片段"
            }
        }

        var systemImage: String {
            switch self {
            case .medium: "square.and.pencil"
            case .ledger: "yensign.circle.fill"
            case .task: "checklist"
            case .note: "note.text"
            }
        }

        var deepLink: URL {
            switch self {
            case .medium: URL(string: "toughtrial://capture/note")!
            case .ledger: URL(string: "toughtrial://capture/ledger")!
            case .task: URL(string: "toughtrial://capture/task")!
            case .note: URL(string: "toughtrial://capture/note")!
            }
        }
    }

    private let variant: Variant

    init() {
        self.variant = .medium
    }

    init(variant: Variant) {
        self.variant = variant
    }

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: variant.kind, provider: Provider()) { entry in
            V2QuickCaptureWidgetView(entry: entry, variant: variant)
        }
        .contentMarginsDisabled()
        .configurationDisplayName(variant.title)
        .description(variant.subtitle)
        .supportedFamilies(variant == .medium ? [.systemMedium] : [.systemSmall])
    }

    fileprivate struct Entry: TimelineEntry {
        let date: Date
    }

    private struct Provider: TimelineProvider {
        func placeholder(in context: Context) -> Entry {
            Entry(date: Date())
        }

        func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
            completion(Entry(date: Date()))
        }

        func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
            completion(Timeline(entries: [Entry(date: Date())], policy: .never))
        }
    }
}

private struct V2QuickCaptureWidgetView: View {
    let entry: V2QuickCaptureWidget.Entry
    let variant: V2QuickCaptureWidget.Variant

    var body: some View {
        Group {
            switch variant {
            case .medium:
                mediumContent
            case .ledger, .task, .note:
                smallContent
                    .widgetURL(variant.deepLink)
            }
        }
        .containerBackground(for: .widget) {
            V2QuickCaptureWidgetPalette.background
        }
    }

    private var mediumContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: variant.systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(V2QuickCaptureWidgetPalette.ink)
                    .frame(width: 34, height: 34)
                    .background(V2QuickCaptureWidgetPalette.surface, in: RoundedRectangle(cornerRadius: 11))

                VStack(alignment: .leading, spacing: 2) {
                    Text(variant.title)
                        .font(.headline)
                        .foregroundStyle(V2QuickCaptureWidgetPalette.ink)
                    Text(variant.subtitle)
                        .font(.caption)
                        .foregroundStyle(V2QuickCaptureWidgetPalette.muted)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                mediumLink(.ledger)
                mediumLink(.task)
                mediumLink(.note)
            }
        }
        .padding(16)
    }

    private func mediumLink(_ destination: V2QuickCaptureWidget.Variant) -> some View {
        Link(destination: destination.deepLink) {
            VStack(alignment: .leading, spacing: 7) {
                Image(systemName: destination.systemImage)
                    .font(.headline)
                    .foregroundStyle(destination.color)
                Text(destination.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(V2QuickCaptureWidgetPalette.ink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 46)
            .padding(10)
            .background(V2QuickCaptureWidgetPalette.surface, in: RoundedRectangle(cornerRadius: 13))
        }
        .accessibilityLabel("打开\(destination.title)")
    }

    private var smallContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: variant.systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(variant.color)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(V2QuickCaptureWidgetPalette.muted)
            }

            Spacer(minLength: 12)

            Text(variant.title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(V2QuickCaptureWidgetPalette.ink)
            Text(variant.subtitle)
                .font(.caption)
                .foregroundStyle(V2QuickCaptureWidgetPalette.muted)
                .lineLimit(2)
                .padding(.top, 4)
        }
        .padding(16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("打开\(variant.title)")
    }
}

private extension V2QuickCaptureWidget.Variant {
    var color: Color {
        switch self {
        case .medium: V2QuickCaptureWidgetPalette.ink
        case .ledger: V2QuickCaptureWidgetPalette.coral
        case .task: V2QuickCaptureWidgetPalette.blue
        case .note: V2QuickCaptureWidgetPalette.green
        }
    }
}

private enum V2QuickCaptureWidgetPalette {
    static let background = Color(red: 0.98, green: 0.965, blue: 0.93)
    static let surface = Color.white.opacity(0.72)
    static let ink = Color(red: 0.14, green: 0.14, blue: 0.16)
    static let muted = Color(red: 0.42, green: 0.41, blue: 0.40)
    static let coral = Color(red: 0.83, green: 0.30, blue: 0.22)
    static let blue = Color(red: 0.20, green: 0.40, blue: 0.72)
    static let green = Color(red: 0.20, green: 0.52, blue: 0.36)
}

#Preview(as: .systemMedium) {
    V2QuickCaptureWidget(variant: .medium)
} timeline: {
    V2QuickCaptureWidget.Entry(date: Date())
}

#Preview(as: .systemSmall) {
    V2QuickCaptureWidget(variant: .ledger)
} timeline: {
    V2QuickCaptureWidget.Entry(date: Date())
}

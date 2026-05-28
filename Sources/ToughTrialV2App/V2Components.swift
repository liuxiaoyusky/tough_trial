import SwiftUI

struct V2IconButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(V2Theme.ink)
                .frame(width: 40, height: 40)
                .background(V2Theme.panel)
                .clipShape(Circle())
                .overlay(
                    Circle().stroke(V2Theme.line, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

struct V2SegmentedPicker: View {
    let items: [String]
    @Binding var selection: String

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(items, id: \.self) { item in
                Text(item).tag(item)
            }
        }
        .pickerStyle(.segmented)
    }
}

struct V2Panel<Content: View>: View {
    let padding: CGFloat
    @ViewBuilder let content: () -> Content

    init(padding: CGFloat = 16, @ViewBuilder content: @escaping () -> Content) {
        self.padding = padding
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(padding)
        .background(V2Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(V2Theme.line, lineWidth: 1)
        )
    }
}

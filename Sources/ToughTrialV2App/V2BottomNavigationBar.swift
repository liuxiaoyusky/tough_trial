import SwiftUI

struct V2BottomNavigationBar: View {
    @ObservedObject var navigation: V2NavigationStore
    let availableIDs: Set<V2NavigationID>
    @Binding var selection: V2NavigationID

    var body: some View {
        HStack(spacing: 2) {
            ForEach(navigation.orderedTabs) { item in
                Button {
                    selection = item
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.systemImage)
                            .font(.system(size: 18, weight: selection == item ? .semibold : .regular))
                        Text(item.title).font(.caption2).lineLimit(1)
                    }
                    .foregroundStyle(selection == item ? V2Theme.blue : .secondary)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("root.tab.\(item.rawValue)")
                .accessibilityAddTraits(selection == item ? .isSelected : [])
                .draggable(item.rawValue)
                .dropDestination(for: String.self) { values, _ in
                    guard let raw = values.first, let dragged = V2NavigationID(rawValue: raw) else { return false }
                    navigation.move(dragged, before: item, availableIDs: availableIDs)
                    return true
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 5)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
    }
}

import SwiftUI

struct V2PlaceholderScreen: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.title.weight(.semibold))
            .foregroundStyle(V2Theme.ink)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .v2ScreenBackground()
    }
}

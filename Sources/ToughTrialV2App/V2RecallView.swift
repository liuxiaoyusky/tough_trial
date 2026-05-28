import SwiftUI

struct V2RecallView: View {
    @ObservedObject var store: V2AppStore

    var body: some View {
        V2PlaceholderScreen(title: "回想")
    }
}

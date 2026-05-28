import SwiftUI

struct V2TodayView: View {
    @ObservedObject var store: V2AppStore

    var body: some View {
        V2PlaceholderScreen(title: "今天")
    }
}

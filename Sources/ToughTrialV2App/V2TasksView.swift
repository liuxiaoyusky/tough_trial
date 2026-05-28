import SwiftUI

struct V2TasksView: View {
    @ObservedObject var store: V2AppStore

    var body: some View {
        V2PlaceholderScreen(title: "任务")
    }
}

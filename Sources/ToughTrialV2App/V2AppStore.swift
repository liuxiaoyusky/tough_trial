import SwiftUI
import ToughTrialV2Core

@MainActor
final class V2AppStore: ObservableObject {
    @Published var state = V2PrototypeState.sample()
    @Published var isPlanPresented = false
    @Published var zenSession: V2ActiveSession?

    func openPlanAgent() { isPlanPresented = true }
    func closePlanAgent() { isPlanPresented = false }

    func startZen(taskID: String?, title: String) {
        guard state.startSession(taskID: taskID, title: title, startedAtLabel: "现在") else { return }
        zenSession = state.activeSessions.last
    }

    func finishZen() {
        guard let id = zenSession?.id else { return }
        state.endSession(id, totalElapsed: 25, endLabel: "刚刚")
        zenSession = nil
    }

    func closeZen() { zenSession = nil }
}

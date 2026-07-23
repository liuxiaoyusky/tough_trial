import SwiftUI
import ToughTrialV2Core

@main
struct ToughTrialV2App: App {
    var body: some Scene {
        WindowGroup {
#if DEBUG
            if let snapshotMode = V2PlanSnapshotMode.current {
                V2PlanSnapshotHost(mode: snapshotMode)
            } else {
                V2RootView()
            }
#else
            V2RootView()
#endif
        }
    }
}

#if DEBUG
private enum V2PlanSnapshotMode: String {
    case empty
    case clarify
    case confirm

    static var current: Self? {
        ProcessInfo.processInfo.environment["PLAN_SNAPSHOT"].flatMap(Self.init(rawValue:))
    }
}

@MainActor
private struct V2PlanSnapshotHost: View {
    @StateObject private var store: V2AppStore

    init(mode: V2PlanSnapshotMode) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
        let fixedDate = calendar.date(from: DateComponents(year: 2026, month: 7, day: 21, hour: 9)) ?? Date()
        var state = V2PrototypeState.empty()

        if mode != .empty {
            state.beginPlanPrompt("这周想跑 10 公里", at: fixedDate, calendar: calendar)
        }
        if mode == .confirm {
            state.confirmPlanClarification("可以", at: fixedDate, calendar: calendar)
        }

        _store = StateObject(
            wrappedValue: V2AppStore(
                engine: V2Engine(),
                initialState: state,
                calendar: calendar
            )
        )
    }

    var body: some View {
        V2PlanAgentView(store: store)
    }
}
#endif

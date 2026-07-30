import SwiftUI
import ToughTrialV2Core

@main
struct ToughTrialV2App: App {
    var body: some Scene {
        WindowGroup {
#if DEBUG
            if let snapshotMode = V2PlanSnapshotMode.current {
                V2PlanSnapshotHost(mode: snapshotMode)
            } else if let snapshotMode = V2RecallSnapshotMode.current {
                V2RecallSnapshotHost(mode: snapshotMode)
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

private enum V2RecallSnapshotMode: String {
    case empty
    case writing
    case evidence

    static var current: Self? {
        ProcessInfo.processInfo.environment["RECALL_SNAPSHOT"].flatMap(Self.init(rawValue:))
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

@MainActor
private struct V2RecallSnapshotHost: View {
    @StateObject private var store: V2AppStore
    private let initiallyShowsReferences: Bool

    init(mode: V2RecallSnapshotMode) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let engine = V2Engine()

        if mode != .empty {
            let writing = try? engine.createTask(title: "完成论文结构", at: today)
            if let writing {
                let plan = try? engine.addTaskToToday(
                    taskID: writing.id,
                    date: today,
                    calendar: calendar
                )
                let segment = try? engine.startExecution(
                    taskID: writing.id,
                    title: writing.title,
                    source: .normal,
                    at: today.addingTimeInterval(9 * 3_600),
                    createdFromPlanItemID: plan?.id
                )
                if let segment {
                    _ = try? engine.endExecution(
                        segmentID: segment.id,
                        at: today.addingTimeInterval(9 * 3_600 + 2_700)
                    )
                }
            }

            _ = try? engine.saveRecallEntry(
                date: today,
                text: "上午完成了论文结构。真正有效的是先限定范围，再开始写。",
                at: now,
                calendar: calendar
            )
        }

        if mode == .evidence {
            let missed = try? engine.createTask(title: "晚间跑步", at: today)
            if let missed {
                let draft = V2PlanDraftRecord(
                    id: "recall-snapshot-missed",
                    mode: .scheduleOnly,
                    userPrompt: "今晚跑步",
                    summary: "安排一次晚间跑步",
                    proposedPlanItems: [
                        V2ProposedPlanItem(
                            id: "recall-snapshot-run",
                            date: today,
                            startAt: today.addingTimeInterval(7 * 3_600),
                            endAt: today.addingTimeInterval(8 * 3_600),
                            taskID: missed.id,
                            title: missed.title
                        )
                    ],
                    createdAt: today,
                    updatedAt: today
                )
                _ = try? engine.savePlanDraft(draft, at: today, calendar: calendar)
                _ = try? engine.acceptPlanDraft(id: draft.id, at: today, calendar: calendar)
            }
        }

        _store = StateObject(
            wrappedValue: V2AppStore(
                engine: engine,
                initialState: .empty(),
                calendar: calendar
            )
        )
        initiallyShowsReferences = mode == .evidence
    }

    var body: some View {
        V2RecallView(store: store, initiallyShowsReferences: initiallyShowsReferences)
    }
}
#endif

import XCTest
import ToughTrialV2Core
@testable import ToughTrial

private struct FixtureConflictClient: V2ScheduleConflictClient {
    var question: String?
    func resolve(_ conflict: V2ScheduleSyncConflict) async throws -> V2ScheduleConflictOutcome {
        if let question { return .clarification(question) }
        return .resolution(conflict.conflicts.map { .init(id: $0.id, choice: .mergeText, text: "保留 3 个示例；最多 2 小时") })
    }
}

@MainActor
final class V2ScheduleConflictTests: XCTestCase {
    private func fixture() throws -> V2AppStore {
        let date = Date(timeIntervalSince1970: 1_788_825_600)
        let task = V2Task(id: "conflict-task", title: "准备演示", note: "原要求", createdAt: date, updatedAt: date)
        let base = V2ScheduleDocument(id: "document", timeZoneIdentifier: "UTC", taskContexts: [], tasks: [task], planItems: [], executionSegments: [])
        var local = base
        local.tasks[0].note = "保留 3 个示例"
        var remote = base
        remote.tasks[0].note = "最多 2 小时"
        let result = try V2ScheduleMerge.merge(base: base, local: local, remote: remote)
        var state = V2ScheduleDocumentState(document: local)
        state.github = .init(location: .init(owner: "fixture", repository: "schedule", branch: "main", path: "schedule.md"))
        state.github?.baseline = base
        state.github?.conflict = .init(base: base, local: local, remote: remote, remoteSHA: String(repeating: "a", count: 40), conflicts: result.conflicts)
        return V2AppStore(engine: V2Engine(snapshot: .init(tasks: local.tasks, scheduleDocumentState: state)))
    }

    func testDefaultConflictApplyHighlightAndUndo() async throws {
        let store = try fixture()
        let applied = await store.resolveScheduleConflict(using: FixtureConflictClient(), requiresConfirmation: false)
        XCTAssertTrue(applied)
        XCTAssertEqual(store.engine.snapshot.tasks[0].note, "保留 3 个示例；最多 2 小时")
        XCTAssertTrue(store.highlightedScheduleIDs.contains("conflict-task"))
        XCTAssertNil(store.engine.snapshot.scheduleDocumentState?.github?.conflict)
        let version = try XCTUnwrap(store.engine.snapshot.scheduleDocumentState?.versions.last)
        XCTAssertEqual(version.source, .conflictResolution)
        store.undoScheduleConflict(id: version.id)
        XCTAssertEqual(store.engine.snapshot.tasks[0].note, "保留 3 个示例")
        XCTAssertEqual(store.engine.snapshot.scheduleDocumentState?.versions.last?.restoredVersionID, version.id)
    }

    func testStrictConflictPreviewCanCancelThenApply() async throws {
        let store = try fixture()
        let before = store.engine.snapshot.tasks
        let applied = await store.resolveScheduleConflict(using: FixtureConflictClient(), requiresConfirmation: true)
        XCTAssertFalse(applied)
        XCTAssertEqual(store.engine.snapshot.tasks, before)
        XCTAssertNotNil(store.pendingScheduleConflict)
        store.pendingScheduleConflict = nil
        XCTAssertEqual(store.engine.snapshot.tasks, before)
        _ = await store.resolveScheduleConflict(using: FixtureConflictClient(), requiresConfirmation: true)
        try store.applyScheduleConflict(XCTUnwrap(store.pendingScheduleConflict))
        XCTAssertEqual(store.engine.snapshot.tasks[0].note, "保留 3 个示例；最多 2 小时")
        XCTAssertNil(store.pendingScheduleConflict)
    }

    func testClarificationKeepsBothCandidatesAndDoesNotWrite() async throws {
        let store = try fixture()
        let before = store.engine.snapshot.tasks
        let applied = await store.resolveScheduleConflict(using: FixtureConflictClient(question: "保留三点还是四点？"), requiresConfirmation: false)
        XCTAssertFalse(applied)
        XCTAssertEqual(store.engine.snapshot.tasks, before)
        XCTAssertEqual(store.scheduleSyncMessage, "保留三点还是四点？")
        XCTAssertNotNil(store.engine.snapshot.scheduleDocumentState?.github?.conflict)
        XCTAssertTrue(store.engine.snapshot.scheduleDocumentState?.versions.isEmpty == true)
    }
    func testAutomaticSyncWaitsForConsentAndBacksOffFailures() {
        let now = Date(timeIntervalSince1970: 1_788_825_600)
        let document = V2ScheduleDocument(id: "auto", timeZoneIdentifier: "UTC", taskContexts: [], tasks: [], planItems: [], executionSegments: [])
        var github = V2ScheduleGitHubState(location: .init(owner: "fixture", repository: "repo", branch: "main", path: "schedule.md"))
        func eligible(after seconds: Double) -> Bool {
            V2AppStore.shouldAutomaticallySync(github, document: document, lastCheckedAt: now.addingTimeInterval(-seconds),
                now: now, isBusy: false, needsConfirmation: false)
        }
        XCTAssertFalse(eligible(after: 100), "Saving a configuration alone cannot upload data")
        github.lastFailure = .network
        XCTAssertFalse(eligible(after: 10), "Offline retries must not run every tick")
        XCTAssertTrue(eligible(after: 30), "An attempted connection may retry after backoff")
        github.lastFailure = .authorization
        XCTAssertFalse(eligible(after: 100), "Invalid credentials require correction")
        github.lastFailure = nil
        github.lastSyncedAt = now
        github.baseline = document
        github.requiresRetry = false
        XCTAssertFalse(eligible(after: 5), "Unchanged data uses the slower remote polling interval")
        XCTAssertTrue(eligible(after: 30))
        github.requiresRetry = true
        XCTAssertTrue(eligible(after: 5), "Pending edits may sync promptly")
        github.automaticSyncEnabled = false
        XCTAssertFalse(eligible(after: 100), "Disabling automatic sync must stop automatic connections")
    }

}

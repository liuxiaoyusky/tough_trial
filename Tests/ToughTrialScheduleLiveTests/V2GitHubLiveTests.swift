import Foundation
import XCTest
import ToughTrialV2Core

private struct OfflineTransport: V2PlanningHTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        throw URLError(.notConnectedToInternet)
    }
}

/// Opt-in integration test. Only writes a unique synthetic Markdown file in the configured repository.
@MainActor
final class V2GitHubLiveTests: XCTestCase {
    func testTwoPersistedClientsConflictAIRecoveryAndRetry() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["TOUGH_TRIAL_REAL_GITHUB_TEST"] == "1" else {
            throw XCTSkip("Requires explicit GitHub write opt-in")
        }
        let repo = try XCTUnwrap(env["SCHEDULE_REPOSITORY"]).split(separator: "/")
        XCTAssertEqual(repo.count, 2)
        guard repo.count == 2 else { return }
        let runID = UUID().uuidString.lowercased()
        let location = V2GitHubScheduleLocation(owner: String(repo[0]), repository: String(repo[1]),
            branch: try XCTUnwrap(env["SCHEDULE_BRANCH"]), path: "acceptance/two-clients-\(runID).md")
        let token = try XCTUnwrap(env["SCHEDULE_GITHUB_TOKEN"])
        let clientA = V2GitHubScheduleClient(location: location, token: token)
        let clientB = V2GitHubScheduleClient(location: location, token: token)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("schedule-clients-\(runID)")
        let storeA = V2JSONSnapshotStore(fileURL: folder.appendingPathComponent("a.json"))
        let storeB = V2JSONSnapshotStore(fileURL: folder.appendingPathComponent("b.json"))
        var a = try V2Engine.load(from: storeA)
        var b = try V2Engine.load(from: storeB)
        let task = try a.createTask(title: "合成演示任务", note: "原要求")
        _ = try a.prepareScheduleDocument(timeZoneIdentifier: "Asia/Shanghai")
        _ = try b.prepareScheduleDocument(timeZoneIdentifier: "Asia/Shanghai")
        try a.configureScheduleGitHub(location)
        try b.configureScheduleGitHub(location)
        func sync(_ engine: V2Engine, _ client: V2GitHubScheduleClient<V2URLSessionPlanningTransport>) async throws {
            let attempt = try engine.beginScheduleSync()
            let result = try await V2ScheduleSynchronizer.synchronize(attempt, using: client)
            try engine.acceptScheduleSync(result, attempt: attempt)
        }
        func edit(_ engine: V2Engine, title: String? = nil, note: String? = nil) throws {
            _ = try engine.applyScheduleProposal(.init(summary: "合成并发修改", operations: [
                .init(kind: .updateTask, targetID: task.id, title: title, note: note)
            ]), requestID: UUID().uuidString)
        }
        func assertConverged() {
            var lhs = a.snapshot.tasks
            let rhs = b.snapshot.tasks
            XCTAssertEqual(lhs.map(\.id), rhs.map(\.id))
            guard lhs.count == rhs.count else { return }
            for index in lhs.indices {
                // The legacy JSON store uses Unix Double dates; a restart can lose one submicrosecond ULP.
                XCTAssertEqual(lhs[index].createdAt.timeIntervalSince1970, rhs[index].createdAt.timeIntervalSince1970, accuracy: 0.000001)
                XCTAssertEqual(lhs[index].updatedAt.timeIntervalSince1970, rhs[index].updatedAt.timeIntervalSince1970, accuracy: 0.000001)
                lhs[index].createdAt = rhs[index].createdAt
                lhs[index].updatedAt = rhs[index].updatedAt
            }
            XCTAssertEqual(lhs, rhs)
        }
        try await sync(a, clientA)
        try await sync(b, clientB)
        let stale = try await clientB.read()
        try edit(a, note: "保留 3 个示例")
        try edit(b, title: "合成内部演示")
        try await sync(a, clientA)
        do {
            _ = try await clientB.write(content: stale.content, expectedSHA: stale.sha)
            XCTFail("Real GitHub must reject stale SHA")
        } catch V2GitHubScheduleError.conflict { }
        try await sync(b, clientB)
        try await sync(a, clientA)
        assertConverged()
        XCTAssertEqual(a.snapshot.tasks[0].title, "合成内部演示")
        XCTAssertEqual(a.snapshot.tasks[0].note, "保留 3 个示例")

        try edit(a, note: "保留 3 个示例，必须配图")
        try edit(b, note: "保留 3 个示例，总共最多 2 小时")
        try await sync(a, clientA)
        try await sync(b, clientB)
        let conflict = try XCTUnwrap(b.snapshot.scheduleDocumentState?.github?.conflict)
        XCTAssertEqual(conflict.conflicts.count, 1)
        let configuration = V2OpenAICompatibleAgentConfiguration(
            endpoint: try XCTUnwrap(URL(string: try XCTUnwrap(env["SCHEDULE_AI_ENDPOINT"]))),
            apiKey: try XCTUnwrap(env["SCHEDULE_AI_API_KEY"]), model: try XCTUnwrap(env["SCHEDULE_AI_MODEL"]))
        let resolver = V2OpenAICompatibleConflictClient(configuration: configuration, guidance: "保留双方的全部要求")
        let start = Date()
        let outcome = try await resolver.resolve(conflict)
        guard case let .resolution(resolutions) = outcome else {
            XCTFail("Independent compatible note requirements should merge")
            return
        }
        let beforeResolution = b.snapshot
        try b.applyScheduleConflictResolution(conflictID: conflict.id, resolutions: resolutions)
        let note = try XCTUnwrap(b.snapshot.tasks.first?.note)
        XCTAssertTrue(note.contains("3") && note.contains("图") && note.contains("2"))
        _ = try b.restoreScheduleDocumentVersion(id: conflict.id)
        XCTAssertEqual(b.snapshot.tasks, beforeResolution.tasks)
        // Restore the saved conflict state to publish the already validated solution after proving undo.
        try storeB.save(beforeResolution)
        b = try V2Engine.load(from: storeB)
        try b.applyScheduleConflictResolution(conflictID: conflict.id, resolutions: resolutions)
        try await sync(b, clientB)
        try await sync(a, clientA)
        assertConverged()
        print("REAL_CONFLICT_AI seconds=\(Date().timeIntervalSince(start)) recovered=true")

        let offlineTask = try a.createTask(title: "合成离线任务")
        let attempt = try a.beginScheduleSync()
        let offline = V2GitHubScheduleClient(location: location, token: token, transport: OfflineTransport())
        do {
            _ = try await V2ScheduleSynchronizer.synchronize(attempt, using: offline)
            XCTFail("Injected network outage must fail")
        } catch is URLError {
            try a.failScheduleSync(attempt, failure: .network)
        }
        a = try V2Engine.load(from: storeA)
        XCTAssertTrue(a.snapshot.scheduleDocumentState?.github?.requiresRetry == true)
        XCTAssertTrue(a.snapshot.tasks.contains { $0.id == offlineTask.id })
        try await sync(a, clientA)
        try await sync(b, clientB)
        let first = try await clientA.read()
        try await sync(a, clientA)
        try await sync(b, clientB)
        let repeated = try await clientB.read()
        XCTAssertEqual(first.sha, repeated.sha)
        assertConverged()
        XCTAssertEqual(b.snapshot.tasks.filter { $0.id == offlineTask.id }.count, 1)
        print("REAL_GITHUB_ACCEPTANCE path=\(location.path) sha=\(repeated.sha) clients=2 repeat_unchanged=true")
    }
}

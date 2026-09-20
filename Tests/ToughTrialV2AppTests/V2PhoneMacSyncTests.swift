import XCTest
import ToughTrialV2Core
@testable import ToughTrial

/// Explicit physical-device acceptance. A Mac edits the published synthetic file independently.
@MainActor
final class V2PhoneMacSyncTests: XCTestCase {
    func testCleanUpInterruptedDeviceUITask() throws {
        guard ProcessInfo.processInfo.environment["TOUGH_TRIAL_CLEANUP_DEVICE_TEST"] == "1" else {
            throw XCTSkip("Explicit cleanup of our interrupted UI test only")
        }
        let store = V2JSONSnapshotStore(fileURL: try V2JSONSnapshotStore.defaultFileURL())
        let engine = try V2Engine.load(from: store)
        guard let task = engine.snapshot.tasks.first(where: { $0.title == "真机界面验收2D017B94" }) else { return }
        let receipt = try XCTUnwrap(engine.snapshot.scheduleReceipts.first { receipt in
            receipt.undoneAt == nil && receipt.changes.count == 1
                && receipt.changes.first?.beforeTask == nil && receipt.changes.first?.afterTask?.id == task.id
        })
        let unrelated = engine.snapshot.tasks.filter { $0.id != task.id }
        _ = try engine.undoScheduleReceipt(id: receipt.id)
        XCTAssertEqual(engine.snapshot.tasks, unrelated)
        XCTAssertNotNil(try store.load().scheduleReceipts.first { $0.id == receipt.id }?.undoneAt)
        print("INTERRUPTED_DEVICE_UI_TASK_UNDONE")
    }

    func testPhoneMacConflictRecoveryAndRetry() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Requires a physical iPhone and an independent Mac editor")
        #else
        let configURL = FileManager.default.temporaryDirectory.appendingPathComponent("tough-trial-phone-sync-config.json")
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            throw XCTSkip("Requires one-use configuration and an explicitly coordinated Mac editor")
        }
        let data = try Data(contentsOf: configURL)
        try FileManager.default.removeItem(at: configURL)
        let config = try JSONDecoder().decode(PhoneSyncConfiguration.self, from: data)
        guard config.path.hasPrefix("acceptance/phone-mac-"), config.path.hasSuffix(".md"),
              !config.path.contains(".."), !config.githubToken.isEmpty, !config.apiKey.isEmpty else {
            throw PhoneSyncError.invalidConfiguration
        }
        let location = V2GitHubScheduleLocation(owner: "liuxiaoyusky", repository: "tough-trial-sync",
            branch: "main", path: config.path)
        let client = V2GitHubScheduleClient(location: location, token: config.githubToken)
        let settings = V2AIProviderSettings(provider: .glmCoding, isEnabled: true,
            baseURL: "https://open.bigmodel.cn/api/coding/paas/v4", model: "glm-5.3-flash", apiKey: config.apiKey)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("phone-sync-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let persistence = V2JSONSnapshotStore(fileURL: folder.appendingPathComponent("snapshot.json"))
        func makeApp() throws -> V2AppStore {
            V2AppStore(engine: try V2Engine.load(from: persistence), memoryEngine: V2MemoryEngine(),
                aiProviderSettings: settings)
        }
        let app = try makeApp()
        // Only the explicit setup flag changes the installed app's selected AI service.
        if config.installAISettings == true {
            try app.updatePlanningSettings(settings)
            let saved = V2AIProviderSettingsStore.load()
            XCTAssertEqual(saved.provider, .glmCoding)
            XCTAssertEqual(saved.model, "glm-5.3-flash")
            XCTAssertTrue(saved.isEnabled && saved.apiKey == config.apiKey, "Authorized AI settings must persist")
        }
        let task = try app.engine.createTask(title: "真机合成同步任务", note: "保留 3 个示例")
        _ = try app.engine.prepareScheduleDocument(timeZoneIdentifier: "Asia/Hong_Kong")
        try app.engine.configureScheduleGitHub(location)
        await app.synchronizeSchedule(using: client)
        XCTAssertNil(app.scheduleSyncError)
        XCTAssertNotNil(app.engine.snapshot.scheduleDocumentState?.github?.lastSyncedAt)

        _ = try app.engine.applyScheduleProposal(.init(summary: "手机补充时间限制", operations: [
            .init(kind: .updateTask, targetID: task.id, note: "保留 3 个示例，总共最多 2 小时")
        ]), requestID: "phone-local-edit")
        print("PHONE_SYNC_WAITING_MAC path=\(config.path)")
        let deadline = Date().addingTimeInterval(120)
        var receivedMacEdit = false
        while Date() < deadline {
            let remote = try await client.read()
            let document = try V2ScheduleMarkdown.decode(remote.content)
            if document.tasks.first?.title == "Mac 修改后的合成任务" {
                receivedMacEdit = true
                break
            }
            try await Task.sleep(for: .seconds(2))
        }
        guard receivedMacEdit else { throw PhoneSyncError.macEditTimedOut }
        await app.synchronizeSchedule(using: client)
        XCTAssertNil(app.scheduleSyncError)
        let conflict = try XCTUnwrap(app.engine.snapshot.scheduleDocumentState?.github?.conflict)
        XCTAssertEqual(conflict.conflicts.count, 1)
        let beforeResolution = app.engine.snapshot
        let resolver = V2OpenAICompatibleConflictClient(configuration: try settings.agentConfiguration(),
            guidance: "保留双方的全部要求：3 个示例、必须配图、最多 2 小时。")
        let waiting = await app.resolveScheduleConflict(using: resolver, requiresConfirmation: true)
        XCTAssertFalse(waiting)
        XCTAssertEqual(app.engine.snapshot.tasks, beforeResolution.tasks)
        let pending = try XCTUnwrap(app.pendingScheduleConflict)
        try app.applyScheduleConflict(pending)
        let resolvedTask = try XCTUnwrap(app.engine.snapshot.tasks.first)
        XCTAssertEqual(resolvedTask.id, task.id)
        XCTAssertEqual(resolvedTask.title, "Mac 修改后的合成任务")
        XCTAssertTrue(resolvedTask.note.contains("3") && resolvedTask.note.contains("图"))
        XCTAssertTrue(resolvedTask.note.contains("2") || resolvedTask.note.contains("两小时"))
        XCTAssertTrue(app.highlightedScheduleIDs.contains(task.id))
        app.undoScheduleConflict(id: conflict.id)
        XCTAssertNil(app.scheduleSyncError)
        XCTAssertEqual(app.engine.snapshot.tasks, beforeResolution.tasks)
        XCTAssertTrue(app.highlightedScheduleIDs.isEmpty)

        // Reopen the exact saved conflict to publish the already validated resolution after proving undo.
        try persistence.save(beforeResolution)
        let restored = try makeApp()
        try restored.applyScheduleConflict(pending)
        await restored.synchronizeSchedule(using: client)
        XCTAssertNil(restored.scheduleSyncError)
        let offlineTask = try restored.engine.createTask(title: "真机离线后恢复任务")
        let offline = V2GitHubScheduleClient(location: location, token: config.githubToken, transport: PhoneOfflineTransport())
        await restored.synchronizeSchedule(using: offline)
        XCTAssertEqual(restored.engine.snapshot.scheduleDocumentState?.github?.lastFailure, .network)
        let rebooted = try makeApp()
        XCTAssertTrue(rebooted.engine.snapshot.scheduleDocumentState?.github?.requiresRetry == true)
        XCTAssertTrue(rebooted.engine.snapshot.tasks.contains { $0.id == offlineTask.id })
        await rebooted.synchronizeSchedule(using: client)
        XCTAssertNil(rebooted.scheduleSyncError)
        let first = try await client.read()
        await rebooted.synchronizeSchedule(using: client)
        let repeated = try await client.read()
        XCTAssertNil(rebooted.scheduleSyncError)
        XCTAssertEqual(first.sha, repeated.sha)
        let final = try V2ScheduleMarkdown.decode(repeated.content)
        XCTAssertEqual(final.tasks.count, 2)
        XCTAssertEqual(final.tasks.filter { $0.id == offlineTask.id }.count, 1)
        XCTAssertEqual(final.tasks.first { $0.id == task.id }?.note, resolvedTask.note)
        let events = V2UsageTrace.shared.events
        XCTAssertTrue(events.contains { $0.kind == .conflictResolved && $0.operationID == conflict.id })
        XCTAssertTrue(events.contains { $0.kind == .scheduleUndone && $0.operationID == conflict.id })
        XCTAssertTrue(events.contains { $0.kind == .syncFailed && $0.source == .sync })
        print("PHONE_MAC_SYNC_ACCEPTANCE path=\(config.path) sha=\(repeated.sha) tasks=2 recovered=true repeat_unchanged=true")
        #endif
    }
}

private struct PhoneSyncConfiguration: Decodable {
    let path: String
    let apiKey: String
    let githubToken: String
    let installAISettings: Bool?
}

private struct PhoneOfflineTransport: V2PlanningHTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        throw URLError(.notConnectedToInternet)
    }
}

private enum PhoneSyncError: Error { case invalidConfiguration, macEditTimedOut }

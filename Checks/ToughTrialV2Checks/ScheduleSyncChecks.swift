import Foundation
import ToughTrialV2Core

func checkScheduleSyncOfflineRetryAndLateLocalEdits() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = V2JSONSnapshotStore(fileURL: directory.appendingPathComponent("snapshot.json"))
    let date = Date(timeIntervalSince1970: 1_788_825_600)
    let task = V2Task(id: "sync-task", title: "原任务", createdAt: date, updatedAt: date)
    let engine = V2Engine(snapshot: .init(tasks: [task]), store: store)
    let document = try engine.prepareScheduleDocument(timeZoneIdentifier: "UTC")
    let location = V2GitHubScheduleLocation(owner: "test", repository: "schedule", branch: "main", path: "schedule.md")
    try engine.configureScheduleGitHub(location)
    let transport = RemoteGitHubTransport(content: try V2ScheduleMarkdown.encode(document))
    let github = V2GitHubScheduleClient(location: location, token: "fixture", transport: transport)
    let initial = try engine.beginScheduleSync()
    try engine.acceptScheduleSync(await V2ScheduleSynchronizer.synchronize(initial, using: github), attempt: initial)
    _ = try engine.createTask(title: "离线新增", at: date)
    await transport.setOffline(true)
    let failed = try engine.beginScheduleSync()
    do {
        _ = try await V2ScheduleSynchronizer.synchronize(failed, using: github)
        fatalError("Offline call must fail without dropping local tasks")
    } catch { try engine.failScheduleSync(failed, failure: .network) }
    let restarted = try V2Engine.load(from: store)
    require(restarted.snapshot.scheduleDocumentState?.github?.requiresRetry == true && restarted.snapshot.tasks.count == 2,
        "Offline pending state and local edits must survive restart")
    await transport.setOffline(false)
    let retry = try restarted.beginScheduleSync()
    let result = try await V2ScheduleSynchronizer.synchronize(retry, using: github)
    _ = try restarted.createTask(title: "网络期间新增", at: date)
    try restarted.acceptScheduleSync(result, attempt: retry)
    require(restarted.snapshot.tasks.count == 3 && restarted.snapshot.scheduleDocumentState?.github?.requiresRetry == true,
        "Late local edits must stay pending rather than disappear behind an older successful upload")
    let next = try restarted.beginScheduleSync()
    try restarted.acceptScheduleSync(await V2ScheduleSynchronizer.synchronize(next, using: github), attempt: next)
    let remote = try V2ScheduleMarkdown.decode(await transport.content)
    require(remote.tasks.count == 3 && restarted.snapshot.scheduleDocumentState?.github?.requiresRetry == false,
        "The next attempt must upload the retained edits")
    let repeatAttempt = try restarted.beginScheduleSync()
    try restarted.acceptScheduleSync(await V2ScheduleSynchronizer.synchronize(repeatAttempt, using: github), attempt: repeatAttempt)
    let writes = await transport.writes
    require(writes == 2, "Repeated sync with no edits must not write another GitHub version")
}

func checkScheduleSyncConcurrentFieldsAndStaleConfiguration() async throws {
    let date = Date(timeIntervalSince1970: 1_788_825_600)
    let task = V2Task(id: "task", title: "原题", createdAt: date, updatedAt: date)
    let engine = V2Engine(snapshot: .init(tasks: [task]))
    let base = try engine.prepareScheduleDocument(timeZoneIdentifier: "UTC")
    let location = V2GitHubScheduleLocation(owner: "test", repository: "schedule", branch: "main", path: "schedule.md")
    try engine.configureScheduleGitHub(location)
    let transport = RemoteGitHubTransport(content: try V2ScheduleMarkdown.encode(base))
    let github = V2GitHubScheduleClient(location: location, token: "fixture", transport: transport)
    let initial = try engine.beginScheduleSync()
    try engine.acceptScheduleSync(await V2ScheduleSynchronizer.synchronize(initial, using: github), attempt: initial)
    _ = try engine.applyScheduleProposal(.init(summary: "改标题", operations: [.init(kind: .updateTask, targetID: task.id, title: "本地标题")]), requestID: "local", at: date.addingTimeInterval(10))
    var remote = base
    remote.tasks[0].note = "远端备注"
    remote.tasks[0].updatedAt = date.addingTimeInterval(20)
    let concurrentTransport = RemoteGitHubTransport(content: try V2ScheduleMarkdown.encode(base), replacementOnFirstWrite: try V2ScheduleMarkdown.encode(remote))
    let concurrent = V2GitHubScheduleClient(location: location, token: "fixture", transport: concurrentTransport)
    let attempt = try engine.beginScheduleSync()
    let result = try await V2ScheduleSynchronizer.synchronize(attempt, using: concurrent)
    try engine.acceptScheduleSync(result, attempt: attempt)
    require(engine.snapshot.tasks[0].title == "本地标题" && engine.snapshot.tasks[0].note == "远端备注",
        "Independent fields merge even when both clients updated metadata timestamps")
    let racingWrites = await concurrentTransport.writes
    require(racingWrites == 2, "A SHA race must re-read and merge before its retry")
    let oldAttempt = try engine.beginScheduleSync()
    var newLocation = location
    newLocation.path = "new.md"
    try engine.configureScheduleGitHub(newLocation)
    let before = engine.snapshot
    do {
        try engine.acceptScheduleSync(result, attempt: oldAttempt)
        fatalError("Old destination result must not mutate a newly configured destination")
    } catch V2ScheduleSyncError.staleAttempt { }
    require(engine.snapshot == before, "Stale sync result must leave current configuration and tasks unchanged")
}

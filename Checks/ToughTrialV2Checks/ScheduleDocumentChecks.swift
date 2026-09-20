import Foundation
import ToughTrialV2Core

func checkDocumentImportAtomicityAndRecovery() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = V2JSONSnapshotStore(fileURL: directory.appendingPathComponent("snapshot.json"))
    let engine = V2Engine(store: store)
    let task = try engine.createTask(title: "原任务", note: "保留数字 3")
    let original = try engine.prepareScheduleDocument(timeZoneIdentifier: "UTC")
    try engine.recordScheduleFileWrite(original)
    var edited = original
    edited.tasks[0].title = "文件里改标题"
    let markdown = try V2ScheduleMarkdown.encode(edited)
    let imported = try engine.importScheduleDocument(V2ScheduleMarkdown.decode(markdown), expectedSnapshot: engine.snapshot,
        requestID: "import-one", bookmark: Data([1, 2]), fileName: "schedule.md")
    require(imported.tasks[0].id == task.id && engine.snapshot.tasks[0].title == "文件里改标题", "File edit must update the existing task")
    let restarted = try V2Engine.load(from: store)
    require(restarted.snapshot.scheduleDocumentState?.versions.count == 1 && restarted.snapshot.scheduleDocumentState?.bookmark == Data([1, 2]),
        "Import, bookmark, and recovery history must survive one atomic save and reload")
    let unrelated = try restarted.createTask(title: "后来新增的无关任务")
    _ = try restarted.restoreScheduleDocumentVersion(id: "import-one")
    require(restarted.snapshot.tasks.contains { $0.id == task.id && $0.title == "原任务" }, "Restore must recover the prior title")
    require(restarted.snapshot.tasks.map(\.id) == [task.id, unrelated.id], "Restore must preserve unrelated later tasks and visible task order")
    let beforeBad = restarted.snapshot
    let diskBeforeBad = try Data(contentsOf: store.fileURL)
    var invalid = imported
    invalid.tasks.append(invalid.tasks[0])
    do {
        _ = try restarted.importScheduleDocument(invalid, expectedSnapshot: beforeBad, requestID: "bad")
        fatalError("Duplicate IDs must not import")
    } catch V2ScheduleMarkdownError.duplicateID { }
    let diskAfterBad = try Data(contentsOf: store.fileURL)
    require(restarted.snapshot == beforeBad && diskAfterBad == diskBeforeBad, "Bad file must leave memory and disk unchanged")
    do {
        _ = try restarted.importScheduleDocument(imported, expectedSnapshot: engine.snapshot, requestID: "stale")
        fatalError("Late read must not overwrite newer state")
    } catch V2ScheduleDocumentError.stale { }

    // A save failure must not leave domain changes without their recovery record.
    let blocked = directory.appendingPathComponent("not-a-directory")
    try Data([0]).write(to: blocked)
    let failing = V2Engine(snapshot: beforeBad, store: .init(fileURL: blocked.appendingPathComponent("snapshot.json")))
    var update = try failing.prepareScheduleDocument(timeZoneIdentifier: "UTC")
    update.tasks[0].note = "新备注"
    do {
        _ = try failing.importScheduleDocument(update, expectedSnapshot: failing.snapshot, requestID: "failure")
        fatalError("Save failure must propagate")
    } catch { }
    require(failing.snapshot == beforeBad, "Failed persistence cannot mutate in-memory tasks or history")
}

func checkDocumentPreservesSubmillisecondExecutionTimes() throws {
    let start = Date(timeIntervalSinceReferenceDate: 810_100_000.1234567)
    let segment = V2ExecutionSegment(id: "precise", titleSnapshot: "执行", startAt: start,
        endAt: start.addingTimeInterval(70.2345678), endReason: .stopped, source: .normal)
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
    defer { try? FileManager.default.removeItem(at: file) }
    let store = V2JSONSnapshotStore(fileURL: file)
    let engine = V2Engine(snapshot: .init(executionSegments: [segment]), store: store)
    let document = try engine.prepareScheduleDocument(timeZoneIdentifier: "UTC")
    let decoded = try V2ScheduleMarkdown.decode(V2ScheduleMarkdown.encode(document))
    require(decoded.executionSegments == document.executionSegments, "Markdown must preserve real execution timestamp precision")
    try engine.recordScheduleFileWrite(document)
    _ = try engine.importScheduleDocument(decoded, expectedSnapshot: engine.snapshot, requestID: "precision", replacingBinding: true)
    require(engine.snapshot.executionSegments == [segment], "Reading our own export must not rewrite execution facts or create false conflicts")
    let reloaded = try V2Engine.load(from: store)
    let factsBeforeRead = reloaded.snapshot.executionSegments
    _ = try reloaded.importScheduleDocument(decoded, expectedSnapshot: reloaded.snapshot, requestID: "after-reload")
    require(reloaded.snapshot.executionSegments == factsBeforeRead, "Unix timestamp persistence precision must not create a false conflict on the next read")
}

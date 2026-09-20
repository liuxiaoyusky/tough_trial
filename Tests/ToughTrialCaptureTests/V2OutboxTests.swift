import Foundation
import XCTest
@testable import ToughTrialV2Core

final class V2OutboxTests: XCTestCase {
    func testOldSnapshotMigratesOnceWithExactBackup() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("snapshot.json")
        var snapshot = V2AppSnapshot.empty
        snapshot.schemaVersion = 1
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let old = try encoder.encode(snapshot)
        try old.write(to: url)
        let store = V2JSONSnapshotStore(fileURL: url)
        let migrated = try store.load()
        XCTAssertEqual(migrated.schemaVersion, 2)
        XCTAssertEqual(try Data(contentsOf: url.appendingPathExtension("schema-1.backup")), old)
        XCTAssertEqual(try store.load(), migrated)
    }

    func testFutureSnapshotIsRejectedWithoutReplacement() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("snapshot.json")
        var future = V2AppSnapshot.empty
        future.schemaVersion = 999
        let data = try JSONEncoder().encode(future)
        try data.write(to: url)
        XCTAssertThrowsError(try V2JSONSnapshotStore(fileURL: url).load())
        XCTAssertEqual(try Data(contentsOf: url), data)
    }

    func testBusinessCommitAndJobPersistTogetherAcrossRestart() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = V2JSONSnapshotStore(fileURL: directory.appendingPathComponent("snapshot.json"))
        let engine = V2Engine(store: store)
        let task = try engine.createTask(title: "准备明天的材料")
        let restored = try V2Engine.load(from: store)
        XCTAssertEqual(restored.snapshot.tasks.first?.id, task.id)
        XCTAssertEqual(restored.snapshot.outbox.map(\.kind), [.taskReminders])
        XCTAssertFalse(restored.snapshot.outbox.contains { $0.kind == .scheduleSync }, "No first upload without user connection")
    }

    func testFailedBusinessSaveCannotPublishJobOrFact() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let engine = V2Engine(store: V2JSONSnapshotStore(fileURL: directory))
        XCTAssertThrowsError(try engine.createTask(title: "暂不应出现"))
        XCTAssertTrue(engine.snapshot.tasks.isEmpty)
        XCTAssertTrue(engine.snapshot.outbox.isEmpty)
    }

    func testCompletionCannotClearNewerCoalescedJobAndRetryIsBounded() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        var snapshot = V2AppSnapshot.empty
        V2OutboxPolicy.enqueue(.financeReminders, into: &snapshot, at: date)
        let oldID = try XCTUnwrap(snapshot.outbox.first?.id)
        V2OutboxPolicy.enqueue(.financeReminders, into: &snapshot, at: date.addingTimeInterval(1))
        let newID = try XCTUnwrap(snapshot.outbox.first?.id)
        V2OutboxPolicy.finish(id: oldID, failureCode: nil, in: &snapshot, at: date)
        XCTAssertEqual(snapshot.outbox.first?.id, newID)
        for _ in 0..<25 { V2OutboxPolicy.finish(id: newID, failureCode: "notification_pending", in: &snapshot, at: date) }
        XCTAssertEqual(snapshot.outbox.first?.attempts, 20)
        XCTAssertEqual(snapshot.outbox.first?.retryAt, date.addingTimeInterval(3600))
        V2OutboxPolicy.finish(id: newID, failureCode: nil, in: &snapshot, at: date)
        XCTAssertTrue(snapshot.outbox.isEmpty)
    }

    func testStopPausesExecutionWithoutRestoringWriteCapability() throws {
        let runtime = V2ModuleRuntime()
        let engine = V2Engine(moduleRuntime: runtime)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let task = try engine.createTask(title: "进行中", at: date)
        _ = try engine.startExecution(taskID: task.id, title: task.title, source: .normal, at: date)
        runtime.update(preferences: .init(disabled: ["core.tasks"]))
        try engine.pauseExecutionsForModuleStop(at: date.addingTimeInterval(60))
        XCTAssertTrue(engine.openExecutionSegments().isEmpty)
        XCTAssertEqual(engine.snapshot.tasks.first?.status, .paused)
        XCTAssertThrowsError(try engine.createTask(title: "不应写入"))
        XCTAssertEqual(engine.snapshot.executionSegments.first?.duration(through: date.addingTimeInterval(100)), 60)
    }
}

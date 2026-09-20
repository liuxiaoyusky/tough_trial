import XCTest
import ToughTrialV2Core
@testable import ToughTrial

@MainActor
final class V2TaskClassificationPersistenceTests: XCTestCase {
    func testDocumentAndTypePersistTogetherAndUndoAfterReload() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let disk = V2JSONSnapshotStore(fileURL: folder.appendingPathComponent("tasks.json"))
        let engine = V2Engine(store: disk)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let original = try engine.createTask(title: "整理", note: "原正文", at: date)
        let store = V2AppStore(engine: engine)
        let receipt = try XCTUnwrap(store.editTask(original, title: "整理相册", note: "挑选十张",
            classification: V2TaskClassification(kind: .maintenance), at: date.addingTimeInterval(60)))
        let reopened = try V2Engine.load(from: disk)
        let saved = try XCTUnwrap(reopened.snapshot.tasks.first)
        XCTAssertEqual(saved.id, original.id)
        XCTAssertEqual(saved.title, "整理相册")
        XCTAssertEqual(saved.note, "挑选十张")
        XCTAssertEqual(saved.kind, .maintenance)
        _ = try reopened.undoScheduleReceipt(id: receipt.id)
        XCTAssertEqual(try V2Engine.load(from: disk).snapshot.tasks.first, original)

        let broken = V2Engine(snapshot: engine.snapshot, store: V2JSONSnapshotStore(fileURL: folder))
        let brokenStore = V2AppStore(engine: broken)
        let before = broken.snapshot
        XCTAssertNil(brokenStore.editTask(saved, title: "失败修改", note: "失败正文",
            classification: V2TaskClassification(kind: .goal)))
        XCTAssertEqual(broken.snapshot, before)
        XCTAssertNotNil(brokenStore.errorMessage)
    }

    func testDisabledTaskModuleRejectsClassificationWithoutPartialWrite() throws {
        let suite = "classification-module-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let plugins = V2PluginStore(defaults: defaults)
        let engine = V2Engine(moduleRuntime: plugins.runtime)
        let original = try engine.createTask(title: "原任务")
        let store = V2AppStore(engine: engine)
        engine.moduleRuntime = plugins.runtime
        plugins.setEnabled("tasks", false)
        let before = engine.snapshot
        XCTAssertNil(store.editTask(original, title: "不可保存", note: "",
            classification: V2TaskClassification(kind: .goal)))
        XCTAssertEqual(engine.snapshot, before)
        XCTAssertNotNil(store.errorMessage)
    }
}

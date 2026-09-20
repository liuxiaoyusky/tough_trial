import XCTest
import ToughTrialV2Core
@testable import ToughTrial

@MainActor
final class V2CompleteModuleIntegrationTests: XCTestCase {
    func testStoppingCaptureSavesDraftBeforeClosingGate() throws {
        let plugins = V2PluginStore.shared
        plugins.setEnabled("capture", true)
        defer { plugins.setEnabled("capture", true) }
        let engine = V2Engine()
        let store = V2CaptureStore(appStore: V2AppStore(engine: engine))
        store.draft = "切换功能时不能丢掉的想法"
        plugins.setEnabled("capture", false)
        XCTAssertFalse(plugins.enabled("capture"))
        XCTAssertEqual(engine.snapshot.capture.latestEntries.first?.text, store.draft)
    }

    func testFailedDraftSaveKeepsCaptureAndInputOpen() throws {
        let plugins = V2PluginStore.shared
        plugins.setEnabled("capture", true)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let engine = V2Engine(store: V2JSONSnapshotStore(fileURL: directory))
        let store = V2CaptureStore(appStore: V2AppStore(engine: engine))
        store.draft = "磁盘失败时也不能消失"
        plugins.setEnabled("capture", false)
        XCTAssertTrue(plugins.enabled("capture"))
        XCTAssertEqual(store.draft, "磁盘失败时也不能消失")
        XCTAssertNotNil(store.issue)
    }

    func testQuickTaskAndManualLedgerDoNotRequireCapture() throws {
        let plugins = V2PluginStore.shared
        plugins.setEnabled("capture", true)
        defer { plugins.setEnabled("capture", true) }
        let engine = V2Engine()
        let store = V2CaptureStore(appStore: V2AppStore(engine: engine))
        plugins.setEnabled("capture", false)
        store.saveQuickTask(title: "买牛奶", note: "回家路上")
        XCTAssertNil(store.issue)
        store.saveManualLedger(amount: "28", text: "午餐", currency: "CNY", direction: .expense)
        XCTAssertNil(store.issue)
        XCTAssertEqual(engine.snapshot.tasks.first?.note, "回家路上")
        XCTAssertEqual(engine.snapshot.capture.ledger.first?.categoryID, "others")
        XCTAssertTrue(engine.snapshot.capture.entries.isEmpty)
    }

    func testOldOCRCannotOverwriteEditedSource() throws {
        let engine = V2Engine()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = V2CaptureStore(appStore: V2AppStore(engine: engine), assetDirectory: directory)
        store.attach(data: Data([1, 2, 3]), kind: .document, fileExtension: "txt")
        let sourceID = try XCTUnwrap(store.editingID)
        let oldRevision = try XCTUnwrap(store.editingRevision)
        let block = try XCTUnwrap(store.mediaBlocks.first)
        store.draft = "我已经手动补充说明"
        XCTAssertNotNil(store.saveDraft())
        store.recognizedMedia("旧 OCR", captureID: sourceID, sourceRevision: oldRevision, blockID: block.id, assetID: block.assetID)
        XCTAssertEqual(engine.snapshot.capture.latestEntries.first?.blocks.first { $0.id == block.id }?.text, nil)
        XCTAssertEqual(engine.snapshot.capture.latestEntries.first?.text, "我已经手动补充说明")
    }
}

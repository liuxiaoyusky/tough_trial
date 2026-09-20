import XCTest
import AppKit
import ToughTrialV2Core
@testable import ToughTrialMac

@MainActor
final class MacAppModelTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mac-app-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testTaskSurfacesShareOneEngineAndPersist() async throws {
        let url = try directory()
        let model = try MacAppModel(directory: url)
        XCTAssertTrue(model.store.engine === model.workspace.engine)
        model.workspace.beginNew()
        model.workspace.updateText("跨页面任务\n正文不丢失", isComposing: false)
        XCTAssertTrue(model.workspace.save())
        await Task.yield()
        model.store.refreshProjection(at: Date())
        let task = try XCTUnwrap(model.store.engine.snapshot.tasks.first)
        XCTAssertEqual(model.store.state.flattenTasks().first?.title, "跨页面任务")
        XCTAssertNotNil(model.store.setTaskCompletion(taskID: task.id, completed: true))
        await Task.yield()
        model.workspace.refresh()
        XCTAssertEqual(model.workspace.tasks.first?.status, .done)
        let restored = try MacAppModel(directory: url)
        XCTAssertEqual(restored.workspace.tasks.first?.note, "正文不丢失")
        XCTAssertEqual(restored.workspace.tasks.first?.status, .done)
    }

    func testCaptureAndRecallSurviveNavigationAndRestart() throws {
        let url = try directory()
        let model = try MacAppModel(directory: url)
        model.capture.draft = "本机记录：下午完成了验收"
        model.select(.recall)
        XCTAssertEqual(model.page, .recall)
        model.store.updateRecallText("今天完成了桌面验证。")
        model.select(.tasks)
        XCTAssertFalse(model.store.isRecallDirty)
        let restored = try MacAppModel(directory: url)
        XCTAssertEqual(restored.capture.state.latestEntries.first?.blocks.first?.text, "本机记录：下午完成了验收")
        XCTAssertEqual(restored.store.recallText, "今天完成了桌面验证。")
    }

    func testPendingNewTaskPreservedWithoutImplicitCreation() throws {
        let url = try directory()
        let model = try MacAppModel(directory: url)
        model.workspace.beginNew()
        model.workspace.updateText("还没决定的草稿", isComposing: false)
        model.select(.assistant)
        XCTAssertTrue(model.store.engine.snapshot.tasks.isEmpty)
        let restored = try MacAppModel(directory: url)
        XCTAssertEqual(restored.workspace.draft?.text, "还没决定的草稿")
        XCTAssertTrue(restored.workspace.tasks.isEmpty)
    }

    func testFileAttachmentPersistsWithMacDirectory() throws {
        let url = try directory()
        let model = try MacAppModel(directory: url)
        let bytes = Data("Synthetic attachment".utf8)
        model.capture.attachFiles([V2PickedFile(data: bytes, fileName: "verification.txt", kind: .document)])
        XCTAssertNil(model.capture.issue)
        let asset = try XCTUnwrap(model.capture.state.assets.first)
        XCTAssertEqual(try model.capture.assets.data(for: asset), bytes)
        let restored = try MacAppModel(directory: url)
        XCTAssertEqual(restored.capture.state.latestEntries.first?.blocks.last?.assetID, asset.id)
        XCTAssertEqual(try restored.capture.assets.data(for: asset), bytes)
    }

    func testCorruptSnapshotRefusesToReplaceExistingFile() throws {
        let url = try directory()
        let original = Data("not-json".utf8)
        let file = url.appendingPathComponent("v2-snapshot.json")
        try original.write(to: file)
        XCTAssertThrowsError(try MacAppModel(directory: url))
        XCTAssertEqual(try Data(contentsOf: file), original)
    }
    func testShutdownFlushesComposerAndKeepsWindowOnFailure() async throws {
        let model = try MacAppModel(directory: directory())
        var flushed = 0
        model.assistant.flushVisibleDraft = { flushed += 1; return false }
        let rejected = await model.shutdown()
        XCTAssertFalse(rejected)
        XCTAssertEqual(flushed, 1)
        XCTAssertFalse(model.isShuttingDown)
        XCTAssertNotNil(model.closeIssue)
        model.assistant.flushVisibleDraft = { flushed += 1; return true }
        let accepted = await model.shutdown()
        XCTAssertTrue(accepted)
        XCTAssertEqual(flushed, 3)
    }

    func testPlanUsesSavedTextAndSourceNavigationPreservesNewDraft() throws {
        let model = try MacAppModel(directory: directory())
        model.workspace.beginNew()
        model.workspace.updateText("原始标题", isComposing: false)
        XCTAssertTrue(model.workspace.save())
        let id = try XCTUnwrap(model.workspace.selectedID)
        model.workspace.updateText("新标题\n新正文", isComposing: false)
        model.openTaskPlan(id)
        XCTAssertEqual(model.store.planningSourceTask?.title, "新标题")
        XCTAssertEqual(model.store.planningSourceTask?.subtitle, "新正文")
        model.workspace.beginNew()
        model.workspace.updateText("不能覆盖这个草稿", isComposing: false)
        model.select(.assistant)
        model.openSourceTask(id)
        XCTAssertEqual(model.page, .assistant)
        XCTAssertNotNil(model.closeIssue)
        XCTAssertEqual(model.workspace.draft?.text, "不能覆盖这个草稿")
    }

    func testSystemPanelsKeepTheirDelegate() {
        let appDelegate = MacAppDelegate()
        let panel = NSPanel()
        // NSWindowDelegate has no required methods.
        let panelDelegate = PanelDelegate()
        panel.identifier = NSUserInterfaceItemIdentifier("workspace")
        panel.delegate = panelDelegate
        appDelegate.observeMainWindow(panel)
        XCTAssertTrue(panel.delegate === panelDelegate)
        let window = NSWindow()
        window.identifier = NSUserInterfaceItemIdentifier("workspace")
        appDelegate.observeMainWindow(window)
        XCTAssertTrue(window.delegate === appDelegate)
    }

    private final class PanelDelegate: NSObject, NSWindowDelegate {}

}

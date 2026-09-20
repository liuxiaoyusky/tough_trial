import XCTest
import ToughTrialV2Core
@testable import ToughTrialAppShared

@MainActor
final class TaskWorkspaceTests: XCTestCase {
    private var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("task-workspace-tests-" + UUID().uuidString)
    }
    override func tearDownWithError() throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    func testDocumentSeparatorsAndOptionalBody() {
        for separator in ["\n", "\r\n", "\u{2029}"] {
            let value = V2TaskDocumentContent.split(" 标题 " + separator + "正文\n第二段")
            XCTAssertEqual(value.title, "标题")
            XCTAssertEqual(value.note, "正文\n第二段")
        }
        XCTAssertEqual(V2TaskDocumentContent.split("").title, "")
        XCTAssertEqual(V2TaskDocumentContent.split("仅标题").note, "")
    }

    func testCreateEditReloadAndUndoPreserveIdentityAndPlacement() throws {
        let workspace = try V2TaskWorkspace(directory: directory)
        XCTAssertTrue(workspace.beginNew())
        workspace.updateText("准备演示\n整理两段说明")
        XCTAssertTrue(workspace.save())
        let original = try XCTUnwrap(workspace.tasks.first)
        XCTAssertTrue(workspace.engine.snapshot.planItems.isEmpty)
        workspace.updateText("准备新版演示\n正文保持连续输入")
        XCTAssertTrue(workspace.save())
        XCTAssertEqual(workspace.tasks.first?.id, original.id)
        let reopened = try V2TaskWorkspace(directory: directory)
        XCTAssertEqual(reopened.tasks.first?.title, "准备新版演示")
        XCTAssertEqual(reopened.draft?.text, "准备新版演示\n正文保持连续输入")
        workspace.undoLastSave()
        XCTAssertEqual(try V2TaskWorkspace(directory: directory).tasks.first?.title, original.title)
    }

    func testUncreatedDraftSurvivesRestartAndExplicitCancelDoesNotCreateTask() throws {
        let first = try V2TaskWorkspace(directory: directory)
        first.beginNew()
        first.updateText("还没准备好的想法\n草稿")
        let reopened = try V2TaskWorkspace(directory: directory)
        XCTAssertTrue(reopened.tasks.isEmpty)
        XCTAssertEqual(reopened.draft?.text, first.draft?.text)
        XCTAssertTrue(reopened.discardDraft())
        XCTAssertNil(try V2TaskWorkspace(directory: directory).draft)
    }

    func testBlankOrStaleEditDoesNotOverwriteSavedData() throws {
        let workspace = try V2TaskWorkspace(directory: directory)
        workspace.beginNew(); workspace.updateText("原版"); XCTAssertTrue(workspace.save())
        let original = try XCTUnwrap(workspace.tasks.first)
        workspace.updateText("\n只有正文")
        XCTAssertFalse(workspace.save())
        XCTAssertEqual(workspace.tasks.first?.title, "原版")
        _ = try workspace.engine.updateTaskClassification(id: original.id, title: "其他入口的新版本", note: "", classification: .init())
        workspace.updateText("旧窗口修改")
        XCTAssertFalse(workspace.save())
        XCTAssertEqual(workspace.draft?.text, "旧窗口修改")
        XCTAssertEqual(try V2TaskWorkspace(directory: directory).tasks.first?.title, "其他入口的新版本")
    }

    func testStorageFailureKeepsOriginalAndDraftThenRetrySucceeds() throws {
        let workspace = try V2TaskWorkspace(directory: directory)
        workspace.beginNew(); workspace.updateText("原版"); XCTAssertTrue(workspace.save())
        let snapshotURL = directory.appendingPathComponent("v2-snapshot.json")
        let backup = try Data(contentsOf: snapshotURL)
        try FileManager.default.removeItem(at: snapshotURL)
        try FileManager.default.createDirectory(at: snapshotURL, withIntermediateDirectories: false)
        workspace.updateText("修改仍在草稿里")
        XCTAssertFalse(workspace.save())
        XCTAssertEqual(workspace.tasks.first?.title, "原版")
        XCTAssertEqual(workspace.draft?.text, "修改仍在草稿里")
        try FileManager.default.removeItem(at: snapshotURL)
        try backup.write(to: snapshotURL)
        XCTAssertTrue(workspace.save())
        XCTAssertEqual(try V2TaskWorkspace(directory: directory).tasks.first?.title, "修改仍在草稿里")
    }

    func testCompletionUndoAndRestart() throws {
        let workspace = try V2TaskWorkspace(directory: directory)
        workspace.beginNew(); workspace.updateText("完成我"); XCTAssertTrue(workspace.save())
        let id = try XCTUnwrap(workspace.tasks.first?.id)
        workspace.toggleCompletion(id)
        XCTAssertEqual(try V2TaskWorkspace(directory: directory).tasks.first?.status, .done)
        workspace.undoLastSave()
        XCTAssertEqual(try V2TaskWorkspace(directory: directory).tasks.first?.status, .notStarted)
        workspace.toggleCompletion(id); workspace.toggleCompletion(id)
        XCTAssertEqual(workspace.tasks.first?.status, .notStarted)
    }

    func testRetryAfterCreateBeforeDraftAcknowledgementDoesNotDuplicate() throws {
        let workspace = try V2TaskWorkspace(directory: directory)
        workspace.beginNew(); workspace.updateText("只创建一次")
        let draftURL = directory.appendingPathComponent("task-editor-draft.json")
        let staleDraft = try Data(contentsOf: draftURL)
        XCTAssertTrue(workspace.save())
        // Simulates process death after snapshot save but before updating the draft file.
        try staleDraft.write(to: draftURL, options: .atomic)
        let reopened = try V2TaskWorkspace(directory: directory)
        XCTAssertTrue(reopened.save())
        XCTAssertEqual(try V2TaskWorkspace(directory: directory).tasks.count, 1)
    }

    func testCorruptSnapshotIsNeverReplacedWithEmpty() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("v2-snapshot.json")
        let bytes = Data("damaged".utf8)
        try bytes.write(to: file)
        XCTAssertThrowsError(try V2TaskWorkspace(directory: directory))
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }

    func testRecoveredCreateCanBeEditedWithoutLosingNewText() throws {
        let workspace = try V2TaskWorkspace(directory: directory)
        workspace.beginNew(); workspace.updateText("先创建")
        let draftURL = directory.appendingPathComponent("task-editor-draft.json")
        let pending = try Data(contentsOf: draftURL)
        XCTAssertTrue(workspace.save())
        try pending.write(to: draftURL, options: .atomic)
        let reopened = try V2TaskWorkspace(directory: directory)
        XCTAssertFalse(try XCTUnwrap(reopened.draft).isNew)
        reopened.updateText("重启后继续修改\n不能丢失这段内容")
        XCTAssertTrue(reopened.save())
        let final = try V2TaskWorkspace(directory: directory)
        XCTAssertEqual(final.tasks.count, 1)
        XCTAssertEqual(final.tasks.first?.title, "重启后继续修改")
        XCTAssertEqual(final.tasks.first?.note, "不能丢失这段内容")
    }

    func testMarkedTextCannotBeSavedOrUsedToSwitchTasks() throws {
        let workspace = try V2TaskWorkspace(directory: directory)
        workspace.beginNew()
        workspace.updateText("zhongwen", isComposing: true)
        XCTAssertFalse(workspace.canSave)
        XCTAssertFalse(workspace.save())
        XCTAssertTrue(workspace.tasks.isEmpty)
        workspace.updateText("中文已确认", isComposing: false)
        XCTAssertTrue(workspace.save())
        workspace.updateText("weiqueren", isComposing: true)
        XCTAssertFalse(workspace.beginNew())
        XCTAssertFalse(workspace.save())
        XCTAssertEqual(workspace.tasks.first?.title, "中文已确认")
    }

    func testRecoveredCreateUsesReceiptVersionToRejectNewerChanges() throws {
        let workspace = try V2TaskWorkspace(directory: directory)
        workspace.beginNew(); workspace.updateText("旧创建文本")
        let file = directory.appendingPathComponent("task-editor-draft.json")
        let pending = try Data(contentsOf: file)
        XCTAssertTrue(workspace.save())
        let id = try XCTUnwrap(workspace.selectedID)
        _ = try workspace.engine.updateTaskClassification(id: id, title: "其他入口更新", note: "不能覆盖", classification: .init())
        try pending.write(to: file, options: .atomic)
        let reopened = try V2TaskWorkspace(directory: directory)
        reopened.updateText("旧草稿继续修改")
        XCTAssertFalse(reopened.save())
        XCTAssertEqual(try V2TaskWorkspace(directory: directory).tasks.first?.title, "其他入口更新")
        XCTAssertTrue(reopened.discardDraft())
        XCTAssertEqual(reopened.draft?.text, "其他入口更新\n不能覆盖")
    }

    func testUndoneCreateRecoveryGetsNewIdempotencyKey() throws {
        let workspace = try V2TaskWorkspace(directory: directory)
        workspace.beginNew(); workspace.updateText("撤销后可以重新创建")
        let file = directory.appendingPathComponent("task-editor-draft.json")
        let oldDraftID = workspace.draft?.id
        let pending = try Data(contentsOf: file)
        XCTAssertTrue(workspace.save())
        workspace.undoLastSave()
        try pending.write(to: file, options: .atomic)
        let reopened = try V2TaskWorkspace(directory: directory)
        XCTAssertNotEqual(reopened.draft?.id, oldDraftID)
        XCTAssertTrue(reopened.save())
        XCTAssertEqual(try V2TaskWorkspace(directory: directory).tasks.count, 1)
    }

    func testDamagedDraftIsPreservedWithoutBlockingSavedTasks() throws {
        let workspace = try V2TaskWorkspace(directory: directory)
        workspace.beginNew(); workspace.updateText("正式任务安全"); XCTAssertTrue(workspace.save())
        let broken = Data("invalid draft".utf8)
        try broken.write(to: directory.appendingPathComponent("task-editor-draft.json"))
        let reopened = try V2TaskWorkspace(directory: directory)
        XCTAssertEqual(reopened.tasks.first?.title, "正式任务安全")
        XCTAssertNotNil(reopened.issue)
        let backup = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .first { $0.pathExtension == "backup" })
        XCTAssertEqual(try Data(contentsOf: backup), broken)
        XCTAssertTrue(reopened.select(try XCTUnwrap(reopened.tasks.first?.id)))
    }

    func testLastWorkspaceUndoSurvivesRestart() throws {
        let workspace = try V2TaskWorkspace(directory: directory)
        workspace.beginNew(); workspace.updateText("原版"); XCTAssertTrue(workspace.save())
        workspace.updateText("新版"); XCTAssertTrue(workspace.save())
        let reopened = try V2TaskWorkspace(directory: directory)
        XCTAssertNotNil(reopened.lastReceiptID)
        reopened.undoLastSave()
        XCTAssertEqual(try V2TaskWorkspace(directory: directory).tasks.first?.title, "原版")
    }

    func testEditingChildPreservesParentContextAndSibling() throws {
        let workspace = try V2TaskWorkspace(directory: directory)
        let context = try workspace.engine.createTaskContext(title: "项目", colorName: "blue")
        let parent = try workspace.engine.createTask(title: "目标", contextID: context.id)
        let child = try workspace.engine.createTask(title: "步骤", parentID: parent.id, contextID: context.id)
        let sibling = try workspace.engine.createTask(title: "另一步", parentID: parent.id, contextID: context.id)
        let persistedSibling = try XCTUnwrap(V2TaskWorkspace(directory: directory).tasks.first { $0.id == sibling.id })
        workspace.refresh(); XCTAssertTrue(workspace.select(child.id))
        workspace.updateText("修改步骤\n正文"); XCTAssertTrue(workspace.save())
        let reopened = try V2TaskWorkspace(directory: directory)
        let updated = try XCTUnwrap(reopened.tasks.first { $0.id == child.id })
        XCTAssertEqual(updated.parentID, parent.id)
        XCTAssertEqual(updated.contextID, context.id)
        XCTAssertEqual(reopened.tasks.first { $0.id == sibling.id }, persistedSibling)
    }

    func testUnsavedExistingDraftSurvivesRestartWithoutFalseStaleError() throws {
        let workspace = try V2TaskWorkspace(directory: directory)
        workspace.beginNew(); workspace.updateText("原版"); XCTAssertTrue(workspace.save())
        workspace.updateText("尚未提交的修改\n重启后继续")
        let reopened = try V2TaskWorkspace(directory: directory)
        XCTAssertTrue(reopened.hasChanges)
        XCTAssertTrue(reopened.save(), reopened.issue ?? "保存失败")
        XCTAssertEqual(try V2TaskWorkspace(directory: directory).tasks.first?.title, "尚未提交的修改")
    }

    func testRenewedCreateRequestSurvivesAnotherCrashWithoutDuplicate() throws {
        let workspace = try V2TaskWorkspace(directory: directory)
        workspace.beginNew(); workspace.updateText("反复中断也只有一条")
        let file = directory.appendingPathComponent("task-editor-draft.json")
        let firstDraft = try Data(contentsOf: file)
        XCTAssertTrue(workspace.save()); workspace.undoLastSave()
        try firstDraft.write(to: file, options: .atomic)
        let recovered = try V2TaskWorkspace(directory: directory)
        var durableDraftAtCommit: Data?
        recovered.engine.onCommandCommitted = { _ in durableDraftAtCommit = try? Data(contentsOf: file) }
        XCTAssertTrue(recovered.save())
        try XCTUnwrap(durableDraftAtCommit).write(to: file, options: .atomic)
        let reopened = try V2TaskWorkspace(directory: directory)
        XCTAssertTrue(reopened.save())
        XCTAssertEqual(try V2TaskWorkspace(directory: directory).tasks.count, 1)
    }

    func testUndoCommittedBeforeDraftAcknowledgementRestoresEditorOnRestart() throws {
        let workspace = try V2TaskWorkspace(directory: directory)
        workspace.beginNew(); workspace.updateText("撤销前的原版"); XCTAssertTrue(workspace.save())
        workspace.updateText("需要撤销的修改"); XCTAssertTrue(workspace.save())
        let file = directory.appendingPathComponent("task-editor-draft.json")
        let priorEditorState = try Data(contentsOf: file)
        workspace.undoLastSave()
        try priorEditorState.write(to: file, options: .atomic)
        let reopened = try V2TaskWorkspace(directory: directory)
        XCTAssertEqual(reopened.draft?.text, "撤销前的原版")
        XCTAssertFalse(reopened.hasExternalChange)
        XCTAssertNil(reopened.lastReceiptID)
    }
    func testCrossSurfaceRefreshUpdatesCleanEditorAndPreservesPendingText() throws {
        let workspace = try V2TaskWorkspace(directory: directory)
        workspace.beginNew(); workspace.updateText("原版"); XCTAssertTrue(workspace.save())
        let id = try XCTUnwrap(workspace.selectedID)
        _ = try workspace.engine.setTaskCompletion(taskID: id, completed: true)
        workspace.refreshExternalChanges()
        XCTAssertFalse(workspace.hasExternalChange)
        XCTAssertEqual(workspace.draft?.original?.status, .done)
        workspace.updateText("正在输入的新文字")
        _ = try workspace.engine.setTaskCompletion(taskID: id, completed: false)
        workspace.refreshExternalChanges()
        XCTAssertTrue(workspace.hasExternalChange)
        XCTAssertEqual(workspace.draft?.text, "正在输入的新文字")
        XCTAssertFalse(workspace.save())
    }

}

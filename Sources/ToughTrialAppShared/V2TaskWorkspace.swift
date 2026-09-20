import Foundation
import Combine
import ToughTrialV2Core

/// Native task workspace: one editor draft, guarded domain commands and durable local storage.
/// Transport is deliberately not implied by a successful local save.
@MainActor
public final class V2TaskWorkspace: ObservableObject {
    public struct Draft: Codable, Equatable {
        public var id: String = UUID().uuidString
        public var original: V2Task?
        public var text: String
        public var isNew: Bool
    }

    private struct EditorState: Codable {
        var formatVersion = 2
        var draft: Draft?
        var lastReceiptID: String?
    }

    private enum DraftError: Error { case unavailable }

    public let engine: V2Engine
    private let draftURL: URL
    private var draftUnavailable = false
    @Published public private(set) var tasks: [V2Task] = []
    @Published public private(set) var draft: Draft?
    @Published public private(set) var issue: String?
    @Published public private(set) var lastReceiptID: String?
    @Published public private(set) var savedAt: Date?
    @Published public private(set) var isComposing = false
    public var selectedID: String? { draft?.original?.id }
    public var hasExternalChange: Bool {
        guard let original = draft?.original else { return false }
        return engine.snapshot.tasks.first(where: { $0.id == original.id }) != original
    }
    public var hasChanges: Bool {
        guard let draft else { return false }
        guard let original = draft.original else { return !draft.text.isEmpty }
        return draft.text != V2TaskDocumentContent.join(title: original.title, note: original.note)
    }
    public var canSave: Bool {
        guard let draft else { return false }
        return !isComposing && !draftUnavailable && !V2TaskDocumentContent.split(draft.text).title.isEmpty && (draft.isNew || hasChanges)
    }

    public init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        engine = try V2Engine.load(from: V2JSONSnapshotStore(fileURL: directory.appendingPathComponent("v2-snapshot.json")))
        draftURL = directory.appendingPathComponent("task-editor-draft.json")
        if FileManager.default.fileExists(atPath: draftURL.path) {
            do {
                let data = try Data(contentsOf: draftURL)
                let object = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) as? [String: Any]
                if let version = object?["formatVersion"] as? Int {
                    guard (1...2).contains(version) else { throw DraftError.unavailable }
                    let decoder = JSONDecoder()
                    if version == 2 { decoder.dateDecodingStrategy = .secondsSince1970 }
                    let state = try decoder.decode(EditorState.self, from: data)
                    draft = state.draft
                    lastReceiptID = state.lastReceiptID
                } else {
                    // Read drafts written by the first local preview without discarding them.
                    draft = try JSONDecoder().decode(Draft?.self, from: data)
                }
            } catch {
                let backup = draftURL.appendingPathExtension("unreadable-" + UUID().uuidString + ".backup")
                do {
                    try FileManager.default.copyItem(at: draftURL, to: backup)
                    issue = "草稿文件无法读取，已保留原始副本。已保存的任务仍可使用。"
                } catch {
                    draftUnavailable = true
                    issue = "草稿无法读取或备份，已保留原文件。任务仍可查看；请恢复草稿文件后重启再编辑。"
                }
            }
        }
        if let original = draft?.original {
            // Match the snapshot's date precision so a restarted draft does not look spuriously stale.
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .secondsSince1970
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970
            draft?.original = try decoder.decode(V2Task.self, from: encoder.encode(original))
        }
        refresh()
        if let pending = draft, pending.isNew,
           let receipt = engine.snapshot.scheduleReceipts.first(where: { $0.requestID == "workspace-create:" + pending.id }) {
            if receipt.undoneAt != nil {
                // Recreating a deliberately undone task needs a new idempotency key.
                draft?.id = UUID().uuidString
            } else if let created = receipt.changes.compactMap(\.afterTask).first {
                // Use the receipt's original after-version, never silently adopt a newer task as the edit base.
                draft = Draft(id: pending.id, original: created, text: pending.text, isNew: false)
                lastReceiptID = receipt.id
                if tasks.first(where: { $0.id == created.id }) != created {
                    issue = "任务已有更新，恢复的草稿已保留。请核对最新内容后再修改。"
                }
            }
        }
        if let id = lastReceiptID {
            let receipt = engine.snapshot.scheduleReceipts.first { $0.id == id }
            if receipt?.undoneAt != nil, let pending = draft, let original = pending.original,
               pending.text == V2TaskDocumentContent.join(title: original.title, note: original.note),
               receipt?.changes.contains(where: { $0.afterTask == original }) == true {
                // Undo committed but the editor acknowledgement did not: render the durable version.
                draft = tasks.first(where: { $0.id == original.id }).map {
                    Draft(original: $0, text: V2TaskDocumentContent.join(title: $0.title, note: $0.note), isNew: false)
                }
            }
            if receipt == nil || receipt?.undoneAt != nil { lastReceiptID = nil }
        }
        // A crash after the business commit but before draft acknowledgement is safe to recover.
        if let pending = draft, let original = pending.original,
           let current = tasks.first(where: { $0.id == original.id }),
           pending.text == V2TaskDocumentContent.join(title: current.title, note: current.note) {
            draft?.original = current
        }
    }

    @discardableResult public func beginNew() -> Bool {
        if draft?.isNew == true { return true }
        guard saveBeforeLeaving() else { return false }
        return setDraft(Draft(original: nil, text: "", isNew: true))
    }

    @discardableResult public func select(_ id: String) -> Bool {
        guard id != selectedID else { return true }
        guard saveBeforeLeaving() else { return false }
        guard let task = tasks.first(where: { $0.id == id && $0.status != .archived }) else { return false }
        return setDraft(Draft(original: task, text: V2TaskDocumentContent.join(title: task.title, note: task.note), isNew: false))
    }

    /// Called only after native text changes; keeps even an invalid/unfinished document as a draft.
    public func updateText(_ text: String, isComposing: Bool = false) {
        guard var updated = draft else { return }
        self.isComposing = isComposing
        updated.text = text
        draft = updated
        do { try persistDraft(updated); issue = nil }
        catch { issue = "草稿未能保存到本机，请保留窗口并重试。" }
    }

    @discardableResult public func save() -> Bool {
        guard !isComposing else { issue = "请先确认输入法候选词，再保存。"; return false }
        guard !draftUnavailable else { issue = "请先恢复草稿文件，再保存修改。"; return false }
        guard let pending = draft else { return true }
        guard pending.isNew || hasChanges else { return true }
        let fields = V2TaskDocumentContent.split(pending.text)
        guard !fields.title.isEmpty else { issue = "第一段需要写下任务标题，正文可以留空。"; return false }
        do {
            // Recovery may have renewed a create request ID. Make it durable before committing business data.
            try persistDraft(pending)
            let receipt: V2ScheduleReceipt
            if pending.isNew {
                receipt = try engine.applyScheduleProposal(.init(summary: "新增任务", operations: [
                    .init(kind: .createTask, title: fields.title, note: fields.note)
                ]), requestID: "workspace-create:" + pending.id)
            } else if let original = pending.original {
                receipt = try engine.updateTaskClassification(id: original.id, title: fields.title, note: fields.note,
                    classification: .init(kind: original.kind), expectedTask: original)
            } else { return false }
            refresh()
            let id = pending.original?.id ?? receipt.changes.first(where: { $0.afterTask != nil })?.entityID
            guard let current = tasks.first(where: { $0.id == id }) else { return false }
            // Update memory before acknowledging the draft: retry cannot create a duplicate task.
            draft = Draft(id: pending.id, original: current, text: V2TaskDocumentContent.join(title: current.title, note: current.note), isNew: false)
            lastReceiptID = receipt.id
            savedAt = Date()
            try persistDraft(draft)
            issue = nil
            return true
        } catch {
            issue = message(error)
            return false
        }
    }

    /// Explicit cancel/discard; never called implicitly by navigation.
    @discardableResult public func discardDraft() -> Bool {
        refresh()
        let next = selectedID.flatMap { id in tasks.first(where: { $0.id == id }) }.map {
            Draft(original: $0, text: V2TaskDocumentContent.join(title: $0.title, note: $0.note), isNew: false)
        }
        return setDraft(next)
    }

    public func toggleCompletion(_ id: String) {
        guard saveBeforeLeaving(), let current = tasks.first(where: { $0.id == id }) else { return }
        do {
            let receipt = try engine.setTaskCompletion(taskID: id, completed: current.status != .done)
            lastReceiptID = receipt.id
            refresh()
            if selectedID == id, let latest = tasks.first(where: { $0.id == id }) {
                _ = setDraft(Draft(original: latest, text: V2TaskDocumentContent.join(title: latest.title, note: latest.note), isNew: false))
            }
            savedAt = Date()
        } catch { issue = message(error) }
    }

    public func undoLastSave() {
        guard !hasChanges else { issue = "请先保存或放弃当前修改，再撤销上次保存。"; return }
        guard let id = lastReceiptID else { return }
        do {
            _ = try engine.undoScheduleReceipt(id: id)
            lastReceiptID = nil
            let oldID = selectedID
            refresh()
            let latest = tasks.first { $0.id == oldID }
            draft = latest.map { Draft(original: $0, text: V2TaskDocumentContent.join(title: $0.title, note: $0.note), isNew: false) }
            do { try persistDraft(draft); issue = nil }
            catch { issue = "任务已撤销，编辑器状态暂未写入；重启后会恢复最新内容。" }
            savedAt = Date()
        } catch { issue = message(error) }
    }

    public func refresh() { tasks = engine.snapshot.tasks.filter { $0.status != .archived } }

    /// Cross-surface commits may refresh an untouched editor, never a pending edit or IME composition.
    public func refreshExternalChanges() {
        refresh()
        guard let pending = draft, !pending.isNew, !hasChanges, !isComposing,
              let current = tasks.first(where: { $0.id == pending.original?.id }), current != pending.original else { return }
        _ = setDraft(Draft(id: pending.id, original: current,
            text: V2TaskDocumentContent.join(title: current.title, note: current.note), isNew: false))
    }

    public func preserveBeforeClosing() -> Bool {
        do { try persistDraft(draft); return true }
        catch { issue = "草稿尚未保存，请保留窗口并重试。"; return false }
    }

    private func saveBeforeLeaving() -> Bool {
        guard !isComposing else { issue = "请先确认输入法候选词，再切换任务。"; return false }
        if draft?.isNew == true && hasChanges { issue = "新任务草稿已保留，请先创建或取消。"; return false }
        return draft?.isNew == true ? true : save()
    }

    private func setDraft(_ next: Draft?) -> Bool {
        do { try persistDraft(next); draft = next; isComposing = false; issue = nil; return true }
        catch { issue = "无法保存草稿，当前内容已保留，请重试。"; return false }
    }

    private func persistDraft(_ next: Draft?) throws {
        guard !draftUnavailable else { throw DraftError.unavailable }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        try encoder.encode(EditorState(draft: next, lastReceiptID: lastReceiptID)).write(to: draftURL, options: .atomic)
    }

    private func message(_ error: Error) -> String {
        switch error {
        case V2EngineError.blankTitle: "第一段需要写下任务标题，正文可以留空。"
        case V2EngineError.staleScheduleProposal: "任务已有更新，当前草稿已保留。请核对最新内容后再修改。"
        case V2EngineError.taskArchived, V2EngineError.taskNotFound: "任务已不可编辑，当前草稿仍保留在这里。"
        default: "保存未完成，当前内容已保留。请检查本机存储后重试。"
        }
    }
}

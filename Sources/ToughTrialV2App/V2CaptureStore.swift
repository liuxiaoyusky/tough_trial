import SwiftUI
import Combine
import ToughTrialV2Core

@MainActor
final class V2CaptureStore: ObservableObject {
    @Published private(set) var state: V2CaptureState
    @Published var draft = ""
    /// Draft owned by the dedicated ledger sheet. It deliberately stays
    /// separate from the mixed capture draft so cancelling that sheet cannot
    /// leak its text into the general capture composer.
    @Published var ledgerDraft = ""
    @Published private(set) var mediaBlocks: [V2CaptureBlock] = []
    @Published private(set) var editingID: String?
    @Published private(set) var editingRevision: Int?
    @Published private(set) var isOrganizing = false
    @Published var issue: String?
    @Published var message: String?
    @Published var activeBatchID: String?
    @Published private(set) var activeLedgerBatchID: String? = nil
    @Published private(set) var lastFinanceReceipt: V2OperationReceipt?
    let appStore: V2AppStore
    let assets: V2CaptureAssetStore
    private var work: Task<Void, Never>?
    private var moduleObservation: AnyCancellable?
    private var stopGuardID: UUID?
    private var presented = Set<String>()
    private var organizingLedger = false
    private var ledgerSourceID: String?
    private var ledgerSourceRevision: Int?
    private let client: (any V2CaptureClient)?

    init(appStore: V2AppStore, client: (any V2CaptureClient)? = nil, assetDirectory: URL? = nil) {
        self.appStore = appStore; self.client = client; state = appStore.engine.snapshot.capture
        let testing = ProcessInfo.processInfo.environment["TOUGH_TRIAL_UI_TESTING"] == "1"
        assets = V2CaptureAssetStore(directory: assetDirectory ?? (testing
            ? FileManager.default.temporaryDirectory.appendingPathComponent("capture-tests-\(UUID().uuidString)")
            : V2PlatformStorage.assets))
        moduleObservation = NotificationCenter.default.publisher(for: .v2ModulesChanged).sink { [weak self] _ in
            guard let self else { return }
            if !V2PluginStore.shared.enabled("capture")
                || !V2PluginStore.shared.enabled("assistant")
                || (self.organizingLedger && !V2PluginStore.shared.enabled("ledger")) { self.cancel() }
        }
        stopGuardID = V2PluginStore.shared.registerStopGuard(moduleID: "core.capture") { [weak self] in
            guard let self, !self.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !self.mediaBlocks.isEmpty else { return }
            guard self.saveDraft() != nil else { throw V2CaptureError.persistenceFailure }
        }
    }
    deinit {
        let token = stopGuardID
        Task { @MainActor in if let token { V2PluginStore.shared.removeStopGuard(token) } }
    }
    #if DEBUG && os(iOS)
    func seedFinanceAttachmentFixture() {
        guard ProcessInfo.processInfo.environment["TOUGH_TRIAL_UI_TESTING"] == "1", state.finance?.plans.isEmpty != false else { return }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 240, height: 160)).pngData { context in
            UIColor.systemBlue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 240, height: 160))
            ("Receipt 20 USD" as NSString).draw(at: CGPoint(x: 15, y: 50), withAttributes: [.font: UIFont.systemFont(ofSize: 22), .foregroundColor: UIColor.white])
        }
        let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 300, height: 400)).pdfData { context in
            context.beginPage(); ("Subscription receipt" as NSString).draw(at: CGPoint(x: 20, y: 40), withAttributes: [.font: UIFont.systemFont(ofSize: 22)])
        }
        attachFiles([.init(data: image, fileName: "receipt.png", kind: .image), .init(data: pdf, fileName: "invoice.pdf", kind: .document), .init(data: Data("original custom bytes".utf8), fileName: "backup.custom", kind: .document)])
        perform {
            let today = V2CaptureContract.localDate(Date(), timeZone: .current)
            _ = try appStore.engine.saveFinancePlan(.init(title: "ChatGPT Test", kind: .subscription, amount: "20", currency: "USD", dueDate: today, recurrence: .monthly, prompt: "核对订阅账单，保留付款凭证。", link: "https://chatgpt.com/", attachmentIDs: mediaBlocks.compactMap(\.assetID)))
            _ = try appStore.engine.saveBudget(.init(currency: "USD", amount: "100", month: String(today.prefix(7))))
        }
    }
    #endif
    var activeBatch: V2CaptureBatch? { state.batches.first { $0.id == activeBatchID } }
    var activeLedgerBatch: V2CaptureBatch? { state.batches.first { $0.id == activeLedgerBatchID } }
    func startNewLedgerEntry() {
        ledgerDraft = ""
        ledgerSourceID = nil
        ledgerSourceRevision = nil
        activeLedgerBatchID = nil
        issue = nil
        message = nil
    }
    var modelLabel: String { client == nil ? appStore.aiProviderSettings.model : "fixture" }
    /// The dedicated ledger flow only offers AI organization when both the
    /// source-capture and assistant capabilities are active. Manual fields
    /// remain available when either capability is stopped or unavailable.
    var canOrganizeLedger: Bool {
        V2PluginStore.shared.enabled("capture")
            && V2PluginStore.shared.enabled("assistant")
            && V2PluginStore.shared.enabled("ledger")
    }
    func refresh() { state = appStore.engine.snapshot.capture }
    @discardableResult
    func executeFinance(_ command: V2FinanceCommand, confirmedPayment: Bool = false) throws -> V2OperationReceipt {
        guard appStore.canWrite else { throw V2CaptureError.persistenceFailure }
        let context = V2CommandContext(actor: .manual, confirmedPayment: confirmedPayment)
        let dispatcher = V2FinanceCommandDispatcher(engine: appStore.engine, authorize: appStore.engine.moduleRuntime.require)
        let receipt = try dispatcher.execute(command, context: context)
        lastFinanceReceipt = receipt
        V2UsageTrace.shared.record(.init(kind: .financeChanged, source: .manual, operationID: receipt.id,
            moduleID: receipt.domainID, commandID: receipt.commandID, traceID: context.traceID))
        return receipt
    }
    func performFinance(operationID: String, _ action: () throws -> Void) {
        let started = Date()
        perform(action)
        V2UsageTrace.shared.record(.init(kind: issue == nil ? .financeChanged : .financeFailed, operationID: operationID, duration: Date().timeIntervalSince(started)))
    }
    func perform(_ action: () throws -> Void) {
        guard appStore.canWrite else { issue = "本机数据暂时无法保存，请先处理存储问题。"; return }
        issue = nil
        do { try action(); refresh(); appStore.refreshAfterCapture() }
        catch { issue = (error as? LocalizedError)?.errorDescription ?? "操作未完成，原始内容已保留。"; refresh() }
    }
    @discardableResult
    func saveDraft() -> V2CaptureEntry? {
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !mediaBlocks.isEmpty else { return nil }
        var entry: V2CaptureEntry?
        perform {
            let beforeID = editingID
            let beforeRevision = editingRevision
            entry = try appStore.engine.saveCapture(text: draft, id: editingID, expectedRevision: editingRevision, mediaBlocks: mediaBlocks)
            editingID = entry?.id; editingRevision = entry?.revision
            if let entry, beforeID != entry.id || beforeRevision != entry.revision { trace(.sourceSaved, source: entry, traceID: entry.id) }
        }
        return entry
    }
    @discardableResult
    func newEntry() -> Bool {
        if (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !mediaBlocks.isEmpty), saveDraft() == nil { return false }
        draft = ""; mediaBlocks = []; editingID = nil; editingRevision = nil; activeBatchID = nil; message = nil
        return true
    }
    func open(_ entry: V2CaptureEntry) {
        guard !isOrganizing else { return }
        if editingID != entry.id, (!draft.isEmpty || !mediaBlocks.isEmpty), saveDraft() == nil { return }
        draft = entry.blocks.first(where: { $0.kind == .text })?.text ?? ""
        mediaBlocks = entry.blocks.filter { $0.kind != .text }; editingID = entry.id; editingRevision = entry.revision
        activeBatchID = state.batches.last(where: { $0.proposal.captureID == entry.id })?.id
    }
    func captureAudio(_ data: Data) throws {
        guard appStore.canWrite else { throw V2CaptureError.persistenceFailure }
        let asset = try appStore.engine.saveCaptureAsset(data, kind: .audio, fileExtension: "wav", store: assets, inputSource: .speech)
        let blocks = mediaBlocks + [V2CaptureBlock(kind: .audio, assetID: asset.id)]
        let entry = try appStore.engine.saveCapture(text: draft, id: editingID, expectedRevision: editingRevision, mediaBlocks: blocks)
        mediaBlocks = blocks; editingID = entry.id; editingRevision = entry.revision
        refresh(); trace(.sourceSaved, source: entry, traceID: entry.id)
    }
    func attach(data: Data, kind: V2CaptureAsset.Kind, fileExtension: String, recognizedText: String? = nil, replacing blockID: String? = nil) {
        perform {
            let asset = try appStore.engine.saveCaptureAsset(data, kind: kind, fileExtension: fileExtension, store: assets)
            let block = V2CaptureBlock(id: blockID ?? UUID().uuidString, kind: .init(rawValue: kind.rawValue)!, text: recognizedText, assetID: asset.id)
            if let index = mediaBlocks.firstIndex(where: { $0.id == blockID }) { mediaBlocks[index] = block }
            else { mediaBlocks.append(block) }
        }
        _ = saveDraft()
    }
    func attachFiles(_ files: [V2PickedFile]) {
        perform {
            guard V2PluginStore.shared.enabled("attachments"), files.count <= 10, mediaBlocks.count + files.count <= 20 else { throw V2CaptureError.invalidSchema }
            var blocks = mediaBlocks
            for file in files {
                let ext = file.storageExtension
                let asset = try appStore.engine.saveCaptureAsset(file.data, kind: file.kind, fileExtension: ext.isEmpty ? "bin" : ext,
                    store: assets, originalFileName: file.fileName)
                blocks.append(.init(kind: V2CaptureBlock.Kind(rawValue: file.kind.rawValue) ?? .document, assetID: asset.id))
            }
            let entry = try appStore.engine.saveCapture(text: draft, id: editingID, expectedRevision: editingRevision, mediaBlocks: blocks)
            mediaBlocks = blocks; editingID = entry.id; editingRevision = entry.revision
            trace(.sourceSaved, source: entry, traceID: entry.id)
        }
    }
    func recognizedMedia(_ text: String?, captureID: String, sourceRevision: Int, blockID: String, assetID: String?) {
        guard let text, !text.isEmpty else { return }
        perform {
            guard let source = appStore.engine.snapshot.capture.latestEntries.first(where: { $0.id == captureID }),
                  source.revision == sourceRevision,
                  let blockIndex = source.blocks.firstIndex(where: { $0.id == blockID && $0.assetID == assetID }) else { return }
            var blocks = source.blocks
            blocks[blockIndex].text = text
            let entry = try appStore.engine.saveCapture(text: blocks.first(where: { $0.kind == .text })?.text ?? "",
                id: source.id, expectedRevision: source.revision, mediaBlocks: blocks.filter { $0.kind != .text })
            if editingID == source.id {
                editingRevision = entry.revision
                mediaBlocks = entry.blocks.filter { $0.kind != .text }
            }
            trace(.sourceSaved, source: entry, traceID: entry.id)
        }
    }
    func asset(for block: V2CaptureBlock) -> V2CaptureAsset? { state.assets.first { $0.id == block.assetID } }
    @discardableResult
    func importRecords(_ preview: V2ImportPreview, selectedIDs: Set<String>, data: Data) -> [V2CaptureEntry]? {
        if (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !mediaBlocks.isEmpty), saveDraft() == nil { return nil }
        var entries: [V2CaptureEntry]?
        perform {
            let existingIDs = Set(appStore.engine.snapshot.capture.latestEntries.map(\.id))
            entries = try appStore.engine.importExternalRecords(preview, selectedIDs: selectedIDs, originalData: data, assetStore: assets)
            for source in entries ?? [] where !existingIDs.contains(source.id) { trace(.sourceSaved, source: source, traceID: source.id) }
        }
        return entries
    }

    func organizeImported(_ entries: [V2CaptureEntry]) {
        guard V2PluginStore.shared.enabled("assistant"), !isOrganizing, !entries.isEmpty, entries.count <= 10 else { return }
        if (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !mediaBlocks.isEmpty), saveDraft() == nil { return }
        open(entries[0])
        guard editingID == entries[0].id else { return }
        isOrganizing = true; issue = nil
        let ticket: V2ModuleTicket
        do { ticket = try V2PluginStore.shared.ticket(["capture", "assistant"]) }
        catch { isOrganizing = false; issue = error.localizedDescription; return }
        work = Task {
            var completed = 0
            var failures = 0
            defer {
                refresh(); appStore.refreshAfterCapture(); isOrganizing = false; work = nil
                if let lastID = activeBatch?.proposal.captureID, let last = state.latestEntries.first(where: { $0.id == lastID }) { open(last) }
                message = "本轮整理 \(completed) 条，失败 \(failures) 条，未处理 \(entries.count - completed - failures) 条。原文已保留；账单分类仍需确认。"
                if failures > 0 { issue = "有 \(failures) 条未能整理。原文已保存，可在记录列表打开后重试。" }
            }
            for (index, source) in entries.enumerated() {
                if Task.isCancelled || (try? V2PluginStore.shared.validate(ticket)) == nil { break }
                message = "正在整理第 \(index + 1) / \(entries.count) 条"
                let started = Date()
                do {
                    let batch: V2CaptureBatch
                    if let existing = state.batches.last(where: { value in
                        value.proposal.captureID == source.id && value.proposal.sourceRevision == source.revision
                            && !state.receipts.contains { $0.batchID == value.id && $0.status == .undone }
                    }) { batch = existing }
                    else {
                        trace(.extractionStarted, source: source, traceID: source.id)
                        let resolved: any V2CaptureClient
                        if let client { resolved = client }
                        else { resolved = V2OpenAICompatibleCaptureClient(configuration: try appStore.aiProviderSettings.agentConfiguration()) }
                        let proposal = try await resolved.extract(source, categories: state.categories.filter { $0.mergedIntoID == nil })
                        try Task.checkCancellation()
                        try V2PluginStore.shared.validate(ticket)
                        trace(.extractionFinished, source: source, traceID: source.id, duration: Date().timeIntervalSince(started))
                        batch = try appStore.engine.stageCaptureProposal(proposal, model: modelLabel, traceID: source.id)
                        refresh(); trace(.proposalSaved, source: source, traceID: source.id, batch: batch)
                    }
                    activeBatchID = batch.id
                    if !V2ScheduleSettings.requiresConfirmation, !hasEarlierResults(batch) {
                        for item in batch.proposal.items { apply(item, batch: batch) }
                    }
                    // A completed model request is not the same as all targets being saved.
                    let receipts = state.receipts.filter { $0.batchID == batch.id }
                    if receipts.contains(where: { $0.status == .failed || $0.error != nil })
                        || (!V2ScheduleSettings.requiresConfirmation && !hasEarlierResults(batch) && receipts.count < batch.proposal.items.count) { failures += 1 }
                    else { completed += 1 }
                } catch is CancellationError {
                    trace(.cancelled, source: source, traceID: source.id); break
                }
                catch {
                    failures += 1
                    trace(.failed, source: source, traceID: source.id, error: error as? V2CaptureError ?? .providerFailure,
                          duration: Date().timeIntervalSince(started))
                }
            }
        }
    }
    func organize() {
        guard V2PluginStore.shared.enabled("assistant"), !isOrganizing, let source = saveDraft() else { return }
        guard !source.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            message = "附件已保存，暂未识别到文字。可以补充说明后再整理。"; return
        }
        let previous = state.batches.filter { $0.proposal.captureID == source.id }
        if let existing = previous.last(where: { batch in
            batch.proposal.sourceRevision == source.revision && !state.receipts.contains { $0.batchID == batch.id && $0.status == .undone }
        }) { activeBatchID = existing.id; message = "已有整理结果，请查看下方去向；不会重复创建。"; return }
        let traceID = source.id
        isOrganizing = true; issue = nil; message = nil
        trace(.extractionStarted, source: source, traceID: traceID)
        let ticket: V2ModuleTicket
        do { ticket = try V2PluginStore.shared.ticket(["capture", "assistant"]) }
        catch { isOrganizing = false; issue = error.localizedDescription; return }
        work = Task {
            let start = Date()
            defer { isOrganizing = false; work = nil }
            do {
                let resolved: any V2CaptureClient
                if let client { resolved = client }
                else { resolved = V2OpenAICompatibleCaptureClient(configuration: try appStore.aiProviderSettings.agentConfiguration()) }
                let proposal = try await resolved.extract(source, categories: state.categories.filter { $0.mergedIntoID == nil })
                try Task.checkCancellation()
                        try V2PluginStore.shared.validate(ticket)
                trace(.extractionFinished, source: source, traceID: traceID, duration: Date().timeIntervalSince(start))
                let batch = try appStore.engine.stageCaptureProposal(proposal, model: modelLabel, traceID: traceID)
                activeBatchID = batch.id; refresh()
                trace(.proposalSaved, source: source, traceID: traceID, batch: batch)
                if hasEarlierResults(batch) {
                    message = "这是重新整理的预览。核对新旧结果后再替换；账单分类需要重新确认。"
                } else if !V2ScheduleSettings.requiresConfirmation {
                    for item in batch.proposal.items { apply(item, batch: batch) }
                } else { message = "严格确认已开启，请逐项确认保存。" }
            } catch is CancellationError {
                trace(.cancelled, source: source, traceID: traceID); message = "已停止整理，原文仍保留。"
            } catch {
                let code = error as? V2CaptureError ?? .providerFailure
                trace(.failed, source: source, traceID: traceID, error: code, duration: Date().timeIntervalSince(start))
                issue = (error as? LocalizedError)?.errorDescription ?? code.localizedDescription
            }
        }
    }

    /// Organize the dedicated ledger draft into a reviewable proposal. Unlike
    /// the mixed capture flow above, this path never applies any candidate,
    /// regardless of the global schedule confirmation setting.
    func organizeLedger(text: String) {
        guard canOrganizeLedger, !isOrganizing else { return }
        ledgerDraft = text
        var source: V2CaptureEntry?
        perform {
            source = try appStore.engine.saveCapture(
                text: ledgerDraft,
                id: ledgerSourceID,
                expectedRevision: ledgerSourceRevision
            )
            ledgerSourceID = source?.id
            ledgerSourceRevision = source?.revision
        }
        guard let source else { return }
        guard !source.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            message = "请先补充一段记账原文。"
            return
        }
        if let existing = state.batches.last(where: { batch in
            batch.proposal.captureID == source.id && batch.proposal.sourceRevision == source.revision
                && !state.receipts.contains { $0.batchID == batch.id && $0.status == .undone }
        }) {
            activeLedgerBatchID = existing.id
            message = "已有整理结果，请核对后保存；不会重复创建。"
            return
        }

        let traceID = source.id
        isOrganizing = true
        issue = nil
        message = nil
        trace(.extractionStarted, source: source, traceID: traceID)
        let ticket: V2ModuleTicket
        do { ticket = try V2PluginStore.shared.ticket(["capture", "assistant", "ledger"]) }
        catch { isOrganizing = false; issue = error.localizedDescription; return }

        organizingLedger = true
        work = Task {
            let start = Date()
            defer { organizingLedger = false; isOrganizing = false; work = nil }
            do {
                let resolved: any V2CaptureClient
                if let client { resolved = client }
                else { resolved = V2OpenAICompatibleCaptureClient(configuration: try appStore.aiProviderSettings.agentConfiguration()) }
                let proposal = try await resolved.extract(
                    source,
                    categories: state.categories.filter { $0.mergedIntoID == nil }
                )
                try Task.checkCancellation()
                try V2PluginStore.shared.validate(ticket)
                trace(.extractionFinished, source: source, traceID: traceID,
                      duration: Date().timeIntervalSince(start))
                let batch = try appStore.engine.stageCaptureProposal(
                    proposal,
                    model: modelLabel,
                    traceID: traceID
                )
                activeLedgerBatchID = batch.id
                refresh()
                trace(.proposalSaved, source: source, traceID: traceID, batch: batch)
                message = "账单已整理，请逐项核对；保存后才会记入账本。"
            } catch is CancellationError {
                trace(.cancelled, source: source, traceID: traceID)
                message = "已停止整理，原文仍保留。"
            } catch {
                let code = error as? V2CaptureError ?? .providerFailure
                trace(.failed, source: source, traceID: traceID, error: code,
                      duration: Date().timeIntervalSince(start))
                issue = (error as? LocalizedError)?.errorDescription ?? code.localizedDescription
            }
        }
    }
    func earlierReceipts(_ batch: V2CaptureBatch) -> [V2CaptureReceipt] {
        let ids = Set(state.batches.filter { $0.id != batch.id && $0.proposal.captureID == batch.proposal.captureID }.map(\.id))
        return state.receipts.filter { ids.contains($0.batchID) && $0.targetID != nil && ($0.status == .applied || $0.status == .needsConfirmation) }
    }
    func hasEarlierResults(_ batch: V2CaptureBatch) -> Bool { !earlierReceipts(batch).isEmpty }
    func replaceResults(_ batch: V2CaptureBatch) {
        perform {
            for receipt in earlierReceipts(batch) {
                if let entry = receipt.recallAfter { try appStore.validateCaptureRecallDate(entry.date) }
            }
            for item in batch.proposal.items where item.kind == .recall {
                if let day = item.payload.localDate, let date = V2CaptureContract.date(day, timeZone: .current) { try appStore.validateCaptureRecallDate(date) }
            }
            let oldScheduleIDs = Set(earlierReceipts(batch).compactMap(\.scheduleReceiptID))
            try appStore.engine.replaceCaptureResults(batchID: batch.id, confirmed: true)
            let newScheduleIDs = Set(appStore.engine.snapshot.capture.receipts.filter { $0.batchID == batch.id }.compactMap(\.scheduleReceiptID))
            for receipt in appStore.engine.snapshot.scheduleReceipts where oldScheduleIDs.contains(receipt.id) || newScheduleIDs.contains(receipt.id) {
                appStore.refreshScheduleReminders(receipt, at: Date())
            }
            appStore.highlightedScheduleIDs = Set(appStore.engine.snapshot.scheduleReceipts.filter { newScheduleIDs.contains($0.id) }.flatMap { $0.changes.map(\.entityID) })
            refresh()
            for receipt in state.receipts where receipt.batchID == batch.id { trace(.itemCommitted, batch: batch, receipt: receipt) }
            message = "已替换为新结果，原文历史仍保留。"
        }
    }
    func cancel() { work?.cancel() }
    func cancelAndWait() async {
        let pending = work
        pending?.cancel()
        await pending?.value
    }
    func receipt(for item: V2CaptureCandidate, batch: V2CaptureBatch) -> V2CaptureReceipt? {
        state.receipts.last { $0.batchID == batch.id && $0.candidateID == item.id }
    }
    func apply(_ item: V2CaptureCandidate, batch: V2CaptureBatch) {
        let module = item.kind == .ledger ? "ledger" : item.kind == .task ? "tasks" : item.kind == .recall ? "recall" : "capture"
        guard V2PluginStore.shared.enabled(module) else { issue = "目标功能已停用，提取结果已保留，开启后可继续保存。"; return }
        perform {
            if item.kind == .recall, let day = item.payload.localDate,
               let source = state.entries.first(where: { $0.id == batch.proposal.captureID && $0.revision == batch.proposal.sourceRevision }),
               let date = V2CaptureContract.date(day, timeZone: TimeZone(identifier: source.timeZoneIdentifier) ?? .current) {
                try appStore.validateCaptureRecallDate(date)
            }
            let receipt = try appStore.engine.applyCaptureCandidate(batchID: batch.id, candidateID: item.id)
            if let id = receipt.scheduleReceiptID, let schedule = appStore.engine.snapshot.scheduleReceipts.first(where: { $0.id == id }) {
                appStore.highlightedScheduleIDs = Set(schedule.changes.map(\.entityID))
                appStore.refreshScheduleReminders(schedule, at: Date())
            }
            trace(receipt.error == nil ? .itemCommitted : .validationFailed, batch: batch, item: item, receipt: receipt, error: receipt.error)
        }
    }
    func reviseLedgerCandidate(_ item: V2CaptureCandidate, batch: V2CaptureBatch, draft: V2LedgerCandidateDraft) {
        perform {
            _ = try appStore.engine.reviseLedgerCandidate(
                batchID: batch.id,
                candidateID: item.candidateID,
                sourceRevision: batch.proposal.sourceRevision,
                draft: draft
            )
            refresh()
            message = "已保留人工修正，请继续核对后保存。"
        }
    }
    func confirmLedgerCandidate(_ item: V2CaptureCandidate, batch: V2CaptureBatch, draft: V2LedgerCandidateDraft) {
        guard V2PluginStore.shared.enabled("ledger") else {
            issue = "记账功能已停用，整理结果已保留，开启后可继续保存。"
            return
        }
        perform {
            let receipt = try appStore.engine.confirmLedgerCandidate(
                batchID: batch.id,
                candidateID: item.candidateID,
                sourceRevision: batch.proposal.sourceRevision,
                draft: draft
            )
            trace(receipt.error == nil ? .itemCommitted : .validationFailed,
                  batch: batch, item: item, receipt: receipt, error: receipt.error)
            message = receipt.error == nil ? "账单已保存，分类仍需你确认。" : "账单还未保存，请补充后重试。"
        }
    }
    func reject(_ item: V2CaptureCandidate, batch: V2CaptureBatch) {
        perform { try appStore.engine.rejectCaptureCandidate(batchID: batch.id, candidateID: item.id) }
    }
    func undo(_ receipt: V2CaptureReceipt) {
        perform {
            if let recall = receipt.recallAfter { try appStore.validateCaptureRecallDate(recall.date) }
            try appStore.engine.undoCaptureReceipt(id: receipt.id)
            if let id = receipt.scheduleReceiptID, let schedule = appStore.engine.snapshot.scheduleReceipts.first(where: { $0.id == id }) {
                appStore.refreshScheduleReminders(schedule, at: Date())
            }
            if let batch = state.batches.first(where: { $0.id == receipt.batchID }) { trace(.undone, batch: batch, receipt: receipt) }
        }
    }
    func saveQuickTask(title: String, note: String) {
        perform {
            try V2PluginStore.shared.require(["tasks"])
            if !V2PluginStore.shared.enabled("capture") {
                let receipt = try appStore.engine.applyScheduleProposal(.init(summary: "新增待办", operations: [
                    .init(kind: .createTask, localID: "task", title: title, note: note)
                ]), requestID: UUID().uuidString)
                appStore.highlightedScheduleIDs = Set(receipt.changes.map(\.entityID))
                V2UsageTrace.shared.record(.init(kind: .commandApplied, source: .manual, operationID: receipt.id,
                    moduleID: "core.tasks", commandID: "core.tasks.create"))
                return
            }
            let source = try appStore.engine.saveCapture(text: "待办：\(title)" + (note.isEmpty ? "" : "\n备注：\(note)"))
            let item = V2CaptureCandidate(candidateID: "quick-task", kind: .task,
                evidence: [.init(blockID: source.blocks[0].id, quote: source.text)],
                payload: .init(text: title, operations: [.init(kind: .createTask, localID: "task", title: title, note: note)]))
            let batch = try appStore.engine.stageCaptureProposal(.init(captureID: source.id, sourceRevision: source.revision, items: [item]), model: "manual")
            let receipt = try appStore.engine.applyCaptureCandidate(batchID: batch.id, candidateID: item.id)
            if let error = receipt.error { throw error }
            activeBatchID = batch.id
            if let id = receipt.scheduleReceiptID, let schedule = appStore.engine.snapshot.scheduleReceipts.first(where: { $0.id == id }) {
                appStore.highlightedScheduleIDs = Set(schedule.changes.map(\.entityID))
            }
            refresh(); trace(.itemCommitted, batch: batch, item: item, receipt: receipt)
        }
    }
    func saveManualLedger(amount: String, text: String, currency: String, direction: V2LedgerDirection,
                          localDate: String? = nil) {
        var saved = false
        perform {
            let entry = try appStore.engine.createManualLedgerEntry(amount: amount, currency: currency,
                direction: direction, text: text,
                localDate: localDate)
            V2UsageTrace.shared.record(.init(kind: .commandApplied, source: .manual, operationID: entry.receiptID,
                moduleID: "core.ledger", commandID: "core.ledger.createPending"))
            saved = true
        }
        if saved { startNewLedgerEntry() }
    }
    func createCategory(name: String, parentID: String?) {
        perform {
            let category = try appStore.engine.createLedgerCategory(name: name, parentID: parentID, confirmed: true)
            V2UsageTrace.shared.record(.init(kind: .manualEdit, source: .manual, operationID: category.id))
        }
    }
    func mergeCategories(sourceID: String, targetID: String, revision: Int) {
        perform {
            let receipt = try appStore.engine.mergeLedgerCategories(sourceID: sourceID, targetID: targetID, expectedTaxonomyRevision: revision, confirmed: true)
            V2UsageTrace.shared.record(.init(kind: .categoryMerged, source: .manual, operationID: receipt.id))
            for row in receipt.afterLedger {
                if let result = state.receipts.first(where: { $0.id == row.receiptID }), let batch = state.batches.first(where: { $0.id == result.batchID }) {
                    trace(.categoryMerged, batch: batch, receipt: result)
                }
            }
        }
    }
    func undoCategory(_ id: String) {
        perform {
            try appStore.engine.undoCategoryReceipt(id: id)
            V2UsageTrace.shared.record(.init(kind: .categoryUndone, source: .manual, operationID: id))
        }
    }
    func confirmCategory(_ entry: V2LedgerEntry, name: String) {
        perform {
            try appStore.engine.confirmLedgerCategory(ledgerID: entry.id, categoryName: name, expectedRevision: entry.revision, confirmed: true)
            if let receipt = state.receipts.first(where: { $0.id == entry.receiptID }), let batch = state.batches.first(where: { $0.id == receipt.batchID }) {
                trace(.categoryConfirmed, batch: batch, receipt: receipt, duration: Date().timeIntervalSince(receipt.createdAt))
            }
        }
    }
    func presented(_ item: V2CaptureCandidate, batch: V2CaptureBatch) {
        guard let receipt = receipt(for: item, batch: batch), presented.insert(receipt.id + receipt.status.rawValue).inserted else { return }
        trace(.itemPresented, batch: batch, item: item, receipt: receipt)
    }
    func trace(_ stage: V2CaptureTraceContext.Stage, batch: V2CaptureBatch, item: V2CaptureCandidate? = nil,
               receipt: V2CaptureReceipt? = nil, error: V2CaptureError? = nil, duration: TimeInterval? = nil) {
        guard let source = state.entries.first(where: { $0.id == batch.proposal.captureID && $0.revision == batch.proposal.sourceRevision }) else { return }
        trace(stage, source: source, traceID: batch.traceID, batch: batch, item: item, receipt: receipt, error: error, duration: duration)
    }
    private func trace(_ stage: V2CaptureTraceContext.Stage, source: V2CaptureEntry, traceID: String,
                       batch: V2CaptureBatch? = nil, item: V2CaptureCandidate? = nil, receipt: V2CaptureReceipt? = nil,
                       error: V2CaptureError? = nil, duration: TimeInterval? = nil) {
        V2UsageTrace.shared.record(.init(kind: .captureStage, duration: duration, capture: .init(traceID: traceID,
            captureID: source.id, sourceRevision: source.revision, batchID: batch?.id, candidateID: item?.id,
            receiptID: receipt?.id, model: batch?.model ?? modelLabel, taxonomyRevision: state.taxonomyRevision, stage: stage, errorCode: error)))
    }
}

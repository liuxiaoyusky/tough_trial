import Foundation
import XCTest
@testable import ToughTrialV2Core

final class V2CaptureLifecycleTests: XCTestCase {
    func testSnapshotPersistsCaptureAcrossRestartAndRetriesIdempotently() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = V2JSONSnapshotStore(fileURL: directory.appendingPathComponent("snapshot.json"))
        let date = fixedDate
        // Use the persisted engine after constructing it from the initial snapshot;
        // this keeps the test independent of any process-global store state.
        let persistedEngine = V2Engine(snapshot: .empty, store: store)
        let source = try persistedEngine.saveCapture(text: "今天午餐实际花了38元", at: date, timeZone: shanghai)
        let candidate = ledgerCandidate(
            id: "ledger-1",
            source: source,
            text: "今天午餐实际花了38元",
            amount: "38",
            currency: "CNY",
            direction: .expense
        )
        let proposal = V2CaptureProposal(captureID: source.id, sourceRevision: source.revision, items: [candidate])
        let firstBatch = try persistedEngine.stageCaptureProposal(proposal, model: "fixture", traceID: "trace-1", at: date)
        let sameBatch = try persistedEngine.stageCaptureProposal(proposal, model: "another-model", traceID: "trace-2", at: date)
        XCTAssertEqual(sameBatch.id, firstBatch.id)

        let firstReceipt = try persistedEngine.applyCaptureCandidate(
            batchID: firstBatch.id,
            candidateID: candidate.candidateID,
            at: date
        )
        let restarted = try V2Engine.load(from: store)
        XCTAssertEqual(restarted.snapshot.capture, persistedEngine.snapshot.capture)

        let retriedReceipt = try restarted.applyCaptureCandidate(
            batchID: firstBatch.id,
            candidateID: candidate.candidateID,
            at: date.addingTimeInterval(60)
        )
        XCTAssertEqual(retriedReceipt, firstReceipt)
        XCTAssertEqual(restarted.snapshot.capture.ledger.count, 1)
        XCTAssertEqual(restarted.snapshot.capture.receipts.count, 1)

        let legacyURL = directory.appendingPathComponent("legacy.json")
        let legacyJSON = """
        {
          "schemaVersion": 1,
          "taskContexts": [],
          "tasks": [],
          "planDrafts": [],
          "planItems": [],
          "executionSegments": [],
          "recallEntries": [],
          "dreamingSuggestions": []
        }
        """
        try Data(legacyJSON.utf8).write(to: legacyURL, options: .atomic)
        let legacyEngine = try V2Engine.load(from: V2JSONSnapshotStore(fileURL: legacyURL))
        XCTAssertEqual(legacyEngine.snapshot.capture, V2CaptureState())
    }

    func testMixedCandidatesPersistOnlyValidLedgerAndKeepIncompleteItemsInformational() throws {
        let engine = V2Engine()
        let source = try engine.saveCapture(
            text: "午餐已支付38元；某件商品只是价格讨论；明天写稿",
            at: fixedDate,
            timeZone: shanghai
        )
        let valid = ledgerCandidate(
            id: "valid",
            source: source,
            text: "午餐已支付38元",
            amount: "38",
            currency: "CNY",
            direction: .expense
        )
        let missingAmount = ledgerCandidate(
            id: "missing-amount",
            source: source,
            text: "某件商品只是价格讨论",
            amount: nil,
            currency: "CNY",
            direction: .expense
        )
        let missingEvidence = V2CaptureCandidate(
            candidateID: "missing-evidence",
            kind: .other,
            evidence: [],
            payload: .init(text: "明天写稿")
        )
        let proposal = V2CaptureProposal(
            captureID: source.id,
            sourceRevision: source.revision,
            items: [valid, missingAmount, missingEvidence]
        )
        let batch = try engine.stageCaptureProposal(proposal, model: "fixture", at: fixedDate)

        let validReceipt = try engine.applyCaptureCandidate(batchID: batch.id, candidateID: "valid", at: fixedDate)
        let amountReceipt = try engine.applyCaptureCandidate(batchID: batch.id, candidateID: "missing-amount", at: fixedDate)
        let evidenceReceipt = try engine.applyCaptureCandidate(batchID: batch.id, candidateID: "missing-evidence", at: fixedDate)

        XCTAssertEqual(validReceipt.status, .needsConfirmation)
        XCTAssertEqual(amountReceipt.status, .needsInformation)
        XCTAssertEqual(amountReceipt.error, .invalidAmount)
        XCTAssertEqual(evidenceReceipt.status, .needsInformation)
        XCTAssertEqual(evidenceReceipt.error, .missingEvidence)
        XCTAssertEqual(engine.snapshot.capture.ledger.count, 1)
        XCTAssertEqual(engine.snapshot.capture.ledger[0].amount, "38")
        XCTAssertEqual(engine.snapshot.capture.ledger[0].categoryID, "others")
        XCTAssertEqual(engine.snapshot.capture.totals(direction: .expense), ["CNY": Decimal(38)])
        XCTAssertTrue(engine.snapshot.capture.notes.isEmpty)
    }

    func testSameBatchTaskUsesExistingTaskAndPlanItemQueriesAndUndoRemovesBoth() throws {
        let engine = V2Engine()
        let source = try engine.saveCapture(text: "明天上午写完项目稿", at: fixedDate, timeZone: shanghai)
        let candidate = V2CaptureCandidate(
            candidateID: "task-1",
            kind: .task,
            evidence: [.init(blockID: source.blocks[0].id, quote: "明天上午写完项目稿")],
            payload: .init(
                text: "明天上午写完项目稿",
                operations: [
                    .init(kind: .createTask, localID: "new-task", title: "写完项目稿", note: "明天上午完成"),
                    .init(kind: .scheduleTask, targetID: "new-task", day: "2026-09-10", startMinute: 540, durationMinutes: 90),
                ]
            )
        )
        let batch = try engine.stageCaptureProposal(
            .init(captureID: source.id, sourceRevision: source.revision, items: [candidate]),
            model: "fixture",
            at: fixedDate
        )

        let receipt = try engine.applyCaptureCandidate(batchID: batch.id, candidateID: candidate.candidateID, at: fixedDate)
        XCTAssertEqual(receipt.status, .applied)
        XCTAssertEqual(engine.snapshot.tasks.count, 1)
        XCTAssertEqual(engine.snapshot.planItems.count, 1)
        XCTAssertEqual(engine.taskTree(contextID: nil).map(\.task.title), ["写完项目稿"])
        XCTAssertEqual(engine.snapshot.planItems.first?.taskID, receipt.targetID)
        XCTAssertEqual(engine.snapshot.planItems.first?.title, "写完项目稿")

        try engine.undoCaptureReceipt(id: receipt.id, at: fixedDate.addingTimeInterval(60))
        XCTAssertTrue(engine.snapshot.tasks.isEmpty)
        XCTAssertTrue(engine.snapshot.planItems.isEmpty)
        XCTAssertEqual(engine.snapshot.capture.receipts.first?.status, .undone)
    }

    func testCategoryMergeWithNoRecordsKeepsReceiptAndAllowsNoRecordTotalsChange() throws {
        let engine = V2Engine()
        let source = try engine.createLedgerCategory(name: "旅行", confirmed: true)
        let target = try engine.createLedgerCategory(name: "休闲", confirmed: true)
        let beforeTaxonomy = engine.snapshot.capture.taxonomyRevision

        let receipt = try engine.mergeLedgerCategories(
            sourceID: source.id,
            targetID: target.id,
            expectedTaxonomyRevision: beforeTaxonomy,
            confirmed: true
        )

        XCTAssertTrue(receipt.beforeLedger.isEmpty)
        XCTAssertTrue(receipt.afterLedger.isEmpty)
        XCTAssertEqual(engine.snapshot.capture.ledger, [])
        XCTAssertEqual(engine.snapshot.capture.categories.first(where: { $0.id == source.id })?.mergedIntoID, target.id)
        XCTAssertEqual(engine.snapshot.capture.categoryReceipts.last?.id, receipt.id)
    }

    func testCategoryMergePreservesPerCurrencyTotalsAndLaterEditBlocksUndo() throws {
        let engine = V2Engine()
        let sourceLedger = try addConfirmedLedger(
            to: engine,
            text: "旅行支出10元",
            amount: "10",
            currency: "CNY",
            categoryName: "旅行",
            date: fixedDate
        )
        let target = try engine.createLedgerCategory(name: "休闲", confirmed: true)
        _ = try addConfirmedLedger(
            to: engine,
            text: "旅行支出5美元",
            amount: "5",
            currency: "USD",
            categoryName: "旅行",
            date: fixedDate.addingTimeInterval(1)
        )
        let beforeTotals = engine.snapshot.capture.totals(direction: .expense)
        let merge = try engine.mergeLedgerCategories(
            sourceID: try XCTUnwrap(engine.snapshot.capture.categories.first(where: { $0.name == "旅行" })).id,
            targetID: target.id,
            expectedTaxonomyRevision: engine.snapshot.capture.taxonomyRevision,
            confirmed: true
        )

        XCTAssertEqual(engine.snapshot.capture.totals(direction: .expense), beforeTotals)
        XCTAssertEqual(engine.snapshot.capture.ledger.map(\.categoryID), [target.id, target.id])
        XCTAssertTrue(merge.beforeLedger.contains(where: { $0.id == sourceLedger.id }))

        try engine.confirmLedgerCategory(
            ledgerID: sourceLedger.id,
            categoryName: "交通",
            expectedRevision: sourceLedger.revision + 1,
            confirmed: true
        )
        do {
            try engine.undoCategoryReceipt(id: merge.id)
            XCTFail("a later category edit must block merge undo")
        } catch let error as V2CaptureError {
            XCTAssertEqual(error, .staleTarget)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        XCTAssertEqual(engine.snapshot.capture.ledger.first(where: { $0.id == sourceLedger.id })?.categoryID,
                       engine.snapshot.capture.categories.first(where: { $0.name == "交通" })?.id)
    }

    func testCategoryCycleAndUnconfirmedOperationsAreRejected() throws {
        let engine = V2Engine()
        let parent = try engine.createLedgerCategory(name: "工作", confirmed: true)
        let child = try engine.createLedgerCategory(name: "差旅", parentID: parent.id, confirmed: true)
        let before = engine.snapshot.capture

        do {
            _ = try engine.mergeLedgerCategories(
                sourceID: parent.id,
                targetID: child.id,
                expectedTaxonomyRevision: before.taxonomyRevision,
                confirmed: true
            )
            XCTFail("merging a parent into its child must be rejected")
        } catch let error as V2CaptureError {
            XCTAssertEqual(error, .invalidReference)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        XCTAssertEqual(engine.snapshot.capture, before)

        do {
            _ = try engine.mergeLedgerCategories(
                sourceID: parent.id,
                targetID: "others",
                expectedTaxonomyRevision: before.taxonomyRevision,
                confirmed: false
            )
            XCTFail("unconfirmed category merge must be rejected")
        } catch let error as V2CaptureError {
            XCTAssertEqual(error, .confirmationRequired)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        XCTAssertEqual(engine.snapshot.capture, before)
    }

    @MainActor
    func testDisablingUsageTraceDoesNotDropBusinessReceipt() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let traceURL = directory.appendingPathComponent("usage-trace.json")
        let trace = V2UsageTraceStore(fileURL: traceURL, isEnabled: false)
        try trace.record(.init(kind: .captureStage, source: .manual), now: fixedDate)
        XCTAssertTrue(trace.events.isEmpty)

        let snapshotStore = V2JSONSnapshotStore(fileURL: directory.appendingPathComponent("snapshot.json"))
        let engine = V2Engine(snapshot: .empty, store: snapshotStore)
        let source = try engine.saveCapture(text: "午餐实际花了38元", at: fixedDate, timeZone: shanghai)
        let candidate = ledgerCandidate(
            id: "ledger-1",
            source: source,
            text: "午餐实际花了38元",
            amount: "38",
            currency: "CNY",
            direction: .expense
        )
        let batch = try engine.stageCaptureProposal(
            .init(captureID: source.id, sourceRevision: source.revision, items: [candidate]),
            model: "fixture",
            at: fixedDate
        )
        _ = try engine.applyCaptureCandidate(batchID: batch.id, candidateID: candidate.candidateID, at: fixedDate)

        let restarted = try V2Engine.load(from: snapshotStore)
        XCTAssertEqual(restarted.snapshot.capture.receipts.count, 1)
        XCTAssertEqual(restarted.snapshot.capture.ledger.count, 1)
        XCTAssertTrue(trace.events.isEmpty)
    }

    private let fixedDate = Date(timeIntervalSince1970: 1_789_307_200)
    private let shanghai = TimeZone(identifier: "Asia/Shanghai")!

    private func ledgerCandidate(
        id: String,
        source: V2CaptureEntry,
        text: String,
        amount: String?,
        currency: String,
        direction: V2LedgerDirection
    ) -> V2CaptureCandidate {
        V2CaptureCandidate(
            candidateID: id,
            kind: .ledger,
            evidence: [.init(blockID: source.blocks[0].id, quote: text)],
            payload: .init(
                text: text,
                amount: amount,
                currency: currency,
                direction: direction,
                localDate: "2026-09-09"
            )
        )
    }

    private func addConfirmedLedger(
        to engine: V2Engine,
        text: String,
        amount: String,
        currency: String,
        categoryName: String,
        date: Date
    ) throws -> V2LedgerEntry {
        let source = try engine.saveCapture(text: text, at: date, timeZone: shanghai)
        let candidate = ledgerCandidate(
            id: UUID().uuidString,
            source: source,
            text: text,
            amount: amount,
            currency: currency,
            direction: .expense
        )
        let batch = try engine.stageCaptureProposal(
            .init(captureID: source.id, sourceRevision: source.revision, items: [candidate]),
            model: "fixture",
            at: date
        )
        let receipt = try engine.applyCaptureCandidate(batchID: batch.id, candidateID: candidate.candidateID, at: date)
        let ledgerID = try XCTUnwrap(receipt.targetID)
        try engine.confirmLedgerCategory(
            ledgerID: ledgerID,
            categoryName: categoryName,
            expectedRevision: 1,
            confirmed: true
        )
        return try XCTUnwrap(engine.snapshot.capture.ledger.first(where: { $0.id == ledgerID }))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tough-trial-capture-lifecycle-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

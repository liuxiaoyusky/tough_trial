import Foundation
import XCTest
@testable import ToughTrialV2Core

final class V2LedgerConfirmationBoundaryTests: XCTestCase {
    private func staged(_ engine: V2Engine, count: Int = 1) throws -> (V2CaptureEntry, V2CaptureBatch) {
        let source = try engine.saveCapture(text: "午饭和咖啡，共两笔", at: Date(timeIntervalSince1970: 1_800_000_000), timeZone: TimeZone(identifier: "Asia/Hong_Kong")!)
        let items = (0..<count).map { index in
            V2CaptureCandidate(candidateID: "bill-\(index)", kind: .ledger,
                evidence: [.init(blockID: source.blocks[0].id, quote: source.text)],
                payload: .init(text: "第\(index)笔", amount: "35", currency: "CNY", direction: .expense))
        }
        return (source, try engine.stageCaptureProposal(.init(captureID: source.id,
            sourceRevision: source.revision, items: items), model: "boundary-fixture"))
    }

    private var draft: V2LedgerCandidateDraft {
        .init(text: "午饭", amount: "35", currency: "CNY", direction: .expense)
    }

    func testReorganizedSourceCannotCreateTheSameBillAgain() throws {
        let engine = V2Engine()
        let (source, first) = try staged(engine)
        _ = try engine.confirmLedgerCandidate(batchID: first.id, candidateID: "bill-0",
            sourceRevision: source.revision, draft: draft)
        var proposal = first.proposal
        proposal.items[0].candidateID = "reorganized-bill"
        let second = try engine.stageCaptureProposal(proposal, model: "another-analysis")
        let before = engine.snapshot
        XCTAssertThrowsError(try engine.confirmLedgerCandidate(batchID: second.id,
            candidateID: "reorganized-bill", sourceRevision: source.revision, draft: draft))
        XCTAssertEqual(engine.snapshot, before)
    }

    func testRejectedCandidateCannotBeSavedFromAnOldReview() throws {
        let engine = V2Engine()
        let (source, batch) = try staged(engine)
        try engine.rejectCaptureCandidate(batchID: batch.id, candidateID: "bill-0")
        let before = engine.snapshot
        do {
            let result = try engine.confirmLedgerCandidate(batchID: batch.id,
                candidateID: "bill-0", sourceRevision: source.revision, draft: draft)
            XCTAssertEqual(result.status, .rejected)
        } catch { /* A stale review may also be rejected with a domain error. */ }
        XCTAssertEqual(engine.snapshot, before)
    }

    func testIncompleteOrInvalidValuesNeverCreatePartialCorrectionsOrLedger() throws {
        let engine = V2Engine()
        let (source, batch) = try staged(engine)
        let invalid: [V2LedgerCandidateDraft] = [
            .init(text: "午饭", currency: "CNY", direction: .expense),
            .init(text: "午饭", amount: "35", direction: .expense),
            .init(text: "午饭", amount: "35", currency: "CNY"),
            .init(text: "午饭", amount: "35", currency: "ZZZ", direction: .expense),
            .init(text: "午饭", amount: "35", currency: "CNY", direction: .expense, localDate: "2026-02-30")
        ]
        for value in invalid {
            let before = engine.snapshot
            XCTAssertThrowsError(try engine.confirmLedgerCandidate(batchID: batch.id,
                candidateID: "bill-0", sourceRevision: source.revision, draft: value))
            XCTAssertEqual(engine.snapshot, before)
        }
    }

    func testSourceRevisionChangeRejectsOldReviewWithoutMutation() throws {
        let engine = V2Engine()
        let (source, batch) = try staged(engine)
        _ = try engine.saveCapture(text: "修改后的原话", id: source.id, expectedRevision: source.revision)
        let before = engine.snapshot
        XCTAssertThrowsError(try engine.confirmLedgerCandidate(batchID: batch.id,
            candidateID: "bill-0", sourceRevision: source.revision, draft: draft))
        XCTAssertEqual(engine.snapshot, before)
    }

    func testMultiBillConfirmationPreservesOriginalsAndCanUndoOneAfterReload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = V2JSONSnapshotStore(fileURL: directory.appendingPathComponent("snapshot.json"))
        let engine = V2Engine(store: disk)
        let (source, batch) = try staged(engine, count: 2)
        let first = try engine.confirmLedgerCandidate(batchID: batch.id, candidateID: "bill-0",
            sourceRevision: source.revision, draft: draft)
        _ = try engine.confirmLedgerCandidate(batchID: batch.id, candidateID: "bill-1",
            sourceRevision: source.revision,
            draft: .init(text: "咖啡", amount: "20", currency: "HKD", direction: .expense))
        let reopened = try V2Engine.load(from: disk)
        XCTAssertEqual(reopened.snapshot.capture.batches.first?.proposal, batch.proposal)
        XCTAssertEqual(reopened.snapshot.capture.entries, [source])
        XCTAssertEqual(reopened.snapshot.capture.ledger.count, 2)
        XCTAssertTrue(reopened.snapshot.capture.ledger.allSatisfy { $0.localDate == nil && $0.categoryID == "others" })
        try reopened.undoCaptureReceipt(id: first.id)
        let afterUndo = try V2Engine.load(from: disk)
        XCTAssertEqual(afterUndo.snapshot.capture.ledger.map(\.text), ["咖啡"])
        XCTAssertEqual(afterUndo.snapshot.capture.totals(direction: .expense)["HKD"], Decimal(20))
        XCTAssertNil(afterUndo.snapshot.capture.totals(direction: .expense)["CNY"])
    }

    func testFailedDiskWriteDoesNotLeaveCorrectionsOrBillInMemory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let engine = V2Engine()
        let (source, batch) = try staged(engine)
        let broken = V2Engine(snapshot: engine.snapshot, store: V2JSONSnapshotStore(fileURL: directory))
        let before = broken.snapshot
        XCTAssertThrowsError(try broken.confirmLedgerCandidate(batchID: batch.id,
            candidateID: "bill-0", sourceRevision: source.revision, draft: draft))
        XCTAssertEqual(broken.snapshot, before)
    }
    func testConfirmationAfterFailedApplyReusesPendingReceipt() throws {
        let engine = V2Engine()
        let source = try engine.saveCapture(text: "午饭35，币种待确认")
        let candidate = V2CaptureCandidate(candidateID: "pending", kind: .ledger,
            evidence: [.init(blockID: source.blocks[0].id, quote: source.text)],
            payload: .init(text: "午饭", amount: "35", direction: .expense))
        let batch = try engine.stageCaptureProposal(.init(captureID: source.id,
            sourceRevision: source.revision, items: [candidate]), model: "boundary-fixture")
        let pending = try engine.applyCaptureCandidate(batchID: batch.id, candidateID: candidate.id)
        XCTAssertEqual(pending.status, .needsInformation)
        let saved = try engine.confirmLedgerCandidate(batchID: batch.id, candidateID: candidate.id,
            sourceRevision: source.revision, draft: draft)
        XCTAssertEqual(saved.id, pending.id)
        XCTAssertEqual(engine.snapshot.capture.receipts.count, 1)
        XCTAssertFalse(engine.snapshot.capture.receipts.contains { $0.status == .needsInformation })
        XCTAssertEqual(engine.snapshot.capture.batches.first?.proposal, batch.proposal)
        try engine.undoCaptureReceipt(id: saved.id)
        XCTAssertTrue(engine.snapshot.capture.ledger.isEmpty)
    }

}

import XCTest
@testable import ToughTrialV2Core

final class V2CaptureTests: XCTestCase {
    func testLedgerNeedsCategoryConfirmationAndRetryIsIdempotent() throws {
        let engine = V2Engine()
        let entry = try engine.saveCapture(text: "午餐花了38元人民币", at: Date())
        let item = V2CaptureCandidate(candidateID: "one", kind: .ledger,
            evidence: [.init(blockID: entry.blocks[0].id, quote: entry.blocks[0].text!)],
            payload: .init(text: "午餐", amount: "38", currency: "CNY", direction: .expense, categoryName: "餐饮"))
        let batch = try engine.stageCaptureProposal(.init(captureID: entry.id, sourceRevision: 1, items: [item]), model: "fixture")
        let result = try engine.applyCaptureCandidate(batchID: batch.id, candidateID: "one")
        XCTAssertEqual(result.status, .needsConfirmation)
        XCTAssertEqual(engine.snapshot.capture.ledger.count, 1)
        XCTAssertEqual(engine.snapshot.capture.ledger[0].categoryID, "others")
        _ = try engine.applyCaptureCandidate(batchID: batch.id, candidateID: "one")
        XCTAssertEqual(engine.snapshot.capture.ledger.count, 1)
        XCTAssertThrowsError(try engine.confirmLedgerCategory(ledgerID: engine.snapshot.capture.ledger[0].id,
            categoryName: "餐饮", expectedRevision: 1, confirmed: false))
        try engine.confirmLedgerCategory(ledgerID: engine.snapshot.capture.ledger[0].id,
            categoryName: "餐饮", expectedRevision: 1, confirmed: true)
        XCTAssertNotEqual(engine.snapshot.capture.ledger[0].categoryID, "others")
    }

    func testRecallAppendPreservesTextHandwritingAndUndoRefusesLaterEdit() throws {
        let engine = V2Engine()
        let date = Date()
        _ = try engine.saveRecallEntry(date: date, text: "已有正文", hasHandwriting: true)
        let entry = try engine.saveCapture(text: "今天沟通很好", at: date)
        let item = V2CaptureCandidate(candidateID: "r", kind: .recall,
            evidence: [.init(blockID: entry.blocks[0].id, quote: "今天沟通很好")],
            payload: .init(text: "今天沟通很好", localDate: V2CaptureContract.localDate(date, timeZone: .current)))
        let batch = try engine.stageCaptureProposal(.init(captureID: entry.id, sourceRevision: 1, items: [item]), model: "fixture")
        let receipt = try engine.applyCaptureCandidate(batchID: batch.id, candidateID: "r")
        XCTAssertEqual(engine.snapshot.recallEntries[0].text, "已有正文\n\n今天沟通很好")
        XCTAssertTrue(engine.snapshot.recallEntries[0].hasHandwriting)
        _ = try engine.saveRecallEntry(date: date, text: "用户后续修改", hasHandwriting: true)
        XCTAssertThrowsError(try engine.undoCaptureReceipt(id: receipt.id))
        XCTAssertEqual(engine.snapshot.recallEntries[0].text, "用户后续修改")
    }

    func testUnknownFieldsAndInvalidAmountsCannotBecomeLedger() throws {
        XCTAssertThrowsError(try V2CaptureContract.decode(Data(#"{"schemaVersion":1,"captureID":"x","sourceRevision":1,"items":[],"hack":true}"#.utf8)))
        for amount in ["-1", "NaN", "1e3", "1,000", "0", "1.123456789"] {
            XCTAssertFalse(V2CaptureContract.validAmount(amount))
        }
        XCTAssertTrue(V2CaptureContract.validAmount("38.50"))
    }
}

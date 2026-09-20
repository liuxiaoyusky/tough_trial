import XCTest
@testable import ToughTrialV2Core

final class V2CaptureRevisionTests: XCTestCase {
    private func bill(_ source: V2CaptureEntry, amount: String) -> V2CaptureProposal {
        .init(captureID: source.id, sourceRevision: source.revision, items: [.init(candidateID: "bill", kind: .ledger,
            evidence: [.init(blockID: source.blocks[0].id, quote: source.text)],
            payload: .init(text: "午餐", amount: amount, currency: "CNY", direction: .expense))])
    }
    func testReanalysisRequiresConfirmedReplacementAndDoesNotDuplicate() throws {
        let engine = V2Engine()
        let old = try engine.saveCapture(text: "午餐人民币38元")
        let original = try engine.stageCaptureProposal(bill(old, amount: "38"), model: "fixture")
        _ = try engine.applyCaptureCandidate(batchID: original.id, candidateID: "bill")
        let edited = try engine.saveCapture(text: "更正：午餐人民币28元", id: old.id, expectedRevision: 1)
        let preview = try engine.stageCaptureProposal(bill(edited, amount: "28"), model: "fixture")
        XCTAssertThrowsError(try engine.applyCaptureCandidate(batchID: preview.id, candidateID: "bill"))
        XCTAssertThrowsError(try engine.replaceCaptureResults(batchID: preview.id, confirmed: false))
        XCTAssertEqual(engine.snapshot.capture.ledger.first?.amount, "38")
        try engine.replaceCaptureResults(batchID: preview.id, confirmed: true)
        XCTAssertEqual(engine.snapshot.capture.ledger.count, 1)
        XCTAssertEqual(engine.snapshot.capture.ledger.first?.amount, "28")
        XCTAssertEqual(engine.snapshot.capture.entries.count, 2)
        XCTAssertEqual(engine.snapshot.capture.receipts.first?.status, .undone)
    }
    func testConfirmedCategoryStillAllowsOriginalUndo() throws {
        let engine = V2Engine()
        let source = try engine.saveCapture(text: "午餐人民币38元")
        let batch = try engine.stageCaptureProposal(bill(source, amount: "38"), model: "fixture")
        let receipt = try engine.applyCaptureCandidate(batchID: batch.id, candidateID: "bill")
        try engine.confirmLedgerCategory(ledgerID: receipt.targetID!, categoryName: "餐饮", expectedRevision: 1, confirmed: true)
        try engine.undoCaptureReceipt(id: receipt.id)
        XCTAssertTrue(engine.snapshot.capture.ledger.isEmpty)
        XCTAssertThrowsError(try engine.undoCategoryReceipt(id: engine.snapshot.capture.categoryReceipts.last!.id))
    }
    func testTextOnlyEditKeepsMediaAndHistoricalVersion() throws {
        let engine = V2Engine()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let asset = try engine.saveCaptureAsset(Data("image fixture".utf8), kind: .image, fileExtension: "png", store: .init(directory: directory))
        let source = try engine.saveCapture(text: "原文", mediaBlocks: [.init(kind: .image, assetID: asset.id)])
        let revised = try engine.saveCapture(text: "修订正文", id: source.id, expectedRevision: 1)
        XCTAssertEqual(revised.blocks.last, source.blocks.last)
        XCTAssertEqual(engine.snapshot.capture.entries.first?.text, "原文")
    }
    func testFutureCaptureVersionCannotBeLoadedOrRewritten() throws {
        var snapshot = V2AppSnapshot.empty
        snapshot.capture.schemaVersion = 999
        let data = try JSONEncoder().encode(snapshot)
        XCTAssertThrowsError(try JSONDecoder().decode(V2AppSnapshot.self, from: data))
    }
}

import XCTest
import UIKit
@testable import ToughTrial
import ToughTrialV2Core

@MainActor
final class V2CaptureStoreTests: XCTestCase {
    func testImportOrganizationFailureIsVisibleAndKeepsSource() async throws {
        let engine = V2Engine()
        let entry = try engine.saveCapture(text: "原始导入内容")
        let store = V2CaptureStore(appStore: V2AppStore(engine: engine), client: FailingImportFixture())
        store.organizeImported([entry])
        for _ in 0..<200 where store.isOrganizing { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNotNil(store.issue)
        XCTAssertTrue(store.message?.contains("失败 1 条") == true)
        XCTAssertEqual(engine.snapshot.capture.latestEntries.first?.text, "原始导入内容")
    }

    func testImportedBatchUsesExistingLedgerConfirmationAndKeepsDisplayedSourceAligned() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let previous = V2ScheduleSettings.defaults.object(forKey: "schedule.requiresConfirmation")
        V2ScheduleSettings.defaults.set(false, forKey: "schedule.requiresConfirmation")
        defer {
            if let previous { V2ScheduleSettings.defaults.set(previous, forKey: "schedule.requiresConfirmation") }
            else { V2ScheduleSettings.defaults.removeObject(forKey: "schedule.requiresConfirmation") }
        }
        let engine = V2Engine()
        let store = V2CaptureStore(appStore: V2AppStore(engine: engine), client: ImportedLedgerFixture(), assetDirectory: directory)
        let data = Data("date,amount,currency,note\n2026-09-01,28,CNY,lunch\n2026-09-01,28,CNY,dinner\n".utf8)
        let preview = try V2ExternalImportParser.recognize(data: data, fileName: "bills.csv")
        let entries = try XCTUnwrap(store.importRecords(preview, selectedIDs: Set(preview.records.map(\.id)), data: data))
        store.organizeImported(entries)
        for _ in 0..<200 where store.isOrganizing { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(store.isOrganizing)
        XCTAssertNil(store.issue)
        XCTAssertEqual(engine.snapshot.capture.ledger.count, 2)
        XCTAssertTrue(engine.snapshot.capture.ledger.allSatisfy { $0.categoryID == "others" })
        XCTAssertTrue(engine.snapshot.capture.receipts.allSatisfy { $0.status == .needsConfirmation })
        XCTAssertEqual(store.editingID, store.activeBatch?.proposal.captureID)
        let count = engine.snapshot.capture.ledger.count
        store.organizeImported(entries)
        for _ in 0..<200 where store.isOrganizing { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(engine.snapshot.capture.ledger.count, count)
    }

    func testNewQuickEntryPreservesExistingDraftAndTaskUsesStandardEngine() throws {
        let engine = V2Engine()
        let store = V2CaptureStore(appStore: V2AppStore(engine: engine))
        store.draft = "未整理的原文"
        XCTAssertTrue(store.newEntry())
        XCTAssertEqual(engine.snapshot.capture.latestEntries.first?.text, "未整理的原文")
        XCTAssertEqual(store.draft, "")
        store.saveQuickTask(title: "买牛奶", note: "回家路上")
        XCTAssertNil(store.issue)
        XCTAssertEqual(engine.snapshot.tasks.first?.title, "买牛奶")
        XCTAssertEqual(engine.snapshot.capture.receipts.last?.status, .applied)
        XCTAssertEqual(engine.snapshot.scheduleReceipts.count, 1)
    }

    func testImageOriginalIsSavedBeforeDerivedOCRText() async throws {
        let engine = V2Engine()
        let app = V2AppStore(engine: engine)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = V2CaptureStore(appStore: app, assetDirectory: directory)
        let data = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 200)).pngData { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 800, height: 200))
            ("LUNCH CNY 38.00" as NSString).draw(at: CGPoint(x: 30, y: 50), withAttributes: [.font: UIFont.systemFont(ofSize: 50), .foregroundColor: UIColor.black])
        }
        store.attach(data: data, kind: .image, fileExtension: "png")
        let source = try XCTUnwrap(engine.snapshot.capture.latestEntries.first)
        let block = try XCTUnwrap(source.blocks.last)
        XCTAssertEqual(try store.assets.data(for: XCTUnwrap(store.asset(for: block))), data)
        let text = await V2CaptureView.recognize(data)
        XCTAssertTrue(text?.contains("38.00") == true)
        store.recognizedMedia(text, captureID: source.id, sourceRevision: source.revision, blockID: block.id, assetID: block.assetID)
        XCTAssertEqual(engine.snapshot.capture.assets.count, 1)
        XCTAssertEqual(engine.snapshot.capture.latestEntries.first?.revision, 2)
        XCTAssertTrue(engine.snapshot.capture.latestEntries.first?.text.contains("38.00") == true)
        XCTAssertNil(engine.snapshot.capture.entries.first?.blocks.last?.text)
    }

    func testCaptureRefreshDoesNotMaskRecallAppendWithCleanUICache() throws {
        let engine = V2Engine()
        let app = V2AppStore(engine: engine)
        app.updateRecallText("原有日记")
        XCTAssertTrue(app.saveRecall(hasHandwriting: true))
        let store = V2CaptureStore(appStore: app)
        store.draft = "今天沟通很好"
        let source = try XCTUnwrap(store.saveDraft())
        let item = V2CaptureCandidate(candidateID: "r", kind: .recall,
            evidence: [.init(blockID: source.blocks[0].id, quote: source.text)],
            payload: .init(text: source.text, localDate: V2CaptureContract.localDate(Date(), timeZone: .current)))
        let batch = try engine.stageCaptureProposal(.init(captureID: source.id, sourceRevision: 1, items: [item]), model: "fixture")
        store.refresh(); store.apply(item, batch: batch)
        XCTAssertNil(store.issue)
        XCTAssertEqual(app.recallText, "原有日记\n\n今天沟通很好")
        XCTAssertTrue(app.savedRecallEntry?.hasHandwriting == true)
    }
    func testUnsavedRecallEditsPreventCaptureOverwrite() throws {
        let engine = V2Engine()
        let app = V2AppStore(engine: engine)
        app.updateRecallText("尚未保存的正文")
        let store = V2CaptureStore(appStore: app)
        store.draft = "今天沟通很好"
        let source = try XCTUnwrap(store.saveDraft())
        let item = V2CaptureCandidate(candidateID: "r", kind: .recall,
            evidence: [.init(blockID: source.blocks[0].id, quote: source.text)],
            payload: .init(text: source.text, localDate: V2CaptureContract.localDate(Date(), timeZone: .current)))
        let batch = try engine.stageCaptureProposal(.init(captureID: source.id, sourceRevision: 1, items: [item]), model: "fixture")
        store.refresh(); store.apply(item, batch: batch)
        XCTAssertNotNil(store.issue)
        XCTAssertEqual(app.recallText, "尚未保存的正文")
        XCTAssertTrue(engine.snapshot.recallEntries.isEmpty)
    }
}

private struct ImportedLedgerFixture: V2CaptureClient {
    func extract(_ entry: V2CaptureEntry, categories: [V2LedgerCategory]) async throws -> V2CaptureProposal {
        .init(captureID: entry.id, sourceRevision: entry.revision, items: [
            .init(candidateID: "bill", kind: .ledger, evidence: [.init(blockID: entry.blocks[0].id, quote: entry.text)],
                  payload: .init(text: "餐费", amount: "28", currency: "CNY", direction: .expense, categoryName: "餐饮", localDate: "2026-09-01"))
        ])
    }
}

private struct FailingImportFixture: V2CaptureClient {
    func extract(_ entry: V2CaptureEntry, categories: [V2LedgerCategory]) async throws -> V2CaptureProposal { throw V2CaptureError.providerFailure }
}

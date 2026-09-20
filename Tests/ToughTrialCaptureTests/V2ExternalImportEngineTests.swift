import XCTest
@testable import ToughTrialV2Core

final class V2ExternalImportEngineTests: XCTestCase {
    func testImportOnlySavesSourcesAndDeduplicatesAfterRestartAndPartialSelection() throws {
        let data = Data("日期,金额,币种,备注\n2026-09-01,28,CNY,午餐\n2026-09-02,-12,HKD,退款\n".utf8)
        let preview = try V2ExternalImportParser.recognize(data: data, fileName: "MoneyThings.csv")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let assets = V2CaptureAssetStore(directory: directory)
        let engine = V2Engine()
        let first = try engine.importExternalRecords(preview, selectedIDs: [preview.records[0].id], originalData: data, assetStore: assets)
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(engine.snapshot.capture.ledger.count, 0)
        XCTAssertEqual(engine.snapshot.tasks.count, 0)
        XCTAssertEqual(engine.snapshot.capture.batches.count, 0)
        let restored = V2Engine(snapshot: try JSONDecoder().decode(V2AppSnapshot.self, from: JSONEncoder().encode(engine.snapshot)))
        let all = try restored.importExternalRecords(preview, selectedIDs: Set(preview.records.map(\.id)), originalData: data, assetStore: assets)
        XCTAssertEqual(all.first?.id, first.first?.id)
        XCTAssertEqual(restored.snapshot.capture.latestEntries.count, 2)
        XCTAssertEqual(restored.snapshot.capture.assets.count, 1)
        XCTAssertEqual(try assets.data(for: restored.snapshot.capture.assets[0]), data)
        XCTAssertTrue(all[1].text.contains("HKD"))
        XCTAssertTrue(all[1].text.contains("-12"))
        _ = try restored.importExternalRecords(preview, selectedIDs: Set(preview.records.map(\.id)), originalData: data, assetStore: assets)
        XCTAssertEqual(restored.snapshot.capture.latestEntries.count, 2)
    }
    func testRecurringCalendarCannotAccidentallyBecomeSingleTask() throws {
        let data = Data("BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:weekly\nSUMMARY:Weekly review\nDTSTART:20260910T100000Z\nRRULE:FREQ=WEEKLY\nEND:VEVENT\nEND:VCALENDAR".utf8)
        let preview = try V2ExternalImportParser.recognize(data: data, fileName: "calendar.ics")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let engine = V2Engine()
        let source = try XCTUnwrap(engine.importExternalRecords(preview, selectedIDs: Set(preview.records.map(\.id)), originalData: data, assetStore: .init(directory: directory)).first)
        let item = V2CaptureCandidate(candidateID: "task", kind: .task, evidence: [.init(blockID: source.blocks[0].id, quote: "Weekly review")], payload: .init(text: "Weekly review", operations: [.init(kind: .createTask, localID: "t", title: "Weekly review")]))
        XCTAssertThrowsError(try engine.stageCaptureProposal(.init(captureID: source.id, sourceRevision: 1, items: [item]), model: "fixture"))
        XCTAssertTrue(engine.snapshot.tasks.isEmpty)
        XCTAssertTrue(source.text.contains("RRULE:FREQ=WEEKLY"))
    }
    func testMismatchedOriginalAndUnknownSelectionCannotWrite() throws {
        let data = Data("今天很好".utf8)
        let preview = try V2ExternalImportParser.recognize(data: data, fileName: "diary.txt")
        let engine = V2Engine()
        let assets = V2CaptureAssetStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        XCTAssertThrowsError(try engine.importExternalRecords(preview, selectedIDs: Set(preview.records.map(\.id)), originalData: Data("wrong".utf8), assetStore: assets))
        XCTAssertThrowsError(try engine.importExternalRecords(preview, selectedIDs: ["unknown"], originalData: data, assetStore: assets))
        XCTAssertTrue(engine.snapshot.capture.entries.isEmpty)
        XCTAssertTrue(engine.snapshot.capture.assets.isEmpty)
    }
    func testQuickRoutesRejectAmbiguousLinks() {
        for action in V2QuickCaptureAction.allCases { XCTAssertEqual(V2QuickCaptureAction(url: action.url), action) }
        for value in ["https://capture/task", "toughtrial://capture/nope", "toughtrial://capture/task?title=x", "toughtrial://capture/task/more", "toughtrial://user@capture/task", "toughtrial://capture/note#x"] {
            XCTAssertNil(V2QuickCaptureAction(url: URL(string: value)!))
        }
    }
    func testMiniMaxReasoningIsSeparateAndGLMFlashUsesLowThinking() {
        let mini = V2OpenAIRequestCompatibility.body(["model": "MiniMax-M2.7-highspeed"], endpoint: URL(string: "https://api.minimax.cn/v1/chat/completions")!, model: "MiniMax-M2.7-highspeed")
        XCTAssertEqual(mini["reasoning_split"] as? Bool, true)
        let glm = V2OpenAIRequestCompatibility.body([:], endpoint: URL(string: "https://open.bigmodel.cn/api/coding/paas/v4/chat/completions")!, model: "glm-5.3-flash")
        XCTAssertEqual((glm["thinking"] as? [String: String])?["type"], "enabled")
        XCTAssertEqual(glm["reasoning_effort"] as? String, "low")
        let other = V2OpenAIRequestCompatibility.body([:], endpoint: URL(string: "https://example.com/v1/chat/completions")!, model: "MiniMax-M2.7-highspeed")
        XCTAssertNil(other["reasoning_split"])
    }
}

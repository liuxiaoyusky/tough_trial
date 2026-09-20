import XCTest
import ToughTrialV2Core
@testable import ToughTrial

@MainActor
final class V2LedgerCaptureStoreTests: XCTestCase {
    func testDedicatedLedgerDraftStaysSeparateAndManualSaveClearsIt() throws {
        let engine = V2Engine()
        let store = V2CaptureStore(appStore: V2AppStore(engine: engine))
        store.draft = "混合随手记"
        store.ledgerDraft = "独立记账原话"

        store.saveManualLedger(
            amount: "18",
            text: store.ledgerDraft,
            currency: "CNY",
            direction: .expense,
            localDate: nil
        )

        XCTAssertNil(store.issue)
        XCTAssertEqual(store.draft, "混合随手记")
        XCTAssertEqual(store.ledgerDraft, "")
        XCTAssertEqual(engine.snapshot.capture.ledger.first?.text, "独立记账原话")
        XCTAssertNil(engine.snapshot.capture.ledger.first?.localDate)
        XCTAssertTrue(engine.snapshot.capture.entries.isEmpty)
    }

    func testDedicatedOrganizationOnlyStagesWhenMixedCaptureWouldAutoApply() async throws {
        let plugins = V2PluginStore.shared
        let pluginIDs = ["capture", "assistant", "ledger"]
        let priorPlugins = Dictionary(uniqueKeysWithValues: pluginIDs.map { ($0, plugins.enabled($0)) })
        defer { for id in pluginIDs { plugins.setEnabled(id, priorPlugins[id] == true) } }
        for id in pluginIDs { plugins.setEnabled(id, true) }

        let priorConfirmation = V2ScheduleSettings.defaults.object(forKey: "schedule.requiresConfirmation")
        V2ScheduleSettings.defaults.set(false, forKey: "schedule.requiresConfirmation")
        defer {
            if let priorConfirmation { V2ScheduleSettings.defaults.set(priorConfirmation, forKey: "schedule.requiresConfirmation") }
            else { V2ScheduleSettings.defaults.removeObject(forKey: "schedule.requiresConfirmation") }
        }

        let engine = V2Engine()
        let store = V2CaptureStore(
            appStore: V2AppStore(engine: engine),
            client: DedicatedLedgerReviewFixture()
        )
        store.draft = "混合随手记原文"
        let mixedDraft = store.draft
        store.organizeLedger(text: "午饭花了三十八元")

        XCTAssertTrue(store.isOrganizing)
        for _ in 0..<200 where store.isOrganizing { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(store.isOrganizing)
        XCTAssertNil(store.issue)
        XCTAssertEqual(store.draft, mixedDraft)
        XCTAssertEqual(store.ledgerDraft, "午饭花了三十八元")
        XCTAssertEqual(engine.snapshot.capture.batches.count, 1)
        XCTAssertTrue(engine.snapshot.capture.ledger.isEmpty)
        XCTAssertTrue(engine.snapshot.capture.notes.isEmpty)
        XCTAssertTrue(engine.snapshot.tasks.isEmpty)
        XCTAssertTrue(engine.snapshot.planItems.isEmpty)
    }
}

private struct DedicatedLedgerReviewFixture: V2CaptureClient {
    func extract(_ entry: V2CaptureEntry, categories: [V2LedgerCategory]) async throws -> V2CaptureProposal {
        let evidence = [V2CaptureEvidence(blockID: entry.blocks[0].id, quote: entry.text)]
        return .init(captureID: entry.id, sourceRevision: entry.revision, items: [
            .init(candidateID: "bill", kind: .ledger, evidence: evidence,
                  payload: .init(text: "午饭", amount: "38", currency: "CNY", direction: .expense)),
            .init(candidateID: "note", kind: .other, evidence: evidence,
                  payload: .init(text: "顺手记下的说明")),
            .init(candidateID: "task", kind: .task, evidence: evidence,
                  payload: .init(text: "整理发票", operations: [
                      .init(kind: .createTask, localID: "invoice-task", title: "整理发票")
                  ]))
        ])
    }
}

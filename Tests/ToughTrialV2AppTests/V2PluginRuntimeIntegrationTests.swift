import XCTest
import ToughTrialV2Core
@testable import ToughTrial

@MainActor
final class V2PluginRuntimeIntegrationTests: XCTestCase {
    func testVisibilityDoesNotDisableCommandsAndPersistsSeparately() throws {
        let name = "runtime-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let plugins = V2PluginStore(defaults: defaults)
        let engine = V2Engine(moduleRuntime: plugins.runtime)
        let ticket = try plugins.ticket(["tasks"])
        plugins.setVisible("today", false); plugins.setVisible("tasks", false)
        XCTAssertFalse(plugins.visible("today")); XCTAssertTrue(plugins.enabled("tasks"))
        try plugins.validate(ticket)
        _ = try engine.createTask(title: "隐藏页面仍可创建")
        let reopened = V2PluginStore(defaults: defaults)
        XCTAssertFalse(reopened.visible("tasks")); XCTAssertTrue(reopened.enabled("tasks"))
        plugins.setEnabled("tasks", false)
        XCTAssertThrowsError(try engine.createTask(title: "停用后拒绝"))
        XCTAssertEqual(engine.snapshot.tasks.count, 1)
    }

    func testLegacyHoldsDoNotSilentlyReactivateFinanceAndMigrationRunsOnce() throws {
        let name = "migration-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(["capture", "today"], forKey: "plugins.disabled")
        defaults.set(false, forKey: "usageTrace.enabled")
        let plugins = V2PluginStore(defaults: defaults)
        XCTAssertTrue(plugins.enabled("tasks")); XCTAssertFalse(plugins.visible("today"))
        XCTAssertTrue(plugins.requested("finance")); XCTAssertFalse(plugins.enabled("finance"))
        XCTAssertFalse(plugins.enabled("trace"))
        plugins.setEnabled("ledger", true); plugins.setEnabled("finance", true)
        XCTAssertTrue(plugins.enabled("finance")); XCTAssertFalse(plugins.enabled("capture"))
        let reopened = V2PluginStore(defaults: defaults)
        XCTAssertTrue(reopened.enabled("finance")); XCTAssertFalse(reopened.enabled("trace"))
        XCTAssertEqual(defaults.stringArray(forKey: "plugins.disabled.v1Backup"), ["capture", "today"])
    }

    func testQuickTaskRefusesDisabledTargetBeforeSavingSource() throws {
        let plugins = V2PluginStore.shared
        defer { plugins.setEnabled("tasks", true) }
        let engine = V2Engine()
        let store = V2CaptureStore(appStore: V2AppStore(engine: engine))
        plugins.setEnabled("tasks", false)
        store.saveQuickTask(title: "被拒绝", note: "")
        XCTAssertNotNil(store.issue)
        XCTAssertTrue(engine.snapshot.capture.entries.isEmpty)
        XCTAssertTrue(engine.snapshot.tasks.isEmpty)
    }

    func testCaptureReturningAfterDisableReenableDoesNotCommit() async throws {
        let plugins = V2PluginStore.shared
        defer { plugins.setEnabled("assistant", true) }
        let engine = V2Engine()
        let client = SuspendedCaptureClient()
        let store = V2CaptureStore(appStore: V2AppStore(engine: engine), client: client)
        store.draft = "旧请求原文"
        store.organize()
        for _ in 0..<100 {
            if await client.hasStarted { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let started = await client.hasStarted
        XCTAssertTrue(started)
        plugins.setEnabled("assistant", false); plugins.setEnabled("assistant", true)
        await client.complete()
        for _ in 0..<100 where store.isOrganizing { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(store.isOrganizing)
        XCTAssertEqual(engine.snapshot.capture.latestEntries.first?.text, "旧请求原文")
        XCTAssertTrue(engine.snapshot.capture.batches.isEmpty)
        XCTAssertTrue(engine.snapshot.capture.notes.isEmpty)
    }

    func testFinanceUICommandRequiresPaymentConfirmationAndKeepsReceiptWhenTraceOff() throws {
        let plugins = V2PluginStore.shared
        let prior = plugins.enabled("trace")
        defer { plugins.setEnabled("trace", prior) }
        let engine = V2Engine()
        let store = V2CaptureStore(appStore: V2AppStore(engine: engine))
        plugins.setEnabled("trace", false)
        let plan = V2FinancePlan(title: "订阅", kind: .subscription, amount: "20", currency: "USD", dueDate: "2026-09-10")
        _ = try store.executeFinance(.savePlan(plan, expectedRevision: nil))
        let pay = V2FinanceCommand.markPaid(id: plan.id, expectedRevision: 1, expectedDueDate: plan.dueDate)
        XCTAssertThrowsError(try store.executeFinance(pay))
        let receipt = try store.executeFinance(pay, confirmedPayment: true)
        XCTAssertEqual(store.lastFinanceReceipt?.id, receipt.id)
        XCTAssertEqual(V2OperationReceipt.paymentReceipts(from: engine.snapshot).first?.id, receipt.id)
        _ = try store.executeFinance(.undoPayment(id: receipt.id))
        XCTAssertTrue(engine.snapshot.capture.ledger.isEmpty)
    }
}

private actor SuspendedCaptureClient: V2CaptureClient {
    var hasStarted = false
    private var pending: CheckedContinuation<V2CaptureProposal, Never>?
    private var source: V2CaptureEntry?
    func extract(_ entry: V2CaptureEntry, categories: [V2LedgerCategory]) async throws -> V2CaptureProposal {
        source = entry; hasStarted = true
        return await withCheckedContinuation { pending = $0 }
    }
    func complete() {
        guard let source else { return }
        pending?.resume(returning: .init(captureID: source.id, sourceRevision: source.revision, items: [
            .init(candidateID: "note", kind: .other, evidence: [.init(blockID: source.blocks[0].id, quote: source.text)], payload: .init(text: source.text))
        ]))
        pending = nil
    }
}

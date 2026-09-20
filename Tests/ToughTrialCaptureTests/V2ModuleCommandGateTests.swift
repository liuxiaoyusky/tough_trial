import XCTest
@testable import ToughTrialV2Core

final class V2ModuleCommandGateTests: XCTestCase {
    func testDirectTaskAndFinanceCallsCannotBypassDisabledModule() throws {
        let runtime = V2ModuleRuntime()
        let engine = V2Engine(moduleRuntime: runtime)
        let task = try engine.createTask(title: "保留任务")
        let plan = try engine.saveFinancePlan(.init(title: "订阅", kind: .subscription, amount: "20", currency: "USD", dueDate: "2026-09-10"))
        let before = engine.snapshot
        runtime.update(preferences: .init(disabled: ["core.tasks", "core.ledger"]))
        XCTAssertThrowsError(try engine.completeTask(id: task.id))
        XCTAssertThrowsError(try engine.payFinancePlan(id: plan.id))
        XCTAssertThrowsError(try engine.saveBudget(.init(currency: "USD", amount: "100", month: "2026-09")))
        XCTAssertEqual(engine.snapshot, before)
    }

    func testFinanceStillWorksWithoutCaptureOrTrace() throws {
        let runtime = V2ModuleRuntime(preferences: .init(disabled: ["core.capture", "core.traceViewer"]))
        let engine = V2Engine(moduleRuntime: runtime)
        let plan = try engine.saveFinancePlan(.init(title: "租金", kind: .rent, amount: "100", currency: "CNY", dueDate: "2026-09-10"))
        let payment = try engine.payFinancePlan(id: plan.id, expectedDueDate: plan.dueDate)
        XCTAssertEqual(engine.snapshot.capture.ledger.count, 1)
        try engine.undoFinancePayment(id: payment.id)
        XCTAssertTrue(engine.snapshot.capture.ledger.isEmpty)
        XCTAssertEqual(engine.snapshot.capture.finance?.payments.first?.status, .undone)
    }

    func testCaptureCannotWriteDisabledTargetAndCanResumeLater() throws {
        let runtime = V2ModuleRuntime()
        let engine = V2Engine(moduleRuntime: runtime)
        let source = try engine.saveCapture(text: "买午饭 25 元")
        let item = V2CaptureCandidate(candidateID: "lunch", kind: .ledger,
            evidence: [.init(blockID: source.blocks[0].id, quote: source.text)],
            payload: .init(text: "午饭", amount: "25", currency: "CNY", direction: .expense))
        let batch = try engine.stageCaptureProposal(.init(captureID: source.id, sourceRevision: source.revision, items: [item]), model: "fixture")
        runtime.update(preferences: .init(disabled: ["core.ledger"]))
        let before = engine.snapshot
        XCTAssertThrowsError(try engine.applyCaptureCandidate(batchID: batch.id, candidateID: item.id))
        XCTAssertEqual(engine.snapshot, before)
        runtime.update(preferences: .init())
        let receipt = try engine.applyCaptureCandidate(batchID: batch.id, candidateID: item.id)
        XCTAssertEqual(receipt.status, .needsConfirmation)
        runtime.update(preferences: .init(disabled: ["core.ledger"]))
        XCTAssertThrowsError(try engine.undoCaptureReceipt(id: receipt.id))
        XCTAssertEqual(engine.snapshot.capture.ledger.count, 1)
    }

    func testCaptureTaskStagingCannotBypassTaskGate() throws {
        let runtime = V2ModuleRuntime()
        let engine = V2Engine(moduleRuntime: runtime)
        let source = try engine.saveCapture(text: "准备明天会议")
        let item = V2CaptureCandidate(candidateID: "meeting", kind: .task,
            evidence: [.init(blockID: source.blocks[0].id, quote: source.text)],
            payload: .init(text: source.text, operations: [.init(kind: .createTask, localID: "task", title: source.text)]))
        let batch = try engine.stageCaptureProposal(.init(captureID: source.id, sourceRevision: source.revision, items: [item]), model: "fixture")
        runtime.update(preferences: .init(disabled: ["core.tasks"]))
        XCTAssertThrowsError(try engine.applyCaptureCandidate(batchID: batch.id, candidateID: item.id))
        XCTAssertTrue(engine.snapshot.tasks.isEmpty)
        XCTAssertTrue(engine.snapshot.scheduleReceipts.isEmpty)
    }

    @MainActor
    func testSyncDoesNotPushAfterModuleDisabledAndReenabledDuringRead() async throws {
        let runtime = V2ModuleRuntime()
        let engine = V2Engine(moduleRuntime: runtime)
        _ = try engine.createTask(title: "待同步")
        _ = try engine.prepareScheduleDocument(timeZoneIdentifier: "UTC")
        let location = V2GitHubScheduleLocation(owner: "fixture", repository: "fixture", branch: "main", path: "schedule.md")
        try engine.configureScheduleGitHub(location)
        let attempt = try engine.beginScheduleSync()
        let ticket = try runtime.ticket(for: ["core.sync"])
        let transport = ModuleSyncTransport(onRead: {
            runtime.update(preferences: .init(disabled: ["core.sync"]))
            runtime.update(preferences: .init())
        })
        let client = V2GitHubScheduleClient(location: location, token: "fixture", transport: transport)
        do {
            _ = try await V2ScheduleSynchronizer.synchronize(attempt, using: client, preflight: { @MainActor in
                try runtime.validate(ticket)
            })
            XCTFail("旧同步不应进入 PUT")
        } catch is V2ModuleRuntimeError { }
        let writes = await transport.writes
        XCTAssertEqual(writes, 0)
        XCTAssertEqual(engine.snapshot.tasks.count, 1)
    }

    func testDisabledAttachmentDoesNotWriteOriginalFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let engine = V2Engine(moduleRuntime: .init(preferences: .init(disabled: ["core.attachments"])))
        XCTAssertThrowsError(try engine.saveCaptureAsset(Data("raw".utf8), kind: .document, fileExtension: "txt", store: .init(directory: directory)))
        XCTAssertTrue(engine.snapshot.capture.assets.isEmpty)
        XCTAssertTrue((try? FileManager.default.contentsOfDirectory(atPath: directory.path))?.isEmpty ?? true)
    }
}

private actor ModuleSyncTransport: V2PlanningHTTPTransport {
    let onRead: @MainActor @Sendable () -> Void
    var writes = 0
    init(onRead: @escaping @MainActor @Sendable () -> Void) { self.onRead = onRead }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if request.httpMethod == "PUT" { writes += 1 }
        else { await onRead() }
        return (Data(), HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!)
    }
}

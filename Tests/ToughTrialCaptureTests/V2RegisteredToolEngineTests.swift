import Foundation
import XCTest
@testable import ToughTrialV2Core

final class V2RegisteredToolEngineTests: XCTestCase {
    private let date = ISO8601DateFormatter().date(from: "2026-09-10T10:00:00Z")!

    private func call(_ toolID: String, _ json: String) -> V2AgentToolCall {
        V2AgentToolCall(toolID: toolID, argumentsJSON: Data(json.utf8))
    }

    private func context(
        _ toolID: String,
        requestID: String = UUID().uuidString,
        source: String = "",
        intent: V2ToolIntent = .explicitWrite,
        ordinal: Int = 0
    ) -> V2ToolExecutionContext {
        V2ToolExecutionContext(
            traceID: "trace-\(requestID)",
            assistantRequestID: requestID,
            attemptID: "attempt-\(requestID)",
            callOrdinal: ordinal,
            toolID: toolID,
            submittedText: source,
            sourceEvidence: source.isEmpty ? [] : [.init(excerpt: source)],
            intent: intent
        )
    }

    private func temporaryStore(_ name: String = UUID().uuidString) -> V2JSONSnapshotStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tough-trial-registered-tools-\(name)", isDirectory: true)
        return V2JSONSnapshotStore(fileURL: directory.appendingPathComponent("snapshot.json"))
    }

    private func isConflict(_ error: Error) -> Bool {
        guard let error = error as? V2RegisteredToolError else { return false }
        if case .conflict = error { return true }
        return false
    }

    func testAssistantTaskUsesSameDomainShapeAsManualTask() throws {
        let manual = V2Engine()
        let manualTask = try manual.createTask(title: "手动任务", at: date)

        let assistant = V2Engine()
        let toolID = "core.tasks.create"
        let result = try assistant.executeRegisteredTool(
            call(toolID, #"{"title":"助手任务"}"#),
            context: context(toolID, requestID: "same-domain", source: "创建助手任务"),
            at: date
        )

        XCTAssertEqual(result.state, .applied)
        let assistantTask = try XCTUnwrap(assistant.snapshot.tasks.first)
        XCTAssertEqual(assistantTask.status, manualTask.status)
        XCTAssertEqual(assistantTask.contextID, manualTask.contextID)
        XCTAssertEqual(assistantTask.parentID, manualTask.parentID)
        XCTAssertEqual(assistantTask.kind, manualTask.kind)
        XCTAssertEqual(assistantTask.note, manualTask.note)
        XCTAssertEqual(assistant.snapshot.toolOperations.count, 1)
    }

    func testFailedSnapshotSaveDoesNotPublishTaskOrOperation() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("tough-trial-atomic-\(UUID().uuidString)", isDirectory: false)
        try Data("blocker".utf8).write(to: root)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = V2JSONSnapshotStore(fileURL: root.appendingPathComponent("snapshot.json"))
        let engine = V2Engine(store: store)
        let before = engine.snapshot
        let toolID = "core.tasks.create"

        XCTAssertThrowsError(try engine.executeRegisteredTool(
            call(toolID, #"{"title":"不会写入"}"#),
            context: context(toolID, requestID: "atomic-failure", source: "创建不会写入的任务"),
            at: date
        ))
        XCTAssertEqual(engine.snapshot, before)
        XCTAssertTrue(engine.snapshot.tasks.isEmpty)
        XCTAssertTrue(engine.snapshot.toolOperations.isEmpty)
    }

    func testRetryAfterReloadReturnsPersistedReceiptWithoutDuplicateTask() throws {
        let store = temporaryStore("retry-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: store.fileURL.deletingLastPathComponent()) }
        let engine = try V2Engine.load(from: store)
        let toolID = "core.tasks.create"
        let toolCall = call(toolID, #"{"title":"只创建一次"}"#)
        let toolContext = context(toolID, requestID: "retry-after-reload", source: "创建只创建一次的任务")

        let first = try engine.executeRegisteredTool(toolCall, context: toolContext, at: date)
        let reloaded = try V2Engine.load(from: store)
        let second = try reloaded.executeRegisteredTool(toolCall, context: toolContext, at: date)

        XCTAssertEqual(second, first)
        XCTAssertEqual(reloaded.snapshot.tasks.count, 1)
        XCTAssertEqual(reloaded.snapshot.toolOperations.count, 1)
        XCTAssertEqual(reloaded.snapshot.tasks[0].title, "只创建一次")
    }

    func testMissingFinancialEvidenceReturnsNeedsInformationWithoutWrite() throws {
        let engine = V2Engine()
        let toolID = "core.finance.createPlan"
        let result = try engine.executeRegisteredTool(
            call(toolID, #"{"title":"ChatGPT","amount":"99","currency":"CNY","dueDate":"2026-10-01","kind":"subscription"}"#),
            context: context(toolID, requestID: "finance-missing-evidence", source: "帮我考虑一下 ChatGPT 订阅", intent: .discussion),
            at: date
        )

        XCTAssertEqual(result.state, .needsInformation)
        XCTAssertTrue(engine.snapshot.capture.finance?.plans.isEmpty ?? true)
        XCTAssertTrue(engine.snapshot.toolOperations.isEmpty)
    }

    func testLedgerCategoryAndPaymentRequireSeparateHumanConfirmation() throws {
        let engine = V2Engine()
        _ = try engine.createManualLedgerEntry(
            amount: "38", currency: "CNY", text: "午餐", localDate: "2026-09-10", at: date
        )
        let categoryTool = "core.ledger.proposeCategory"
        let pendingCategory = try engine.executeRegisteredTool(
            call(categoryTool, #"{"ledgerReference":"午餐","category":"餐饮"}"#),
            context: context(categoryTool, requestID: "category-confirm", source: "请把午餐分类为餐饮"),
            at: date
        )

        XCTAssertEqual(pendingCategory.state, .pendingConfirmation)
        XCTAssertEqual(engine.snapshot.capture.ledger.first?.categoryID, "others")
        XCTAssertEqual(engine.snapshot.toolOperations.count, 1)

        let appliedCategory = try engine.confirmRegisteredTool(operationID: pendingCategory.operationID, at: date)
        XCTAssertEqual(appliedCategory.state, .applied)
        XCTAssertNotEqual(engine.snapshot.capture.ledger.first?.categoryID, "others")

        let plan = try engine.saveFinancePlan(.init(
            title: "ChatGPT", kind: .subscription, amount: "99", currency: "CNY",
            dueDate: "2026-10-01", timeZoneIdentifier: "UTC"
        ))
        let paidTool = "core.finance.markPaid"
        let pendingPayment = try engine.executeRegisteredTool(
            call(paidTool, #"{"planReference":"ChatGPT","dueDate":"2026-10-01"}"#),
            context: context(paidTool, requestID: "paid-confirm", source: "ChatGPT 已支付 99 CNY，2026-10-01"),
            at: date
        )

        XCTAssertEqual(pendingPayment.state, .pendingConfirmation)
        XCTAssertTrue(engine.snapshot.capture.finance?.payments.isEmpty ?? true)
        let appliedPayment = try engine.confirmRegisteredTool(operationID: pendingPayment.operationID, at: date)
        XCTAssertEqual(appliedPayment.state, .applied)
        XCTAssertEqual(engine.snapshot.capture.finance?.payments.count, 1)
        XCTAssertEqual(engine.snapshot.capture.finance?.payments.first?.planID, plan.id)
        XCTAssertEqual(engine.snapshot.capture.finance?.payments.first?.status, .applied)
    }

    func testPendingCategoryRejectsWhenLedgerRevisionChanges() throws {
        let engine = V2Engine()
        let ledger = try engine.createManualLedgerEntry(
            amount: "20", currency: "CNY", text: "咖啡", localDate: "2026-09-10", at: date
        )
        let toolID = "core.ledger.proposeCategory"
        let pending = try engine.executeRegisteredTool(
            call(toolID, #"{"ledgerReference":"咖啡","category":"饮品"}"#),
            context: context(toolID, requestID: "category-stale", source: "请把咖啡分类为饮品"),
            at: date
        )
        XCTAssertEqual(pending.state, .pendingConfirmation)

        try engine.confirmLedgerCategory(
            ledgerID: ledger.id, categoryName: "其他餐饮", expectedRevision: ledger.revision, confirmed: true
        )
        XCTAssertThrowsError(try engine.confirmRegisteredTool(operationID: pending.operationID, at: date)) { error in
            XCTAssertTrue(self.isConflict(error))
        }
        XCTAssertEqual(engine.snapshot.capture.ledger.first?.categoryID == "others", false)
    }

    func testUndoRefusesToOverwriteLaterManualTaskEdit() throws {
        let engine = V2Engine()
        let toolID = "core.tasks.create"
        let result = try engine.executeRegisteredTool(
            call(toolID, #"{"title":"原始任务"}"#),
            context: context(toolID, requestID: "undo-conflict", source: "创建原始任务"),
            at: date
        )
        let task = try XCTUnwrap(engine.snapshot.tasks.first)
        _ = try engine.updateTask(
            id: task.id, title: "用户后来改过", note: task.note,
            parentID: task.parentID, contextID: task.contextID, kind: task.kind, at: date
        )

        XCTAssertThrowsError(try engine.undoRegisteredTool(operationID: result.operationID, at: date)) { error in
            XCTAssertTrue(self.isConflict(error))
        }
        XCTAssertEqual(engine.snapshot.tasks.first?.title, "用户后来改过")
    }

    func testFinanceLedgerAndBudgetAreVisibleThroughTypedProjections() throws {
        let engine = V2Engine()
        let ledgerTool = "core.ledger.createPending"
        let ledgerResult = try engine.executeRegisteredTool(
            call(ledgerTool, #"{"description":"午餐","amount":"38","currency":"CNY","date":"2026-09-10"}"#),
            context: context(ledgerTool, requestID: "projection-ledger", source: "午餐 38 CNY 2026-09-10"),
            at: date
        )
        XCTAssertEqual(ledgerResult.state, .applied)

        let financeTool = "core.finance.createPlan"
        let financeResult = try engine.executeRegisteredTool(
            call(financeTool, #"{"title":"ChatGPT","amount":"99","currency":"CNY","dueDate":"2026-10-01","kind":"subscription","recurrence":"monthly"}"#),
            context: context(financeTool, requestID: "projection-finance", source: "创建 ChatGPT 订阅，每月 99 CNY，2026-10-01"),
            at: date
        )
        XCTAssertEqual(financeResult.state, .applied)

        let budgetTool = "core.budget.set"
        let budgetResult = try engine.executeRegisteredTool(
            call(budgetTool, #"{"amount":"500","currency":"CNY","period":"monthly","month":"2026-09"}"#),
            context: context(budgetTool, requestID: "projection-budget", source: "设置 500 CNY 的 2026-09 月度预算"),
            at: date
        )
        XCTAssertEqual(budgetResult.state, .applied)

        let windowStart = date.addingTimeInterval(-60)
        let windowEnd = date.addingTimeInterval(60)
        let ledgerRead: V2NativeLedgerRead = try engine.nativeQuery(
            V2NativeLedgerRead.self,
            request: .init(id: "core.ledger.recent", limit: 20, from: windowStart, to: windowEnd),
            now: date
        )
        let financeRead: V2NativeFinanceRead = try engine.nativeQuery(
            V2NativeFinanceRead.self,
            request: .init(id: "core.finance.plans", limit: 20),
            now: date
        )
        let budgetRead: V2NativeBudgetProgressRead = try engine.nativeQuery(
            V2NativeBudgetProgressRead.self,
            request: .init(id: "core.budget.queryProgress", limit: 20),
            now: date
        )

        XCTAssertEqual(ledgerRead.entries.count, 1)
        XCTAssertEqual(ledgerRead.entries.first?.amount, "38")
        XCTAssertEqual(financeRead.plans.count, 1)
        XCTAssertEqual(financeRead.plans.first?.title, "ChatGPT")
        XCTAssertEqual(budgetRead.budgets.count, 1)
        XCTAssertEqual(budgetRead.progress.first?.spent, Decimal(38))
    }

    func testDisabledModuleRemovesToolAndBlocksExecution() throws {
        let runtime = V2ModuleRuntime()
        var preferences = runtime.preferences
        preferences.disabled.insert("core.tasks")
        runtime.update(preferences: preferences)
        let engine = V2Engine(moduleRuntime: runtime)
        let toolID = "core.tasks.create"

        XCTAssertNil(engine.registeredToolCatalog().tool(toolID))
        XCTAssertThrowsError(try engine.executeRegisteredTool(
            call(toolID, #"{"title":"不可用任务"}"#),
            context: context(toolID, requestID: "disabled-task", source: "创建不可用任务"),
            at: date
        )) { error in
            XCTAssertEqual(error as? V2ToolSchemaError, .unknownTool(toolID))
        }
        XCTAssertTrue(engine.snapshot.tasks.isEmpty)
        XCTAssertTrue(engine.snapshot.toolOperations.isEmpty)
    }

    func testEnabledFieldDefinitionAddsTypedFillToolAndPersistsAttribute() throws {
        let engine = V2Engine()
        let definition = V2FieldDefinition(
            id: "core.notes.custom.mood", domain: "core.notes", type: .enumID,
            displayName: "心情", enums: ["calm", "tired"]
        )
        _ = try engine.saveExtensionField(definition, expectedRevision: nil, confirmed: true)

        let noteTool = "core.notes.create"
        let noteResult = try engine.executeRegisteredTool(
            call(noteTool, #"{"text":"今天完成了一个小目标","kind":"inspiration"}"#),
            context: context(noteTool, requestID: "field-note", source: "记录今天完成了一个小目标"),
            at: date
        )
        XCTAssertEqual(noteResult.state, .applied)

        let fillTool = "core.notes.custom.mood.fill"
        let catalog = engine.registeredToolCatalog()
        XCTAssertNotNil(catalog.tool(fillTool))
        let fillResult = try engine.executeRegisteredTool(
            call(fillTool, #"{"recordReference":"今天完成了一个小目标","value":"calm"}"#),
            context: context(fillTool, requestID: "field-fill", source: "把今天完成了一个小目标的心情记为 calm"),
            at: date
        )

        XCTAssertEqual(fillResult.state, .applied)
        let attributes = try XCTUnwrap(engine.snapshot.extensionFields.records.first)
        XCTAssertEqual(attributes.domainID, "core.notes")
        XCTAssertEqual(attributes.recordID, engine.snapshot.capture.notes.first?.id)
        XCTAssertEqual(attributes.values, [.init(fieldID: definition.id, value: .enumID("calm"))])
    }
}

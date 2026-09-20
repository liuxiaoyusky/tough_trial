import Foundation
import XCTest
@testable import ToughTrialV2Core

final class V2ToolBoundaryRegressionTests: XCTestCase {
    let date = ISO8601DateFormatter().date(from: "2026-09-10T10:00:00Z")!
    func context(_ tool: String, source: String, intent: V2ToolIntent = .explicitWrite) -> V2ToolExecutionContext {
        .init(traceID: "trace", assistantRequestID: UUID().uuidString, callOrdinal: 0, toolID: tool, submittedText: source, intent: intent)
    }
    func call(_ tool: String, _ json: String) -> V2AgentToolCall { .init(toolID: tool, argumentsJSON: Data(json.utf8)) }

    func testNegatedInstructionsAndUnevidencedBudgetsNeverWrite() throws {
        for source in ["不要创建任务", "我不想记录", "如果创建订阅会怎样", "只是讨论设置预算"] {
            XCTAssertEqual(V2ToolIntentClassifier.classify(source), .discussion)
        }
        let engine = V2Engine()
        let tool = "core.budget.set"
        let result = try engine.executeRegisteredTool(call(tool, #"{"amount":"999","currency":"USD","period":"monthly"}"#), context: context(tool, source: "设置一个预算"))
        XCTAssertEqual(result.state, .needsInformation)
        XCTAssertTrue(engine.snapshot.capture.finance?.budgets.isEmpty ?? true)
    }

    func testChineseCurrencyAndRelativeDateAreGrounded() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let engine = V2Engine(), tool = "core.ledger.createPending"
        let source = "记录今天午饭20美元"
        let good = try engine.executeRegisteredTool(call(tool, #"{"description":"午饭","amount":"20","currency":"USD","date":"2026-09-10"}"#), context: context(tool, source: source), at: date, calendar: calendar)
        XCTAssertEqual(good.state, .applied)
        let inventedDate = try engine.executeRegisteredTool(call(tool, #"{"description":"午饭","amount":"20","currency":"USD","date":"2030-09-10"}"#), context: context(tool, source: source), at: date, calendar: calendar)
        XCTAssertEqual(inventedDate.state, .needsInformation)
        let wrongCurrency = try engine.executeRegisteredTool(call(tool, #"{"description":"午饭","amount":"20","currency":"CNY","date":"2026-09-10"}"#), context: context(tool, source: "记录今天午饭20港元"), at: date, calendar: calendar)
        XCTAssertEqual(wrongCurrency.state, .needsInformation)
        XCTAssertEqual(engine.snapshot.capture.ledger.count, 1)
    }

    func testOneSidedQueryCannotExpandWindow() throws {
        let engine = V2Engine()
        let request = V2NativeQueryRequest(id: "core.trace.recent", from: date.addingTimeInterval(-365 * 86_400))
        XCTAssertThrowsError(try engine.nativeQueryData(request, now: date))
        XCTAssertThrowsError(try engine.moduleRuntime.requireQuery(request, now: date))
    }

    func testDateComponentsCannotSupplyAnInventedAmount() throws {
        let engine = V2Engine(), tool = "core.finance.createPlan"
        for source in ["创建订阅，到期2026-09-10，币种USD", "创建订阅，到期2026年9月10日，币种USD"] {
            let result = try engine.executeRegisteredTool(call(tool, #"{"title":"订阅","kind":"subscription","amount":"10","currency":"USD","dueDate":"2026-09-10","recurrence":"monthly"}"#), context: context(tool, source: source), at: date)
            XCTAssertEqual(result.state, .needsInformation)
        }
        XCTAssertTrue(engine.snapshot.capture.finance?.plans.isEmpty ?? true)
    }

    func testScheduleUndoProtectsExecutionReferences() throws {
        let engine = V2Engine(), tool = "core.tasks.schedule"
        let task = try engine.createTask(title: "已有任务", at: date)
        let proposal = V2ScheduleProposal(summary: "安排任务", operations: [.init(kind: .scheduleTask, targetID: task.id, day: "2026-09-10", startMinute: 10 * 60, durationMinutes: 30)])
        let receipt = try engine.executeRegisteredTool(call(tool, #"{"request":"安排已有任务"}"#), context: context(tool, source: "安排已有任务"), scheduleProposal: proposal, at: date)
        let item = try XCTUnwrap(engine.snapshot.planItems.first)
        _ = try engine.startExecution(taskID: task.id, title: task.title, source: .normal, at: date, createdFromPlanItemID: item.id)
        XCTAssertThrowsError(try engine.undoRegisteredTool(operationID: receipt.operationID))
        XCTAssertEqual(engine.snapshot.planItems.first?.id, item.id)
        XCTAssertEqual(engine.snapshot.executionSegments.first?.createdFromPlanItemID, item.id)
    }

    func testConfirmationRechecksTargetAndFieldSchema() throws {
        let engine = V2Engine(), tool = "core.tasks.create"
        let domain = try engine.createTaskContext(title: "工作", colorName: "blue", at: date)
        let pending = try engine.executeRegisteredTool(call(tool, #"{"title":"发邮件","contextReference":"工作"}"#), context: context(tool, source: "创建发邮件任务"), requiresConfirmation: true)
        try engine.commitHost { snapshot in snapshot.taskContexts[0].archivedAt = Date() }
        XCTAssertThrowsError(try engine.confirmRegisteredTool(operationID: pending.operationID))
        XCTAssertTrue(engine.snapshot.tasks.isEmpty)
        XCTAssertEqual(engine.snapshot.taskContexts.first?.id, domain.id)

        let task = try engine.createTask(title: "目标", at: date)
        let definition = V2FieldDefinition(id: "core.tasks.custom.priority", domain: "core.tasks", type: .enumID, displayName: "优先级", enums: ["low", "high"])
        try engine.saveExtensionField(definition, expectedRevision: nil, confirmed: true)
        let fieldTool = definition.id + ".fill"
        let fieldPending = try engine.executeRegisteredTool(call(fieldTool, #"{"recordReference":"目标","value":"high"}"#), context: context(fieldTool, source: "设置优先级high"), requiresConfirmation: true)
        let updated = V2FieldDefinition(id: definition.id, domain: definition.domain, type: definition.type, displayName: definition.displayName, enums: ["low"], revision: 2)
        try engine.saveExtensionField(updated, expectedRevision: 1, confirmed: true)
        XCTAssertThrowsError(try engine.confirmRegisteredTool(operationID: fieldPending.operationID))
        XCTAssertFalse(engine.snapshot.extensionFields.records.contains { $0.recordID == task.id })
    }

    func testHostCaptureIdentityCreatesAndDeduplicatesOnlyThatSubmission() throws {
        let engine = V2Engine()
        let first = try engine.saveCapture(text: "同样的日记", newSourceID: "plugin:one")
        let retry = try engine.saveCapture(text: "同样的日记", newSourceID: "plugin:one")
        let next = try engine.saveCapture(text: "同样的日记", newSourceID: "plugin:two")
        XCTAssertEqual(first.id, retry.id)
        XCTAssertNotEqual(first.id, next.id)
        XCTAssertEqual(engine.snapshot.capture.entries.count, 2)
        XCTAssertThrowsError(try engine.saveCapture(text: "不同内容", newSourceID: "plugin:one"))
    }
}

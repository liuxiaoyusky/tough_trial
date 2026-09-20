import Foundation
import XCTest
@testable import ToughTrialV2Core

final class V2AssistantScheduleContextTests: XCTestCase {
    func testTodayToolCreationAndUndoUseSharedPlanRecords() throws {
        let engine = V2Engine()
        let call = V2AgentToolCall(toolID: "core.tasks.create", argumentsJSON: Data(#"{"title":"取快递"}"#.utf8))
        let context = V2ToolExecutionContext(traceID: "trace", assistantRequestID: "request", callOrdinal: 0,
            toolID: call.toolID, submittedText: "今天新增任务取快递")
        let receipt = try engine.executeRegisteredTool(call, context: context)
        XCTAssertEqual(engine.snapshot.planItems.count, 1)
        XCTAssertEqual(engine.snapshot.planItems.first?.taskID, engine.snapshot.tasks.first?.id)
        _ = try engine.undoRegisteredTool(operationID: receipt.operationID)
        XCTAssertTrue(engine.snapshot.tasks.isEmpty)
        XCTAssertTrue(engine.snapshot.planItems.isEmpty)
    }

    func testTypoSearchRetainsSelectedReferenceByID() throws {
        let engine = V2Engine()
        let task = try engine.createTask(title: "漫剧课15/35")
        let call = V2AgentToolCall(toolID: "core.tasks.query", argumentsJSON: Data(#"{"query":"慢剧课"}"#.utf8))
        let result = try engine.executeRegisteredTool(call, context: .init(traceID: "trace", assistantRequestID: "request",
            callOrdinal: 0, toolID: call.toolID, assistantContext: .init(sourceTask: .init(id: task.id, title: "旧标题"), referenceState: .available)))
        XCTAssertTrue(result.summary.contains("漫剧课15/35"))
    }

    func testTodayNormalizerIsIdempotentAndRespectsUnscheduledRequest() {
        let proposal = V2ScheduleProposal(summary: "取快递", operations: [.init(kind: .createTask, title: "取快递")])
        let date = Date(timeIntervalSince1970: 1_788_998_400)
        let normalized = V2AssistantScheduleContext.preservingToday(proposal, userText: "今天取快递", at: date, timeZoneIdentifier: "Asia/Hong_Kong")
        XCTAssertEqual(normalized.operations.count, 2)
        XCTAssertEqual(normalized.operations.last?.targetID, normalized.operations.first?.localID)
        XCTAssertEqual(V2AssistantScheduleContext.preservingToday(normalized, userText: "今天取快递", at: date, timeZoneIdentifier: "Asia/Hong_Kong"), normalized)
        XCTAssertEqual(V2AssistantScheduleContext.preservingToday(proposal, userText: "今天想到要取快递，先不要排期", at: date, timeZoneIdentifier: "Asia/Hong_Kong"), proposal)
    }
}

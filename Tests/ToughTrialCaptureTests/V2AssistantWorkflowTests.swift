import XCTest
import ToughTrialV2Core

final class V2AssistantWorkflowTests: XCTestCase {
    func testCheckboxSharesTodayStateAndRoundTripKeepsCreationUndoable() throws {
        let engine = V2Engine()
        let created = try engine.applyScheduleProposal(.init(summary: "创建", operations: [
            .init(kind: .createTask, localID: "a", title: "整理文件"),
            .init(kind: .scheduleTask, targetID: "a", day: "2026-09-11")
        ]), requestID: "create")
        let task = try XCTUnwrap(engine.snapshot.tasks.first)
        let plan = try XCTUnwrap(engine.snapshot.planItems.first)
        try engine.toggleAssistantTaskCompletion(taskID: task.id, planItemID: plan.id)
        XCTAssertEqual(engine.snapshot.tasks.first?.status, .done)
        XCTAssertEqual(engine.snapshot.planItems.first?.status, .completed)
        let reloaded = V2Engine(snapshot: engine.snapshot)
        try reloaded.toggleAssistantTaskCompletion(taskID: task.id, planItemID: plan.id)
        XCTAssertEqual(reloaded.snapshot.tasks.first, task)
        XCTAssertEqual(reloaded.snapshot.planItems.first, plan)
        _ = try reloaded.undoScheduleReceipt(id: created.id)
        XCTAssertTrue(reloaded.snapshot.tasks.isEmpty)
    }

    func testCheckboxDoesNotUndoSubsequentTaskEdits() throws {
        let engine = V2Engine()
        let task = try engine.createTask(title: "原名")
        try engine.toggleAssistantTaskCompletion(taskID: task.id, planItemID: nil)
        _ = try engine.applyScheduleProposal(.init(summary: "改名", operations: [.init(kind: .updateTask, targetID: task.id, title: "新名字")]), requestID: "rename")
        try engine.toggleAssistantTaskCompletion(taskID: task.id, planItemID: nil)
        XCTAssertEqual(engine.snapshot.tasks.first?.title, "新名字")
        XCTAssertEqual(engine.snapshot.tasks.first?.status, .notStarted)
    }

    func testWorkflowsFollowEnabledSchemasRatherThanAdvertisingUnavailableTools() {
        XCTAssertTrue(V2AssistantWorkflows.available(in: .empty).isEmpty)
        let full = V2Engine().registeredToolCatalog()
        XCTAssertTrue(V2AssistantWorkflows.available(in: full).contains { $0.id == "tasks.organize" })
        let withoutSchedule = V2ToolCatalog(revision: "without-schedule", modules: full.modules,
            tools: full.tools.filter { $0.id != "core.tasks.schedule" })
        XCTAssertFalse(V2AssistantWorkflows.available(in: withoutSchedule).contains { $0.id == "tasks.organize" })
    }

    func testScheduleRequestCarriesHostReviewModeIntoProviderPayload() throws {
        let client = V2OpenAICompatibleScheduleClient(configuration: .init(endpoint: URL(string: "https://example.com/v1/chat/completions")!, apiKey: "fixture", model: "fixture"))
        let request = V2ScheduleRequest(userText: "今天要做三件事", snapshot: .empty, referenceDate: Date(), timeZoneIdentifier: "Asia/Hong_Kong", requiresReview: true)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(client.makeURLRequest(for: request).httpBody)) as? [String: Any])
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let content = try XCTUnwrap(messages.last?["content"] as? String)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(content.utf8)) as? [String: Any])
        XCTAssertEqual(payload["requires_review"] as? Bool, true)
    }

    func testCreateAndScheduleOperationsProduceOnePreviewPerTask() {
        let proposal = V2ScheduleProposal(summary: "三件事", operations: (0..<3).flatMap { index in
            [V2ScheduleOperation(kind: .createTask, localID: "item\(index)", title: "任务\(index)", note: "原始细节"),
             V2ScheduleOperation(kind: .scheduleTask, targetID: "item\(index)", day: "2026-09-11")]
        })
        let card = V2AgentScheduleCard(requestID: "fixture", proposal: proposal, baseline: .empty)
        XCTAssertEqual(card.taskPreviews().count, 3)
        XCTAssertEqual(card.taskPreviews().map(\.day), Array(repeating: "2026-09-11", count: 3))
        XCTAssertEqual(card.taskPreviews().map(\.note), Array(repeating: "原始细节", count: 3))
    }
}

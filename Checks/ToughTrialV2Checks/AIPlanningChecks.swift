import Foundation
import ToughTrialV2Core

func checkAIPlanningClients() async throws {
    let calendar = Calendar(identifier: .gregorian)
    let referenceDate = calendar.date(from: DateComponents(year: 2026, month: 7, day: 23))!
    let baseRequest = V2PlanningRequest(
        userPrompt: "这周想跑 10 公里",
        referenceDate: referenceDate,
        timeZoneIdentifier: "Asia/Tokyo",
        tasks: [
            V2PlanningTaskContext(
                id: "task-existing",
                title: "跑步",
                kind: .maintenance,
                status: .notStarted
            ),
        ]
    )

    let deterministic = V2DeterministicPlanningClient()
    let first = try await deterministic.generate(baseRequest)
    guard case .clarification(let clarification) = first else {
        fatalError("Local planning should clarify before drafting")
    }
    require(!clarification.question.isEmpty, "Local clarification should contain a question")

    var confirmedRequest = baseRequest
    confirmedRequest.clarificationResponse = "分三次完成"
    let confirmed = try await deterministic.generate(confirmedRequest)
    guard case .proposal(let localProposal) = confirmed else {
        fatalError("Local planning should return a proposal after clarification")
    }
    require(
        !localProposal.draft.taskChanges.isEmpty && !localProposal.draft.scheduleItems.isEmpty,
        "Local running proposal should include both task breakdown and schedule items"
    )

    let configuration = V2RemotePlanningConfiguration(
        endpoint: URL(string: "https://example.invalid/v1/responses")!,
        apiKey: "test-key",
        model: "test-model"
    )
    let remote = V2RemotePlanningClient(configuration: configuration)
    let urlRequest = try remote.makeURLRequest(for: baseRequest)
    let requestBody = try JSONSerialization.jsonObject(with: urlRequest.httpBody!) as! [String: Any]
    require(requestBody["store"] as? Bool == false, "Remote planning requests must disable response storage")
    let text = requestBody["text"] as! [String: Any]
    let format = text["format"] as! [String: Any]
    require(format["type"] as? String == "json_schema", "Remote planning must request strict JSON schema output")
    require(format["strict"] as? Bool == true, "Remote planning schema must be strict")

    let structured: [String: Any] = [
        "kind": "proposal",
        "message": "我整理成了三次轻量跑步。",
        "suggested_replies": [],
        "title": "本周跑步",
        "summary": "三次完成 10 公里，具体执行由你决定。",
        "decisions": ["不强制具体时刻"],
        "task_changes": [
            [
                "temporary_id": "run-root",
                "title": "本周跑 10 公里",
                "parent_id": NSNull(),
                "context_id": NSNull(),
                "kind": "maintenance",
            ],
        ],
        "schedule_items": [
            [
                "temporary_id": "run-plan-1",
                "day_offset": 1,
                "start_minute": NSNull(),
                "duration_minutes": NSNull(),
                "existing_task_id": NSNull(),
                "proposed_task_id": "run-root",
                "title": "轻松跑",
            ],
        ],
    ]
    let responseData = try planningResponseData(structuredOutput: structured)
    let decoded = try remote.decodeResponse(responseData, request: baseRequest)
    guard case .proposal(let remoteProposal) = decoded else {
        fatalError("Valid structured output should decode as a proposal")
    }
    require(remoteProposal.draft.taskChanges.first?.id == "run-root", "Remote task proposal ID should survive decoding")
    require(
        remoteProposal.draft.scheduleItems.first?.proposedTaskID == "run-root",
        "Remote schedule should preserve its proposed-task reference"
    )

    var invalid = structured
    invalid["schedule_items"] = [
        [
            "temporary_id": "bad-plan",
            "day_offset": 1,
            "start_minute": NSNull(),
            "duration_minutes": NSNull(),
            "existing_task_id": "hallucinated-task",
            "proposed_task_id": NSNull(),
            "title": "无效任务",
        ],
    ]
    do {
        _ = try remote.decodeResponse(
            planningResponseData(structuredOutput: invalid),
            request: baseRequest
        )
        fatalError("Hallucinated task IDs must be rejected")
    } catch V2PlanningClientError.invalidOutput {
        // Expected: model output cannot introduce a durable reference that was not supplied.
    }
}

private func planningResponseData(structuredOutput: [String: Any]) throws -> Data {
    let structuredData = try JSONSerialization.data(withJSONObject: structuredOutput, options: [.sortedKeys])
    let structuredText = String(decoding: structuredData, as: UTF8.self)
    let envelope: [String: Any] = [
        "output": [
            [
                "type": "message",
                "content": [
                    [
                        "type": "output_text",
                        "text": structuredText,
                    ],
                ],
            ],
        ],
    ]
    return try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
}

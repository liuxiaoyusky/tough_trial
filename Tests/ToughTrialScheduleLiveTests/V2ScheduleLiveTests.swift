import XCTest
import ToughTrialV2Core

private struct SyntheticAgentTransport: V2PlanningHTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let result = try await V2URLSessionPlanningTransport().data(for: request)
        if let body = try? JSONSerialization.jsonObject(with: result.0) as? [String: Any],
           let choices = body["choices"] as? [[String: Any]],
           let message = choices.first?["message"] as? [String: Any], let content = message["content"] as? String {
            print("SYNTHETIC_AGENT_CONTENT \(content)")
        }
        return result
    }
}

/// Explicit real-provider check against synthetic in-memory tasks; never uses the person's schedule.
@MainActor
final class V2ScheduleLiveTests: XCTestCase {
    private func configuration() throws -> V2OpenAICompatibleAgentConfiguration {
        let env = ProcessInfo.processInfo.environment
        guard env["TOUGH_TRIAL_REAL_SCHEDULE_TEST"] == "1" else {
            throw XCTSkip("Requires explicit real-provider opt-in and synthetic data only")
        }
        return .init(endpoint: try XCTUnwrap(URL(string: try XCTUnwrap(env["SCHEDULE_AI_ENDPOINT"]))),
                     apiKey: try XCTUnwrap(env["SCHEDULE_AI_API_KEY"]), model: try XCTUnwrap(env["SCHEDULE_AI_MODEL"]))
    }

    func testRemoteBreakdownPreservesSpecificLimit() async throws {
        let client = V2OpenAICompatibleScheduleClient(configuration: try configuration())
        let document = V2ScheduleDocument(id: "live-synthetic-limit", timeZoneIdentifier: "Asia/Shanghai",
            taskContexts: [], tasks: [], planItems: [], executionSegments: [], remoteRequests: [
                .init(id: "request-limit", prompt: "新增准备演示的任务，拆成整理提纲和检查演示两个步骤。先不要安排日期，备注保留总共最多 2 小时。", createdAt: Date())
            ])
        let result = try await V2ScheduleRemoteProcessor.processNext(in: document, using: client)
        let updated = try XCTUnwrap(result)
        let parent = try XCTUnwrap(updated.tasks.first { $0.parentID == nil })
        XCTAssertEqual(updated.tasks.filter { $0.parentID == parent.id }.count, 2)
        XCTAssertTrue(parent.note.contains("2 小时") || parent.note.contains("2小时") || parent.note.contains("两小时") || parent.note.contains("120"), "Concrete two-hour limit must survive in the durable note")
        XCTAssertFalse(parent.note == "保留用户限制")
        XCTAssertTrue(updated.planItems.isEmpty)
        let repeated = try await V2ScheduleRemoteProcessor.processNext(in: updated, using: client)
        XCTAssertNil(repeated)
    }

    func testRealAssistantAnswersAndRoutesSchedule() async throws {
        let client = V2OpenAICompatibleAgentClient(configuration: try configuration(), transport: SyntheticAgentTransport())
        let answer = try await client.respond(.init(userText: "只解释什么是番茄工作法，不要新增或修改日程，不需要联网。",
            conversation: [], observations: []))
        guard case let .answer(text) = answer.action else {
            XCTFail("Read-only conversation should return an answer")
            return
        }
        XCTAssertFalse(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        let action = try await client.respond(.init(userText: "请新增明天16:00写周报的任务，留30分钟，备注先核对数字。",
            conversation: [], observations: []))
        guard case let .schedule(query) = action.action else {
            XCTFail("An explicit schedule edit must reach the schedule client")
            return
        }
        XCTAssertTrue(query.contains("周报") && query.contains("数字") && query.contains("30"))
        print("REAL_ASSISTANT_ROUTING answer=true schedule=true")
    }

    func testRealProviderPreservesCorrectionsAndEditsExistingTasks() async throws {
        let client = V2OpenAICompatibleScheduleClient(configuration: try configuration())
        let engine = V2Engine()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Hong_Kong")!
        let date = Date()
        let untouched = try engine.createTask(title: "不要动的历史任务", note: "保持原样", at: date)
        var conversation: [V2AgentConversationMessage] = []

        func apply(_ text: String, requestID: String) async throws -> V2ScheduleReceipt {
            let baseline = engine.snapshot
            let request = V2ScheduleRequest(userText: text, conversation: conversation,
                snapshot: baseline, referenceDate: date, timeZoneIdentifier: calendar.timeZone.identifier)
            let start = Date()
            let outcome = try await client.generate(request)
            guard case let .proposal(proposal) = outcome else {
                XCTFail("Expected executable proposal for unambiguous request")
                throw NSError(domain: "LiveSchedule", code: 1)
            }
            // This opt-in test creates synthetic inputs only; never log provider headers or credentials.
            print("SYNTHETIC_PROPOSAL request=\(requestID) \(String(decoding: try JSONEncoder().encode(proposal), as: UTF8.self))")
            let receipt = try engine.applyScheduleProposal(proposal, requestID: requestID,
                at: Date(), calendar: calendar, expectedSnapshot: baseline)
            conversation.append(.init(role: .user, text: text))
            conversation.append(.init(role: .assistant, text: receipt.summary))
            print("REAL_SCHEDULE_RESULT request=\(requestID) seconds=\(Date().timeIntervalSince(start)) changes=\(receipt.changes.count)")
            return receipt
        }

        _ = try await apply("帮我新增一个任务，明天下午三点，哦不，四点写周报，留三十分钟。备注要先核对数字，不要修改其他任务。", requestID: "create-report")
        XCTAssertEqual(engine.snapshot.tasks.count, 2)
        let report = try XCTUnwrap(engine.snapshot.tasks.first { $0.id != untouched.id })
        XCTAssertTrue(report.title.contains("周报"))
        XCTAssertTrue(report.note.contains("数字"))
        let plan = try XCTUnwrap(engine.snapshot.planItems.first)
        XCTAssertEqual(plan.taskID, report.id)
        XCTAssertEqual(calendar.component(.hour, from: try XCTUnwrap(plan.startAt)), 16)
        XCTAssertEqual(try XCTUnwrap(plan.endAt).timeIntervalSince(try XCTUnwrap(plan.startAt)), 1800, accuracy: 1)
        XCTAssertTrue(calendar.isDate(plan.date, inSameDayAs: calendar.date(byAdding: .day, value: 1, to: date)!))

        _ = try await apply("把刚才的周报改到后天下午五点，时长不变。不要新增另一个任务。", requestID: "postpone-report")
        XCTAssertEqual(engine.snapshot.tasks.count, 2)
        XCTAssertEqual(engine.snapshot.planItems.count, 1)
        let postponed = try XCTUnwrap(engine.snapshot.planItems.first)
        XCTAssertEqual(postponed.id, plan.id)
        XCTAssertEqual(calendar.component(.hour, from: try XCTUnwrap(postponed.startAt)), 17)
        XCTAssertTrue(calendar.isDate(postponed.date, inSameDayAs: calendar.date(byAdding: .day, value: 2, to: date)!))
        XCTAssertEqual(try XCTUnwrap(postponed.endAt).timeIntervalSince(try XCTUnwrap(postponed.startAt)), 1800, accuracy: 1)

        let completed = try await apply("把写周报标记完成。其他任务不要动。", requestID: "complete-report")
        XCTAssertEqual(engine.snapshot.tasks.first { $0.id == report.id }?.status, .done)
        XCTAssertEqual(engine.snapshot.tasks.first { $0.id == untouched.id }, untouched)
        _ = try engine.undoScheduleReceipt(id: completed.id)
        XCTAssertEqual(engine.snapshot.tasks.first { $0.id == report.id }?.status, .notStarted)

        _ = try await apply("新增准备演示，并拆成收集资料、写提纲两个子任务，不用安排时间。备注是总共只有两小时。", requestID: "breakdown-presentation")
        let presentation = try XCTUnwrap(engine.snapshot.tasks.first { $0.title.contains("准备演示") })
        XCTAssertEqual(engine.snapshot.tasks.filter { $0.parentID == presentation.id }.count, 2)
        XCTAssertTrue(presentation.note.contains("两小时") || presentation.note.contains("2") || presentation.note.contains("120"))
        XCTAssertEqual(engine.snapshot.planItems.count, 1)

        let discussion = try await client.generate(.init(userText: "我还没确定要不要取消周报，只是讨论，不要修改任何任务。",
            conversation: conversation, snapshot: engine.snapshot, referenceDate: date, timeZoneIdentifier: calendar.timeZone.identifier))
        if case .proposal = discussion { XCTFail("Discussion and explicit no-write must not produce commands") }
        _ = try engine.createTask(title: "买牛奶")
        _ = try engine.createTask(title: "买牛奶")
        let ambiguous = try await client.generate(.init(userText: "把买牛奶改到明天", snapshot: engine.snapshot,
            referenceDate: date, timeZoneIdentifier: calendar.timeZone.identifier))
        if case let .proposal(proposal) = ambiguous {
            print("SYNTHETIC_AMBIGUOUS_PROPOSAL \(String(decoding: try JSONEncoder().encode(proposal), as: UTF8.self))")
        }
        if case .proposal = ambiguous { XCTFail("Ambiguous duplicate titles require clarification") }
    }
}

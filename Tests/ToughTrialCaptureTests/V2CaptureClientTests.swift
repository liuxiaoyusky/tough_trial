import Foundation
import XCTest
@testable import ToughTrialV2Core

final class V2CaptureClientTests: XCTestCase {
    func testMixedProposalUsesSourceContractAndNonStreamingRequest() async throws {
        let entry = makeEntry()
        let ledger = V2CaptureCandidate(
            candidateID: "ledger-1",
            kind: .ledger,
            evidence: [.init(blockID: "text-1", quote: "午餐实际花了38元人民币")],
            payload: .init(
                text: "午餐实际花了38元人民币",
                amount: "38",
                currency: "CNY",
                direction: .expense,
                categoryName: "餐饮",
                localDate: "2026-09-09"
            )
        )
        let task = V2CaptureCandidate(
            candidateID: "task-1",
            kind: .task,
            evidence: [.init(blockID: "text-2", quote: "明天把稿子改完")],
            payload: .init(
                text: "明天把稿子改完",
                operations: [
                    .init(kind: .createTask, localID: "new-draft", title: "把稿子改完"),
                    .init(kind: .scheduleTask, targetID: "new-draft", day: "2026-09-10", startMinute: 600, durationMinutes: 60),
                ]
            )
        )
        let proposal = V2CaptureProposal(captureID: entry.id, sourceRevision: entry.revision, items: [ledger, task])
        let responseContent = String(data: try JSONEncoder().encode(proposal), encoding: .utf8)!
        let state = CaptureTransportState()
        let client = makeClient(content: "```json\n\(responseContent)\n```", state: state)

        let result = try await client.extract(entry, categories: [.init(id: "others", name: "Others")])

        XCTAssertEqual(result, proposal)
        let recordedRequest = await state.recordedRequest()
        let request = try XCTUnwrap(recordedRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.timeoutInterval, V2CaptureClientLimits.requestTimeout)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-secret")
        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(object["model"] as? String, "glm-5.3-flash")
        XCTAssertEqual(object["stream"] as? Bool, false)
        let thinking = try XCTUnwrap(object["thinking"] as? [String: Any])
        XCTAssertEqual(thinking["type"] as? String, "enabled")
        XCTAssertEqual(object["reasoning_effort"] as? String, "low")
        XCTAssertFalse(String(decoding: body, as: UTF8.self).contains("test-secret"))

        let messages = try XCTUnwrap(object["messages"] as? [[String: Any]])
        let userContent = try XCTUnwrap(messages.last?["content"] as? String)
        XCTAssertTrue(userContent.contains(entry.id))
        XCTAssertTrue(userContent.contains("source_revision"))
        XCTAssertTrue(userContent.contains("text-1"))
        XCTAssertTrue(userContent.contains("2026-09-09T"))
        XCTAssertTrue(userContent.contains("Asia"))
    }

    func testUnknownPayloadFieldIsRejected() async throws {
        let entry = makeEntry()
        let content = #"{"schemaVersion":1,"captureID":"capture-1","sourceRevision":1,"items":[{"candidateID":"bad","kind":"other","evidence":[{"blockID":"text-1","quote":"午餐实际花了38元人民币"}],"payload":{"text":"午餐实际花了38元人民币","secretField":"do not accept"}}]}"#
        let client = makeClient(content: content)

        do {
            _ = try await client.extract(entry, categories: [])
            XCTFail("expected invalid schema")
        } catch let error as V2CaptureError {
            XCTAssertEqual(error, .invalidSchema)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testStaleSourceIsRejectedBeforeAnyCandidateCanBeUsed() async throws {
        let entry = makeEntry()
        let content = #"{"schemaVersion":1,"captureID":"capture-1","sourceRevision":2,"items":[]}"#
        let client = makeClient(content: content)

        do {
            _ = try await client.extract(entry, categories: [])
            XCTFail("expected stale source")
        } catch let error as V2CaptureError {
            XCTAssertEqual(error, .staleSource)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testNonSuccessResponseUsesSafeErrorWithoutProviderBody() async throws {
        let entry = makeEntry()
        let client = makeClient(content: #"{"error":{"message":"provider secret response"}}"#, statusCode: 500)

        do {
            _ = try await client.extract(entry, categories: [])
            XCTFail("expected provider failure")
        } catch let error as V2CaptureError {
            XCTAssertEqual(error, .providerFailure)
            XCTAssertFalse(String(describing: error).contains("provider secret response"))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testTaskCannotScheduleHistoricalTargetOrMutateExistingTask() async throws {
        let entry = makeEntry()
        let content = #"{"schemaVersion":1,"captureID":"capture-1","sourceRevision":1,"items":[{"candidateID":"task-1","kind":"task","evidence":[{"blockID":"text-2","quote":"明天把稿子改完"}],"payload":{"text":"明天把稿子改完","operations":[{"kind":"createTask","localID":"new-draft","title":"把稿子改完"},{"kind":"scheduleTask","targetID":"existing-task","day":"2026-09-10"}]}}]}"#
        let client = makeClient(content: content)

        do {
            _ = try await client.extract(entry, categories: [])
            XCTFail("expected invalid historical reference")
        } catch let error as V2CaptureError {
            XCTAssertEqual(error, .invalidReference)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testCancellationPassesThrough() async throws {
        let entry = makeEntry()
        let state = CaptureTransportState()
        let client = makeClient(content: "{}", state: state, shouldCancel: true)

        do {
            _ = try await client.extract(entry, categories: [])
            XCTFail("expected cancellation")
        } catch is CancellationError {
            // Expected: cancellation is not converted into a retryable provider error.
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    private func makeEntry() -> V2CaptureEntry {
        V2CaptureEntry(
            id: "capture-1",
            revision: 1,
            recordedAt: ISO8601DateFormatter().date(from: "2026-09-09T08:00:00Z")!,
            timeZoneIdentifier: "Asia/Shanghai",
            blocks: [
                .init(id: "text-1", kind: .text, text: "午餐实际花了38元人民币"),
                .init(id: "text-2", kind: .text, text: "明天把稿子改完"),
            ]
        )
    }

    private func makeClient(
        content: String,
        statusCode: Int = 200,
        state: CaptureTransportState = CaptureTransportState(),
        shouldCancel: Bool = false
    ) -> V2OpenAICompatibleCaptureClient<CaptureTransport> {
        let transport = CaptureTransport(
            state: state,
            responseData: Data("{\"choices\":[{\"message\":{\"content\":\(String(data: try! JSONEncoder().encode(content), encoding: .utf8)!)}}]}".utf8),
            statusCode: statusCode,
            shouldCancel: shouldCancel
        )
        return V2OpenAICompatibleCaptureClient(
            configuration: .init(
                endpoint: URL(string: "https://open.bigmodel.cn/api/coding/paas/v4/chat/completions")!,
                apiKey: "test-secret",
                model: "glm-5.3-flash",
                providerLabel: "test"
            ),
            transport: transport
        )
    }
}

private actor CaptureTransportState {
    var request: URLRequest?

    func record(_ request: URLRequest) {
        self.request = request
    }

    func recordedRequest() -> URLRequest? {
        request
    }
}

private struct CaptureTransport: V2PlanningHTTPTransport {
    let state: CaptureTransportState
    let responseData: Data
    let statusCode: Int
    let shouldCancel: Bool

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        await state.record(request)
        if shouldCancel { throw CancellationError() }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (responseData, response)
    }
}

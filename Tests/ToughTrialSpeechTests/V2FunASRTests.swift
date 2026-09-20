import XCTest
@testable import ToughTrialV2Core

final class V2FunASRTests: XCTestCase {
    func event(_ text: String, id: Int = 1, final: Bool = false, task: String = "one", heartbeat: Bool = false) throws -> V2FunASREvent {
        let data = try JSONSerialization.data(withJSONObject: [
            "header": ["event": "result-generated", "task_id": task],
            "payload": ["output": ["sentence": ["sentence_id": id, "text": text,
                                                     "sentence_end": final, "heartbeat": heartbeat]]]
        ])
        return try JSONDecoder().decode(V2FunASREvent.self, from: data)
    }

    func testCorrectionsReplaceDraftAndFinalCannotBeRegressed() throws {
        var transcript = V2FunASRTranscript(taskID: "one")
        transcript.apply(try event("明天三点"))
        transcript.apply(try event("明天下午三点，不，四点。", final: true))
        transcript.apply(try event("明天三点"))
        transcript.apply(try event("提醒我。", id: 2, final: true))
        XCTAssertEqual(transcript.text, "明天下午三点，不，四点。提醒我。")
        XCTAssertFalse(transcript.hasUnfinishedText)
    }

    func testStaleTasksAndHeartbeatsNeverEnterTranscript() throws {
        var transcript = V2FunASRTranscript(taskID: "one")
        transcript.apply(try event("其他会话", task: "old"))
        transcript.apply(try event("噪音", heartbeat: true))
        transcript.apply(try event("不要取消", id: 2))
        transcript.apply(try event("明天的会", id: 1, final: true))
        XCTAssertEqual(transcript.text, "明天的会不要取消")
        XCTAssertTrue(transcript.hasUnfinishedText)
    }

    func testHeartbeatMayOmitTranscriptFields() throws {
        let data = Data(#"{"header":{"event":"result-generated","task_id":"one"},"payload":{"output":{"sentence":{"heartbeat":true}}}}"#.utf8)
        let event = try JSONDecoder().decode(V2FunASREvent.self, from: data)
        var transcript = V2FunASRTranscript(taskID: "one")
        transcript.apply(event)
        XCTAssertEqual(transcript.text, "")
        XCTAssertFalse(transcript.hasUnfinishedText)
    }

    func testWireCommandsUseSameTaskAndPCM() throws {
        let start = try JSONSerialization.jsonObject(with: Data(V2FunASR.startMessage(taskID: "one").utf8)) as! [String: Any]
        let payload = start["payload"] as! [String: Any]
        XCTAssertEqual(payload["model"] as? String, "fun-asr-realtime")
        XCTAssertEqual((payload["parameters"] as? [String: Any])?["sample_rate"] as? Int, 16000)
        let finish = try JSONSerialization.jsonObject(with: Data(V2FunASR.finishMessage(taskID: "one").utf8)) as! [String: Any]
        XCTAssertEqual((finish["header"] as? [String: String])?["task_id"], "one")
        XCTAssertEqual((finish["header"] as? [String: String])?["action"], "finish-task")
    }
}

import XCTest
@testable import ToughTrialV2Core

final class V2RecordedSpeechTests: XCTestCase {
    func testWholeRecordingRequestDisablesStreamingAndEncodesWAV() throws {
        let pcm = Data([1, 2, 3, 4])
        let request = try V2RecordedSpeechClient.request(pcm: pcm, key: "test-key")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-DashScope-SSE"), "disable")
        let body = try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as! [String: Any]
        XCTAssertEqual(body["model"] as? String, "fun-asr-realtime")
        let input = body["input"] as! [String: Any]
        let messages = input["messages"] as! [[String: Any]]
        let content = messages[0]["content"] as! [[String: String]]
        let encoded = try XCTUnwrap(content[0]["audio"]?.split(separator: ",").last)
        let wav = try XCTUnwrap(Data(base64Encoded: String(encoded)))
        XCTAssertEqual(String(data: wav.prefix(4), encoding: .utf8), "RIFF")
        XCTAssertEqual(String(data: wav[8..<12], encoding: .utf8), "WAVE")
        XCTAssertEqual(wav.suffix(4), pcm)
        XCTAssertEqual(wav.count, 48)
        XCTAssertFalse(String(data: request.httpBody!, encoding: .utf8)!.contains("test-key"))
    }

    func testCompleteTextNotLastSentenceAndErrorsDoNotBecomeText() throws {
        let response = Data(#"{"output":{"text":"第一句。第二句。","sentence":{"text":"第二句。"}}}"#.utf8)
        XCTAssertEqual(try V2RecordedSpeechClient.text(from: response, statusCode: 200), "第一句。第二句。")
        for (data, status) in [(Data(#"{"output":{"text":""}}"#.utf8), 200),
                               (Data(#"{"message":"secret server detail"}"#.utf8), 401),
                               (Data("bad".utf8), 200)] {
            XCTAssertThrowsError(try V2RecordedSpeechClient.text(from: data, statusCode: status))
        }
        XCTAssertThrowsError(try V2RecordedSpeechClient.request(pcm: Data(), key: "test"))
        XCTAssertThrowsError(try V2RecordedSpeechClient.request(pcm: Data([1, 2]), key: ""))
    }
}

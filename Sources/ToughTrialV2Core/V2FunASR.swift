import Foundation

/// Provider wire events stay separate from the assistant's interpreted messages.
public struct V2FunASREvent: Decodable, Sendable {
    public struct Header: Decodable, Sendable {
        public let event: String
        public let task_id: String
        public let error_code: String?
    }
    public struct Payload: Decodable, Sendable {
        public struct Output: Decodable, Sendable {
            public let sentence: Sentence?
        }
        public let output: Output?
    }
    public struct Sentence: Decodable, Sendable {
        public let sentence_id: Int
        public let text: String
        public let sentence_end: Bool
        public let heartbeat: Bool?

        private enum CodingKeys: String, CodingKey { case sentence_id, text, sentence_end, heartbeat }

        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            heartbeat = try values.decodeIfPresent(Bool.self, forKey: .heartbeat)
            if heartbeat == true {
                sentence_id = 0
                text = ""
                sentence_end = false
            } else {
                sentence_id = try values.decode(Int.self, forKey: .sentence_id)
                text = try values.decode(String.self, forKey: .text)
                sentence_end = try values.decode(Bool.self, forKey: .sentence_end)
            }
        }
    }
    public let header: Header
    public let payload: Payload?
}

public struct V2FunASRTranscript: Sendable {
    public let taskID: String
    private var sentences: [Int: V2FunASREvent.Sentence] = [:]

    public init(taskID: String) { self.taskID = taskID }

    public mutating func apply(_ event: V2FunASREvent) {
        guard event.header.task_id == taskID,
              event.header.event == "result-generated",
              let sentence = event.payload?.output?.sentence,
              sentence.heartbeat != true,
              sentences[sentence.sentence_id]?.sentence_end != true else { return }
        sentences[sentence.sentence_id] = sentence
    }

    public var text: String {
        sentences.keys.sorted().compactMap { sentences[$0]?.text }.joined()
    }

    public var hasUnfinishedText: Bool {
        sentences.values.contains { !$0.sentence_end && !$0.text.isEmpty }
    }
}

public enum V2FunASR {
    public static let endpoint = URL(string: "wss://dashscope.aliyuncs.com/api-ws/v1/inference")!
    public static let model = "fun-asr-realtime"

    public static func startMessage(taskID: String) throws -> String {
        try message([
            "header": ["action": "run-task", "task_id": taskID, "streaming": "duplex"],
            "payload": ["task_group": "audio", "task": "asr", "function": "recognition",
                        "model": model, "parameters": ["format": "pcm", "sample_rate": 16000, "heartbeat": true],
                        "input": [:]]
        ])
    }

    public static func finishMessage(taskID: String) throws -> String {
        try message([
            "header": ["action": "finish-task", "task_id": taskID, "streaming": "duplex"],
            "payload": ["input": [:]]
        ])
    }

    private static func message(_ object: [String: Any]) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }
}

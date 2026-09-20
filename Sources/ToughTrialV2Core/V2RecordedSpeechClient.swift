import Foundation

/// One HTTP request after recording; no streaming or externally hosted audio URL.
public enum V2RecordedSpeechClient {
    public static let maximumPCMBytes = 16_000 * 2 * 300

    public static func request(pcm: Data, key: String) throws -> URLRequest {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw Failure.credential }
        let wav = try wavData(pcm: pcm)
        var request = URLRequest(url: URL(string: "https://dashscope.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("disable", forHTTPHeaderField: "X-DashScope-SSE")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": "fun-asr-realtime",
            "input": ["messages": [["role": "user", "content": [["audio": "data:audio/wav;base64," + wav.base64EncodedString()]]]]],
            "parameters": ["format": "wav"], "resources": []
        ])
        return request
    }

    public static func wavData(pcm: Data) throws -> Data {
        guard !pcm.isEmpty, pcm.count <= maximumPCMBytes, pcm.count.isMultiple(of: 2) else { throw Failure.audio }
        var wav = Data("RIFF".utf8)
        func append<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { wav.append(contentsOf: $0) }
        }
        append(UInt32(36 + pcm.count))
        wav.append(Data("WAVEfmt ".utf8))
        append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(16_000)); append(UInt32(32_000)); append(UInt16(2)); append(UInt16(16))
        wav.append(Data("data".utf8)); append(UInt32(pcm.count)); wav.append(pcm)
        return wav
    }

    public static func transcribe(pcm: Data, key: String) async throws -> String {
        let request = try request(pcm: pcm, key: key)
        let (data, response) = try await V2URLSessionPlanningTransport().data(for: request)
        return try text(from: data, statusCode: response.statusCode)
    }

    public static func text(from data: Data, statusCode: Int) throws -> String {
        guard statusCode != 401 && statusCode != 403 else { throw Failure.credential }
        guard (200..<300).contains(statusCode) else { throw Failure.service }
        guard let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let output = envelope["output"] as? [String: Any],
              let text = output["text"] as? String else { throw Failure.service }
        let result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw Failure.empty }
        return result
    }

    public enum Failure: Error, LocalizedError {
        case credential, audio, service, empty
        public var errorDescription: String? {
            switch self {
            case .credential: "请检查百炼语音密钥与访问权限。"
            case .audio: "录音为空或超过单段 5 分钟限制。"
            case .service: "语音服务未完成转写，请稍后重试。"
            case .empty: "没有识别到文字，可以重新录音。"
            }
        }
    }
}

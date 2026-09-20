import Foundation

public struct V2GitHubScheduleLocation: Codable, Equatable, Sendable {
    public var owner: String
    public var repository: String
    public var branch: String
    public var path: String

    public init(owner: String, repository: String, branch: String, path: String) {
        self.owner = owner
        self.repository = repository
        self.branch = branch
        self.path = path
    }
}

public struct V2GitHubScheduleRevision: Codable, Equatable, Sendable {
    public let content: String
    public let sha: String
    public init(content: String, sha: String) { self.content = content; self.sha = sha }
}

public enum V2GitHubScheduleError: Error, Equatable, LocalizedError, Sendable {
    case invalidLocation, missingCredential, invalidResponse, tooLarge, unauthorized, notFound, conflict
    case requestFailed(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidLocation: "请检查 GitHub 仓库、分支和 Markdown 文件路径。"
        case .missingCredential: "请先配置 GitHub 访问凭据。"
        case .invalidResponse: "GitHub 返回的文件信息无法使用。"
        case .tooLarge: "日程文件超过 1 MB，暂时无法同步。"
        case .unauthorized: "GitHub 授权失效或没有该仓库的文件权限。"
        case .notFound: "没有找到指定的仓库、分支或日程文件。"
        case .conflict: "远端文件已有新版本，需要重新合并后上传。"
        case let .requestFailed(status): "GitHub 同步失败（\(status)），本地日程已保留。"
        }
    }
}

/// Contents API writes use the exact blob SHA read by the caller; this client never force-overwrites.
public struct V2GitHubScheduleClient<Transport: V2PlanningHTTPTransport>: Sendable {
    public let location: V2GitHubScheduleLocation
    private let token: String
    private let transport: Transport
    private static var maximumFileBytes: Int { 1_000_000 }

    public init(location: V2GitHubScheduleLocation, token: String, transport: Transport) {
        self.location = location
        self.token = token
        self.transport = transport
    }

    public func read() async throws -> V2GitHubScheduleRevision {
        let (data, response) = try await transport.data(for: makeReadRequest())
        try validateResponse(response, data: data)
        guard let payload = try? JSONDecoder().decode(FilePayload.self, from: data),
              payload.type == "file", payload.encoding == "base64", Self.isSHA(payload.sha),
              let encoded = payload.content,
              let content = Data(base64Encoded: encoded.filter { !$0.isWhitespace }),
              content.count <= Self.maximumFileBytes,
              let text = String(data: content, encoding: .utf8) else {
            throw V2GitHubScheduleError.invalidResponse
        }
        return .init(content: text, sha: payload.sha)
    }

    @discardableResult
    public func write(content: String, expectedSHA: String?) async throws -> V2GitHubScheduleRevision {
        let request = try makeWriteRequest(content: content, expectedSHA: expectedSHA)
        let (data, response) = try await transport.data(for: request)
        try validateResponse(response, data: data)
        guard let payload = try? JSONDecoder().decode(WritePayload.self, from: data),
              Self.isSHA(payload.content.sha) else { throw V2GitHubScheduleError.invalidResponse }
        return .init(content: content, sha: payload.content.sha)
    }

    public func makeReadRequest() throws -> URLRequest {
        var request = try baseRequest()
        var components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "ref", value: location.branch)]
        request.url = components.url
        request.httpMethod = "GET"
        return request
    }

    public func makeWriteRequest(content: String, expectedSHA: String?) throws -> URLRequest {
        guard content.utf8.count <= Self.maximumFileBytes else { throw V2GitHubScheduleError.tooLarge }
        if let expectedSHA, !Self.isSHA(expectedSHA) { throw V2GitHubScheduleError.invalidResponse }
        var request = try baseRequest()
        request.httpMethod = "PUT"
        var body: [String: Any] = ["message": "Update Tough Trial schedule", "branch": location.branch,
                                  "content": Data(content.utf8).base64EncodedString()]
        if let expectedSHA { body["sha"] = expectedSHA }
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return request
    }

    private func baseRequest() throws -> URLRequest {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        func validName(_ value: String) -> Bool {
            !value.isEmpty && value != "." && value != ".." && value.unicodeScalars.allSatisfy(allowed.contains)
        }
        let parts = location.path.split(separator: "/", omittingEmptySubsequences: false)
        guard validName(location.owner), validName(location.repository),
              !location.branch.isEmpty, !location.branch.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              location.branch == location.branch.trimmingCharacters(in: .whitespacesAndNewlines),
              !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
              !location.path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              ["md", "markdown"].contains((location.path as NSString).pathExtension.lowercased()),
              parts.first != ".github", parts.first != ".git" else { throw V2GitHubScheduleError.invalidLocation }
        let credential = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !credential.isEmpty else { throw V2GitHubScheduleError.missingCredential }
        var url = URL(string: "https://api.github.com/repos")!
        for part in [location.owner, location.repository, "contents"] + parts.map(String.init) {
            url.appendPathComponent(part)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        return request
    }

    private func validateResponse(_ response: HTTPURLResponse, data: Data) throws {
        guard response.url?.scheme == "https", response.url?.host == "api.github.com" else {
            throw V2GitHubScheduleError.invalidResponse
        }
        switch response.statusCode {
        case 200, 201: break
        case 401, 403: throw V2GitHubScheduleError.unauthorized
        case 404: throw V2GitHubScheduleError.notFound
        case 409: throw V2GitHubScheduleError.conflict
        default: throw V2GitHubScheduleError.requestFailed(response.statusCode)
        }
        guard data.count <= 2_000_000 else { throw V2GitHubScheduleError.tooLarge }
    }

    private static func isSHA(_ value: String) -> Bool {
        [40, 64].contains(value.count) && value.allSatisfy { $0.isASCII && $0.isHexDigit }
    }

    private struct FilePayload: Decodable {
        let type: String
        let encoding: String
        let sha: String
        let content: String?
    }
    private struct WritePayload: Decodable { let content: Blob }
    private struct Blob: Decodable { let sha: String }
}

public extension V2GitHubScheduleClient where Transport == V2URLSessionPlanningTransport {
    init(location: V2GitHubScheduleLocation, token: String) {
        self.init(location: location, token: token, transport: V2URLSessionPlanningTransport())
    }
}

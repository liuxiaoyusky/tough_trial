import Foundation

public protocol V2WebSearchClient: Sendable {
    func search(query: String, limit: Int) async throws -> [V2WebSearchResult]
}

public protocol V2WebPageReader: Sendable {
    func read(url: URL, maxCharacters: Int) async throws -> String
}

public protocol V2WebHTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct V2WebSearchResult: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let url: URL
    public let snippet: String
    public let siteName: String?

    public init(
        id: String,
        title: String,
        url: URL,
        snippet: String,
        siteName: String? = nil
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.snippet = snippet
        self.siteName = siteName
    }

    public init(
        title: String,
        url: URL,
        snippet: String = "",
        siteName: String? = nil
    ) {
        self.init(
            id: Self.stableID(for: url),
            title: title,
            url: url,
            snippet: snippet,
            siteName: siteName
        )
    }

    public static func stableID(for url: URL) -> String {
        url.absoluteString
    }
}

public enum V2WebToolError: Error, Equatable, LocalizedError, Sendable {
    case invalidQuery
    case invalidLimit
    case unsupportedURL
    case invalidResponse
    case requestFailed(statusCode: Int)
    case unsupportedContentType
    case payloadTooLarge
    case invalidPayload
    case unsupportedMarkup
    case tooManyRedirects

    public var errorDescription: String? {
        switch self {
        case .invalidQuery:
            "网页搜索需要输入关键词。"
        case .invalidLimit:
            "网页工具的数量限制无效。"
        case .unsupportedURL:
            "网页地址不是允许访问的公开 HTTP(S) 地址。"
        case .invalidResponse:
            "网页服务没有返回 HTTP 响应。"
        case let .requestFailed(statusCode):
            "网页请求失败（\(statusCode)）。"
        case .unsupportedContentType:
            "网页响应不是支持的 HTML 或文本内容。"
        case .payloadTooLarge:
            "网页响应超过读取上限。"
        case .invalidPayload:
            "网页内容无法按 UTF-8 文本读取。"
        case .unsupportedMarkup:
            "搜索页面的标记结构无法识别。"
        case .tooManyRedirects:
            "网页重定向次数超过上限。"
        }
    }
}

public struct V2DuckDuckGoSearchClient<Transport: V2WebHTTPTransport>: V2WebSearchClient {
    private let transport: Transport

    public init(transport: Transport) {
        self.transport = transport
    }

    public func search(query: String, limit: Int) async throws -> [V2WebSearchResult] {
        guard limit >= 0 else {
            throw V2WebToolError.invalidLimit
        }

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            throw V2WebToolError.invalidQuery
        }

        let effectiveLimit = min(limit, V2WebRequestBounds.maxSearchResults)
        guard let endpoint = URL(string: "https://html.duckduckgo.com/html/") else {
            throw V2WebToolError.invalidResponse
        }
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "q", value: trimmedQuery)]
        guard let url = components?.url else {
            throw V2WebToolError.invalidQuery
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = V2WebRequestBounds.requestTimeout
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        request.setValue("ToughTrial/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await transport.data(for: request)
        try V2WebResponseValidation.validate(response: response)
        guard (200..<300).contains(response.statusCode) else {
            throw V2WebToolError.requestFailed(statusCode: response.statusCode)
        }
        try V2WebPayloadBounds.validate(data: data)
        guard try V2WebContentType.kind(for: response, data: data) == .html else {
            throw V2WebToolError.unsupportedContentType
        }

        return try V2DuckDuckGoHTMLParser.parse(data, limit: effectiveLimit)
    }
}

public extension V2DuckDuckGoSearchClient where Transport == V2URLSessionWebTransport {
    init() {
        self.init(transport: V2URLSessionWebTransport())
    }
}

public struct V2URLSessionWebPageReader<Transport: V2WebHTTPTransport>: V2WebPageReader {
    private let transport: Transport

    public init(transport: Transport) {
        self.transport = transport
    }

    public func read(url: URL, maxCharacters: Int) async throws -> String {
        guard maxCharacters >= 0 else {
            throw V2WebToolError.invalidLimit
        }
        try V2WebURLPolicy.validate(url)

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = V2WebRequestBounds.requestTimeout
        request.setValue("text/html, text/plain;q=0.9", forHTTPHeaderField: "Accept")
        request.setValue("ToughTrial/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await transport.data(for: request)
        try V2WebResponseValidation.validate(response: response)
        guard (200..<300).contains(response.statusCode) else {
            throw V2WebToolError.requestFailed(statusCode: response.statusCode)
        }
        try V2WebPayloadBounds.validate(data: data)

        let kind = try V2WebContentType.kind(for: response, data: data)
        let text: String
        switch kind {
        case .html:
            text = try V2WebHTMLTextExtractor.extract(from: data)
        case .plain:
            guard let decoded = String(data: data, encoding: .utf8) else {
                throw V2WebToolError.invalidPayload
            }
            text = V2WebHTMLTextExtractor.normalizeWhitespace(decoded)
        }

        let outputLimit = min(maxCharacters, V2WebRequestBounds.maxPageCharacters)
        return String(text.prefix(outputLimit))
    }
}

public extension V2URLSessionWebPageReader where Transport == V2URLSessionWebTransport {
    init() {
        self.init(transport: V2URLSessionWebTransport())
    }
}

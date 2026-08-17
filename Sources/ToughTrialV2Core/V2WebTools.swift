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
        }
    }
}

public struct V2URLSessionWebTransport: V2WebHTTPTransport {
    public init() {}

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw V2WebToolError.invalidResponse
        }
        return (data, httpResponse)
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

        let effectiveLimit = min(limit, V2WebToolBounds.maxSearchResults)
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
        request.timeoutInterval = V2WebToolBounds.requestTimeout
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        request.setValue("ToughTrial/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await transport.data(for: request)
        try V2WebResponseValidation.validate(response: response)
        guard (200..<300).contains(response.statusCode) else {
            throw V2WebToolError.requestFailed(statusCode: response.statusCode)
        }
        guard data.count <= V2WebToolBounds.maxPayloadBytes else {
            throw V2WebToolError.payloadTooLarge
        }
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
        request.timeoutInterval = V2WebToolBounds.requestTimeout
        request.setValue("text/html, text/plain;q=0.9", forHTTPHeaderField: "Accept")
        request.setValue("ToughTrial/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await transport.data(for: request)
        try V2WebResponseValidation.validate(response: response)
        guard (200..<300).contains(response.statusCode) else {
            throw V2WebToolError.requestFailed(statusCode: response.statusCode)
        }
        guard data.count <= V2WebToolBounds.maxPayloadBytes else {
            throw V2WebToolError.payloadTooLarge
        }

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

        let outputLimit = min(maxCharacters, V2WebToolBounds.maxPageCharacters)
        return String(text.prefix(outputLimit))
    }
}

public extension V2URLSessionWebPageReader where Transport == V2URLSessionWebTransport {
    init() {
        self.init(transport: V2URLSessionWebTransport())
    }
}

public enum V2DuckDuckGoHTMLParser {
    public static func parse(_ data: Data, limit: Int) throws -> [V2WebSearchResult] {
        guard limit >= 0 else {
            throw V2WebToolError.invalidLimit
        }
        let effectiveLimit = min(limit, V2WebToolBounds.maxSearchResults)
        guard effectiveLimit > 0 else {
            return []
        }
        guard let html = String(data: data, encoding: .utf8) else {
            throw V2WebToolError.invalidPayload
        }

        let anchors = try findAnchors(in: html)
        let titleAnchors = anchors.filter { $0.classes.contains("result__a") }
        guard !titleAnchors.isEmpty else {
            throw V2WebToolError.unsupportedMarkup
        }

        var results: [V2WebSearchResult] = []
        results.reserveCapacity(min(titleAnchors.count, effectiveLimit))
        for (index, titleAnchor) in titleAnchors.enumerated() {
            guard results.count < effectiveLimit else {
                break
            }
            let nextTitleStart = titleAnchors.dropFirst(index + 1).first?.start
            let snippet = anchors.first {
                $0.classes.contains("result__snippet")
                    && $0.start >= titleAnchor.end
                    && (nextTitleStart == nil || $0.start < nextTitleStart!)
            }?.text ?? ""

            guard let rawURL = titleAnchor.href?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !rawURL.isEmpty else {
                throw V2WebToolError.unsupportedURL
            }
            let url = try destinationURL(from: rawURL)
            try V2WebURLPolicy.validate(url)

            let title = titleAnchor.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else {
                throw V2WebToolError.unsupportedMarkup
            }
            results.append(
                V2WebSearchResult(
                    title: title,
                    url: url,
                    snippet: snippet,
                    siteName: siteName(for: url)
                )
            )
        }
        return results
    }
}

private enum V2WebToolBounds {
    static let maxSearchResults = 8
    static let maxPageCharacters = 24_000
    static let maxPayloadBytes = 1_048_576
    static let requestTimeout: TimeInterval = 15
}

private enum V2WebURLPolicy {
    static func validate(_ url: URL) throws {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw V2WebToolError.unsupportedURL
        }
        guard let host = url.host?.lowercased(), !host.isEmpty else {
            throw V2WebToolError.unsupportedURL
        }
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           components.user != nil || components.password != nil {
            throw V2WebToolError.unsupportedURL
        }

        let normalizedHost = host.hasSuffix(".") ? String(host.dropLast()) : host
        guard !isUnsafeHost(normalizedHost) else {
            throw V2WebToolError.unsupportedURL
        }
    }

    private static func isUnsafeHost(_ host: String) -> Bool {
        if host == "localhost"
            || host.hasSuffix(".localhost")
            || host == "local"
            || host.hasSuffix(".local") {
            return true
        }
        if let address = parseIPv4(host) {
            return isUnsafeIPv4(address)
        }
        if looksLikeNumericIPAddress(host) {
            return true
        }
        if host.contains(":") {
            return isUnsafeIPv6(host)
        }
        return false
    }

    private static func looksLikeNumericIPAddress(_ host: String) -> Bool {
        let pieces = host.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count <= 4 else {
            return false
        }
        let decimal = pieces.allSatisfy { piece in
            !piece.isEmpty && piece.unicodeScalars.allSatisfy { scalar in
                (48...57).contains(scalar.value)
            }
        }
        let hexadecimal = pieces.contains { piece in
            piece.lowercased().hasPrefix("0x")
        }
        return decimal || hexadecimal
    }

    private static func parseIPv4(_ host: String) -> [UInt8]? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else {
            return nil
        }
        var values: [UInt8] = []
        values.reserveCapacity(4)
        for part in parts {
            guard !part.isEmpty,
                  !(part.count > 1 && part.first == "0"),
                  part.unicodeScalars.allSatisfy({ (48...57).contains($0.value) }),
                  let value = UInt16(part),
                  value <= UInt16(UInt8.max) else {
                return nil
            }
            values.append(UInt8(value))
        }
        return values
    }

    private static func isUnsafeIPv4(_ address: [UInt8]) -> Bool {
        let first = address[0]
        let second = address[1]
        if first == 0 || first == 10 || first == 127 || first >= 224 {
            return true
        }
        if first == 100 && (64...127).contains(second) {
            return true
        }
        if first == 169 && second == 254 {
            return true
        }
        if first == 172 && (16...31).contains(second) {
            return true
        }
        if first == 192 && (second == 0 || second == 168) {
            return true
        }
        if first == 198 && (18...19).contains(second) {
            return true
        }
        if first == 198 && second == 51 && address[2] == 100 {
            return true
        }
        if first == 203 && second == 0 && address[2] == 113 {
            return true
        }
        return false
    }

    private static func isUnsafeIPv6(_ host: String) -> Bool {
        guard let groups = parseIPv6(host) else {
            return true
        }
        let allZero = groups.allSatisfy { $0 == 0 }
        let loopback = groups.dropLast().allSatisfy { $0 == 0 } && groups.last == 1
        let first = groups[0]
        let linkLocal = (0xfe80...0xfebf).contains(first)
        let uniqueLocal = (0xfc00...0xfdff).contains(first)
        let siteLocal = (0xfec0...0xfeff).contains(first)
        let multicast = (0xff00...0xffff).contains(first)
        if allZero || loopback || linkLocal || uniqueLocal || siteLocal || multicast {
            return true
        }

        if groups[0..<5].allSatisfy({ $0 == 0 }) && groups[5] == 0xffff {
            return isUnsafeIPv4([
                UInt8(groups[6] >> 8),
                UInt8(groups[6] & 0xff),
                UInt8(groups[7] >> 8),
                UInt8(groups[7] & 0xff),
            ])
        }
        if groups[0..<6].allSatisfy({ $0 == 0 }) {
            return isUnsafeIPv4([
                UInt8(groups[6] >> 8),
                UInt8(groups[6] & 0xff),
                UInt8(groups[7] >> 8),
                UInt8(groups[7] & 0xff),
            ])
        }
        return false
    }

    private static func parseIPv6(_ host: String) -> [UInt16]? {
        var address = host
        if address.hasPrefix("[") && address.hasSuffix("]") {
            address.removeFirst()
            address.removeLast()
        }
        if let zoneStart = address.firstIndex(of: "%") {
            address = String(address[..<zoneStart])
        }
        guard !address.isEmpty else {
            return nil
        }

        let sections = address.components(separatedBy: "::")
        guard sections.count <= 2 else {
            return nil
        }
        if sections.count == 2 {
            guard let left = parseIPv6Part(sections[0]),
                  let right = parseIPv6Part(sections[1]),
                  left.count + right.count < 8 else {
                return nil
            }
            return left + Array(repeating: UInt16(0), count: 8 - left.count - right.count) + right
        }
        guard let complete = parseIPv6Part(address), complete.count == 8 else {
            return nil
        }
        return complete
    }

    private static func parseIPv6Part(_ part: String) -> [UInt16]? {
        guard !part.isEmpty else {
            return []
        }
        let pieces = part.split(separator: ":", omittingEmptySubsequences: false)
        guard !pieces.contains(where: { $0.isEmpty }) else {
            return nil
        }
        var groups: [UInt16] = []
        for (index, piece) in pieces.enumerated() {
            if piece.contains(".") {
                guard index == pieces.count - 1,
                      let ipv4 = parseIPv4(String(piece)) else {
                    return nil
                }
                groups.append((UInt16(ipv4[0]) << 8) | UInt16(ipv4[1]))
                groups.append((UInt16(ipv4[2]) << 8) | UInt16(ipv4[3]))
                continue
            }
            guard (1...4).contains(piece.count),
                  piece.unicodeScalars.allSatisfy({
                      (48...57).contains($0.value)
                          || (65...70).contains($0.value)
                          || (97...102).contains($0.value)
                  }),
                  let value = UInt16(String(piece), radix: 16) else {
                return nil
            }
            groups.append(value)
        }
        return groups
    }
}

private enum V2WebResponseValidation {
    static func validate(response: HTTPURLResponse) throws {
        guard let responseURL = response.url else {
            throw V2WebToolError.invalidResponse
        }
        try V2WebURLPolicy.validate(responseURL)
        guard (300..<400).contains(response.statusCode) else {
            return
        }
        guard let location = response.value(forHTTPHeaderField: "Location"),
              let destination = URL(string: location, relativeTo: responseURL)?.absoluteURL else {
            return
        }
        try V2WebURLPolicy.validate(destination)
    }
}

private enum V2WebContentType {
    enum Kind {
        case html
        case plain
    }

    static func kind(for response: HTTPURLResponse, data: Data) throws -> Kind {
        if let contentType = response.value(forHTTPHeaderField: "Content-Type") {
            let mimeType = contentType
                .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true)
                .first
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                ?? ""
            if mimeType == "text/html" || mimeType == "application/xhtml+xml" {
                return .html
            }
            if mimeType.hasPrefix("text/") {
                return .plain
            }
            throw V2WebToolError.unsupportedContentType
        }

        guard let text = String(data: data, encoding: .utf8) else {
            throw V2WebToolError.invalidPayload
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("<") {
            return .html
        }
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            throw V2WebToolError.unsupportedContentType
        }
        return .plain
    }
}

private enum V2WebHTMLTextExtractor {
    static func extract(from data: Data) throws -> String {
        guard let html = String(data: data, encoding: .utf8) else {
            throw V2WebToolError.invalidPayload
        }
        var text = replacingMatches(
            in: html,
            pattern: "(?is)<script\\b[^>]*>.*?(?:</script\\s*>|$)",
            with: " "
        )
        text = replacingMatches(
            in: text,
            pattern: "(?is)<style\\b[^>]*>.*?(?:</style\\s*>|$)",
            with: " "
        )
        text = replacingMatches(in: text, pattern: "(?is)<!--.*?-->", with: " ")
        text = replacingMatches(in: text, pattern: "(?is)<[^>]*>", with: " ")
        return normalizeWhitespace(decodeEntities(text))
    }

    static func normalizeWhitespace(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    static func stripTags(_ text: String) -> String {
        replacingMatches(in: text, pattern: "(?is)<[^>]*>", with: " ")
    }

    static func decodeEntities(_ text: String) -> String {
        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            guard text[index] == "&" else {
                result.append(text[index])
                index = text.index(after: index)
                continue
            }

            let entityStart = text.index(after: index)
            guard let semicolon = text[entityStart...].firstIndex(of: ";"),
                  text.distance(from: index, to: semicolon) <= 32 else {
                result.append(text[index])
                index = entityStart
                continue
            }
            let entity = String(text[entityStart..<semicolon])
            guard let decoded = decodeEntity(entity) else {
                result.append(text[index])
                index = entityStart
                continue
            }
            result.append(contentsOf: decoded)
            index = text.index(after: semicolon)
        }
        return result
    }

    private static func decodeEntity(_ entity: String) -> String? {
        switch entity.lowercased() {
        case "amp":
            return "&"
        case "lt":
            return "<"
        case "gt":
            return ">"
        case "quot":
            return "\""
        case "apos", "#39":
            return "'"
        case "nbsp":
            return " "
        default:
            break
        }

        let value: UInt32?
        if entity.lowercased().hasPrefix("#x") {
            value = UInt32(entity.dropFirst(2), radix: 16)
        } else if entity.hasPrefix("#") {
            value = UInt32(entity.dropFirst(), radix: 10)
        } else {
            value = nil
        }
        guard let value, let scalar = UnicodeScalar(value) else {
            return nil
        }
        return String(scalar)
    }

    private static func replacingMatches(in text: String, pattern: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: replacement)
    }
}

private extension V2DuckDuckGoHTMLParser {
    struct Anchor {
        var classes: Set<String>
        var href: String?
        var text: String
        var start: Int
        var end: Int
    }

    static func findAnchors(in html: String) throws -> [Anchor] {
        guard let openingRegex = try? NSRegularExpression(pattern: "(?is)<a\\b[^>]*>"),
              let closingRegex = try? NSRegularExpression(pattern: "(?is)</a\\s*>") else {
            throw V2WebToolError.unsupportedMarkup
        }
        let documentRange = NSRange(html.startIndex..<html.endIndex, in: html)
        var anchors: [Anchor] = []
        for opening in openingRegex.matches(in: html, range: documentRange) {
            let openingEnd = NSMaxRange(opening.range)
            guard openingEnd < documentRange.length,
                  let closing = closingRegex.firstMatch(
                      in: html,
                      range: NSRange(location: openingEnd, length: documentRange.length - openingEnd)
                  ),
                  let contentRange = Range(
                      NSRange(
                          location: openingEnd,
                          length: closing.range.location - openingEnd
                      ),
                      in: html
                  ),
                  let openingRange = Range(opening.range, in: html) else {
                continue
            }

            let openingTag = String(html[openingRange])
            let classValue = attribute(named: "class", in: openingTag) ?? ""
            let classes = Set(
                V2WebHTMLTextExtractor
                    .decodeEntities(classValue)
                    .split(whereSeparator: { $0.isWhitespace })
                    .map(String.init)
            )
            let href = attribute(named: "href", in: openingTag)
                .map { V2WebHTMLTextExtractor.decodeEntities($0) }
            let text = V2WebHTMLTextExtractor.normalizeWhitespace(
                V2WebHTMLTextExtractor.decodeEntities(
                    V2WebHTMLTextExtractor.stripTags(String(html[contentRange]))
                )
            )
            anchors.append(
                Anchor(
                    classes: classes,
                    href: href,
                    text: text,
                    start: opening.range.location,
                    end: NSMaxRange(closing.range)
                )
            )
        }
        return anchors.sorted { $0.start < $1.start }
    }

    static func attribute(named name: String, in tag: String) -> String? {
        let pattern = "(?is)\\b\(name)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                  in: tag,
                  range: NSRange(tag.startIndex..<tag.endIndex, in: tag)
              ) else {
            return nil
        }
        for captureIndex in 1...3 {
            let capture = match.range(at: captureIndex)
            if capture.location != NSNotFound,
               let range = Range(capture, in: tag) {
                return String(tag[range])
            }
        }
        return nil
    }

    static func destinationURL(from rawURL: String) throws -> URL {
        let base = URL(string: "https://duckduckgo.com")!
        guard let candidate = URL(string: rawURL, relativeTo: base)?.absoluteURL else {
            throw V2WebToolError.unsupportedURL
        }
        guard isDuckDuckGoRedirect(candidate) else {
            return candidate
        }
        guard let components = URLComponents(url: candidate, resolvingAgainstBaseURL: false),
              let destination = components.queryItems?.first(where: { $0.name == "uddg" })?.value else {
            throw V2WebToolError.unsupportedURL
        }

        var decodedDestination = destination
        for _ in 0..<2 {
            guard let next = decodedDestination.removingPercentEncoding,
                  next != decodedDestination else {
                break
            }
            decodedDestination = next
        }
        guard let destinationURL = URL(string: decodedDestination) else {
            throw V2WebToolError.unsupportedURL
        }
        return destinationURL
    }

    static func isDuckDuckGoRedirect(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(),
              host == "duckduckgo.com" || host.hasSuffix(".duckduckgo.com") else {
            return false
        }
        return url.path == "/l" || url.path == "/l/" || url.path.hasPrefix("/l/")
    }

    static func siteName(for url: URL) -> String? {
        guard let host = url.host?.lowercased(), !host.isEmpty else {
            return nil
        }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

import Foundation

public enum V2WebPayloadBounds {
    public static let maxBytes = 1_048_576

    public static func validate(data: Data) throws {
        guard data.count <= maxBytes else {
            throw V2WebToolError.payloadTooLarge
        }
    }

    public static func validateContentLength(_ response: HTTPURLResponse) throws {
        if response.expectedContentLength > Int64(maxBytes) {
            throw V2WebToolError.payloadTooLarge
        }
        guard let header = response.value(forHTTPHeaderField: "Content-Length"),
              let contentLength = Int64(header.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return
        }
        if contentLength > Int64(maxBytes) {
            throw V2WebToolError.payloadTooLarge
        }
    }
}

public struct V2WebBoundedDataCollector: Sendable {
    private let limit: Int
    private var buffer = Data()

    public init(limit: Int = V2WebPayloadBounds.maxBytes) {
        self.limit = max(0, limit)
    }

    public var data: Data {
        buffer
    }

    public var count: Int {
        buffer.count
    }

    public mutating func append(_ chunk: Data) throws {
        guard chunk.count <= limit - buffer.count else {
            throw V2WebToolError.payloadTooLarge
        }
        buffer.append(chunk)
    }
}

public enum V2WebRedirectDecision: Equatable, Sendable {
    case follow
    case reject(V2WebToolError)
}

public struct V2WebRedirectPolicy: Sendable {
    public let maxRedirects: Int

    public init(maxRedirects: Int = 5) {
        self.maxRedirects = max(0, maxRedirects)
    }

    public func decide(nextURL: URL?, redirectCount: Int) -> V2WebRedirectDecision {
        guard let nextURL else {
            return .reject(.unsupportedURL)
        }
        do {
            try V2WebURLPolicy.validate(nextURL)
        } catch let error as V2WebToolError {
            return .reject(error)
        } catch {
            return .reject(.unsupportedURL)
        }
        guard redirectCount > 0, redirectCount <= maxRedirects else {
            return .reject(.tooManyRedirects)
        }
        return .follow
    }
}

public struct V2URLSessionWebTransport: V2WebHTTPTransport {
    private let redirectPolicy: V2WebRedirectPolicy

    public init(maxRedirects: Int = 5) {
        redirectPolicy = V2WebRedirectPolicy(maxRedirects: maxRedirects)
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let requestURL = request.url else {
            throw V2WebToolError.unsupportedURL
        }
        try V2WebURLPolicy.validate(requestURL)
        let delegate = V2BoundedURLSessionDelegate(redirectPolicy: redirectPolicy)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        let task = session.dataTask(with: request)
        defer { session.finishTasksAndInvalidate() }
        return try await delegate.perform(task: task)
    }
}

enum V2WebRequestBounds {
    static let maxSearchResults = 8
    static let maxPageCharacters = 24_000
    static let requestTimeout: TimeInterval = 15
}

enum V2WebURLPolicy {
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

enum V2WebResponseValidation {
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

private final class V2BoundedURLSessionDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let redirectPolicy: V2WebRedirectPolicy
    private let lock = NSLock()
    private var continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>?
    private var task: URLSessionDataTask?
    private var response: HTTPURLResponse?
    private var collector = V2WebBoundedDataCollector()
    private var redirectCount = 0
    private var finished = false
    private var cancelled = false

    init(redirectPolicy: V2WebRedirectPolicy) {
        self.redirectPolicy = redirectPolicy
    }

    func perform(task: URLSessionDataTask) async throws -> (Data, HTTPURLResponse) {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>) in
                install(continuation: continuation, task: task)
            }
        } onCancel: {
            cancel()
        }
    }

    private func install(
        continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>,
        task: URLSessionDataTask
    ) {
        lock.lock()
        if cancelled {
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return
        }
        self.continuation = continuation
        self.task = task
        lock.unlock()
        task.resume()
    }

    private func cancel() {
        var continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>?
        var task: URLSessionDataTask?
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        cancelled = true
        finished = true
        continuation = self.continuation
        self.continuation = nil
        task = self.task
        lock.unlock()
        task?.cancel()
        continuation?.resume(throwing: CancellationError())
    }

    private func fail(_ error: Error) {
        var continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>?
        var task: URLSessionDataTask?
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        continuation = self.continuation
        self.continuation = nil
        task = self.task
        lock.unlock()
        task?.cancel()
        continuation?.resume(throwing: error)
    }

    private func append(_ data: Data) throws {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else {
            return
        }
        try collector.append(data)
    }

    private func nextRedirectCount() -> Int {
        lock.lock()
        redirectCount += 1
        let count = redirectCount
        lock.unlock()
        return count
    }

    private func finishSuccessfully() {
        var continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>?
        var result: (Data, HTTPURLResponse)?
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        guard let response else {
            lock.unlock()
            fail(V2WebToolError.invalidResponse)
            return
        }
        finished = true
        continuation = self.continuation
        self.continuation = nil
        result = (collector.data, response)
        lock.unlock()
        if let continuation, let result {
            continuation.resume(returning: result)
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @Sendable @escaping (URLRequest?) -> Void
    ) {
        let decision = redirectPolicy.decide(
            nextURL: request.url,
            redirectCount: nextRedirectCount()
        )
        switch decision {
        case .follow:
            completionHandler(request)
        case let .reject(error):
            fail(error)
            completionHandler(nil)
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @Sendable @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let httpResponse = response as? HTTPURLResponse else {
            fail(V2WebToolError.invalidResponse)
            completionHandler(.cancel)
            return
        }
        do {
            try V2WebPayloadBounds.validateContentLength(httpResponse)
        } catch {
            fail(error)
            completionHandler(.cancel)
            return
        }
        lock.lock()
        self.response = httpResponse
        lock.unlock()
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        do {
            try append(data)
        } catch {
            fail(error)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            fail(error)
        } else {
            finishSuccessfully()
        }
    }
}

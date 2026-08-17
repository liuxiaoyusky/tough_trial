import Foundation
import ToughTrialV2Core

func checkDuckDuckGoResultsBecomeSources() throws {
    let html = """
    <a class="result__a" href="https://example.com/a?one=1&amp;two=2">示例 &amp; 标题</a>
    <a class="result__snippet">这是 &lt;摘要&gt;，&#x4E2D;&#25991;</a>
    """

    let results = try V2DuckDuckGoHTMLParser.parse(Data(html.utf8), limit: 5)
    require(results.count == 1, "One result should be parsed")
    require(
        results[0].url.absoluteString == "https://example.com/a?one=1&two=2",
        "Result URL should decode HTML entities"
    )
    require(results[0].title == "示例 & 标题", "Result title should decode HTML entities")
    require(results[0].snippet == "这是 <摘要>，中文", "Result snippet should decode numeric entities")
    require(results[0].siteName == "example.com", "Result should expose its site name")

    let repeated = try V2DuckDuckGoHTMLParser.parse(Data(html.utf8), limit: 5)
    require(results[0].id == repeated[0].id, "Result IDs should be stable across parses")
}

func checkDuckDuckGoRedirectsResolveToDestination() throws {
    let html = """
    <a class="result__a" href="https://duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.com%2Farticle%3Fq%3Done&amp;rut=fixture">标题</a>
    <a class="result__snippet">摘要</a>
    """

    let results = try V2DuckDuckGoHTMLParser.parse(Data(html.utf8), limit: 5)
    require(results.count == 1, "A redirect-wrapped result should be parsed")
    require(
        results[0].url.absoluteString == "https://example.com/article?q=one",
        "DuckDuckGo redirect wrappers should resolve to their destination"
    )
    require(!results[0].url.host!.contains("duckduckgo"), "Search results must not expose the redirect wrapper")
}

func checkDuckDuckGoRedirectRejectsNonHTTPDestination() throws {
    let html = """
    <a class="result__a" href="https://duckduckgo.com/l/?uddg=file%3A%2F%2F%2Fetc%2Fpasswd">不安全</a>
    <a class="result__snippet">摘要</a>
    """

    do {
        _ = try V2DuckDuckGoHTMLParser.parse(Data(html.utf8), limit: 5)
        fatalError("Redirects to non-HTTP(S) destinations must fail")
    } catch V2WebToolError.unsupportedURL {
        // Expected: result URLs are limited to public HTTP(S) pages.
    }
}

func checkWebRedirectPolicyValidatesEveryDestination() throws {
    let policy = V2WebRedirectPolicy(maxRedirects: 2)
    let safeURL = URL(string: "https://example.com/next")!
    require(
        policy.decide(nextURL: safeURL, redirectCount: 1) == .follow,
        "A public redirect within the limit should be followed"
    )
    require(
        policy.decide(nextURL: URL(string: "http://127.0.0.1/private")!, redirectCount: 1)
            == .reject(.unsupportedURL),
        "A redirect to loopback must be rejected before following"
    )
    require(
        policy.decide(nextURL: URL(string: "file:///etc/passwd")!, redirectCount: 1)
            == .reject(.unsupportedURL),
        "A redirect to a non-HTTP(S) URL must be rejected before following"
    )
    require(
        policy.decide(nextURL: safeURL, redirectCount: 3) == .reject(.tooManyRedirects),
        "A redirect beyond the maximum must be rejected"
    )
}

func checkDuckDuckGoParserFailsUnsupportedMarkup() throws {
    do {
        _ = try V2DuckDuckGoHTMLParser.parse(
            Data("<html><body>没有搜索结果标记</body></html>".utf8),
            limit: 5
        )
        fatalError("Unsupported result markup must fail visibly")
    } catch V2WebToolError.unsupportedMarkup {
        // Expected: the parser must not invent sources from unknown markup.
    }
}

func checkDuckDuckGoParserRejectsLookalikeAttributes() throws {
    let html = """
    <a data-class="result__a" data-href="https://example.com/fabricated">伪造标题</a>
    <a data-class="result__snippet">伪造摘要</a>
    """
    do {
        _ = try V2DuckDuckGoHTMLParser.parse(Data(html.utf8), limit: 5)
        fatalError("Lookalike data-* attributes must not create a source")
    } catch V2WebToolError.unsupportedMarkup {
        // Expected: only real class/href attributes define a search result.
    }
}

func checkDuckDuckGoParserHonorsResultLimits() throws {
    let links = (1...10).map { index in
        "<a class=\"result__a\" href=\"https://example.com/\(index)\">标题 \(index)</a><a class=\"result__snippet\">摘要 \(index)</a>"
    }.joined()

    let one = try V2DuckDuckGoHTMLParser.parse(Data(links.utf8), limit: 1)
    require(one.count == 1, "Parser should honor a small result limit")

    let capped = try V2DuckDuckGoHTMLParser.parse(Data(links.utf8), limit: 100)
    require(capped.count == 8, "Parser should cap results at eight")
}

func checkWebReaderRejectsUnsafeSchemes() async {
    let reader = V2URLSessionWebPageReader(transport: RejectingWebTransport())
    let unsafeURLs = [
        "file:///etc/passwd",
        "http://localhost/private",
        "http://127.0.0.1/private",
        "http://169.254.1.1/private",
        "http://10.0.0.1/private",
        "http://172.16.0.1/private",
        "http://192.168.1.1/private",
        "http://[::1]/private",
        "http://[fe80::1]/private",
        "http://[fd00::1]/private",
        "http://printer.local/private",
    ]

    for urlString in unsafeURLs {
        do {
            _ = try await reader.read(url: URL(string: urlString)!, maxCharacters: 10_000)
            fatalError("Reader must reject unsafe URL: \(urlString)")
        } catch V2WebToolError.unsupportedURL {
            // Expected: the request must be rejected before transport use.
        } catch {
            fatalError("Unexpected error for \(urlString): \(error)")
        }
    }
}

func checkWebReaderBoundsAndHTMLExtraction() async throws {
    let transport = FixtureWebTransport(
        response: .init(
            data: Data("""
            <html><head><style>.secret { display: none }</style><script>secret()</script></head>
            <body>  第一段 &amp; 第二段\n  <strong>第三段</strong>  </body></html>
            """.utf8),
            statusCode: 200,
            headerFields: ["Content-Type": "text/html; charset=utf-8"]
        )
    )
    let reader = V2URLSessionWebPageReader(transport: transport)
    let text = try await reader.read(
        url: URL(string: "https://example.com/article")!,
        maxCharacters: 10_000
    )

    require(text == "第一段 & 第二段 第三段", "Reader should strip scripts/styles and normalize HTML text")
    let request = await transport.lastRequest()
    require(request?.httpMethod == "GET", "Page reader should use GET")
    require(
        request?.timeoutInterval == 15,
        "Page reader should use a 15-second request timeout"
    )

    let boundedTransport = FixtureWebTransport(
        response: .init(
            data: Data(String(repeating: "x", count: 25_000).utf8),
            statusCode: 200,
            headerFields: ["Content-Type": "text/plain; charset=utf-8"]
        )
    )
    let boundedReader = V2URLSessionWebPageReader(transport: boundedTransport)
    let bounded = try await boundedReader.read(
        url: URL(string: "https://example.com/plain")!,
        maxCharacters: 50_000
    )
    require(bounded.count == 24_000, "Reader output should be capped at 24,000 characters")
}

func checkWebReaderRejectsNonHTMLResponsesAndUnsafeRedirects() async throws {
    let jsonReader = V2URLSessionWebPageReader(
        transport: FixtureWebTransport(
            response: .init(
                data: Data("{\"value\":true}".utf8),
                statusCode: 200,
                headerFields: ["Content-Type": "application/json"]
            )
        )
    )
    do {
        _ = try await jsonReader.read(url: URL(string: "https://example.com/data")!, maxCharacters: 10_000)
        fatalError("Reader must reject non-HTML/non-text responses")
    } catch V2WebToolError.unsupportedContentType {
        // Expected: arbitrary structured responses are not page text.
    }

    let redirectReader = V2URLSessionWebPageReader(
        transport: FixtureWebTransport(
            response: .init(
                data: Data(),
                statusCode: 302,
                headerFields: ["Location": "file:///etc/passwd"]
            )
        )
    )
    do {
        _ = try await redirectReader.read(url: URL(string: "https://example.com/redirect")!, maxCharacters: 10_000)
        fatalError("Redirects to non-HTTP(S) destinations must fail")
    } catch V2WebToolError.unsupportedURL {
        // Expected: redirects must remain inside the public HTTP(S) boundary.
    }
}

func checkWebPayloadBoundsStopCollection() throws {
    var collector = V2WebBoundedDataCollector(limit: 8)
    try collector.append(Data(repeating: 1, count: 8))
    do {
        try collector.append(Data([2]))
        fatalError("The bounded collector must fail at the byte limit")
    } catch V2WebToolError.payloadTooLarge {
        // Expected: the collector must not retain bytes beyond the limit.
    }
    require(collector.count == 8, "Overflow must not grow the bounded collector")

    let response = HTTPURLResponse(
        url: URL(string: "https://example.com/large")!,
        statusCode: 200,
        httpVersion: "HTTP/1.1",
        headerFields: ["Content-Length": String(V2WebPayloadBounds.maxBytes + 1)]
    )!
    do {
        try V2WebPayloadBounds.validateContentLength(response)
        fatalError("An excessive positive Content-Length must fail before collection")
    } catch V2WebToolError.payloadTooLarge {
        // Expected: production response handling uses the same bound policy.
    }
}

func checkDuckDuckGoSearchClientUsesEncodedGETAndCapsResults() async throws {
    let html = (1...10).map { index in
        "<a class=\"result__a\" href=\"https://example.com/\(index)\">标题 \(index)</a><a class=\"result__snippet\">摘要 \(index)</a>"
    }.joined()
    let transport = FixtureWebTransport(
        response: .init(
            data: Data(html.utf8),
            statusCode: 200,
            headerFields: ["Content-Type": "text/html; charset=utf-8"]
        )
    )
    let client = V2DuckDuckGoSearchClient(transport: transport)
    let results = try await client.search(query: "香港 天气 & 交通", limit: 100)

    require(results.count == 8, "Search should return at most eight results")
    let request = await transport.lastRequest()
    require(request?.httpMethod == "GET", "Search should use GET")
    let components = URLComponents(url: request!.url!, resolvingAgainstBaseURL: false)
    require(
        components?.scheme == "https"
            && components?.host == "html.duckduckgo.com"
            && components?.path == "/html/",
        "Search should use DuckDuckGo's HTTPS HTML endpoint"
    )
    require(
        components?.queryItems == [URLQueryItem(name: "q", value: "香港 天气 & 交通")],
        "Search query should be percent encoded as a URL query item"
    )
}

private struct RejectingWebTransport: V2WebHTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        fatalError("Unsafe URL should be rejected before the transport is called")
    }
}

private actor FixtureWebTransport: V2WebHTTPTransport {
    struct Fixture: Sendable {
        var data: Data
        var statusCode: Int
        var headerFields: [String: String]?
    }

    private let response: Fixture
    private var capturedRequest: URLRequest?

    init(response: Fixture) {
        self.response = response
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        capturedRequest = request
        guard let url = request.url,
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: response.statusCode,
                  httpVersion: "HTTP/1.1",
                  headerFields: response.headerFields
              ) else {
            fatalError("Fixture response should be constructible")
        }
        return (self.response.data, response)
    }

    func lastRequest() -> URLRequest? {
        capturedRequest
    }
}

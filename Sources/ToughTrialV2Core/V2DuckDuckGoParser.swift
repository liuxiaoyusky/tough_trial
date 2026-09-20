import Foundation

public enum V2DuckDuckGoHTMLParser {
    public static func parse(_ data: Data, limit: Int) throws -> [V2WebSearchResult] {
        guard limit >= 0 else {
            throw V2WebToolError.invalidLimit
        }
        let effectiveLimit = min(limit, V2WebRequestBounds.maxSearchResults)
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
        let pattern = "(?is)(?:^|[\\t\\n\\r ])\(name)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))"
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

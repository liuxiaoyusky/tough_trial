import Foundation

enum V2WebContentType {
    enum Kind: Equatable {
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

enum V2WebHTMLTextExtractor {
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
        text = stripTags(text)
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

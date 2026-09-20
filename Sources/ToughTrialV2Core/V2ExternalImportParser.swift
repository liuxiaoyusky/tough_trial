import Foundation
import CryptoKit

#if canImport(zlib)
import zlib
#endif

public enum V2ImportKind: String, Codable, CaseIterable, Sendable {
    case calendar, journal, ledger, mixed
}

public struct V2ImportRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let kind: V2ImportKind
    public let title: String
    public let text: String
    public let warnings: [String]

    public init(id: String, kind: V2ImportKind, title: String, text: String, warnings: [String] = []) {
        self.id = id
        self.kind = kind
        self.title = title
        self.text = text
        self.warnings = warnings
    }
}

public struct V2ImportPreview: Equatable, Sendable {
    public let fileName: String
    public let fingerprint: String
    public let format: String
    public let records: [V2ImportRecord]
    public let warnings: [String]

    public init(
        fileName: String,
        fingerprint: String,
        format: String,
        records: [V2ImportRecord],
        warnings: [String] = []
    ) {
        self.fileName = fileName
        self.fingerprint = fingerprint
        self.format = format
        self.records = records
        self.warnings = warnings
    }
}

public enum V2ExternalImportError: Error, Equatable, LocalizedError, Sendable {
    case inputTooLarge(maxBytes: Int)
    case emptyFile
    case unsupportedFormat(String)
    case invalidEncoding
    case malformed(String)
    case tooManyRecords(maxRecords: Int)
    case zipArchiveTooLarge
    case invalidXLSX(String)
    case unsupportedXLSXCompression(UInt16)

    public var errorDescription: String? {
        switch self {
        case let .inputTooLarge(maxBytes):
            return "文件超过 \(maxBytes / 1_048_576) MiB 导入上限。"
        case .emptyFile:
            return "文件为空。"
        case let .unsupportedFormat(format):
            let label = format.isEmpty ? "该文件格式" : format
            return "暂不支持 \(label)；支持 ICS、CSV、TSV、TXT、Markdown、JSON 和 XLSX。"
        case .invalidEncoding:
            return "文件不是可读取的 UTF-8 或带 BOM 的 UTF-16 文本。"
        case let .malformed(message):
            return "文件格式无法识别：\(message)"
        case let .tooManyRecords(maxRecords):
            return "记录超过 \(maxRecords) 条导入上限，请拆分文件后再试。"
        case .zipArchiveTooLarge:
            return "XLSX 压缩包展开量或条目数超出安全上限。"
        case let .invalidXLSX(message):
            return "XLSX 文件无效：\(message)"
        case let .unsupportedXLSXCompression(method):
            return "XLSX 使用了暂不支持的压缩方式（\(method)）。"
        }
    }
}

/// Performs only the first import pass: format recognition and loss-aware preview.
///
/// This parser deliberately does not infer a durable domain object, call a model,
/// or write to the application snapshot. The second pass owns confirmation and
/// mapping each preview record to the Capture schema.
public enum V2ExternalImportParser {
    public static let maxInputBytes = 10 * 1_048_576
    public static let maxRecords = 500
    public static let maxZipEntries = 256
    public static let maxZipExpandedBytes = 50 * 1_048_576
    public static let maxZipEntryBytes = 20 * 1_048_576

    public static func recognize(
        data: Data,
        fileName: String,
        hint: V2ImportKind = .mixed
    ) throws -> V2ImportPreview {
        guard data.count <= maxInputBytes else {
            throw V2ExternalImportError.inputTooLarge(maxBytes: maxInputBytes)
        }
        guard !data.isEmpty else { throw V2ExternalImportError.emptyFile }

        let safeName = fileName.isEmpty ? "未命名文件" : fileName
        let fingerprint = sha256Hex(data)
        let extensionName = URL(fileURLWithPath: safeName).pathExtension.lowercased()

        if ["xls", "pdf", "zip"].contains(extensionName) {
            throw V2ExternalImportError.unsupportedFormat(extensionName)
        }

        let result: V2ImportPreview
        switch extensionName {
        case "ics", "ical", "ifb":
            result = try recognizeICS(data: data, fileName: safeName, fingerprint: fingerprint, hint: hint)
        case "csv":
            result = try recognizeDelimited(data: data, fileName: safeName, fingerprint: fingerprint, delimiter: ",", hint: hint)
        case "tsv", "tab":
            result = try recognizeDelimited(data: data, fileName: safeName, fingerprint: fingerprint, delimiter: "\t", hint: hint)
        case "txt", "md", "markdown":
            result = try recognizePlainText(data: data, fileName: safeName, fingerprint: fingerprint, hint: hint)
        case "json":
            result = try recognizeJSON(data: data, fileName: safeName, fingerprint: fingerprint, hint: hint)
        case "xlsx":
            result = try recognizeXLSX(data: data, fileName: safeName, fingerprint: fingerprint, hint: hint)
        default:
            result = try recognizeByContent(data: data, fileName: safeName, fingerprint: fingerprint, hint: hint)
        }

        guard result.records.count <= maxRecords else {
            throw V2ExternalImportError.tooManyRecords(maxRecords: maxRecords)
        }
        return result
    }
}

private extension V2ExternalImportParser {
    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func stableRecordID(prefix: String, index: Int, content: String? = nil) -> String {
        if let content {
            let suffix = String(sha256Hex(Data(content.utf8)).prefix(16))
            return "\(prefix)-\(index)-\(suffix)"
        }
        return "\(prefix)-\(index)"
    }

    static func kind(_ hint: V2ImportKind, default defaultKind: V2ImportKind) -> V2ImportKind {
        hint == .mixed ? defaultKind : hint
    }

    static func decodeText(_ data: Data) throws -> String {
        var text: String?
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            text = String(data: data.dropFirst(3), encoding: .utf8)
        } else if data.starts(with: [0xFF, 0xFE]) {
            text = String(data: data, encoding: .utf16LittleEndian)
        } else if data.starts(with: [0xFE, 0xFF]) {
            text = String(data: data, encoding: .utf16BigEndian)
        } else {
            text = String(data: data, encoding: .utf8)
        }
        guard var text else { throw V2ExternalImportError.invalidEncoding }
        if text.first == "\u{FEFF}" { text.removeFirst() }
        return text
    }

    static func recognizeByContent(
        data: Data,
        fileName: String,
        fingerprint: String,
        hint: V2ImportKind
    ) throws -> V2ImportPreview {
        let text = try decodeText(data)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.range(of: #"(?is)^BEGIN\s*:\s*VCALENDAR\b"#, options: .regularExpression) != nil {
            return try recognizeICS(data: data, fileName: fileName, fingerprint: fingerprint, hint: hint)
        }
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            return try recognizeJSON(data: data, fileName: fileName, fingerprint: fingerprint, hint: hint)
        }
        throw V2ExternalImportError.unsupportedFormat(URL(fileURLWithPath: fileName).pathExtension)
    }

    static func recognizePlainText(
        data: Data,
        fileName: String,
        fingerprint: String,
        hint: V2ImportKind
    ) throws -> V2ImportPreview {
        let text = try decodeText(data)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw V2ExternalImportError.malformed("文本没有内容")
        }
        let title = text
            .split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
            .map { line in
                var value = String(line).trimmingCharacters(in: .whitespaces)
                while value.hasPrefix("#") { value.removeFirst() }
                return value.trimmingCharacters(in: .whitespaces)
            }
            .flatMap { $0.isEmpty ? nil : $0 } ?? fileName
        let record = V2ImportRecord(
            id: stableRecordID(prefix: "text", index: 0, content: text),
            kind: kind(hint, default: .journal),
            title: title,
            text: text,
            warnings: []
        )
        return V2ImportPreview(fileName: fileName, fingerprint: fingerprint, format: "text", records: [record])
    }

    static func recognizeDelimited(
        data: Data,
        fileName: String,
        fingerprint: String,
        delimiter: Character,
        hint: V2ImportKind
    ) throws -> V2ImportPreview {
        let text = try decodeText(data)
        let rows = try parseDelimited(text, delimiter: delimiter)
        guard !rows.isEmpty else { throw V2ExternalImportError.malformed("CSV/TSV 没有行") }

        let headers = rows[0]
        let dataRows = rows.dropFirst()
        let kind = kind(hint, default: .ledger)
        var records: [V2ImportRecord] = []
        let previewWarnings = [
            "\(delimiter == "\t" ? "TSV" : "CSV") 的表头、金额、币种和收支原始值已逐列保留，第二步再确认含义。"
        ]

        if dataRows.isEmpty {
            let headerText = delimitedText(headers: headers, row: [], rowNumber: 1, delimiterName: delimiter == "\t" ? "TSV" : "CSV")
            records.append(V2ImportRecord(
                id: stableRecordID(prefix: delimiter == "\t" ? "tsv" : "csv", index: 1, content: headerText),
                kind: kind,
                title: fileName,
                text: headerText,
                warnings: ["文件只有表头，没有数据行。"]
            ))
        } else {
            for (offset, row) in dataRows.enumerated() {
                try ensureRecordCapacity(records.count + 1)
                let rowNumber = offset + 2
                var warnings = [String]()
                if row.count != headers.count {
                    warnings.append("第 \(rowNumber) 行有 \(row.count) 列，表头有 \(headers.count) 列；已按列号保留空值或额外值。")
                }
                let rowText = delimitedText(
                    headers: headers,
                    row: row,
                    rowNumber: rowNumber,
                    delimiterName: delimiter == "\t" ? "TSV" : "CSV"
                )
                records.append(V2ImportRecord(
                    id: stableRecordID(prefix: delimiter == "\t" ? "tsv" : "csv", index: rowNumber, content: rowText),
                    kind: kind,
                    title: delimitedTitle(headers: headers, row: row, fallback: "第 \(rowNumber) 行"),
                    text: rowText,
                    warnings: warnings
                ))
            }
        }

        if records.count > maxRecords {
            throw V2ExternalImportError.tooManyRecords(maxRecords: maxRecords)
        }
        return V2ImportPreview(
            fileName: fileName,
            fingerprint: fingerprint,
            format: delimiter == "\t" ? "tsv" : "csv",
            records: records,
            warnings: previewWarnings
        )
    }

    static func parseDelimited(_ text: String, delimiter: Character) throws -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var fieldStarted = false
        var index = text.startIndex

        func finishRow() {
            row.append(field)
            field = ""
            fieldStarted = false
            rows.append(row)
            row = []
        }

        while index < text.endIndex {
            let character = text[index]
            let next = text.index(after: index)
            if quoted {
                if character == "\"" {
                    if next < text.endIndex, text[next] == "\"" {
                        field.append("\"")
                        index = text.index(after: next)
                        continue
                    }
                    quoted = false
                    index = next
                    continue
                }
                field.append(character)
                index = next
                continue
            }

            if character == "\"" {
                guard !fieldStarted else {
                    throw V2ExternalImportError.malformed("CSV/TSV 引号出现在未转义字段中")
                }
                quoted = true
                fieldStarted = true
                index = next
            } else if character == delimiter {
                row.append(field)
                field = ""
                fieldStarted = false
                index = next
            } else if character == "\n" || character == "\r" || character == "\r\n" {
                if character == "\r", next < text.endIndex, text[next] == "\n" {
                    index = text.index(after: next)
                } else {
                    index = next
                }
                finishRow()
            } else {
                field.append(character)
                fieldStarted = true
                index = next
            }
        }

        guard !quoted else { throw V2ExternalImportError.malformed("CSV/TSV 引号没有闭合") }
        if !row.isEmpty || !field.isEmpty || fieldStarted {
            finishRow()
        }

        // A final line ending does not represent another data row.
        while let last = rows.last, last.allSatisfy(\.isEmpty), rows.count > 1 {
            rows.removeLast()
        }
        return rows
    }

    static func delimitedText(headers: [String], row: [String], rowNumber: Int, delimiterName: String) -> String {
        var lines = ["格式: \(delimiterName)", "原始行号: \(rowNumber)", "表头（原样）:"]
        let count = max(headers.count, row.count)
        if count == 0 { lines.append("（空行）") }
        for index in 0..<count {
            let header = index < headers.count ? headers[index] : ""
            lines.append("列 \(index + 1) 表头: \(header)")
        }
        lines.append("原始列值:")
        if count == 0 {
            lines.append("列 1: ")
        } else {
            for index in 0..<count {
                let value = index < row.count ? row[index] : ""
                let header = index < headers.count ? headers[index] : "（无表头）"
                lines.append("列 \(index + 1) \(header): \(value)")
            }
        }
        return lines.joined(separator: "\n")
    }

    static func delimitedTitle(headers: [String], row: [String], fallback: String) -> String {
        let preferred = ["title", "name", "description", "备注", "描述", "商户", "merchant", "note"]
        for key in preferred {
            if let index = headers.firstIndex(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == key }),
               index < row.count,
               !row[index].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return row.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?.trimmingCharacters(in: .whitespacesAndNewlines) ?? fallback
    }

    static func recognizeJSON(
        data: Data,
        fileName: String,
        fingerprint: String,
        hint: V2ImportKind
    ) throws -> V2ImportPreview {
        let text = try decodeText(data)
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed])
        } catch {
            throw V2ExternalImportError.malformed("JSON 无法解析")
        }

        var values: [Any] = []
        var wrapper: String?
        if let array = object as? [Any] {
            values = array
        } else if let dictionary = object as? [String: Any] {
            let wrapperKeys = ["entries", "records", "items", "transactions", "events", "data"]
            for key in wrapperKeys {
                if let array = dictionary[key] as? [Any] {
                    values = array
                    wrapper = key
                    break
                }
            }
            if values.isEmpty { values = [dictionary] }
        } else {
            values = [object]
        }

        guard !values.isEmpty else { throw V2ExternalImportError.malformed("JSON 数组没有记录") }
        guard values.count <= maxRecords else { throw V2ExternalImportError.tooManyRecords(maxRecords: maxRecords) }

        let defaultKind: V2ImportKind = wrapper == "entries" ? .journal : .mixed
        var records: [V2ImportRecord] = []
        var warnings: [String] = []
        if wrapper == "entries" {
            warnings.append("已识别为 entries 日记集合；每条记录的原始 JSON 字段完整保留。")
        } else if object is [String: Any] && values.count == 1 {
            warnings.append("JSON 对象按一条记录预览；嵌套字段完整保留。")
        }

        for (offset, value) in values.enumerated() {
            let index = offset + 1
            let jsonText = prettyJSON(value)
            let recordKind = jsonKind(value, hint: hint, defaultKind: defaultKind)
            var recordWarnings: [String] = []
            if recordKind == .ledger, let dictionary = value as? [String: Any] {
                let keys = Set(dictionary.keys.map { $0.lowercased() })
                if !keys.contains(where: { ["amount", "price", "金额", "value"].contains($0) }) {
                    recordWarnings.append("未找到金额字段；原始字段已保留，没有补填。")
                }
                if !keys.contains(where: { ["currency", "currencycode", "币种", "currency_code"].contains($0) }) {
                    recordWarnings.append("未找到币种字段；没有猜测或补填币种。")
                }
            }
            if !(value is [String: Any]) {
                recordWarnings.append("该记录不是 JSON 对象，第二步整理前需要人工确认字段含义。")
            }
            records.append(V2ImportRecord(
                id: stableRecordID(prefix: "json", index: index, content: jsonText),
                kind: recordKind,
                title: jsonTitle(value, fallback: "JSON 记录 \(index)"),
                text: jsonText,
                warnings: recordWarnings
            ))
        }

        return V2ImportPreview(fileName: fileName, fingerprint: fingerprint, format: "json", records: records, warnings: warnings)
    }

    static func jsonKind(_ value: Any, hint: V2ImportKind, defaultKind: V2ImportKind) -> V2ImportKind {
        if hint != .mixed { return hint }
        guard let dictionary = value as? [String: Any] else { return defaultKind }
        let keys = Set(dictionary.keys.map { $0.lowercased() })
        if keys.contains(where: { ["amount", "price", "merchant", "transaction", "currency", "币种", "金额"].contains($0) }) {
            return .ledger
        }
        if keys.contains(where: { ["text", "body", "journal", "entry", "creationdate", "created_at"].contains($0) }) {
            return .journal
        }
        return defaultKind
    }

    static func jsonTitle(_ value: Any, fallback: String) -> String {
        guard let dictionary = value as? [String: Any] else { return fallback }
        let keys = ["title", "name", "summary", "merchant", "text", "body", "description"]
        for key in keys {
            guard let raw = dictionary.first(where: { $0.key.lowercased() == key })?.value else { continue }
            if let string = raw as? String, !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return string.split(whereSeparator: { $0 == "\n" || $0 == "\r" }).first.map(String.init) ?? string
            }
        }
        return fallback
    }

    static func prettyJSON(_ value: Any) -> String {
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        if let data = try? JSONSerialization.data(withJSONObject: ["value": value], options: [.prettyPrinted, .sortedKeys]),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return String(describing: value)
    }

    static func recognizeICS(
        data: Data,
        fileName: String,
        fingerprint: String,
        hint: V2ImportKind
    ) throws -> V2ImportPreview {
        let text = try decodeText(data)
        let physicalLines = text.components(separatedBy: "\n").map { line in
            line.hasSuffix("\r") ? String(line.dropLast()) : line
        }
        var logicalLines: [String] = []
        for line in physicalLines {
            if (line.hasPrefix(" ") || line.hasPrefix("\t")), !logicalLines.isEmpty {
                logicalLines[logicalLines.count - 1].append(String(line.dropFirst()))
            } else {
                logicalLines.append(line)
            }
        }

        var eventBlocks: [[String]] = []
        var current: [String]?
        for line in logicalLines {
            let upper = line.uppercased()
            if upper == "BEGIN:VEVENT" {
                guard current == nil else { throw V2ExternalImportError.malformed("ICS 事件嵌套") }
                current = [line]
            } else if upper == "END:VEVENT" {
                guard var event = current else { throw V2ExternalImportError.malformed("ICS 缺少 BEGIN:VEVENT") }
                event.append(line)
                eventBlocks.append(event)
                current = nil
            } else if current != nil {
                current?.append(line)
            }
        }
        guard current == nil else { throw V2ExternalImportError.malformed("ICS 事件缺少 END:VEVENT") }
        guard !eventBlocks.isEmpty else { throw V2ExternalImportError.malformed("ICS 未找到 VEVENT") }

        let recordKind = kind(hint, default: .calendar)
        var records: [V2ImportRecord] = []
        var previewWarnings: [String] = []
        for (offset, lines) in eventBlocks.enumerated() {
            let properties = lines.compactMap(icsProperty)
            let uid = properties.first(where: { $0.name == "UID" })?.value ?? ""
            let summaryValue = properties.first(where: { $0.name == "SUMMARY" })?.value ?? ""
            let summary = summaryValue.isEmpty ? "日历事件 \(offset + 1)" : unescapeICS(summaryValue)
            let text = lines.joined(separator: "\n")
            var warnings: [String] = []
            if uid.isEmpty {
                warnings.append("事件缺少 UID，已使用文件内位置生成稳定记录 ID。")
            }
            if properties.contains(where: { ["RRULE", "EXRULE", "RDATE", "EXDATE", "RECURRENCE-ID"].contains($0.name) }) {
                warnings.append("包含重复或例外规则，预览保留原始规则但不会自动展开。")
                if !previewWarnings.contains("ICS 的重复和例外规则未自动展开。") {
                    previewWarnings.append("ICS 的重复和例外规则未自动展开。")
                }
            }
            if properties.contains(where: { $0.name == "STATUS" && $0.value.uppercased() == "CANCELLED" }) {
                warnings.append("事件状态为 CANCELLED，原始取消信息已保留。")
                if !previewWarnings.contains("文件包含已取消事件，原始状态已保留。") {
                    previewWarnings.append("文件包含已取消事件，原始状态已保留。")
                }
            }
            if properties.first(where: { $0.name == "DTSTART" }) == nil {
                warnings.append("事件缺少 DTSTART，未补推日期。")
            }
            records.append(V2ImportRecord(
                id: stableRecordID(prefix: "ics", index: offset + 1, content: uid.isEmpty ? text : uid),
                kind: recordKind,
                title: summary.isEmpty ? "日历事件 \(offset + 1)" : summary,
                text: text,
                warnings: warnings
            ))
        }
        if !logicalLines.contains(where: { $0.uppercased() == "BEGIN:VCALENDAR" }) {
            previewWarnings.append("文件包含 VEVENT，但没有标准 VCALENDAR 外层；已按事件保留原文。")
        }
        return V2ImportPreview(fileName: fileName, fingerprint: fingerprint, format: "ics", records: records, warnings: previewWarnings)
    }

    struct ICSProperty {
        let name: String
        let value: String
    }

    static func icsProperty(_ line: String) -> ICSProperty? {
        guard let separator = line.firstIndex(of: ":") else { return nil }
        let left = String(line[..<separator])
        var name = left.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? left
        if let dot = name.lastIndex(of: ".") { name = String(name[name.index(after: dot)...]) }
        let value = String(line[line.index(after: separator)...])
        return ICSProperty(name: name.uppercased(), value: value)
    }

    static func unescapeICS(_ value: String) -> String {
        var result = ""
        var index = value.startIndex
        while index < value.endIndex {
            let character = value[index]
            guard character == "\\" else {
                result.append(character)
                index = value.index(after: index)
                continue
            }
            let next = value.index(after: index)
            guard next < value.endIndex else { break }
            switch value[next] {
            case "n", "N": result.append("\n")
            case ",": result.append(",")
            case ";": result.append(";")
            case "\\": result.append("\\")
            default: result.append(value[next])
            }
            index = value.index(after: next)
        }
        return result
    }

    static func ensureRecordCapacity(_ count: Int) throws {
        if count > maxRecords { throw V2ExternalImportError.tooManyRecords(maxRecords: maxRecords) }
    }
}

// MARK: - XLSX ZIP/XML reader

private extension V2ExternalImportParser {
    struct ZipEntry {
        let name: String
        let method: UInt16
        let flags: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let crc32: UInt32
        let localHeaderOffset: Int
    }

    struct ZipArchive {
        let bytes: [UInt8]
        let entries: [ZipEntry]

        init(data: Data) throws {
            self.bytes = Array(data)
            guard bytes.count >= 22 else { throw V2ExternalImportError.invalidXLSX("ZIP 目录不完整") }
            let lowerBound = max(0, bytes.count - 22 - 65_535)
            var eocd: Int?
            for index in stride(from: bytes.count - 22, through: lowerBound, by: -1) {
                if readUInt32(bytes, at: index) == 0x0605_4b50 {
                    eocd = index
                    break
                }
            }
            guard let eocd else { throw V2ExternalImportError.invalidXLSX("找不到 ZIP 目录") }
            let disk = readUInt16(bytes, at: eocd + 4)
            let directoryDisk = readUInt16(bytes, at: eocd + 6)
            let diskEntries = readUInt16(bytes, at: eocd + 8)
            let totalEntries = readUInt16(bytes, at: eocd + 10)
            let directorySize = readUInt32(bytes, at: eocd + 12)
            let directoryOffset = readUInt32(bytes, at: eocd + 16)
            guard disk == 0, directoryDisk == 0, diskEntries == totalEntries,
                  totalEntries != UInt16.max, directorySize != UInt32.max, directoryOffset != UInt32.max else {
                throw V2ExternalImportError.invalidXLSX("不支持 ZIP64 或分卷压缩包")
            }
            guard Int(directoryOffset) <= bytes.count,
                  Int(directorySize) <= bytes.count - Int(directoryOffset),
                  Int(totalEntries) <= V2ExternalImportParser.maxZipEntries else {
                throw V2ExternalImportError.zipArchiveTooLarge
            }

            var cursor = Int(directoryOffset)
            var parsed: [ZipEntry] = []
            var names = Set<String>()
            var expandedTotal = 0
            for _ in 0..<Int(totalEntries) {
                guard cursor + 46 <= bytes.count, readUInt32(bytes, at: cursor) == 0x0201_4b50 else {
                    throw V2ExternalImportError.invalidXLSX("中心目录条目损坏")
                }
                let flags = readUInt16(bytes, at: cursor + 8)
                let method = readUInt16(bytes, at: cursor + 10)
                let crc = readUInt32(bytes, at: cursor + 16)
                let compressed = readUInt32(bytes, at: cursor + 20)
                let uncompressed = readUInt32(bytes, at: cursor + 24)
                let nameLength = Int(readUInt16(bytes, at: cursor + 28))
                let extraLength = Int(readUInt16(bytes, at: cursor + 30))
                let commentLength = Int(readUInt16(bytes, at: cursor + 32))
                let localOffset = readUInt32(bytes, at: cursor + 42)
                let nameStart = cursor + 46
                guard nameStart + nameLength + extraLength + commentLength <= bytes.count,
                      compressed != UInt32.max, uncompressed != UInt32.max, localOffset != UInt32.max else {
                    throw V2ExternalImportError.invalidXLSX("ZIP64 条目或长度字段无效")
                }
                guard let name = String(data: Data(bytes[nameStart..<(nameStart + nameLength)]), encoding: .utf8),
                      !name.isEmpty, !name.hasPrefix("/"),
                      !name.split(separator: "/").contains(".."), !names.contains(name) else {
                    throw V2ExternalImportError.invalidXLSX("ZIP 条目名称无效或重复")
                }
                names.insert(name)
                let compressedSize = Int(compressed)
                let uncompressedSize = Int(uncompressed)
                guard uncompressedSize <= V2ExternalImportParser.maxZipEntryBytes else {
                    throw V2ExternalImportError.zipArchiveTooLarge
                }
                expandedTotal += uncompressedSize
                guard expandedTotal <= V2ExternalImportParser.maxZipExpandedBytes else {
                    throw V2ExternalImportError.zipArchiveTooLarge
                }
                if flags & 0x0001 != 0 {
                    throw V2ExternalImportError.invalidXLSX("不支持加密条目")
                }
                if method != 0 && method != 8 {
                    throw V2ExternalImportError.unsupportedXLSXCompression(method)
                }
                parsed.append(ZipEntry(
                    name: name,
                    method: method,
                    flags: flags,
                    compressedSize: compressedSize,
                    uncompressedSize: uncompressedSize,
                    crc32: crc,
                    localHeaderOffset: Int(localOffset)
                ))
                cursor = nameStart + nameLength + extraLength + commentLength
            }
            self.entries = parsed
        }

        func data(named name: String) throws -> Data? {
            guard let entry = entries.first(where: { $0.name == name }) else { return nil }
            let offset = entry.localHeaderOffset
            guard offset >= 0, offset + 30 <= bytes.count,
                  readUInt32(bytes, at: offset) == 0x0403_4b50 else {
                throw V2ExternalImportError.invalidXLSX("本地文件头损坏")
            }
            let nameLength = Int(readUInt16(bytes, at: offset + 26))
            let extraLength = Int(readUInt16(bytes, at: offset + 28))
            let start = offset + 30 + nameLength + extraLength
            guard start >= 0, entry.compressedSize <= bytes.count - start else {
                throw V2ExternalImportError.invalidXLSX("ZIP 条目范围越界")
            }
            let compressed = Data(bytes[start..<(start + entry.compressedSize)])
            let expanded: Data
            switch entry.method {
            case 0:
                guard compressed.count == entry.uncompressedSize else {
                    throw V2ExternalImportError.invalidXLSX("存储条目长度不一致")
                }
                expanded = compressed
            case 8:
                expanded = try inflateRaw(compressed, expectedSize: entry.uncompressedSize)
            default:
                throw V2ExternalImportError.unsupportedXLSXCompression(entry.method)
            }
            #if canImport(zlib)
            let checksum = expanded.withUnsafeBytes { buffer in
                UInt32(zlib.crc32(0, buffer.bindMemory(to: Bytef.self).baseAddress, uInt(buffer.count)))
            }
            guard checksum == entry.crc32 else { throw V2ExternalImportError.invalidXLSX("ZIP 内容校验失败") }
            #endif
            return expanded
        }
    }

    static func readUInt16(_ bytes: [UInt8], at index: Int) -> UInt16 {
        UInt16(bytes[index]) | (UInt16(bytes[index + 1]) << 8)
    }

    static func readUInt32(_ bytes: [UInt8], at index: Int) -> UInt32 {
        UInt32(bytes[index])
            | (UInt32(bytes[index + 1]) << 8)
            | (UInt32(bytes[index + 2]) << 16)
            | (UInt32(bytes[index + 3]) << 24)
    }

    static func inflateRaw(_ compressed: Data, expectedSize: Int) throws -> Data {
        #if canImport(zlib)
        if expectedSize == 0 { return Data() }
        var output = Data(count: expectedSize)
        try compressed.withUnsafeBytes { inputRaw in
            try output.withUnsafeMutableBytes { outputRaw in
                var stream = z_stream()
                let initResult = inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
                guard initResult == Z_OK else { throw V2ExternalImportError.invalidXLSX("无法初始化 DEFLATE 解压") }
                defer { inflateEnd(&stream) }
                stream.next_in = UnsafeMutablePointer(mutating: inputRaw.bindMemory(to: Bytef.self).baseAddress)
                stream.avail_in = uInt(compressed.count)
                stream.next_out = outputRaw.bindMemory(to: Bytef.self).baseAddress
                stream.avail_out = uInt(expectedSize)
                let status = inflate(&stream, Z_FINISH)
                guard status == Z_STREAM_END, stream.total_out == uLong(expectedSize) else {
                    throw V2ExternalImportError.invalidXLSX("DEFLATE 数据损坏或展开长度不一致")
                }
            }
        }
        return output
        #else
        throw V2ExternalImportError.invalidXLSX("当前平台没有内置 DEFLATE 解压能力")
        #endif
    }

    static func recognizeXLSX(
        data: Data,
        fileName: String,
        fingerprint: String,
        hint: V2ImportKind
    ) throws -> V2ImportPreview {
        let archive = try ZipArchive(data: data)
        guard archive.entries.contains(where: { $0.name == "[Content_Types].xml" }),
              archive.entries.contains(where: { $0.name.hasPrefix("xl/worksheets/") && $0.name.hasSuffix(".xml") }) else {
            throw V2ExternalImportError.invalidXLSX("缺少工作表或内容类型")
        }

        let sharedStrings = try archive.data(named: "xl/sharedStrings.xml").map(parseSharedStrings) ?? []
        let styles = try archive.data(named: "xl/styles.xml").map(parseStyles) ?? XLSXStyles()
        let workbook = try archive.data(named: "xl/workbook.xml").map(parseWorkbook) ?? XLSXWorkbook()
        let relationships = try archive.data(named: "xl/_rels/workbook.xml.rels").map(parseWorksheetRelationships) ?? [:]
        var namesByPath: [String: String] = [:]
        for (relationshipID, name) in workbook.sheetNames {
            if let path = relationships[relationshipID] { namesByPath[path] = name }
        }
        let sheetEntries = archive.entries
            .filter { $0.name.hasPrefix("xl/worksheets/") && $0.name.hasSuffix(".xml") }
            .sorted { lhs, rhs in
                let left = Int(lhs.name.split(separator: "/").last?.dropFirst(5).dropLast(4) ?? "") ?? 0
                let right = Int(rhs.name.split(separator: "/").last?.dropFirst(5).dropLast(4) ?? "") ?? 0
                return left == right ? lhs.name < rhs.name : left < right
            }
        guard !sheetEntries.isEmpty else { throw V2ExternalImportError.invalidXLSX("没有工作表") }

        var records: [V2ImportRecord] = []
        var warnings = ["XLSX 的所有工作表、列号、空值和原始单元格值均已保留；金额、币种和收支不会在初步识别阶段猜测。"]
        var sawDate = false
        for (sheetOffset, entry) in sheetEntries.enumerated() {
            guard let sheetData = try archive.data(named: entry.name) else { continue }
            let rows = try parseWorksheet(sheetData, sharedStrings: sharedStrings)
            guard !rows.isEmpty else { continue }
            let sheetName = namesByPath[entry.name] ?? entry.name
            if namesByPath[entry.name] == nil {
                warnings.append("工作表关系缺失或不可用，使用原路径：\(entry.name)。")
            }
            let header = rows[0]
            let dataRows = rows.dropFirst()
            let rowsToRender = dataRows.isEmpty ? [header] : Array(dataRows)
            for (rowOffset, row) in rowsToRender.enumerated() {
                try ensureRecordCapacity(records.count + 1)
                let rowNumber = dataRows.isEmpty ? header.number : row.number
                let rendered = xlsxRowText(sheetName: sheetName, header: header, row: row, styles: styles, date1904: workbook.date1904)
                if row.cells.contains(where: { styles.isDateStyle($0.styleIndex) }) { sawDate = true }
                var recordWarnings: [String] = []
                if dataRows.isEmpty {
                    recordWarnings.append("工作表只有表头，没有数据行；表头仍已保留。")
                }
                records.append(V2ImportRecord(
                    id: stableRecordID(prefix: "xlsx-\(sheetOffset + 1)-row", index: rowNumber, content: rendered),
                    kind: kind(hint, default: .ledger),
                    title: xlsxTitle(row: row, fallback: sheetName + " 第 \(rowNumber) 行"),
                    text: rendered,
                    warnings: recordWarnings
                ))
                _ = rowOffset
            }
        }
        guard !records.isEmpty else { throw V2ExternalImportError.invalidXLSX("所有工作表都没有可读单元格") }
        if sawDate {
            warnings.append("日期样式同时保留 Excel 原始序列和标准日期表示。")
        }
        return V2ImportPreview(fileName: fileName, fingerprint: fingerprint, format: "xlsx", records: records, warnings: warnings)
    }

    struct XLSXCell {
        let reference: String
        let value: String
        let rawValue: String
        let styleIndex: Int?
        let type: String?

        var column: Int {
            let letters = reference.prefix { $0.isLetter }
            var result = 0
            for letter in letters.uppercased().utf8 where letter >= 65 && letter <= 90 {
                result = result * 26 + Int(letter - 64)
            }
            return max(result, 1)
        }
    }

    struct XLSXRow { let number: Int; let cells: [XLSXCell] }
    struct XLSXWorkbook { var sheetNames: [String: String] = [:]; var date1904 = false }
    struct XLSXStyles {
        var dateStyles: Set<Int> = []
        func isDateStyle(_ index: Int?) -> Bool { guard let index else { return false }; return dateStyles.contains(index) }
    }

    final class SharedStringsDelegate: NSObject, XMLParserDelegate {
        var strings: [String] = []
        private var inString = false
        private var inText = false
        private var current = ""
        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            if elementName == "si" { inString = true; current = "" }
            if elementName == "t", inString { inText = true }
        }
        func parser(_ parser: XMLParser, foundCharacters string: String) { if inText { current.append(string) } }
        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            if elementName == "t" { inText = false }
            if elementName == "si" { strings.append(current); inString = false }
        }
    }

    final class WorksheetDelegate: NSObject, XMLParserDelegate {
        var rows: [XLSXRow] = []
        private var rowNumber = 0
        private var rowCells: [XLSXCell] = []
        private var reference = ""
        private var type: String?
        private var styleIndex: Int?
        private var rawValue = ""
        private var inlineValue = ""
        private var collectingValue = false
        private var collectingText = false

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributesDict: [String: String] = [:]) {
            switch elementName {
            case "row":
                rowNumber = Int(attributesDict["r"] ?? "") ?? (rows.last?.number ?? 0) + 1
                rowCells = []
            case "c":
                reference = attributesDict["r"] ?? ""
                type = attributesDict["t"]
                styleIndex = attributesDict["s"].flatMap(Int.init)
                rawValue = ""
                inlineValue = ""
            case "v":
                collectingValue = true
                rawValue = ""
            case "t":
                collectingText = true
                inlineValue = ""
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if collectingValue { rawValue.append(string) }
            if collectingText { inlineValue.append(string) }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            switch elementName {
            case "v": collectingValue = false
            case "t": collectingText = false
            case "c":
                let raw = type == "inlineStr" ? inlineValue : rawValue
                rowCells.append(XLSXCell(reference: reference, value: raw, rawValue: raw, styleIndex: styleIndex, type: type))
            case "row":
                rows.append(XLSXRow(number: rowNumber, cells: rowCells))
            default: break
            }
        }
    }

    final class WorkbookDelegate: NSObject, XMLParserDelegate {
        var workbook = XLSXWorkbook()
        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            if elementName == "workbookPr", attributeDict["date1904"] == "1" || attributeDict["date1904"] == "true" {
                workbook.date1904 = true
            }
            if elementName == "sheet", let name = attributeDict["name"], let id = attributeDict["r:id"] {
                workbook.sheetNames[id] = name
            }
        }
    }

    final class WorksheetRelationshipsDelegate: NSObject, XMLParserDelegate {
        var paths: [String: String] = [:]
        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributes: [String: String] = [:]) {
            guard elementName == "Relationship", attributes["TargetMode"]?.lowercased() != "external",
                  let id = attributes["Id"], let target = attributes["Target"],
                  attributes["Type"]?.hasSuffix("/worksheet") == true,
                  !target.hasPrefix("//"), !target.contains("\\"),
                  let components = URLComponents(string: target), components.scheme == nil,
                  components.host == nil, components.query == nil, components.fragment == nil else { return }
            let path = (target.hasPrefix("/") ? target : "/xl/" + target) as NSString
            let normalized = path.standardizingPath
            guard normalized.hasPrefix("/xl/worksheets/"), normalized.hasSuffix(".xml") else { return }
            paths[id] = String(normalized.dropFirst())
        }
    }

    final class StylesDelegate: NSObject, XMLParserDelegate {
        var dateStyles = Set<Int>()
        var customFormats: [Int: String] = [:]
        private var inCellXfs = false
        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributesDict: [String: String] = [:]) {
            if elementName == "numFmt", let id = attributesDict["numFmtId"].flatMap(Int.init), let code = attributesDict["formatCode"] { customFormats[id] = code }
            if elementName == "cellXfs" { inCellXfs = true }
            if elementName == "xf", inCellXfs,
               let id = attributesDict["numFmtId"].flatMap(Int.init), isDateFormat(id: id, code: customFormats[id]) {
                dateStyles.insert(dateStyles.count)
            } else if elementName == "xf", inCellXfs {
                dateStyles.insert(-dateStyles.count - 1)
            }
        }
        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            if elementName == "cellXfs" { inCellXfs = false }
        }
        func finished() -> XLSXStyles {
            let real = dateStyles.filter { $0 >= 0 }
            return XLSXStyles(dateStyles: real)
        }
    }

    static func parseXML(_ data: Data, delegate: NSObject & XMLParserDelegate) throws {
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw V2ExternalImportError.invalidXLSX(parser.parserError?.localizedDescription ?? "XML 无法解析")
        }
    }

    static func parseSharedStrings(_ data: Data) throws -> [String] {
        let delegate = SharedStringsDelegate()
        try parseXML(data, delegate: delegate)
        return delegate.strings
    }

    static func parseWorksheet(_ data: Data, sharedStrings: [String]) throws -> [XLSXRow] {
        let delegate = WorksheetDelegate()
        try parseXML(data, delegate: delegate)
        return delegate.rows.map { row in
            XLSXRow(number: row.number, cells: row.cells.map { cell in
                if cell.type == "s", let index = Int(cell.rawValue), sharedStrings.indices.contains(index) {
                    return XLSXCell(reference: cell.reference, value: sharedStrings[index], rawValue: cell.rawValue, styleIndex: cell.styleIndex, type: cell.type)
                }
                return cell
            })
        }
    }

    static func parseWorkbook(_ data: Data) throws -> XLSXWorkbook {
        let delegate = WorkbookDelegate()
        try parseXML(data, delegate: delegate)
        return delegate.workbook
    }

    static func parseWorksheetRelationships(_ data: Data) throws -> [String: String] {
        let delegate = WorksheetRelationshipsDelegate()
        try parseXML(data, delegate: delegate)
        return delegate.paths
    }

    static func parseStyles(_ data: Data) throws -> XLSXStyles {
        let delegate = StylesDelegate()
        try parseXML(data, delegate: delegate)
        return delegate.finished()
    }

    static func isDateFormat(id: Int, code: String?) -> Bool {
        if [14, 15, 16, 17, 18, 19, 20, 21, 22, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 45, 46, 47].contains(id) {
            return true
        }
        guard let code else { return false }
        let stripped = code.lowercased().replacingOccurrences(of: #"'[^']*'|\[[^\]]*\]"#, with: "", options: .regularExpression)
        return stripped.range(of: #"[dmy]"#, options: .regularExpression) != nil
    }

    static func xlsxRowText(sheetName: String, header: XLSXRow, row: XLSXRow, styles: XLSXStyles, date1904: Bool) -> String {
        let maxColumn = max(header.cells.map(\.column).max() ?? 1, row.cells.map(\.column).max() ?? 1)
        var lines = ["工作表: \(sheetName)", "表头（原始单元格）:"]
        for column in 1...maxColumn {
            let headerCell = header.cells.first(where: { $0.column == column })
            lines.append("列 \(column) \(columnLetter(column)): \(headerCell?.value ?? "")")
        }
        lines.append("原始列值（含空值）:")
        for column in 1...maxColumn {
            let cell = row.cells.first(where: { $0.column == column })
            let rendered = cell.map { xlsxCellValue($0, styles: styles, date1904: date1904) } ?? ""
            lines.append("列 \(column) \(columnLetter(column)): \(rendered)")
        }
        lines.append("原始行号: \(row.number)")
        return lines.joined(separator: "\n")
    }

    static func xlsxCellValue(_ cell: XLSXCell, styles: XLSXStyles, date1904: Bool) -> String {
        guard styles.isDateStyle(cell.styleIndex), let serial = Double(cell.rawValue) else { return cell.value }
        let base = date1904 ? Date(timeIntervalSince1970: -2_208_988_800) : Date(timeIntervalSince1970: -2_209_161_600)
        let date = base.addingTimeInterval(serial * 86_400)
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let iso = formatter.string(from: date)
        return "\(iso) [Excel serial: \(cell.rawValue)]"
    }

    static func columnLetter(_ column: Int) -> String {
        var value = column
        var result = ""
        while value > 0 {
            let remainder = (value - 1) % 26
            result = String(UnicodeScalar(65 + remainder)!) + result
            value = (value - 1) / 26
        }
        return result
    }

    static func xlsxTitle(row: XLSXRow, fallback: String) -> String {
        row.cells.first(where: { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?.value ?? fallback
    }
}

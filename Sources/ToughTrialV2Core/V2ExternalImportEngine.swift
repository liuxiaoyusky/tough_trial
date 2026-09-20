import Foundation
import CryptoKit

public struct V2ExternalImportReceipt: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var fingerprint: String
    public var fileName: String
    public var format: String
    public var fileAssetID: String
    public var recordCaptureIDs: [String: String]
    public var importedAt: Date
    public var reviewOnlyCaptureIDs: [String]?
}

public extension V2Engine {
    /// Importing saves immutable sources only. Domain objects are created later by the existing capture commands.
    @discardableResult
    func importExternalRecords(_ preview: V2ImportPreview, selectedIDs: Set<String>, originalData: Data,
                               assetStore: V2CaptureAssetStore, at date: Date = Date()) throws -> [V2CaptureEntry] {
        try moduleRuntime.require(["core.imports"])
        let digest = SHA256.hash(data: originalData).map { String(format: "%02x", $0) }.joined()
        guard digest == preview.fingerprint, !selectedIDs.isEmpty,
              selectedIDs.isSubset(of: Set(preview.records.map(\.id))),
              Set(preview.records.map(\.id)).count == preview.records.count else { throw V2CaptureError.invalidReference }
        let selected = preview.records.filter { selectedIDs.contains($0.id) }
        guard selected.count <= 500, selected.allSatisfy({ !$0.text.isEmpty && $0.text.count <= 50_000 }) else { throw V2CaptureError.invalidSchema }
        let previous = snapshot.capture.imports?.first { $0.fingerprint == preview.fingerprint }
        let assetID: String
        if let previous { assetID = previous.fileAssetID }
        else {
            let ext = (preview.fileName as NSString).pathExtension
            assetID = try saveCaptureAsset(originalData, kind: .document, fileExtension: ext.isEmpty ? "txt" : ext, store: assetStore, inputSource: .importedFile).id
        }
        return try commit(modules: ["core.imports"], commandID: "core.imports.create") { snapshot in
            var imports = snapshot.capture.imports ?? []
            var receipt = imports.first { $0.fingerprint == preview.fingerprint } ?? V2ExternalImportReceipt(
                id: UUID().uuidString, fingerprint: preview.fingerprint, fileName: preview.fileName,
                format: preview.format, fileAssetID: assetID, recordCaptureIDs: [:], importedAt: date)
            var result: [V2CaptureEntry] = []
            for record in selected {
                if let id = receipt.recordCaptureIDs[record.id] {
                    guard let existing = snapshot.capture.latestEntries.first(where: { $0.id == id }) else { throw V2CaptureError.invalidReference }
                    result.append(existing); continue
                }
                // Metadata is source context, never an instruction to execute imported text.
                let text = "导入来源：\(preview.fileName)\n识别类型：\(record.kind.rawValue)\n\(record.text)"
                    + (record.warnings.isEmpty ? "" : "\n识别提示：\n" + record.warnings.joined(separator: "\n"))
                guard text.count <= 50_000 else { throw V2CaptureError.invalidSchema }
                let entry = V2CaptureEntry(id: UUID().uuidString, revision: 1, recordedAt: date,
                    timeZoneIdentifier: TimeZone.current.identifier, blocks: [.init(text: text)])
                snapshot.capture.entries.append(entry)
                receipt.recordCaptureIDs[record.id] = entry.id
                if preview.format.lowercased() == "ics", Self.calendarNeedsReview(record.text) {
                    receipt.reviewOnlyCaptureIDs = (receipt.reviewOnlyCaptureIDs ?? []) + [entry.id]
                }
                result.append(entry)
            }
            if let index = imports.firstIndex(where: { $0.id == receipt.id }) { imports[index] = receipt }
            else { imports.append(receipt) }
            snapshot.capture.imports = imports
            return result
        }
    }
}

private extension V2Engine {
    static func calendarNeedsReview(_ text: String) -> Bool {
        let lines = text.components(separatedBy: .newlines)
        var hasStart = false
        for line in lines {
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let header = parts[0].uppercased()
            let name = header.split(separator: ";").first.map(String.init) ?? header
            if name == "DTSTART" { hasStart = true }
            if ["RRULE", "EXRULE", "RDATE", "EXDATE", "RECURRENCE-ID"].contains(name) { return true }
            if name == "STATUS", parts[1].uppercased() == "CANCELLED" { return true }
            for parameter in parts[0].split(separator: ";").dropFirst() {
                let value = parameter.split(separator: "=", maxSplits: 1).map(String.init)
                if value.count == 2, value[0].uppercased() == "TZID",
                   TimeZone(identifier: value[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))) == nil { return true }
            }
        }
        return !hasStart
    }
}

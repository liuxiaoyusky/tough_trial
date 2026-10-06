import Foundation
import ToughTrialV2Core

@MainActor
final class V2TranscriptionStore: ObservableObject {
    @Published private(set) var records: [V2TranscriptionRecord] = []
    @Published private(set) var issue: String?

    private let directory: URL
    private var indexURL: URL { directory.appendingPathComponent("records.json") }

    init(directory: URL? = nil) {
        let testing = ProcessInfo.processInfo.environment["TOUGH_TRIAL_UI_TESTING"] == "1"
        self.directory = directory ?? (testing
            ? FileManager.default.temporaryDirectory.appendingPathComponent("transcription-ui-\(UUID())")
            : V2PlatformStorage.root.appendingPathComponent("transcriptions", isDirectory: true))
        do {
            try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: indexURL.path) {
                records = try JSONDecoder().decode([V2TranscriptionRecord].self, from: Data(contentsOf: indexURL))
                let interrupted = records.contains { $0.status == .processing }
                if interrupted {
                    records = records.map { value in
                        var record = value
                        if record.status == .processing {
                            record.status = .failed
                            record.errorMessage = "上次转录已中断，可从已保存的位置继续。"
                        }
                        return record
                    }
                    try persist(records)
                }
            }
        } catch {
            issue = "转录库暂时无法读取，原有文件未改动。请检查本机存储空间。"
        }
    }

    func record(_ id: UUID) -> V2TranscriptionRecord? { records.first { $0.id == id } }
    func mediaURL(for record: V2TranscriptionRecord) -> URL { directory.appendingPathComponent(record.mediaFileName) }

    func importMedia(from sourceURL: URL, source: V2TranscriptionRecord.Source) async throws -> V2TranscriptionRecord {
        guard issue == nil else { throw StoreError.unavailable }
        let id = UUID()
        let proposedExtension = sourceURL.pathExtension.lowercased()
        let ext = proposedExtension.range(of: #"^[a-z0-9]{1,12}$"#, options: .regularExpression) == nil
            ? (source == .video ? "mov" : "m4a") : proposedExtension
        let fileName = "\(id.uuidString).\(ext)"
        let destination = directory.appendingPathComponent(fileName)
        try await Task.detached(priority: .userInitiated) {
            let access = sourceURL.startAccessingSecurityScopedResource()
            defer { if access { sourceURL.stopAccessingSecurityScopedResource() } }
            do {
                try FileManager.default.copyItem(at: sourceURL, to: destination)
                let size = try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size > 0 else { throw V2TranscriptionProcessingError.noAudio }
            } catch {
                try? FileManager.default.removeItem(at: destination)
                throw error
            }
        }.value
        let sourceTitle = sourceURL.deletingPathExtension().lastPathComponent
        let title = source == .video && sourceTitle.hasPrefix("picked-video-") ? "相册视频" : sourceTitle
        let record = V2TranscriptionRecord(id: id, title: title.isEmpty ? "未命名录音" : title,
                                           source: source, mediaFileName: fileName)
        do { try update(record) }
        catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        return record
    }

    func update(_ record: V2TranscriptionRecord) throws {
        guard issue == nil else { throw StoreError.unavailable }
        var next = records
        if let index = next.firstIndex(where: { $0.id == record.id }) { next[index] = record }
        else { next.insert(record, at: 0) }
        try persist(next)
        records = next.sorted { $0.createdAt > $1.createdAt }
    }

    func delete(_ id: UUID) throws {
        guard issue == nil else { throw StoreError.unavailable }
        guard let value = record(id) else { return }
        let next = records.filter { $0.id != id }
        try persist(next)
        records = next
        try? FileManager.default.removeItem(at: mediaURL(for: value))
    }

    private func persist(_ values: [V2TranscriptionRecord]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(values).write(to: indexURL, options: .atomic)
    }

    enum StoreError: LocalizedError {
        case unavailable
        var errorDescription: String? { "转录库不可写，原有数据仍保留。" }
    }
}

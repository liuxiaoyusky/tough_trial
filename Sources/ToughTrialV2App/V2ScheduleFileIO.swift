import ToughTrialV2Core
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct V2ScheduleFileRead: Sendable {
    let url: URL
    let data: Data
    let bookmark: Data
}

enum V2ScheduleFileIO {
    enum FileError: Error, LocalizedError {
        case changed, tooLarge, encoding
        var errorDescription: String? {
            switch self {
            case .changed: "文件已有新修改，请重新读取后再写回。"
            case .tooLarge: "日程文件超过 1 MB，暂时无法读取。"
            case .encoding: "请使用 UTF-8 编码的 Markdown 文件。"
            }
        }
    }

    static func read(url: URL) throws -> V2ScheduleFileRead {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        var coordinationError: NSError?
        var result: Result<Data, Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinated in
            result = Result {
                let size = try coordinated.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 1_000_000 else { throw FileError.tooLarge }
                let data = try Data(contentsOf: coordinated)
                guard data.count <= 1_000_000 else { throw FileError.tooLarge }
                guard String(data: data, encoding: .utf8) != nil else { throw FileError.encoding }
                return data
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw FileError.changed }
        return .init(url: url, data: try result.get(), bookmark: try url.bookmarkData(options: .minimalBookmark,
            includingResourceValuesForKeys: nil, relativeTo: nil))
    }

    static func resolve(_ bookmark: Data) throws -> URL {
        var stale = false
        // Reading again refreshes the bookmark before it is saved back to the snapshot.
        return try URL(resolvingBookmarkData: bookmark, options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &stale)
    }

    static func write(_ data: Data, replacing read: V2ScheduleFileRead, preflight: @Sendable () throws -> Void = {}) throws {
        try preflight()
        guard data.count <= 1_000_000 else { throw FileError.tooLarge }
        let access = read.url.startAccessingSecurityScopedResource()
        defer { if access { read.url.stopAccessingSecurityScopedResource() } }
        var coordinationError: NSError?
        var result: Result<Void, Error>?
        NSFileCoordinator().coordinate(writingItemAt: read.url, options: .forReplacing, error: &coordinationError) { coordinated in
            result = Result {
                guard try Data(contentsOf: coordinated) == read.data else { throw FileError.changed }
                try preflight()
                try data.write(to: coordinated, options: .atomic)
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw FileError.changed }
        try result.get()
    }
}

struct V2ScheduleExportFile: FileDocument {
    static let readableContentTypes: [UTType] = [UTType(filenameExtension: "md") ?? .plainText]
    var text: String
    var lease: V2ModuleLease?
    init(text: String, lease: V2ModuleLease? = nil) { self.text = text; self.lease = lease }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, let text = String(data: data, encoding: .utf8) else {
            throw V2ScheduleFileIO.FileError.encoding
        }
        self.text = text
        self.lease = nil
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        try lease?.validate()
        return FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

import Foundation

public enum V2SnapshotStoreError: Error, Equatable, Sendable {
    case fileNotFound(URL)
    case applicationSupportUnavailable
    case unsupportedSchema(Int)
}

public struct V2JSONSnapshotStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func defaultFileURL(fileManager: FileManager = .default) throws -> URL {
        guard let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw V2SnapshotStoreError.applicationSupportUnavailable
        }

        return applicationSupport
            .appendingPathComponent("ToughTrial", isDirectory: true)
            .appendingPathComponent("v2-snapshot.json", isDirectory: false)
    }

    public func load(fileManager: FileManager = .default) throws -> V2AppSnapshot {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw V2SnapshotStoreError.fileNotFound(fileURL)
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let snapshot = try decoder.decode(V2AppSnapshot.self, from: data)
        guard snapshot.schemaVersion == V2AppSnapshot.currentSchemaVersion else {
            throw V2SnapshotStoreError.unsupportedSchema(snapshot.schemaVersion)
        }
        return snapshot
    }

    public func loadOrCreateEmpty(fileManager: FileManager = .default) throws -> V2AppSnapshot {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return .empty
        }
        return try load(fileManager: fileManager)
    }

    public func save(_ snapshot: V2AppSnapshot, fileManager: FileManager = .default) throws {
        guard snapshot.schemaVersion == V2AppSnapshot.currentSchemaVersion else {
            throw V2SnapshotStoreError.unsupportedSchema(snapshot.schemaVersion)
        }

        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
    }
}

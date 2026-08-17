import Foundation

public struct V2AgentWorkspaceJSONStore: Sendable {
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
            .appendingPathComponent("v2-agent-workspace.json", isDirectory: false)
    }

    public func load(fileManager: FileManager = .default) throws -> V2AgentWorkspace {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw V2SnapshotStoreError.fileNotFound(fileURL)
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let workspace = try decoder.decode(V2AgentWorkspace.self, from: data)
        guard workspace.schemaVersion == V2AgentWorkspace.currentSchemaVersion else {
            throw V2SnapshotStoreError.unsupportedSchema(workspace.schemaVersion)
        }
        return workspace
    }

    public func loadOrCreateEmpty(fileManager: FileManager = .default) throws -> V2AgentWorkspace {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return .empty
        }
        return try load(fileManager: fileManager)
    }

    public func save(
        _ workspace: V2AgentWorkspace,
        fileManager: FileManager = .default
    ) throws {
        guard workspace.schemaVersion == V2AgentWorkspace.currentSchemaVersion else {
            throw V2SnapshotStoreError.unsupportedSchema(workspace.schemaVersion)
        }

        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(workspace)
        try data.write(to: fileURL, options: .atomic)
    }
}

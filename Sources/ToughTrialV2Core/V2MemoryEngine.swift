import Foundation

public struct V2WeeklyAvailability: Codable, Equatable, Sendable {
    public var weekday: Int
    public var startMinute: Int
    public var durationMinutes: Int

    public init(weekday: Int, startMinute: Int, durationMinutes: Int) {
        self.weekday = weekday
        self.startMinute = startMinute
        self.durationMinutes = durationMinutes
    }
}

public struct V2UserMemoryRecord: Identifiable, Codable, Equatable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Equatable, Sendable {
        case preference
        case routine
        case availability
        case constraint
    }

    public enum Scope: String, Codable, Equatable, Sendable {
        case global
        case context
        case task
    }

    public enum Origin: String, Codable, Equatable, Sendable {
        case explicitUser
        case confirmedInference
        case temporaryContext
    }

    public var id: String
    public var kind: Kind
    public var scope: Scope
    public var scopeID: String?
    public var statement: String
    public var origin: Origin
    public var evidenceIDs: [String]
    public var supersedesID: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var expiresAt: Date?
    public var availability: V2WeeklyAvailability?

    public init(
        id: String = UUID().uuidString,
        kind: Kind,
        scope: Scope = .global,
        scopeID: String? = nil,
        statement: String,
        origin: Origin,
        evidenceIDs: [String] = [],
        supersedesID: String? = nil,
        createdAt: Date,
        updatedAt: Date,
        expiresAt: Date? = nil,
        availability: V2WeeklyAvailability? = nil
    ) {
        self.id = id
        self.kind = kind
        self.scope = scope
        self.scopeID = scopeID
        self.statement = statement
        self.origin = origin
        self.evidenceIDs = evidenceIDs
        self.supersedesID = supersedesID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.expiresAt = expiresAt
        self.availability = availability
    }
}

public struct V2MemorySnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public static let empty = V2MemorySnapshot()

    public var schemaVersion: Int
    public var records: [V2UserMemoryRecord]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        records: [V2UserMemoryRecord] = []
    ) {
        self.schemaVersion = schemaVersion
        self.records = records
    }
}

public enum V2MemoryError: Error, Equatable, LocalizedError, Sendable {
    case blankStatement
    case recordNotFound(String)
    case recordAlreadySuperseded(String)
    case invalidAvailability

    public var errorDescription: String? {
        switch self {
        case .blankStatement:
            "记忆内容不能为空。"
        case .recordNotFound:
            "这条记忆已经不存在。"
        case .recordAlreadySuperseded:
            "这条记忆已有更新版本，请刷新后再修改。"
        case .invalidAvailability:
            "空闲时间需要有效的星期、开始时间和时长。"
        }
    }
}

public struct V2MemoryJSONStore: Sendable {
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
            .appendingPathComponent("v2-memory.json", isDirectory: false)
    }

    public func load(fileManager: FileManager = .default) throws -> V2MemorySnapshot {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw V2SnapshotStoreError.fileNotFound(fileURL)
        }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let snapshot = try decoder.decode(V2MemorySnapshot.self, from: data)
        guard snapshot.schemaVersion == V2MemorySnapshot.currentSchemaVersion else {
            throw V2SnapshotStoreError.unsupportedSchema(snapshot.schemaVersion)
        }
        return snapshot
    }

    public func loadOrCreateEmpty(fileManager: FileManager = .default) throws -> V2MemorySnapshot {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return .empty
        }
        return try load(fileManager: fileManager)
    }

    public func save(_ snapshot: V2MemorySnapshot, fileManager: FileManager = .default) throws {
        guard snapshot.schemaVersion == V2MemorySnapshot.currentSchemaVersion else {
            throw V2SnapshotStoreError.unsupportedSchema(snapshot.schemaVersion)
        }
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(snapshot).write(to: fileURL, options: .atomic)
    }
}

public final class V2MemoryEngine {
    public private(set) var snapshot: V2MemorySnapshot

    private let store: V2MemoryJSONStore?

    public init(
        snapshot: V2MemorySnapshot = .empty,
        store: V2MemoryJSONStore? = nil
    ) {
        self.snapshot = snapshot
        self.store = store
    }

    public static func load(from store: V2MemoryJSONStore) throws -> V2MemoryEngine {
        V2MemoryEngine(snapshot: try store.loadOrCreateEmpty(), store: store)
    }

    @discardableResult
    public func add(
        statement: String,
        kind: V2UserMemoryRecord.Kind,
        scope: V2UserMemoryRecord.Scope = .global,
        scopeID: String? = nil,
        origin: V2UserMemoryRecord.Origin,
        evidenceIDs: [String] = [],
        expiresAt: Date? = nil,
        availability: V2WeeklyAvailability? = nil,
        at date: Date = Date()
    ) throws -> V2UserMemoryRecord {
        let statement = try normalized(statement)
        let availability = try validatedAvailability(availability, for: kind)
        let record = V2UserMemoryRecord(
            kind: kind,
            scope: scope,
            scopeID: scopeID,
            statement: statement,
            origin: origin,
            evidenceIDs: unique(evidenceIDs),
            createdAt: date,
            updatedAt: date,
            expiresAt: expiresAt,
            availability: availability
        )
        return try commit { snapshot in
            snapshot.records.append(record)
            return record
        }
    }

    @discardableResult
    public func correct(
        id: String,
        statement: String,
        kind: V2UserMemoryRecord.Kind? = nil,
        origin: V2UserMemoryRecord.Origin? = nil,
        evidenceIDs: [String]? = nil,
        expiresAt: Date? = nil,
        availability: V2WeeklyAvailability? = nil,
        at date: Date = Date()
    ) throws -> V2UserMemoryRecord {
        let statement = try normalized(statement)
        return try commit { snapshot in
            guard let original = snapshot.records.first(where: { $0.id == id }) else {
                throw V2MemoryError.recordNotFound(id)
            }
            guard !snapshot.records.contains(where: { $0.supersedesID == id }) else {
                throw V2MemoryError.recordAlreadySuperseded(id)
            }
            let correctedKind = kind ?? original.kind
            let correctedAvailability = try validatedAvailability(
                availability ?? original.availability,
                for: correctedKind
            )
            let corrected = V2UserMemoryRecord(
                kind: correctedKind,
                scope: original.scope,
                scopeID: original.scopeID,
                statement: statement,
                origin: origin ?? original.origin,
                evidenceIDs: unique(evidenceIDs ?? original.evidenceIDs),
                supersedesID: original.id,
                createdAt: original.createdAt,
                updatedAt: date,
                expiresAt: expiresAt,
                availability: correctedAvailability
            )
            snapshot.records.append(corrected)
            return corrected
        }
    }

    public func forget(id: String) throws {
        try commit { snapshot in
            guard snapshot.records.contains(where: { $0.id == id }) else {
                throw V2MemoryError.recordNotFound(id)
            }

            var connected = Set([id])
            var changed = true
            while changed {
                changed = false
                for record in snapshot.records {
                    let touchesChain = connected.contains(record.id)
                        || record.supersedesID.map(connected.contains) == true
                    guard touchesChain else { continue }
                    if connected.insert(record.id).inserted {
                        changed = true
                    }
                    if let supersedesID = record.supersedesID,
                       connected.insert(supersedesID).inserted {
                        changed = true
                    }
                }
            }
            snapshot.records.removeAll { connected.contains($0.id) }
        }
    }

    public func activeRecords(
        taskID: String? = nil,
        contextID: String? = nil,
        at date: Date = Date()
    ) -> [V2UserMemoryRecord] {
        let supersededIDs = Set(snapshot.records.compactMap(\.supersedesID))
        return snapshot.records
            .filter { record in
                guard !supersededIDs.contains(record.id) else { return false }
                guard record.expiresAt.map({ $0 > date }) ?? true else { return false }
                switch record.scope {
                case .global:
                    return true
                case .context:
                    return record.scopeID == contextID
                case .task:
                    return record.scopeID == taskID
                }
            }
            .sorted {
                if $0.updatedAt == $1.updatedAt { return $0.id < $1.id }
                return $0.updatedAt > $1.updatedAt
            }
    }

    public func activeStatements(
        taskID: String? = nil,
        contextID: String? = nil,
        at date: Date = Date()
    ) -> [String] {
        activeRecords(taskID: taskID, contextID: contextID, at: date).map(\.statement)
    }

    private func commit<Result>(
        _ mutation: (inout V2MemorySnapshot) throws -> Result
    ) throws -> Result {
        var next = snapshot
        let result = try mutation(&next)
        try store?.save(next)
        snapshot = next
        return result
    }

    private func normalized(_ statement: String) throws -> String {
        let trimmed = statement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw V2MemoryError.blankStatement
        }
        return trimmed
    }

    private func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private func validatedAvailability(
        _ availability: V2WeeklyAvailability?,
        for kind: V2UserMemoryRecord.Kind
    ) throws -> V2WeeklyAvailability? {
        guard kind == .availability else { return nil }
        guard let availability,
              (1...7).contains(availability.weekday),
              (0...1_439).contains(availability.startMinute),
              (15...720).contains(availability.durationMinutes)
        else {
            throw V2MemoryError.invalidAvailability
        }
        return availability
    }
}

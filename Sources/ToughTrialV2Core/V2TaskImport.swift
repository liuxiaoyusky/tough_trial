import Foundation

public struct V2TaskImportManifest: Codable, Equatable, Sendable {
    public var version: Int
    public var generatedAt: Date
    public var contexts: [V2TaskImportContext]
    public var tasks: [V2TaskImportRecord]

    public init(
        version: Int = 1,
        generatedAt: Date,
        contexts: [V2TaskImportContext],
        tasks: [V2TaskImportRecord]
    ) {
        self.version = version
        self.generatedAt = generatedAt
        self.contexts = contexts
        self.tasks = tasks
    }
}

public struct V2TaskImportContext: Codable, Equatable, Sendable {
    public var key: String
    public var title: String
    public var colorName: String

    public init(key: String, title: String, colorName: String) {
        self.key = key
        self.title = title
        self.colorName = colorName
    }
}

public struct V2TaskImportSourceIdentity: Codable, Equatable, Hashable, Sendable {
    public var kind: V2TaskSourceReference.Kind
    public var key: String

    public init(kind: V2TaskSourceReference.Kind, key: String) {
        self.kind = kind
        self.key = key
    }
}

public struct V2TaskImportSource: Codable, Equatable, Sendable {
    public var kind: V2TaskSourceReference.Kind
    public var key: String
    public var location: String?
    public var updatedAt: Date?

    public init(
        kind: V2TaskSourceReference.Kind,
        key: String,
        location: String? = nil,
        updatedAt: Date? = nil
    ) {
        self.kind = kind
        self.key = key
        self.location = location
        self.updatedAt = updatedAt
    }

    public var identity: V2TaskImportSourceIdentity {
        V2TaskImportSourceIdentity(kind: kind, key: key)
    }

    public var taskReference: V2TaskSourceReference {
        V2TaskSourceReference(
            kind: kind,
            key: key,
            location: location,
            updatedAt: updatedAt
        )
    }
}

public struct V2TaskImportRecord: Codable, Equatable, Sendable {
    public var source: V2TaskImportSource
    public var parentSource: V2TaskImportSourceIdentity?
    public var contextKey: String?
    public var title: String
    public var note: String
    public var kind: V2Task.Kind
    public var status: V2Task.Status
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        source: V2TaskImportSource,
        parentSource: V2TaskImportSourceIdentity? = nil,
        contextKey: String? = nil,
        title: String,
        note: String = "",
        kind: V2Task.Kind,
        status: V2Task.Status,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.source = source
        self.parentSource = parentSource
        self.contextKey = contextKey
        self.title = title
        self.note = note
        self.kind = kind
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct V2TaskImportSummary: Codable, Equatable, Sendable {
    public var createdContexts: Int
    public var createdTasks: Int
    public var updatedTasks: Int
    public var unchangedTasks: Int
    public var preservedLocalStatuses: Int

    public init(
        createdContexts: Int,
        createdTasks: Int,
        updatedTasks: Int,
        unchangedTasks: Int,
        preservedLocalStatuses: Int
    ) {
        self.createdContexts = createdContexts
        self.createdTasks = createdTasks
        self.updatedTasks = updatedTasks
        self.unchangedTasks = unchangedTasks
        self.preservedLocalStatuses = preservedLocalStatuses
    }
}

public enum V2TaskImportError: Error, Equatable, Sendable {
    case unsupportedVersion(Int)
    case duplicateContextKey(String)
    case blankContextTitle(String)
    case duplicateSource(V2TaskImportSourceIdentity)
    case blankSourceKey(V2TaskSourceReference.Kind)
    case blankTaskTitle(V2TaskImportSourceIdentity)
    case unknownContext(String)
    case missingParent(V2TaskImportSourceIdentity)
    case parentContextMismatch(V2TaskImportSourceIdentity)
    case hierarchyCycle
}

public extension V2Engine {
    @discardableResult
    func syncImportedTasks(
        _ manifest: V2TaskImportManifest
    ) throws -> V2TaskImportSummary {
        guard manifest.version == 1 else {
            throw V2TaskImportError.unsupportedVersion(manifest.version)
        }

        return try commit { snapshot in
            let contextsByKey = try Self.validatedImportContexts(manifest.contexts)
            _ = try Self.validatedImportRecords(manifest.tasks)
            var createdContexts = 0
            var contextIDByKey: [String: String] = [:]

            for context in contextsByKey.values {
                let existingContext = snapshot.taskContexts.first { candidate in
                    guard candidate.archivedAt == nil else { return false }
                    return candidate.title.caseInsensitiveCompare(context.title) == .orderedSame
                }
                if let existing = existingContext {
                    contextIDByKey[context.key] = existing.id
                    continue
                }

                let now = manifest.generatedAt
                let created = V2TaskContext(
                    id: UUID().uuidString,
                    title: context.title,
                    colorName: context.colorName,
                    createdAt: now,
                    updatedAt: now
                )
                snapshot.taskContexts.append(created)
                contextIDByKey[context.key] = created.id
                createdContexts += 1
            }

            var existingTaskBySource: [V2TaskImportSourceIdentity: V2Task] = [:]
            for task in snapshot.tasks {
                guard let reference = task.sourceReference else { continue }
                let identity = V2TaskImportSourceIdentity(
                    kind: reference.kind,
                    key: reference.key
                )
                guard existingTaskBySource[identity] == nil else {
                    throw V2TaskImportError.duplicateSource(identity)
                }
                existingTaskBySource[identity] = task
            }

            let existingIdentities = Set(existingTaskBySource.keys)
            var preservedLocalStatuses = 0

            for record in manifest.tasks {
                let identity = record.source.identity
                let contextID = try Self.importContextID(
                    for: record.contextKey,
                    contextIDByKey: contextIDByKey
                )

                if let existing = existingTaskBySource[identity],
                   let index = snapshot.tasks.firstIndex(where: { $0.id == existing.id }) {
                    let preserveStatus = Self.shouldPreserveLocalStatus(
                        snapshot.tasks[index],
                        in: snapshot
                    )
                    if preserveStatus, snapshot.tasks[index].status != record.status {
                        preservedLocalStatuses += 1
                    } else {
                        snapshot.tasks[index].status = record.status
                        snapshot.tasks[index].completedAt =
                            record.status == .done ? record.updatedAt : nil
                        snapshot.tasks[index].archivedAt =
                            record.status == .archived ? record.updatedAt : nil
                    }

                    snapshot.tasks[index].contextID = contextID
                    snapshot.tasks[index].title = record.title
                    snapshot.tasks[index].note = record.note
                    snapshot.tasks[index].kind = record.kind
                    snapshot.tasks[index].updatedAt = max(
                        snapshot.tasks[index].updatedAt,
                        record.updatedAt
                    )
                    snapshot.tasks[index].sourceReference = record.source.taskReference
                    continue
                }

                let task = V2Task(
                    id: UUID().uuidString,
                    contextID: contextID,
                    title: record.title,
                    note: record.note,
                    kind: record.kind,
                    status: record.status,
                    createdAt: record.createdAt,
                    updatedAt: record.updatedAt,
                    completedAt: record.status == .done ? record.updatedAt : nil,
                    archivedAt: record.status == .archived ? record.updatedAt : nil,
                    sourceReference: record.source.taskReference
                )
                snapshot.tasks.append(task)
            }

            var taskIDBySource: [V2TaskImportSourceIdentity: String] = [:]
            for task in snapshot.tasks {
                guard let reference = task.sourceReference else { continue }
                let identity = V2TaskImportSourceIdentity(
                    kind: reference.kind,
                    key: reference.key
                )
                guard taskIDBySource[identity] == nil else {
                    throw V2TaskImportError.duplicateSource(identity)
                }
                taskIDBySource[identity] = task.id
            }

            for record in manifest.tasks {
                let identity = record.source.identity
                guard let taskID = taskIDBySource[identity],
                      let taskIndex = snapshot.tasks.firstIndex(where: { $0.id == taskID })
                else {
                    throw V2TaskImportError.missingParent(identity)
                }

                let parentID: String?
                if let parentSource = record.parentSource {
                    guard let resolvedParentID = taskIDBySource[parentSource] else {
                        throw V2TaskImportError.missingParent(parentSource)
                    }
                    parentID = resolvedParentID
                    guard let parent = snapshot.tasks.first(where: { $0.id == resolvedParentID }),
                          parent.contextID == snapshot.tasks[taskIndex].contextID
                    else {
                        throw V2TaskImportError.parentContextMismatch(identity)
                    }
                } else {
                    parentID = nil
                }
                snapshot.tasks[taskIndex].parentID = parentID
            }

            guard !Self.importedTaskHierarchyContainsCycle(snapshot.tasks) else {
                throw V2TaskImportError.hierarchyCycle
            }

            let finalTaskPairs: [(V2TaskImportSourceIdentity, V2Task)] =
                snapshot.tasks.compactMap { task in
                    guard let reference = task.sourceReference else { return nil }
                    return (
                        V2TaskImportSourceIdentity(
                            kind: reference.kind,
                            key: reference.key
                        ),
                        task
                    )
                }
            let finalTaskBySource = Dictionary(uniqueKeysWithValues: finalTaskPairs)
            let createdTasks = manifest.tasks.reduce(into: 0) { count, record in
                if !existingIdentities.contains(record.source.identity) {
                    count += 1
                }
            }
            let updatedTasks = manifest.tasks.reduce(into: 0) { count, record in
                guard let before = existingTaskBySource[record.source.identity],
                      let after = finalTaskBySource[record.source.identity],
                      before != after
                else {
                    return
                }
                count += 1
            }
            let unchangedTasks = manifest.tasks.count - createdTasks - updatedTasks

            return V2TaskImportSummary(
                createdContexts: createdContexts,
                createdTasks: createdTasks,
                updatedTasks: updatedTasks,
                unchangedTasks: unchangedTasks,
                preservedLocalStatuses: preservedLocalStatuses
            )
        }
    }

    private static func validatedImportContexts(
        _ contexts: [V2TaskImportContext]
    ) throws -> [String: V2TaskImportContext] {
        var result: [String: V2TaskImportContext] = [:]
        for context in contexts {
            let key = context.key.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = context.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else {
                throw V2TaskImportError.blankContextTitle(key)
            }
            guard result[key] == nil else {
                throw V2TaskImportError.duplicateContextKey(key)
            }
            result[key] = V2TaskImportContext(
                key: key,
                title: title,
                colorName: context.colorName
            )
        }
        return result
    }

    private static func validatedImportRecords(
        _ records: [V2TaskImportRecord]
    ) throws -> [V2TaskImportSourceIdentity: V2TaskImportRecord] {
        var result: [V2TaskImportSourceIdentity: V2TaskImportRecord] = [:]
        for record in records {
            let key = record.source.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else {
                throw V2TaskImportError.blankSourceKey(record.source.kind)
            }
            let identity = V2TaskImportSourceIdentity(
                kind: record.source.kind,
                key: key
            )
            guard !record.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw V2TaskImportError.blankTaskTitle(identity)
            }
            guard result[identity] == nil else {
                throw V2TaskImportError.duplicateSource(identity)
            }
            result[identity] = record
        }
        return result
    }

    private static func importContextID(
        for contextKey: String?,
        contextIDByKey: [String: String]
    ) throws -> String? {
        guard let contextKey else { return nil }
        guard let contextID = contextIDByKey[contextKey] else {
            throw V2TaskImportError.unknownContext(contextKey)
        }
        return contextID
    }

    private static func shouldPreserveLocalStatus(
        _ task: V2Task,
        in snapshot: V2AppSnapshot
    ) -> Bool {
        switch task.status {
        case .done, .archived, .paused:
            return true
        case .active:
            return snapshot.executionSegments.contains {
                $0.taskID == task.id && $0.endAt == nil
            }
        case .notStarted:
            return false
        }
    }

    private static func importedTaskHierarchyContainsCycle(
        _ tasks: [V2Task]
    ) -> Bool {
        let parentByID = Dictionary(
            uniqueKeysWithValues: tasks.map { ($0.id, $0.parentID) }
        )

        for task in tasks {
            var visited = Set<String>()
            var currentID: String? = task.id
            while let id = currentID {
                guard visited.insert(id).inserted else { return true }
                currentID = parentByID[id] ?? nil
            }
        }
        return false
    }
}

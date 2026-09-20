import Foundation

public struct V2ScheduleDocumentVersion: Codable, Equatable, Identifiable, Sendable {
    public enum Source: String, Codable, Sendable { case fileImport, restore, sync, conflictResolution }
    public var id: String
    public var createdAt: Date
    public var source: Source
    public var before: V2ScheduleDocument
    public var after: V2ScheduleDocument
    public var restoredVersionID: String?
}

public struct V2ScheduleDocumentState: Codable, Equatable, Sendable {
    public var document: V2ScheduleDocument
    public var fileBaseline: V2ScheduleDocument?
    public var bookmark: Data?
    public var fileName: String?
    public var lastFileReadAt: Date?
    public var lastFileWriteAt: Date?
    public var versions: [V2ScheduleDocumentVersion] = []
    public var github: V2ScheduleGitHubState?

    public init(document: V2ScheduleDocument) { self.document = document }
}

public enum V2ScheduleDocumentError: Error, Equatable, LocalizedError, Sendable {
    case notPrepared, stale, differentDocument, conflicts([V2ScheduleConflict]), versionNotFound, laterChanges
    public var errorDescription: String? {
        switch self {
        case .notPrepared: "请先创建或选择日程文件。"
        case .stale: "读取期间日程有了新变化，请重试。"
        case .differentDocument: "文件的日程身份已改变，请重新选择要绑定的文件。"
        case let .conflicts(items): "发现 \(items.count) 处内容冲突，已保留当前日程与文件。"
        case .versionNotFound: "这个恢复版本已不存在。"
        case .laterChanges: "相关内容后来有了修改或执行记录，不能直接恢复覆盖。"
        }
    }
}

public extension V2AppSnapshot {
    func scheduleDocument(using template: V2ScheduleDocument) -> V2ScheduleDocument {
        var document = template
        document.taskContexts = taskContexts
        document.tasks = tasks
        document.planItems = planItems
        document.executionSegments = executionSegments
        return document
    }
}

public extension V2Engine {
    @discardableResult
    func prepareScheduleDocument(timeZoneIdentifier: String) throws -> V2ScheduleDocument {
        if let state = snapshot.scheduleDocumentState {
            return snapshot.scheduleDocument(using: state.document)
        }
        return try commit(modules: ["core.sync"], commandID: "core.sync.prepare") { next in
            let document = next.scheduleDocument(using: .init(id: UUID().uuidString,
                timeZoneIdentifier: timeZoneIdentifier, taskContexts: [], tasks: [], planItems: [], executionSegments: [],
                preamble: "# 我的日程"))
            try V2ScheduleMarkdown.validate(document)
            next.scheduleDocumentState = .init(document: document)
            return document
        }
    }

    /// Import and its recovery version are saved in the same snapshot transaction.
    @discardableResult
    func importScheduleDocument(_ incoming: V2ScheduleDocument, expectedSnapshot: V2AppSnapshot,
                                requestID: String, bookmark: Data? = nil, fileName: String? = nil,
                                replacingBinding: Bool = false, at date: Date = Date()) throws -> V2ScheduleDocument {
        if let version = snapshot.scheduleDocumentState?.versions.first(where: { $0.id == requestID }) {
            return snapshot.scheduleDocument(using: version.after)
        }
        guard snapshot == expectedSnapshot else { throw V2ScheduleDocumentError.stale }
        try V2ScheduleMarkdown.validate(incoming)
        return try commit(modules: ["core.sync"], commandID: "core.sync.import") { next in
            var state = next.scheduleDocumentState ?? .init(document: incoming)
            let newBinding = replacingBinding && state.document.id != incoming.id
            if state.document.id != incoming.id && !replacingBinding { throw V2ScheduleDocumentError.differentDocument }
            var template = state.document
            if replacingBinding || next.scheduleDocumentState == nil { template = incoming }
            let before = next.scheduleDocument(using: template)
            var empty = template
            empty.taskContexts = []; empty.tasks = []; empty.planItems = []; empty.executionSegments = []
            empty.remoteRequests = []; empty.preamble = ""; empty.postamble = ""
            let baseline = newBinding ? empty : (state.fileBaseline ?? empty)
            let merged = try V2ScheduleMerge.merge(base: baseline, local: before, remote: incoming)
            guard merged.conflicts.isEmpty else { throw V2ScheduleDocumentError.conflicts(merged.conflicts) }
            // Protect known local execution facts even when the file baseline predates them.
            let protected = try V2ScheduleMerge.merge(base: before, local: before, remote: merged.document)
            guard protected.conflicts.isEmpty else { throw V2ScheduleDocumentError.conflicts(protected.conflicts) }
            let after = protected.document
            try Self.validateDocumentPlacement(after)
            if newBinding { state = .init(document: after) }
            if before != after {
                state.versions.append(.init(id: requestID, createdAt: date, source: .fileImport, before: before, after: after))
                state.versions = Array(state.versions.suffix(20))
            }
            state.document = after
            state.fileBaseline = incoming
            state.lastFileReadAt = date
            if let bookmark { state.bookmark = bookmark }
            if let fileName { state.fileName = fileName }
            next.taskContexts = after.taskContexts
            next.tasks = after.tasks
            next.planItems = after.planItems
            next.executionSegments = after.executionSegments
            next.scheduleDocumentState = state
            return after
        }
    }

    func recordScheduleFileWrite(_ document: V2ScheduleDocument, bookmark: Data? = nil,
                                 fileName: String? = nil, at date: Date = Date()) throws {
        try commit(modules: ["core.sync"], commandID: "core.sync.write") { next in
            guard var state = next.scheduleDocumentState else { throw V2ScheduleDocumentError.notPrepared }
            guard state.document.id == document.id else { throw V2ScheduleDocumentError.differentDocument }
            state.fileBaseline = document
            state.lastFileWriteAt = date
            if let bookmark { state.bookmark = bookmark }
            if let fileName { state.fileName = fileName }
            next.scheduleDocumentState = state
        }
    }

    @discardableResult
    func restoreScheduleDocumentVersion(id: String, at date: Date = Date()) throws -> V2ScheduleDocument {
        try commit(modules: ["core.sync"], commandID: "core.sync.import") { next in
            guard var state = next.scheduleDocumentState,
                  let version = state.versions.first(where: { $0.id == id }) else { throw V2ScheduleDocumentError.versionNotFound }
            let current = next.scheduleDocument(using: state.document)
            var restored = current
            restored.tasks = try Self.restoreDocumentRows(before: version.before.tasks, after: version.after.tasks, current: current.tasks)
            restored.taskContexts = try Self.restoreDocumentRows(before: version.before.taskContexts, after: version.after.taskContexts, current: current.taskContexts)
            restored.planItems = try Self.restoreDocumentRows(before: version.before.planItems, after: version.after.planItems, current: current.planItems)
            for keyPath in [\V2ScheduleDocument.preamble, \.postamble, \.timeZoneIdentifier] {
                if version.before[keyPath: keyPath] != version.after[keyPath: keyPath] {
                    guard current[keyPath: keyPath] == version.after[keyPath: keyPath] else { throw V2ScheduleDocumentError.laterChanges }
                    restored[keyPath: keyPath] = version.before[keyPath: keyPath]
                }
            }
            // Execution facts and processed requests are never erased by version recovery.
            do { try Self.validateDocumentPlacement(restored) }
            catch { throw V2ScheduleDocumentError.laterChanges }
            guard restored != current else { return current }
            state.versions.append(.init(id: UUID().uuidString, createdAt: date, source: .restore, before: current, after: restored, restoredVersionID: id))
            state.versions = Array(state.versions.suffix(20))
            state.document = restored
            next.taskContexts = restored.taskContexts
            next.tasks = restored.tasks
            next.planItems = restored.planItems
            next.scheduleDocumentState = state
            return restored
        }
    }

    private static func restoreDocumentRows<T: Identifiable & Equatable>(before: [T], after: [T], current: [T]) throws -> [T] where T.ID == String {
        var result = current
        for id in Set(before.map(\.id)).union(after.map(\.id)) {
            let b = before.first { $0.id == id }
            let a = after.first { $0.id == id }
            guard b != a else { continue }
            guard current.first(where: { $0.id == id }) == a else { throw V2ScheduleDocumentError.laterChanges }
            if let b {
                if let index = result.firstIndex(where: { $0.id == id }) {
                    result[index] = b
                } else {
                    result.insert(b, at: min(before.firstIndex(where: { $0.id == id }) ?? result.count, result.count))
                }
            } else {
                result.removeAll { $0.id == id }
            }
        }
        return result
    }

    internal static func validateDocumentPlacement(_ document: V2ScheduleDocument) throws {
        try V2ScheduleMarkdown.validate(document)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: document.timeZoneIdentifier)!
        for item in document.planItems {
            if let start = item.startAt {
                guard calendar.isDate(start, inSameDayAs: item.date), item.endAt == nil || item.endAt! > start else {
                    throw V2EngineError.invalidPlanTimeRange(item.id)
                }
            } else if item.endAt != nil { throw V2EngineError.invalidPlanTimeRange(item.id) }
        }
        for task in document.tasks {
            if let parentID = task.parentID,
               document.tasks.first(where: { $0.id == parentID })?.contextID != task.contextID {
                throw V2EngineError.parentContextMismatch
            }
        }
    }
}

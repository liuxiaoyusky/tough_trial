import Foundation

public struct V2ScheduleConflictResolution: Codable, Equatable, Sendable {
    public enum Choice: String, Codable, Sendable { case local, remote, base, mergeText }
    public var id: String
    public var choice: Choice
    public var text: String?
    public init(id: String, choice: Choice, text: String? = nil) { self.id = id; self.choice = choice; self.text = text }
}

public enum V2ScheduleConflictOutcome: Equatable, Sendable {
    case resolution([V2ScheduleConflictResolution])
    case clarification(String)
}

public enum V2ScheduleConflictResolutionError: Error, LocalizedError, Sendable {
    case stale, invalidChoice, invalidCandidate
    public var errorDescription: String? {
        switch self {
        case .stale: "冲突内容已有变化，请按最新日程重新处理。"
        case .invalidChoice: "AI 的处理结果不符合当前冲突，双方内容已保留。"
        case .invalidCandidate: "处理后的时间或任务关系仍不完整，尚未应用。"
        }
    }
}

public enum V2ScheduleConflictResolver {
    public static func allowedChoices(for item: V2ScheduleConflict, in conflict: V2ScheduleSyncConflict) -> [V2ScheduleConflictResolution.Choice] {
        if item.objectType == .executionSegment,
           let original = conflict.base.executionSegments.first(where: { $0.id == item.objectID }),
           item.field != "note", (original.endAt != nil || !["endAt", "endReason"].contains(item.field)) {
            return [.base]
        }
        if item.objectType == .remoteRequest,
           conflict.base.remoteRequests.first(where: { $0.id == item.objectID })?.status != .pending,
           conflict.base.remoteRequests.contains(where: { $0.id == item.objectID }) { return [.base] }
        let textFields: Set<String> = ["title", "note", "text"]
        return textFields.contains(item.field) ? [.local, .remote, .base, .mergeText] : [.local, .remote, .base]
    }

    public static func resolve(_ conflict: V2ScheduleSyncConflict, using resolutions: [V2ScheduleConflictResolution]) throws -> V2ScheduleDocument {
        let fresh = try V2ScheduleMerge.merge(base: conflict.base, local: conflict.local, remote: conflict.remote)
        guard fresh.conflicts == conflict.conflicts else { throw V2ScheduleConflictResolutionError.stale }
        guard resolutions.count == conflict.conflicts.count,
              Set(resolutions.map(\.id)).count == resolutions.count,
              Set(resolutions.map(\.id)) == Set(conflict.conflicts.map(\.id)) else { throw V2ScheduleConflictResolutionError.invalidChoice }
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(fresh.document)) as! [String: Any]
        for resolution in resolutions {
            let item = conflict.conflicts.first { $0.id == resolution.id }!
            guard allowedChoices(for: item, in: conflict).contains(resolution.choice) else { throw V2ScheduleConflictResolutionError.invalidChoice }
            let value: V2SchedulePrimitive
            switch resolution.choice {
            case .base: value = item.base
            case .local: value = item.local
            case .remote: value = item.remote
            case .mergeText:
                guard let text = resolution.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 16_000 else {
                    throw V2ScheduleConflictResolutionError.invalidChoice
                }
                value = .string(text)
            }
            if resolution.choice != .mergeText, resolution.text != nil { throw V2ScheduleConflictResolutionError.invalidChoice }
            try patch(item, value: value, document: &object)
        }
        do {
            let document = try JSONDecoder().decode(V2ScheduleDocument.self, from: JSONSerialization.data(withJSONObject: object))
            try V2Engine.validateDocumentPlacement(document)
            let protected = try V2ScheduleMerge.merge(base: conflict.local, local: conflict.local, remote: document)
            guard protected.conflicts.isEmpty else { throw V2ScheduleConflictResolutionError.invalidCandidate }
            return protected.document
        } catch { throw V2ScheduleConflictResolutionError.invalidCandidate }
    }

    private static func patch(_ item: V2ScheduleConflict, value: V2SchedulePrimitive, document: inout [String: Any]) throws {
        if item.objectType == .preamble || item.objectType == .postamble {
            document[item.objectType == .preamble ? "preamble" : "postamble"] = try jsonValue(value, field: "text")
            return
        }
        if item.objectType == .document {
            guard item.field == "timeZoneIdentifier" else { throw V2ScheduleConflictResolutionError.invalidChoice }
            document[item.field] = try jsonValue(value, field: item.field)
            return
        }
        let collection: String
        switch item.objectType {
        case .context: collection = "taskContexts"
        case .task: collection = "tasks"
        case .planItem: collection = "planItems"
        case .executionSegment: collection = "executionSegments"
        case .remoteRequest: collection = "remoteRequests"
        default: throw V2ScheduleConflictResolutionError.invalidChoice
        }
        guard var rows = document[collection] as? [[String: Any]],
              let index = rows.firstIndex(where: { $0["id"] as? String == item.objectID }) else { throw V2ScheduleConflictResolutionError.invalidChoice }
        if item.objectType == .remoteRequest {
            guard case let .string(json) = value, let row = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
                  row["id"] as? String == item.objectID else { throw V2ScheduleConflictResolutionError.invalidChoice }
            rows[index] = row
        } else if item.field.hasPrefix("source.") {
            let field = String(item.field.dropFirst("source.".count))
            var source = rows[index]["sourceReference"] as? [String: Any] ?? [:]
            source[field] = try jsonValue(value, field: field)
            rows[index]["sourceReference"] = source
        } else {
            rows[index][item.field] = try jsonValue(value, field: item.field)
        }
        document[collection] = rows
    }

    private static func jsonValue(_ value: V2SchedulePrimitive, field: String) throws -> Any {
        switch value {
        case .null: return NSNull()
        case let .boolean(value): return value
        case let .number(value): return value
        case let .string(value):
            if ["date", "startAt", "endAt", "createdAt", "updatedAt", "completedAt", "archivedAt"].contains(field) {
                guard let date = V2ScheduleDateCoding.decode(value) else { throw V2ScheduleConflictResolutionError.invalidChoice }
                return date.timeIntervalSinceReferenceDate
            }
            return value
        }
    }
}

public extension V2Engine {
    func refreshScheduleSyncConflict() throws -> V2ScheduleSyncConflict? {
        try commit(modules: ["core.sync"], commandID: "core.sync.refreshConflict") { next in
            guard var state = next.scheduleDocumentState, var github = state.github,
                  let old = github.conflict else { return nil }
            let current = next.scheduleDocument(using: state.document)
            guard current != old.local else { return old }
            let merged = try V2ScheduleMerge.merge(base: old.base, local: current, remote: old.remote)
            github.conflict = merged.conflicts.isEmpty ? nil : .init(base: old.base, local: current,
                remote: old.remote, remoteSHA: old.remoteSHA, conflicts: merged.conflicts)
            github.requiresRetry = true
            state.github = github
            next.scheduleDocumentState = state
            return github.conflict
        }
    }

    func applyScheduleConflictResolution(conflictID: String, resolutions: [V2ScheduleConflictResolution], at date: Date = Date()) throws {
        try commit(modules: ["core.sync"], commandID: "core.sync.resolveConflict") { next in
            guard var state = next.scheduleDocumentState, var github = state.github,
                  let conflict = github.conflict, conflict.id == conflictID,
                  next.scheduleDocument(using: state.document) == conflict.local else { throw V2ScheduleConflictResolutionError.stale }
            let resolved = try V2ScheduleConflictResolver.resolve(conflict, using: resolutions)
            state.versions.append(.init(id: conflict.id, createdAt: date, source: .conflictResolution, before: conflict.local, after: resolved))
            state.versions = Array(state.versions.suffix(20))
            state.document = resolved
            github.baseline = conflict.remote
            github.sha = conflict.remoteSHA
            github.conflict = nil
            github.requiresRetry = true
            github.activeAttemptID = nil
            state.github = github
            next.taskContexts = resolved.taskContexts
            next.tasks = resolved.tasks
            next.planItems = resolved.planItems
            next.executionSegments = resolved.executionSegments
            next.scheduleDocumentState = state
        }
    }
}

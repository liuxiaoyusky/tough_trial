import Foundation

public enum V2SchedulePrimitive: Codable, Equatable, Sendable {
    case null
    case string(String)
    case number(Double)
    case boolean(Bool)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            throw DecodingError.typeMismatch(
                V2SchedulePrimitive.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected a JSON primitive")
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case let .string(value):
            try container.encode(value)
        case let .number(value):
            try container.encode(value)
        case let .boolean(value):
            try container.encode(value)
        }
    }
}

public struct V2ScheduleConflict: Codable, Equatable, Identifiable, Sendable {
    public enum ObjectType: String, Codable, Equatable, Sendable {
        case document
        case context
        case task
        case planItem
        case executionSegment
        case remoteRequest
        case preamble
        case postamble
    }

    public let objectType: ObjectType
    public let objectID: String
    public let field: String
    public let base: V2SchedulePrimitive
    public let local: V2SchedulePrimitive
    public let remote: V2SchedulePrimitive

    public var id: String {
        "\(objectType.rawValue):\(objectID):\(field)"
    }

    public init(
        objectType: ObjectType,
        objectID: String,
        field: String,
        base: V2SchedulePrimitive,
        local: V2SchedulePrimitive,
        remote: V2SchedulePrimitive
    ) {
        self.objectType = objectType
        self.objectID = objectID
        self.field = field
        self.base = base
        self.local = local
        self.remote = remote
    }
}

public struct V2ScheduleMergeResult: Equatable, Sendable {
    public let document: V2ScheduleDocument
    public let conflicts: [V2ScheduleConflict]

    public init(document: V2ScheduleDocument, conflicts: [V2ScheduleConflict]) {
        self.document = document
        self.conflicts = conflicts
    }
}

public enum V2ScheduleMergeError: Error, Equatable, Sendable {
    case differentDocumentID(base: String, local: String, remote: String)
    case invalidDocument(String)
}

public enum V2ScheduleMerge {
    public static func merge(
        base: V2ScheduleDocument,
        local: V2ScheduleDocument,
        remote: V2ScheduleDocument
    ) throws -> V2ScheduleMergeResult {
        do {
            try V2ScheduleMarkdown.validate(base)
            try V2ScheduleMarkdown.validate(local)
            try V2ScheduleMarkdown.validate(remote)
        } catch {
            throw V2ScheduleMergeError.invalidDocument(String(describing: error))
        }
        guard base.id == local.id, base.id == remote.id else {
            throw V2ScheduleMergeError.differentDocumentID(
                base: base.id,
                local: local.id,
                remote: remote.id
            )
        }

        var conflicts: [V2ScheduleConflict] = []
        let timeZone = mergedScalar(
            base: .string(base.timeZoneIdentifier),
            local: .string(local.timeZoneIdentifier),
            remote: .string(remote.timeZoneIdentifier),
            objectType: .document,
            objectID: base.id,
            field: "timeZoneIdentifier",
            conflicts: &conflicts
        )
        let preamble = mergedFreeText(
            base: base.preamble,
            local: local.preamble,
            remote: remote.preamble,
            objectType: .preamble,
            objectID: base.id,
            conflicts: &conflicts
        )
        let postamble = mergedFreeText(
            base: base.postamble,
            local: local.postamble,
            remote: remote.postamble,
            objectType: .postamble,
            objectID: base.id,
            conflicts: &conflicts
        )

        let mergedContexts = mergeContexts(
            base: base.taskContexts,
            local: local.taskContexts,
            remote: remote.taskContexts,
            conflicts: &conflicts
        )
        let mergedTasks = mergeTasks(
            base: base.tasks,
            local: local.tasks,
            remote: remote.tasks,
            conflicts: &conflicts
        )
        let mergedPlans = mergePlans(
            base: base.planItems,
            local: local.planItems,
            remote: remote.planItems,
            conflicts: &conflicts
        )
        let mergedExecutions = mergeExecutions(
            base: base.executionSegments,
            local: local.executionSegments,
            remote: remote.executionSegments,
            conflicts: &conflicts
        )

        let merged = V2ScheduleDocument(
            version: base.version,
            id: base.id,
            timeZoneIdentifier: stringValue(timeZone) ?? local.timeZoneIdentifier,
            taskContexts: mergedContexts,
            tasks: mergedTasks,
            planItems: mergedPlans,
            executionSegments: mergedExecutions,
            remoteRequests: try mergeRequests(base: base.remoteRequests, local: local.remoteRequests, remote: remote.remoteRequests, conflicts: &conflicts),
            preamble: preamble,
            postamble: postamble
        )
        do {
            try V2ScheduleMarkdown.validate(merged)
        } catch {
            throw V2ScheduleMergeError.invalidDocument(String(describing: error))
        }
        return V2ScheduleMergeResult(document: merged, conflicts: conflicts)
    }
}

private extension V2ScheduleMerge {
    typealias PrimitiveMap = [String: V2SchedulePrimitive]

    static func mergeContexts(
        base: [V2TaskContext],
        local: [V2TaskContext],
        remote: [V2TaskContext],
        conflicts: inout [V2ScheduleConflict]
    ) -> [V2TaskContext] {
        mergeIDs(base: base.map(\.id), local: local.map(\.id), remote: remote.map(\.id)).compactMap { id in
            let b = base.first { $0.id == id }
            let l = local.first { $0.id == id }
            let r = remote.first { $0.id == id }
            guard let candidate = mergePresence(base: b, local: l, remote: r) else { return nil }
            guard let localCandidate = l, let remoteCandidate = r else { return candidate }
            return mergeContextFields(
                id: id,
                base: b,
                local: localCandidate,
                remote: remoteCandidate,
                conflicts: &conflicts
            )
        }
    }

    static func mergeTasks(
        base: [V2Task],
        local: [V2Task],
        remote: [V2Task],
        conflicts: inout [V2ScheduleConflict]
    ) -> [V2Task] {
        mergeIDs(base: base.map(\.id), local: local.map(\.id), remote: remote.map(\.id)).compactMap { id in
            let b = base.first { $0.id == id }
            let l = local.first { $0.id == id }
            let r = remote.first { $0.id == id }
            guard let candidate = mergePresence(base: b, local: l, remote: r) else { return nil }
            guard let localCandidate = l, let remoteCandidate = r else { return candidate }
            return mergeTaskFields(
                id: id,
                base: b,
                local: localCandidate,
                remote: remoteCandidate,
                conflicts: &conflicts
            )
        }
    }

    static func mergePlans(
        base: [V2PlanItem],
        local: [V2PlanItem],
        remote: [V2PlanItem],
        conflicts: inout [V2ScheduleConflict]
    ) -> [V2PlanItem] {
        mergeIDs(base: base.map(\.id), local: local.map(\.id), remote: remote.map(\.id)).compactMap { id in
            let b = base.first { $0.id == id }
            let l = local.first { $0.id == id }
            let r = remote.first { $0.id == id }
            guard let candidate = mergePresence(base: b, local: l, remote: r) else { return nil }
            guard let localCandidate = l, let remoteCandidate = r else { return candidate }
            return mergePlanFields(
                id: id,
                base: b,
                local: localCandidate,
                remote: remoteCandidate,
                conflicts: &conflicts
            )
        }
    }

    static func mergeExecutions(
        base: [V2ExecutionSegment],
        local: [V2ExecutionSegment],
        remote: [V2ExecutionSegment],
        conflicts: inout [V2ScheduleConflict]
    ) -> [V2ExecutionSegment] {
        mergeIDs(base: base.map(\.id), local: local.map(\.id), remote: remote.map(\.id)).compactMap { id in
            let b = base.first { $0.id == id }
            let l = local.first { $0.id == id }
            let r = remote.first { $0.id == id }
            guard let candidate = mergePresence(base: b, local: l, remote: r) else { return nil }
            guard let localCandidate = l ?? b, let remoteCandidate = r ?? b else { return candidate }
            return mergeExecutionFields(
                id: id,
                base: b,
                local: localCandidate,
                remote: remoteCandidate,
                conflicts: &conflicts
            )
        }
    }

    static func mergeRequests(
        base: [V2ScheduleRemoteRequest], local: [V2ScheduleRemoteRequest], remote: [V2ScheduleRemoteRequest],
        conflicts: inout [V2ScheduleConflict]
    ) throws -> [V2ScheduleRemoteRequest] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        func value(_ request: V2ScheduleRemoteRequest?) throws -> V2SchedulePrimitive {
            guard let request else { return .null }
            return .string(String(decoding: try encoder.encode(request), as: UTF8.self))
        }
        return try mergeIDs(base: base.map(\.id), local: local.map(\.id), remote: remote.map(\.id)).compactMap { id in
            let b = base.first { $0.id == id }
            let l = local.first { $0.id == id } ?? b
            let r = remote.first { $0.id == id } ?? b
            if let b, b.status != .pending, l != b || r != b {
                conflicts.append(.init(objectType: .remoteRequest, objectID: id, field: "request",
                    base: try value(b), local: try value(l), remote: try value(r)))
                return b
            }
            if l == r { return l }
            if l == b { return r }
            if r == b { return l }
            // Prompt and processing result are one unit: a result cannot attach to a different prompt.
            conflicts.append(.init(objectType: .remoteRequest, objectID: id, field: "request",
                base: try value(b), local: try value(l), remote: try value(r)))
            return l ?? r
        }
    }

    static func mergePresence<T: Equatable>(base: T?, local: T?, remote: T?) -> T? {
        if let base {
            if local == nil && remote == nil { return base }
            return local ?? remote ?? base
        }
        return local ?? remote
    }

    static func mergeIDs(base: [String], local: [String], remote: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for id in base + local + remote where seen.insert(id).inserted {
            result.append(id)
        }
        return result
    }

    static func mergeContextFields(
        id: String,
        base: V2TaskContext?,
        local: V2TaskContext,
        remote: V2TaskContext,
        conflicts: inout [V2ScheduleConflict]
    ) -> V2TaskContext {
        let values = mergeFields(
            base: base.map(contextValues) ?? [:],
            local: contextValues(local),
            remote: contextValues(remote),
            objectType: .context,
            objectID: id,
            conflicts: &conflicts
        )
        return V2TaskContext(
            id: id,
            title: stringValue(values["title"]) ?? local.title,
            note: stringValue(values["note"]) ?? "",
            colorName: stringValue(values["colorName"]) ?? local.colorName,
            createdAt: dateValue(values["createdAt"], fallback: local.createdAt),
            updatedAt: dateValue(values["updatedAt"], fallback: local.updatedAt),
            archivedAt: optionalDateValue(values["archivedAt"])
        )
    }

    static func mergeTaskFields(
        id: String,
        base: V2Task?,
        local: V2Task,
        remote: V2Task,
        conflicts: inout [V2ScheduleConflict]
    ) -> V2Task {
        let values = mergeFields(
            base: base.map(taskValues) ?? [:],
            local: taskValues(local),
            remote: taskValues(remote),
            objectType: .task,
            objectID: id,
            conflicts: &conflicts
        )
        let sourceKind = stringValue(values["source.kind"])
        let sourceKey = stringValue(values["source.key"])
        let source: V2TaskSourceReference?
        if let sourceKind, let sourceKey, let kind = V2TaskSourceReference.Kind(rawValue: sourceKind) {
            source = V2TaskSourceReference(
                kind: kind,
                key: sourceKey,
                location: stringValue(values["source.location"]),
                updatedAt: optionalDateValue(values["source.updatedAt"])
            )
        } else {
            source = nil
        }
        return V2Task(
            id: id,
            contextID: stringValue(values["contextID"]),
            parentID: stringValue(values["parentID"]),
            title: stringValue(values["title"]) ?? local.title,
            note: stringValue(values["note"]) ?? "",
            kind: enumValue(values["kind"], as: V2Task.Kind.self),
            status: enumValue(values["status"], as: V2Task.Status.self) ?? local.status,
            createdAt: dateValue(values["createdAt"], fallback: local.createdAt),
            updatedAt: dateValue(values["updatedAt"], fallback: local.updatedAt),
            completedAt: optionalDateValue(values["completedAt"]),
            archivedAt: optionalDateValue(values["archivedAt"]),
            sourceReference: source
        )
    }

    static func mergePlanFields(
        id: String,
        base: V2PlanItem?,
        local: V2PlanItem,
        remote: V2PlanItem,
        conflicts: inout [V2ScheduleConflict]
    ) -> V2PlanItem {
        let values = mergeFields(
            base: base.map(planValues) ?? [:],
            local: planValues(local),
            remote: planValues(remote),
            objectType: .planItem,
            objectID: id,
            conflicts: &conflicts
        )
        return V2PlanItem(
            id: id,
            date: dateValue(values["date"], fallback: local.date),
            startAt: optionalDateValue(values["startAt"]),
            endAt: optionalDateValue(values["endAt"]),
            taskID: stringValue(values["taskID"]),
            title: stringValue(values["title"]) ?? local.title,
            sourceDraftID: stringValue(values["sourceDraftID"]),
            status: enumValue(values["status"], as: V2PlanItem.Status.self) ?? local.status
        )
    }

    static func mergeExecutionFields(
        id: String,
        base: V2ExecutionSegment?,
        local: V2ExecutionSegment,
        remote: V2ExecutionSegment,
        conflicts: inout [V2ScheduleConflict]
    ) -> V2ExecutionSegment {
        var values = mergeFields(
            base: base.map(executionValues) ?? [:],
            local: executionValues(local),
            remote: executionValues(remote),
            objectType: .executionSegment,
            objectID: id,
            conflicts: &conflicts
        )
        if let base {
            let original = executionValues(base)
            let localValues = executionValues(local)
            let remoteValues = executionValues(remote)
            var immutableFields = ["sessionID", "taskID", "titleSnapshot", "startAt", "source", "createdFromPlanItemID"]
            if base.endAt != nil { immutableFields += ["endAt", "endReason"] }
            for field in immutableFields {
                let value = original[field] ?? .null
                let l = localValues[field] ?? .null
                let r = remoteValues[field] ?? .null
                if !equivalent(l, value, field: field) || !equivalent(r, value, field: field) {
                    conflicts.removeAll { $0.objectType == .executionSegment && $0.objectID == id && $0.field == field }
                    conflicts.append(.init(objectType: .executionSegment, objectID: id, field: field, base: value, local: l, remote: r))
                }
                values[field] = value
            }
        }
        return V2ExecutionSegment(
            id: id,
            sessionID: stringValue(values["sessionID"]),
            taskID: stringValue(values["taskID"]),
            titleSnapshot: stringValue(values["titleSnapshot"]) ?? local.titleSnapshot,
            startAt: dateValue(values["startAt"], fallback: local.startAt),
            endAt: optionalDateValue(values["endAt"]),
            endReason: enumValue(values["endReason"], as: V2ExecutionSegment.EndReason.self),
            source: enumValue(values["source"], as: V2ExecutionSegment.Source.self) ?? local.source,
            createdFromPlanItemID: stringValue(values["createdFromPlanItemID"]),
            note: stringValue(values["note"]) ?? ""
        )
    }

    static func mergeFields(
        base: PrimitiveMap,
        local: PrimitiveMap,
        remote: PrimitiveMap,
        objectType: V2ScheduleConflict.ObjectType,
        objectID: String,
        conflicts: inout [V2ScheduleConflict]
    ) -> PrimitiveMap {
        let keys = Set(base.keys).union(local.keys).union(remote.keys).sorted()
        var result: PrimitiveMap = [:]
        for key in keys {
            let value = mergedScalar(
                base: base[key] ?? .null,
                local: local[key] ?? .null,
                remote: remote[key] ?? .null,
                objectType: objectType,
                objectID: objectID,
                field: key,
                conflicts: &conflicts
            )
            result[key] = value
        }
        return result
    }

    static func mergedScalar(
        base: V2SchedulePrimitive,
        local: V2SchedulePrimitive,
        remote: V2SchedulePrimitive,
        objectType: V2ScheduleConflict.ObjectType,
        objectID: String,
        field: String,
        conflicts: inout [V2ScheduleConflict]
    ) -> V2SchedulePrimitive {
        if ["updatedAt", "source.updatedAt"].contains(field),
           case let .string(l) = local, case let .string(r) = remote,
           let localDate = decodeISO(l), let remoteDate = decodeISO(r) {
            return localDate >= remoteDate ? local : remote
        }
        if equivalent(local, remote, field: field) { return local }
        if equivalent(local, base, field: field) { return remote }
        if equivalent(remote, base, field: field) { return local }
        conflicts.append(
            V2ScheduleConflict(
                objectType: objectType,
                objectID: objectID,
                field: field,
                base: base,
                local: local,
                remote: remote
            )
        )
        return local
    }

    static func equivalent(_ lhs: V2SchedulePrimitive, _ rhs: V2SchedulePrimitive, field: String) -> Bool {
        if lhs == rhs { return true }
        let dateFields: Set<String> = ["date", "startAt", "endAt", "createdAt", "updatedAt", "completedAt", "archivedAt", "source.updatedAt"]
        guard dateFields.contains(field), case let .string(a) = lhs, case let .string(b) = rhs,
              let first = decodeISO(a), let second = decodeISO(b) else { return false }
        // Legacy snapshots encode Unix Double seconds. Their unit of precision can be larger
        // than Date's reference-epoch precision; do not mistake that conversion for an edit.
        let precision = max(first.timeIntervalSince1970.ulp, second.timeIntervalSince1970.ulp)
        return abs(first.timeIntervalSince(second)) <= precision
    }

    static func mergedFreeText(
        base: String,
        local: String,
        remote: String,
        objectType: V2ScheduleConflict.ObjectType,
        objectID: String,
        conflicts: inout [V2ScheduleConflict]
    ) -> String {
        let value = mergedScalar(
            base: .string(base),
            local: .string(local),
            remote: .string(remote),
            objectType: objectType,
            objectID: objectID,
            field: "text",
            conflicts: &conflicts
        )
        guard case let .string(text) = value else { return local }
        if local != remote, local != base, remote != base {
            return "<<<<<<< local\n\(local)\n=======\n\(remote)\n>>>>>>> remote"
        }
        return text
    }

    static func contextValues(_ context: V2TaskContext) -> PrimitiveMap {
        [
            "title": .string(context.title),
            "note": .string(context.note),
            "colorName": .string(context.colorName),
            "createdAt": .string(encodeISO(context.createdAt)),
            "updatedAt": .string(encodeISO(context.updatedAt)),
            "archivedAt": context.archivedAt.map { .string(encodeISO($0)) } ?? .null
        ]
    }

    static func taskValues(_ task: V2Task) -> PrimitiveMap {
        [
            "contextID": task.contextID.map(V2SchedulePrimitive.string) ?? .null,
            "parentID": task.parentID.map(V2SchedulePrimitive.string) ?? .null,
            "title": .string(task.title),
            "note": .string(task.note),
            "kind": task.kind.map { .string($0.rawValue) } ?? .null,
            "status": .string(task.status.rawValue),
            "createdAt": .string(encodeISO(task.createdAt)),
            "updatedAt": .string(encodeISO(task.updatedAt)),
            "completedAt": task.completedAt.map { .string(encodeISO($0)) } ?? .null,
            "archivedAt": task.archivedAt.map { .string(encodeISO($0)) } ?? .null,
            "source.kind": task.sourceReference.map { .string($0.kind.rawValue) } ?? .null,
            "source.key": task.sourceReference.map { .string($0.key) } ?? .null,
            "source.location": task.sourceReference?.location.map(V2SchedulePrimitive.string) ?? .null,
            "source.updatedAt": task.sourceReference?.updatedAt.map { .string(encodeISO($0)) } ?? .null
        ]
    }

    static func planValues(_ item: V2PlanItem) -> PrimitiveMap {
        [
            "date": .string(encodeISO(item.date)),
            "startAt": item.startAt.map { .string(encodeISO($0)) } ?? .null,
            "endAt": item.endAt.map { .string(encodeISO($0)) } ?? .null,
            "taskID": item.taskID.map(V2SchedulePrimitive.string) ?? .null,
            "title": .string(item.title),
            "sourceDraftID": item.sourceDraftID.map(V2SchedulePrimitive.string) ?? .null,
            "status": .string(item.status.rawValue)
        ]
    }

    static func executionValues(_ segment: V2ExecutionSegment) -> PrimitiveMap {
        [
            "sessionID": segment.sessionID.map(V2SchedulePrimitive.string) ?? .null,
            "taskID": segment.taskID.map(V2SchedulePrimitive.string) ?? .null,
            "titleSnapshot": .string(segment.titleSnapshot),
            "startAt": .string(encodeISO(segment.startAt)),
            "endAt": segment.endAt.map { .string(encodeISO($0)) } ?? .null,
            "endReason": segment.endReason.map { .string($0.rawValue) } ?? .null,
            "source": .string(segment.source.rawValue),
            "createdFromPlanItemID": segment.createdFromPlanItemID.map(V2SchedulePrimitive.string) ?? .null,
            "note": .string(segment.note)
        ]
    }

    static func stringValue(_ value: V2SchedulePrimitive?) -> String? {
        guard case let .string(value) = value else { return nil }
        return value
    }

    static func dateValue(_ value: V2SchedulePrimitive?, fallback: Date) -> Date {
        guard let raw = stringValue(value), let date = decodeISO(raw) else { return fallback }
        return date
    }

    static func optionalDateValue(_ value: V2SchedulePrimitive?) -> Date? {
        guard let raw = stringValue(value) else { return nil }
        return decodeISO(raw)
    }

    static func enumValue<T: RawRepresentable>(
        _ value: V2SchedulePrimitive?,
        as type: T.Type
    ) -> T? where T.RawValue == String {
        guard let raw = stringValue(value) else { return nil }
        return T(rawValue: raw)
    }

    static func encodeISO(_ date: Date) -> String { V2ScheduleDateCoding.encode(date) }

    static func decodeISO(_ value: String) -> Date? { V2ScheduleDateCoding.decode(value) }
}

extension V2ScheduleMergeError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .differentDocumentID: "这几份文件属于不同日程，无法直接合并。"
        case .invalidDocument: "日程内容暂时无法合并，请检查任务关系与时间；原数据已保留。"
        }
    }
}

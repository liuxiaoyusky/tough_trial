import Foundation

public struct V2ScheduleDocument: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var id: String
    public var timeZoneIdentifier: String
    public var taskContexts: [V2TaskContext]
    public var tasks: [V2Task]
    public var planItems: [V2PlanItem]
    public var executionSegments: [V2ExecutionSegment]
    public var remoteRequests: [V2ScheduleRemoteRequest]
    public var preamble: String
    public var postamble: String

    public init(
        version: Int = V2ScheduleDocument.currentVersion,
        id: String,
        timeZoneIdentifier: String,
        taskContexts: [V2TaskContext],
        tasks: [V2Task],
        planItems: [V2PlanItem],
        executionSegments: [V2ExecutionSegment],
        remoteRequests: [V2ScheduleRemoteRequest] = [],
        preamble: String = "",
        postamble: String = ""
    ) {
        self.version = version
        self.id = id
        self.timeZoneIdentifier = timeZoneIdentifier
        self.taskContexts = taskContexts
        self.tasks = tasks
        self.planItems = planItems
        self.executionSegments = executionSegments
        self.remoteRequests = remoteRequests
        self.preamble = preamble
        self.postamble = postamble
    }

    private enum CodingKeys: String, CodingKey {
        case version, id, timeZoneIdentifier, taskContexts, tasks, planItems, executionSegments, remoteRequests, preamble, postamble
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        id = try c.decode(String.self, forKey: .id)
        timeZoneIdentifier = try c.decode(String.self, forKey: .timeZoneIdentifier)
        taskContexts = try c.decode([V2TaskContext].self, forKey: .taskContexts)
        tasks = try c.decode([V2Task].self, forKey: .tasks)
        planItems = try c.decode([V2PlanItem].self, forKey: .planItems)
        executionSegments = try c.decode([V2ExecutionSegment].self, forKey: .executionSegments)
        remoteRequests = try c.decodeIfPresent([V2ScheduleRemoteRequest].self, forKey: .remoteRequests) ?? []
        preamble = try c.decode(String.self, forKey: .preamble)
        postamble = try c.decode(String.self, forKey: .postamble)
    }

}

public enum V2ScheduleMarkdownError: Error, Equatable, Sendable {
    case emptyDocument
    case missingOwnedRegion
    case duplicateOwnedMarker(String)
    case missingDocumentHeader
    case invalidDocumentHeader
    case unsupportedVersion(Int)
    case invalidTimeZone(String)
    case invalidAttribute(String)
    case missingAttribute(String)
    case invalidVisibleValue(String)
    case malformedRecord(String)
    case duplicateID(String)
    case invalidReference(String)
    case invalidHierarchy(String)
}

public enum V2ScheduleMarkdown {
    private static let beginMarker = "<!-- tough-trial:begin owned -->"
    private static let endMarker = "<!-- tough-trial:end owned -->"

    public static func decode(_ markdown: String) throws -> V2ScheduleDocument {
        let normalized = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        guard !normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw V2ScheduleMarkdownError.emptyDocument
        }

        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let beginIndexes = lines.indices.filter { lines[$0].trimmingCharacters(in: .whitespaces) == beginMarker }
        let endIndexes = lines.indices.filter { lines[$0].trimmingCharacters(in: .whitespaces) == endMarker }
        guard beginIndexes.count == 1 else {
            if beginIndexes.isEmpty { throw V2ScheduleMarkdownError.missingOwnedRegion }
            throw V2ScheduleMarkdownError.duplicateOwnedMarker("begin")
        }
        guard endIndexes.count == 1 else {
            if endIndexes.isEmpty { throw V2ScheduleMarkdownError.missingOwnedRegion }
            throw V2ScheduleMarkdownError.duplicateOwnedMarker("end")
        }
        let beginIndex = beginIndexes[0]
        let endIndex = endIndexes[0]
        guard beginIndex < endIndex else {
            throw V2ScheduleMarkdownError.missingOwnedRegion
        }

        let preamble = lines[..<beginIndex].joined(separator: "\n")
        let postamble: String
        if endIndex + 1 < lines.count {
            postamble = lines[(endIndex + 1)...].joined(separator: "\n")
        } else {
            postamble = ""
        }
        let owned = Array(lines[(beginIndex + 1)..<endIndex])

        var version: Int?
        var documentID: String?
        var timeZoneIdentifier: String?
        var textEncoding: String?
        var contexts: [V2TaskContext] = []
        var tasks: [V2Task] = []
        var planItems: [V2PlanItem] = []
        var executionSegments: [V2ExecutionSegment] = []
        var remoteRequests: [V2ScheduleRemoteRequest] = []
        var section: Section?
        section = nil
        var index = 0
        var ordinal = 0

        while index < owned.count {
            let line = owned[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                index += 1
                continue
            }

            if let header = try parseMarker(line, keyword: "document", requireVisiblePrefix: false) {
                guard version == nil else {
                    throw V2ScheduleMarkdownError.invalidDocumentHeader
                }
                let rawVersion = try requiredText(header.attributes, key: "version")
                guard let parsedVersion = Int(rawVersion) else {
                    throw V2ScheduleMarkdownError.invalidDocumentHeader
                }
                version = parsedVersion
                documentID = try requiredText(header.attributes, key: "id")
                timeZoneIdentifier = try requiredText(header.attributes, key: "timezone")
                textEncoding = try optionalText(header.attributes, key: "textEncoding")
                guard textEncoding == nil || textEncoding == "entities-v1" else {
                    throw V2ScheduleMarkdownError.invalidAttribute("textEncoding")
                }
                index += 1
                continue
            }

            if trimmed.hasPrefix("<!-- tough-trial:") {
                throw V2ScheduleMarkdownError.malformedRecord("unexpected metadata")
            }

            if trimmed.hasPrefix("## ") {
                guard let nextSection = Section(rawValue: String(trimmed.dropFirst(3))) else {
                    throw V2ScheduleMarkdownError.malformedRecord("unknown section")
                }
                section = nextSection
                index += 1
                continue
            }

            guard let currentSection = section else {
                throw V2ScheduleMarkdownError.malformedRecord("record outside section")
            }
            ordinal += 1
            switch currentSection {
            case .contexts:
                contexts.append(try parseContext(
                    lines: owned,
                    index: &index,
                    ordinal: ordinal
                ))
            case .tasks:
                tasks.append(try parseTask(
                    lines: owned,
                    index: &index,
                    ordinal: ordinal
                ))
            case .plans:
                planItems.append(try parsePlanItem(
                    lines: owned,
                    index: &index,
                    ordinal: ordinal,
                    timeZoneIdentifier: timeZoneIdentifier ?? ""
                ))
            case .requests:
                remoteRequests.append(try parseRemoteRequest(lines: owned, index: &index, ordinal: ordinal))
            case .executions:
                executionSegments.append(try parseExecutionSegment(
                    lines: owned,
                    index: &index,
                    ordinal: ordinal
                ))
            }
        }

        guard let version, let documentID, let timeZoneIdentifier else {
            throw V2ScheduleMarkdownError.missingDocumentHeader
        }
        var document = V2ScheduleDocument(
            version: version,
            id: documentID,
            timeZoneIdentifier: timeZoneIdentifier,
            taskContexts: contexts,
            tasks: tasks,
            planItems: planItems,
            executionSegments: executionSegments,
            remoteRequests: remoteRequests,
            preamble: preamble,
            postamble: postamble
        )
        if textEncoding == "entities-v1" {
            document = mapRecordText(document) { text, _ in decodeRecordText(text) }
        }
        try validate(document)
        return document
    }

    public static func encode(_ document: V2ScheduleDocument) throws -> String {
        try validate(document)
        let document = mapRecordText(document, transform: encodeRecordText)
        let attributes = [
            attribute("version", String(document.version)),
            attribute("id", document.id),
            attribute("timezone", document.timeZoneIdentifier),
            attribute("textEncoding", "entities-v1")
        ].joined(separator: " ")
        var lines: [String] = [
            beginMarker,
            "<!-- tough-trial:document \(attributes) -->",
            "",
            "## 分类"
        ]

        for context in document.taskContexts {
            lines.append("- \(context.title) \(inlineMarker("context", contextIDAttributes(context)))")
            appendNote(context.note, to: &lines)
            lines.append(metadataMarker("context-meta", contextIDAttributes(context)))
            lines.append("")
        }

        lines.append("## 任务")
        for task in document.tasks {
            let checkbox = task.status == .done ? "x" : " "
            lines.append("- [\(checkbox)] \(task.title) \(inlineMarker("task", taskAttributes(task)))")
            appendNote(task.note, to: &lines)
            lines.append(metadataMarker("task-meta", taskAttributes(task)))
            lines.append("")
        }

        lines.append("## 排期")
        for item in document.planItems {
            let visible = try visiblePlanValue(item, timeZoneIdentifier: document.timeZoneIdentifier)
            lines.append("- \(visible) \(inlineMarker("plan", planAttributes(item)))")
            lines.append(metadataMarker("plan-meta", planAttributes(item)))
            lines.append("")
        }

        lines.append("## 执行记录")
        for segment in document.executionSegments {
            let visible = visibleExecutionValue(segment)
            lines.append("- \(visible) \(inlineMarker("execution", executionAttributes(segment)))")
            appendNote(segment.note, to: &lines)
            lines.append(metadataMarker("execution-meta", executionAttributes(segment)))
            lines.append("")
        }

        if !document.remoteRequests.isEmpty {
            lines.append("## 云端请求")
            for request in document.remoteRequests {
                let promptLines = request.prompt.components(separatedBy: "\n")
                let checkbox = request.status == .pending ? " " : "x"
                lines.append("- [\(checkbox)] \(promptLines[0]) \(inlineMarker("request", ["id": request.id]))")
                for line in promptLines.dropFirst() { lines.append("  " + line) }
                lines.append(metadataMarker("request-meta", [
                    "id": request.id, "status": request.status.rawValue,
                    "created": encodeISO(request.createdAt), "processed": request.processedAt.map(encodeISO)
                ]))
                if let result = request.result {
                    for line in result.components(separatedBy: "\n") { lines.append("> " + line) }
                }
                lines.append("")
            }
        }
        while lines.last == "" { lines.removeLast() }
        lines.append(endMarker)
        var result = lines.joined(separator: "\n")
        if !document.preamble.isEmpty {
            result = document.preamble + "\n" + result
        }
        if !document.postamble.isEmpty {
            if !result.hasSuffix("\n") { result += "\n" }
            result += document.postamble
        }
        return result
    }

    public static func validate(_ document: V2ScheduleDocument) throws {
        guard document.version == V2ScheduleDocument.currentVersion else {
            throw V2ScheduleMarkdownError.unsupportedVersion(document.version)
        }
        guard !document.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw V2ScheduleMarkdownError.invalidDocumentHeader
        }
        guard TimeZone(identifier: document.timeZoneIdentifier) != nil else {
            throw V2ScheduleMarkdownError.invalidTimeZone(document.timeZoneIdentifier)
        }
        for (kind, titles) in [
            ("context", document.taskContexts.map(\.title)), ("task", document.tasks.map(\.title)),
            ("plan", document.planItems.map(\.title)), ("execution", document.executionSegments.map(\.titleSnapshot))
        ] {
            guard titles.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                throw V2ScheduleMarkdownError.malformedRecord("empty \(kind) title")
            }
        }
        try ensureUniqueIDs(document.taskContexts.map(\.id), collection: "context")
        try ensureUniqueIDs(document.tasks.map(\.id), collection: "task")
        try ensureUniqueIDs(document.planItems.map(\.id), collection: "plan")
        try ensureUniqueIDs(document.executionSegments.map(\.id), collection: "execution")

        try ensureUniqueIDs(document.remoteRequests.map(\.id), collection: "request")
        for request in document.remoteRequests {
            guard request.prompt.components(separatedBy: "\n").first?.trimmingCharacters(in: .whitespaces).isEmpty == false else {
                throw V2ScheduleMarkdownError.malformedRecord("empty request")
            }
            if request.status == .pending {
                guard request.processedAt == nil, request.result == nil else {
                    throw V2ScheduleMarkdownError.invalidVisibleValue("pending request contains a result")
                }
            } else {
                guard let processedAt = request.processedAt, processedAt >= request.createdAt,
                      request.result?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                    throw V2ScheduleMarkdownError.invalidVisibleValue("processed request lacks a result")
                }
            }
        }
        let contextIDs = Set(document.taskContexts.map(\.id))
        let taskIDs = Set(document.tasks.map(\.id))
        let planIDs = Set(document.planItems.map(\.id))
        for task in document.tasks {
            if let contextID = task.contextID, !contextIDs.contains(contextID) {
                throw V2ScheduleMarkdownError.invalidReference("task \(task.id) context \(contextID)")
            }
            if let parentID = task.parentID {
                guard parentID != task.id, taskIDs.contains(parentID) else {
                    throw V2ScheduleMarkdownError.invalidReference("task \(task.id) parent \(parentID)")
                }
            }
            if task.status == .done, task.completedAt == nil {
                // Completion can predate the protocol migration. The visible checkbox remains sufficient.
                _ = task.completedAt
            }
            if let source = task.sourceReference, source.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw V2ScheduleMarkdownError.invalidReference("task \(task.id) source")
            }
        }
        guard !containsTaskCycle(document.tasks) else {
            throw V2ScheduleMarkdownError.invalidHierarchy("task cycle")
        }
        for item in document.planItems {
            if let taskID = item.taskID, !taskIDs.contains(taskID) {
                throw V2ScheduleMarkdownError.invalidReference("plan \(item.id) task \(taskID)")
            }
        }
        for segment in document.executionSegments {
            if let taskID = segment.taskID, !taskIDs.contains(taskID) {
                throw V2ScheduleMarkdownError.invalidReference("execution \(segment.id) task \(taskID)")
            }
            if let planID = segment.createdFromPlanItemID, !planIDs.contains(planID) {
                throw V2ScheduleMarkdownError.invalidReference("execution \(segment.id) plan \(planID)")
            }
            if let endAt = segment.endAt, endAt < segment.startAt {
                throw V2ScheduleMarkdownError.invalidVisibleValue("execution end before start")
            }
            if segment.endAt == nil, segment.endReason != nil {
                throw V2ScheduleMarkdownError.invalidVisibleValue("open execution has end reason")
            }
        }
    }
}

private extension V2ScheduleMarkdown {
    enum Section: String {
        case contexts = "分类"
        case tasks = "任务"
        case plans = "排期"
        case executions = "执行记录"
        case requests = "云端请求"
    }

    enum AttributeValue: Equatable {
        case text(String)
        case null
    }

    struct ParsedMarker {
        let attributes: [String: AttributeValue]
        let visiblePrefix: String
    }

    static func parseContext(lines: [String], index: inout Int, ordinal: Int) throws -> V2TaskContext {
        let row = lines[index]
        guard row.hasPrefix("- ") else { throw V2ScheduleMarkdownError.malformedRecord("context row") }
        let marker = try parseMarker(row, keyword: "context", requireVisiblePrefix: true)
        let markerPrefix = marker.map { String($0.visiblePrefix.dropFirst(2)) }
        let title = try visibleText(markerPrefix ?? String(row.dropFirst(2)), kind: "context")
        let inlineID = marker.flatMap { try? optionalText($0.attributes, key: "id") }
        index += 1
        let tail = try consumeTail(lines: lines, index: &index, keyword: "context-meta")
        let metadataID = try optionalText(tail.attributes, key: "id")
        let id = inlineID ?? metadataID ?? generatedID("context", seed: "\(title)|\(ordinal)")
        if !tail.attributes.isEmpty {
            try requireMetadataKeys(
                tail.attributes,
                keys: ["id", "color", "created", "updated", "archived"]
            )
        }
        try ensureMetadataID(tail.attributes, expected: id, required: inlineID != nil)
        let createdAt = try dateAttribute(tail.attributes, key: "created") ?? .distantPast
        let updatedAt = try dateAttribute(tail.attributes, key: "updated") ?? createdAt
        return V2TaskContext(
            id: id,
            title: title,
            note: tail.note,
            colorName: try textAttribute(tail.attributes, key: "color", fallback: "default"),
            createdAt: createdAt,
            updatedAt: updatedAt,
            archivedAt: try dateAttribute(tail.attributes, key: "archived")
        )
    }

    static func parseTask(lines: [String], index: inout Int, ordinal: Int) throws -> V2Task {
        let row = lines[index]
        let parsedCheckbox = try parseCheckboxRow(row, keyword: "task")
        index += 1
        let tail = try consumeTail(lines: lines, index: &index, keyword: "task-meta")
        let inlineID = parsedCheckbox.marker.flatMap { try? optionalText($0.attributes, key: "id") }
        let metadataID = try optionalText(tail.attributes, key: "id")
        let id = inlineID ?? metadataID ?? generatedID("task", seed: "\(parsedCheckbox.title)|\(ordinal)")
        if !tail.attributes.isEmpty {
            try requireMetadataKeys(
                tail.attributes,
                keys: [
                    "id", "context", "parent", "kind", "status", "created", "updated",
                    "completed", "archived", "sourceKind", "sourceKey", "sourceLocation", "sourceUpdated"
                ]
            )
        }
        try ensureMetadataID(tail.attributes, expected: id, required: inlineID != nil)
        let defaultStatus: V2Task.Status = parsedCheckbox.checked ? .done : .notStarted
        var status = try enumAttribute(tail.attributes, key: "status", fallback: defaultStatus)
        if parsedCheckbox.checked { status = .done }
        if !parsedCheckbox.checked, status == .done { status = .notStarted }
        return V2Task(
            id: id,
            contextID: try optionalTextAttribute(tail.attributes, key: "context"),
            parentID: try optionalTextAttribute(tail.attributes, key: "parent"),
            title: parsedCheckbox.title,
            note: tail.note,
            kind: try optionalEnumAttribute(tail.attributes, key: "kind", as: V2Task.Kind.self),
            status: status,
            createdAt: try dateAttribute(tail.attributes, key: "created") ?? .distantPast,
            updatedAt: try dateAttribute(tail.attributes, key: "updated") ?? .distantPast,
            completedAt: try dateAttribute(tail.attributes, key: "completed"),
            archivedAt: try dateAttribute(tail.attributes, key: "archived"),
            sourceReference: try sourceReference(tail.attributes)
        )
    }

    static func parsePlanItem(
        lines: [String],
        index: inout Int,
        ordinal: Int,
        timeZoneIdentifier: String
    ) throws -> V2PlanItem {
        let row = lines[index]
        guard row.hasPrefix("- ") else { throw V2ScheduleMarkdownError.malformedRecord("plan row") }
        let marker = try parseMarker(row, keyword: "plan", requireVisiblePrefix: true)
        let markerPrefix = marker.map { String($0.visiblePrefix.dropFirst(2)) }
        let visible = try visibleText(markerPrefix ?? String(row.dropFirst(2)), kind: "plan")
        let parsedVisible = try parsePlanVisible(visible, timeZoneIdentifier: timeZoneIdentifier)
        index += 1
        let tail = try consumeTail(lines: lines, index: &index, keyword: "plan-meta")
        let inlineID = marker.flatMap { try? optionalText($0.attributes, key: "id") }
        let metadataID = try optionalText(tail.attributes, key: "id")
        let id = inlineID ?? metadataID ?? generatedID("plan", seed: "\(visible)|\(ordinal)")
        if !tail.attributes.isEmpty {
            try requireMetadataKeys(tail.attributes, keys: ["id", "task", "sourceDraft", "status"])
        }
        try ensureMetadataID(tail.attributes, expected: id, required: inlineID != nil)
        return V2PlanItem(
            id: id,
            date: parsedVisible.date,
            startAt: parsedVisible.startAt,
            endAt: parsedVisible.endAt,
            taskID: try optionalTextAttribute(tail.attributes, key: "task"),
            title: parsedVisible.title,
            sourceDraftID: try optionalTextAttribute(tail.attributes, key: "sourceDraft"),
            status: try enumAttribute(tail.attributes, key: "status", fallback: .planned)
        )
    }

    static func parseExecutionSegment(lines: [String], index: inout Int, ordinal: Int) throws -> V2ExecutionSegment {
        let row = lines[index]
        guard row.hasPrefix("- ") else { throw V2ScheduleMarkdownError.malformedRecord("execution row") }
        let marker = try parseMarker(row, keyword: "execution", requireVisiblePrefix: true)
        let markerPrefix = marker.map { String($0.visiblePrefix.dropFirst(2)) }
        let visible = try visibleText(markerPrefix ?? String(row.dropFirst(2)), kind: "execution")
        let parsedVisible = try parseExecutionVisible(visible)
        index += 1
        let tail = try consumeTail(lines: lines, index: &index, keyword: "execution-meta")
        let inlineID = marker.flatMap { try? optionalText($0.attributes, key: "id") }
        let metadataID = try optionalText(tail.attributes, key: "id")
        let id = inlineID ?? metadataID ?? generatedID("execution", seed: "\(visible)|\(ordinal)")
        if !tail.attributes.isEmpty {
            try requireMetadataKeys(
                tail.attributes,
                keys: ["id", "session", "task", "endReason", "source", "plan"]
            )
        }
        try ensureMetadataID(tail.attributes, expected: id, required: inlineID != nil)
        return V2ExecutionSegment(
            id: id,
            sessionID: try optionalTextAttribute(tail.attributes, key: "session"),
            taskID: try optionalTextAttribute(tail.attributes, key: "task"),
            titleSnapshot: parsedVisible.title,
            startAt: parsedVisible.startAt,
            endAt: parsedVisible.endAt,
            endReason: try optionalEnumAttribute(tail.attributes, key: "endReason", as: V2ExecutionSegment.EndReason.self),
            source: try enumAttribute(tail.attributes, key: "source", fallback: .normal),
            createdFromPlanItemID: try optionalTextAttribute(tail.attributes, key: "plan"),
            note: tail.note
        )
    }

    static func parseRemoteRequest(lines: [String], index: inout Int, ordinal: Int) throws -> V2ScheduleRemoteRequest {
        let row = try parseCheckboxRow(lines[index], keyword: "request")
        index += 1
        let tail = try consumeTail(lines: lines, index: &index, keyword: "request-meta")
        let inlineID = try row.marker.flatMap { try optionalText($0.attributes, key: "id") }
        let prompt = row.title + (tail.hasNoteLines ? "\n" + tail.note : "")
        let id = try inlineID ?? optionalText(tail.attributes, key: "id") ?? generatedID("request", seed: "\(prompt)|\(ordinal)")
        try ensureMetadataID(tail.attributes, expected: id, required: inlineID != nil)
        let status: V2ScheduleRemoteRequest.Status = try enumAttribute(tail.attributes, key: "status", fallback: .pending)
        guard row.checked == (status != .pending) else {
            throw V2ScheduleMarkdownError.invalidVisibleValue("request checkbox differs from status")
        }
        var resultLines: [String] = []
        while index < lines.count, lines[index].hasPrefix("> ") {
            resultLines.append(String(lines[index].dropFirst(2)))
            index += 1
        }
        return V2ScheduleRemoteRequest(id: id, prompt: prompt, status: status,
            createdAt: try dateAttribute(tail.attributes, key: "created") ?? .distantPast,
            processedAt: try dateAttribute(tail.attributes, key: "processed"),
            result: resultLines.isEmpty ? nil : resultLines.joined(separator: "\n"))
    }

    struct RecordTail {
        let note: String
        let hasNoteLines: Bool
        let attributes: [String: AttributeValue]
    }

    static func consumeTail(
        lines: [String],
        index: inout Int,
        keyword: String
    ) throws -> RecordTail {
        var noteLines: [String] = []
        while index < lines.count {
            let line = lines[index]
            if line.hasPrefix("  ") {
                noteLines.append(String(line.dropFirst(2)))
                index += 1
                continue
            }
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                index += 1
                continue
            }
            break
        }
        guard index < lines.count else {
            return RecordTail(note: noteLines.joined(separator: "\n"), hasNoteLines: !noteLines.isEmpty, attributes: [:])
        }
        if let marker = try parseMarker(lines[index], keyword: keyword, requireVisiblePrefix: false) {
            index += 1
            return RecordTail(note: noteLines.joined(separator: "\n"), hasNoteLines: !noteLines.isEmpty, attributes: marker.attributes)
        }
        if lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("<!-- tough-trial:") {
            throw V2ScheduleMarkdownError.malformedRecord("\(keyword) metadata")
        }
        return RecordTail(note: noteLines.joined(separator: "\n"), hasNoteLines: !noteLines.isEmpty, attributes: [:])
    }

    struct CheckboxRow {
        let checked: Bool
        let title: String
        let marker: ParsedMarker?
    }

    static func parseCheckboxRow(_ line: String, keyword: String) throws -> CheckboxRow {
        let characters = Array(line)
        guard characters.count >= 6,
              characters[0] == "-",
              characters[1] == " ",
              characters[2] == "[",
              characters[4] == "]",
              characters[5] == " " else {
            throw V2ScheduleMarkdownError.malformedRecord("task checkbox")
        }
        guard characters[3] == " " || characters[3] == "x" || characters[3] == "X" else {
            throw V2ScheduleMarkdownError.invalidVisibleValue("task checkbox")
        }
        let rest = String(characters.dropFirst(6))
        let marker = try parseMarker(line, keyword: keyword, requireVisiblePrefix: true)
        let markerPrefix = marker.map { String($0.visiblePrefix.dropFirst(6)) }
        let title = try visibleText(markerPrefix ?? rest, kind: "task")
        return CheckboxRow(checked: characters[3] != " ", title: title, marker: marker)
    }

    static func parseMarker(
        _ line: String,
        keyword: String,
        requireVisiblePrefix: Bool
    ) throws -> ParsedMarker? {
        let needle = "<!-- tough-trial:\(keyword)"
        guard let markerStart = line.range(of: needle) else {
            if line.contains("<!-- tough-trial:") && requireVisiblePrefix {
                throw V2ScheduleMarkdownError.malformedRecord("unexpected marker")
            }
            return nil
        }
        let afterKeyword = line[markerStart.upperBound...]
        guard afterKeyword.first == " " else {
            throw V2ScheduleMarkdownError.invalidAttribute(keyword)
        }
        guard let close = line.range(of: "-->", range: markerStart.upperBound..<line.endIndex) else {
            throw V2ScheduleMarkdownError.malformedRecord("unterminated marker")
        }
        let suffix = line[close.upperBound...].trimmingCharacters(in: .whitespaces)
        guard suffix.isEmpty else { throw V2ScheduleMarkdownError.malformedRecord("marker suffix") }
        let rawAttributes = String(line[markerStart.upperBound..<close.lowerBound])
            .trimmingCharacters(in: .whitespaces)
        let attributes = try parseAttributes(rawAttributes)
        let visiblePrefix = String(line[..<markerStart.lowerBound]).trimmingCharacters(in: .whitespaces)
        if !requireVisiblePrefix && !visiblePrefix.isEmpty {
            throw V2ScheduleMarkdownError.malformedRecord("metadata visible text")
        }
        return ParsedMarker(attributes: attributes, visiblePrefix: visiblePrefix)
    }

    static func parseAttributes(_ raw: String) throws -> [String: AttributeValue] {
        var result: [String: AttributeValue] = [:]
        var index = raw.startIndex
        while index < raw.endIndex {
            while index < raw.endIndex, raw[index].isWhitespace { index = raw.index(after: index) }
            if index == raw.endIndex { break }
            let keyStart = index
            while index < raw.endIndex,
                  raw[index].isLetter || raw[index].isNumber || raw[index] == "_" || raw[index] == "-" {
                index = raw.index(after: index)
            }
            guard keyStart != index else { throw V2ScheduleMarkdownError.invalidAttribute(raw) }
            let key = String(raw[keyStart..<index])
            while index < raw.endIndex, raw[index].isWhitespace { index = raw.index(after: index) }
            guard index < raw.endIndex, raw[index] == "=" else {
                throw V2ScheduleMarkdownError.invalidAttribute(key)
            }
            index = raw.index(after: index)
            while index < raw.endIndex, raw[index].isWhitespace { index = raw.index(after: index) }
            guard index < raw.endIndex else { throw V2ScheduleMarkdownError.invalidAttribute(key) }
            let value: AttributeValue
            if raw[index] == "\"" {
                index = raw.index(after: index)
                var decoded = ""
                var closed = false
                while index < raw.endIndex {
                    let character = raw[index]
                    index = raw.index(after: index)
                    if character == "\"" {
                        closed = true
                        break
                    }
                    if character == "\\" {
                        guard index < raw.endIndex else { throw V2ScheduleMarkdownError.invalidAttribute(key) }
                        let escaped = raw[index]
                        index = raw.index(after: index)
                        switch escaped {
                        case "n": decoded.append("\n")
                        case "r": decoded.append("\r")
                        case "\\": decoded.append("\\")
                        case "\"": decoded.append("\"")
                        default: throw V2ScheduleMarkdownError.invalidAttribute(key)
                        }
                    } else {
                        decoded.append(character)
                    }
                }
                guard closed else { throw V2ScheduleMarkdownError.invalidAttribute(key) }
                value = .text(decoded)
            } else {
                let valueStart = index
                while index < raw.endIndex, !raw[index].isWhitespace { index = raw.index(after: index) }
                let rawValue = String(raw[valueStart..<index])
                guard rawValue == "null" else { throw V2ScheduleMarkdownError.invalidAttribute(key) }
                value = .null
            }
            guard result[key] == nil else { throw V2ScheduleMarkdownError.invalidAttribute(key) }
            result[key] = value
        }
        return result
    }

    static func visibleText(_ text: String, kind: String) throws -> String {
        let value = text.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { throw V2ScheduleMarkdownError.malformedRecord("empty \(kind) title") }
        return value
    }

    static func requiredText(_ attributes: [String: AttributeValue], key: String) throws -> String {
        guard case let .text(value) = attributes[key], !value.isEmpty else {
            throw V2ScheduleMarkdownError.missingAttribute(key)
        }
        return value
    }

    static func optionalText(_ attributes: [String: AttributeValue], key: String) throws -> String? {
        guard let value = attributes[key] else { return nil }
        switch value {
        case let .text(value): return value.isEmpty ? nil : value
        case .null: return nil
        }
    }

    static func textAttribute(
        _ attributes: [String: AttributeValue],
        key: String,
        fallback: String
    ) throws -> String {
        try optionalText(attributes, key: key) ?? fallback
    }

    static func optionalTextAttribute(_ attributes: [String: AttributeValue], key: String) throws -> String? {
        try optionalText(attributes, key: key)
    }

    static func requireMetadataKeys(
        _ attributes: [String: AttributeValue],
        keys: [String]
    ) throws {
        for key in keys where attributes[key] == nil {
            throw V2ScheduleMarkdownError.missingAttribute(key)
        }
    }

    static func enumAttribute<T: RawRepresentable>(
        _ attributes: [String: AttributeValue],
        key: String,
        fallback: T
    ) throws -> T where T.RawValue == String {
        guard let raw = try optionalText(attributes, key: key) else { return fallback }
        guard let value = T(rawValue: raw) else { throw V2ScheduleMarkdownError.invalidAttribute(key) }
        return value
    }

    static func optionalEnumAttribute<T: RawRepresentable>(
        _ attributes: [String: AttributeValue],
        key: String,
        as type: T.Type
    ) throws -> T? where T.RawValue == String {
        guard let raw = try optionalText(attributes, key: key) else { return nil }
        guard let value = T(rawValue: raw) else { throw V2ScheduleMarkdownError.invalidAttribute(key) }
        return value
    }

    static func dateAttribute(
        _ attributes: [String: AttributeValue],
        key: String,
        fallback: Date? = nil
    ) throws -> Date? {
        guard let raw = try optionalText(attributes, key: key) else { return fallback }
        guard let date = decodeISO(raw) else { throw V2ScheduleMarkdownError.invalidAttribute(key) }
        return date
    }

    static func ensureMetadataID(
        _ attributes: [String: AttributeValue],
        expected: String,
        required: Bool
    ) throws {
        guard let raw = try optionalText(attributes, key: "id") else {
            if required { throw V2ScheduleMarkdownError.missingAttribute("id") }
            return
        }
        guard raw == expected else { throw V2ScheduleMarkdownError.invalidReference("metadata id") }
    }

    static func sourceReference(_ attributes: [String: AttributeValue]) throws -> V2TaskSourceReference? {
        let kindRaw = try optionalText(attributes, key: "sourceKind")
        let key = try optionalText(attributes, key: "sourceKey")
        guard kindRaw != nil || key != nil else { return nil }
        guard let kindRaw, let kind = V2TaskSourceReference.Kind(rawValue: kindRaw), let key, !key.isEmpty else {
            throw V2ScheduleMarkdownError.invalidReference("source")
        }
        return V2TaskSourceReference(
            kind: kind,
            key: key,
            location: try optionalTextAttribute(attributes, key: "sourceLocation"),
            updatedAt: try dateAttribute(attributes, key: "sourceUpdated")
        )
    }

    struct VisiblePlan {
        let date: Date
        let startAt: Date?
        let endAt: Date?
        let title: String
    }

    static func parsePlanVisible(_ value: String, timeZoneIdentifier: String) throws -> VisiblePlan {
        let parts = value.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2 else { throw V2ScheduleMarkdownError.invalidVisibleValue("plan") }
        let dateAndTime = parts[0].trimmingCharacters(in: .whitespaces)
        let title = try visibleText(parts[1], kind: "plan")
        let tokens = dateAndTime.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard let dateRaw = tokens.first else { throw V2ScheduleMarkdownError.invalidVisibleValue("plan date") }
        let timeZone = try scheduleTimeZone(timeZoneIdentifier)
        guard let date = parseDate(dateRaw, timeZone: timeZone) else {
            throw V2ScheduleMarkdownError.invalidVisibleValue("plan date")
        }
        guard tokens.count <= 2 else { throw V2ScheduleMarkdownError.invalidVisibleValue("plan time") }
        guard tokens.count == 2 else {
            return VisiblePlan(date: date, startAt: nil, endAt: nil, title: title)
        }
        let timeRange = tokens[1]
        let rangeParts: [String]
        if timeRange.contains("–") {
            rangeParts = timeRange.split(separator: "–", omittingEmptySubsequences: false).map(String.init)
        } else if timeRange.count == 11, timeRange[timeRange.index(timeRange.startIndex, offsetBy: 5)] == "-" {
            rangeParts = timeRange.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        } else {
            rangeParts = [timeRange]
        }
        guard rangeParts.count <= 2,
              let start = parseLocalDateTime(dateRaw: dateRaw, time: rangeParts[0], timeZone: timeZone) else {
            throw V2ScheduleMarkdownError.invalidVisibleValue("plan time")
        }
        var end: Date?
        if rangeParts.count == 2 {
            let endParts = rangeParts[1].split(separator: "+", omittingEmptySubsequences: false).map(String.init)
            guard endParts.count <= 2 else { throw V2ScheduleMarkdownError.invalidVisibleValue("plan end") }
            var endDay = date
            if endParts.count == 2 {
                guard endParts[1].hasSuffix("d"), let days = Int(endParts[1].dropLast()),
                      (1...366).contains(days) else { throw V2ScheduleMarkdownError.invalidVisibleValue("plan end day") }
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = timeZone
                guard let shifted = calendar.date(byAdding: .day, value: days, to: date) else {
                    throw V2ScheduleMarkdownError.invalidVisibleValue("plan end day")
                }
                endDay = shifted
            }
            end = parseLocalDateTime(dateRaw: localDateString(endDay, timeZone: timeZone), time: endParts[0], timeZone: timeZone)
        }
        guard rangeParts.count != 2 || end != nil, end == nil || end! >= start else {
            throw V2ScheduleMarkdownError.invalidVisibleValue("plan time range")
        }
        return VisiblePlan(date: date, startAt: start, endAt: end, title: title)
    }

    struct VisibleExecution {
        let startAt: Date
        let endAt: Date?
        let title: String
    }

    static func parseExecutionVisible(_ value: String) throws -> VisibleExecution {
        let parts = value.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2 else { throw V2ScheduleMarkdownError.invalidVisibleValue("execution") }
        let times = parts[0].trimmingCharacters(in: .whitespaces)
        let timeParts: [String]
        if times.contains("→") {
            timeParts = times.split(separator: "→", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        } else {
            timeParts = times.components(separatedBy: "->")
        }
        guard timeParts.count == 2, let start = decodeISO(timeParts[0].trimmingCharacters(in: .whitespaces)) else {
            throw V2ScheduleMarkdownError.invalidVisibleValue("execution time")
        }
        let endRaw = timeParts[1].trimmingCharacters(in: .whitespaces)
        let end = endRaw == "—" || endRaw == "-" || endRaw.isEmpty ? nil : decodeISO(endRaw)
        guard endRaw == "—" || endRaw == "-" || endRaw.isEmpty || end != nil else {
            throw V2ScheduleMarkdownError.invalidVisibleValue("execution end")
        }
        guard end == nil || end! >= start else { throw V2ScheduleMarkdownError.invalidVisibleValue("execution range") }
        return VisibleExecution(startAt: start, endAt: end, title: try visibleText(parts[1], kind: "execution"))
    }

    static func parseDate(_ raw: String, timeZone: TimeZone) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: raw), formatter.string(from: date) == raw else { return nil }
        return date
    }

    static func parseLocalDateTime(dateRaw: String, time: String, timeZone: TimeZone) -> Date? {
        guard time.count == 5,
              time[time.index(time.startIndex, offsetBy: 2)] == ":",
              let hour = Int(time.prefix(2)),
              let minute = Int(time.suffix(2)),
              (0..<24).contains(hour),
              (0..<60).contains(minute),
              let date = parseDate(dateRaw, timeZone: timeZone) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let result = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date),
              calendar.isDate(result, inSameDayAs: date),
              calendar.component(.hour, from: result) == hour,
              calendar.component(.minute, from: result) == minute else { return nil }
        return result
    }

    static func scheduleTimeZone(_ identifier: String) throws -> TimeZone {
        guard let timeZone = TimeZone(identifier: identifier) else {
            throw V2ScheduleMarkdownError.invalidTimeZone(identifier)
        }
        return timeZone
    }

    static func visiblePlanValue(_ item: V2PlanItem, timeZoneIdentifier: String) throws -> String {
        let timeZone = try scheduleTimeZone(timeZoneIdentifier)
        let date = localDateString(item.date, timeZone: timeZone)
        let time: String
        if let startAt = item.startAt {
            let start = localTimeString(startAt, timeZone: timeZone)
            if let endAt = item.endAt {
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = timeZone
                let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: item.date), to: calendar.startOfDay(for: endAt)).day ?? 0
                let suffix = days > 0 ? "+\(days)d" : ""
                time = " \(start)–\(localTimeString(endAt, timeZone: timeZone))\(suffix)"
            } else {
                time = " \(start)"
            }
        } else {
            time = ""
        }
        return "\(date)\(time) | \(item.title)"
    }

    static func visibleExecutionValue(_ segment: V2ExecutionSegment) -> String {
        let end = segment.endAt.map(encodeISO) ?? "—"
        return "\(encodeISO(segment.startAt)) → \(end) | \(segment.titleSnapshot)"
    }

    static func localDateString(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func localTimeString(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    static func encodeISO(_ date: Date) -> String { V2ScheduleDateCoding.encode(date) }

    static func decodeISO(_ value: String) -> Date? { V2ScheduleDateCoding.decode(value) }

    static func appendNote(_ note: String, to lines: inout [String]) {
        guard !note.isEmpty else { return }
        for line in note.split(separator: "\n", omittingEmptySubsequences: false) {
            lines.append("  \(line)")
        }
    }

    /// Only human text is escaped; identifiers, dates, and prose outside the owned region stay unchanged.
    static func mapRecordText(_ document: V2ScheduleDocument, transform: (String, Bool) -> String) -> V2ScheduleDocument {
        var result = document
        for index in result.taskContexts.indices {
            result.taskContexts[index].title = transform(result.taskContexts[index].title, false)
            result.taskContexts[index].note = transform(result.taskContexts[index].note, true)
        }
        for index in result.tasks.indices {
            result.tasks[index].title = transform(result.tasks[index].title, false)
            result.tasks[index].note = transform(result.tasks[index].note, true)
        }
        for index in result.planItems.indices {
            result.planItems[index].title = transform(result.planItems[index].title, false)
        }
        for index in result.executionSegments.indices {
            result.executionSegments[index].titleSnapshot = transform(result.executionSegments[index].titleSnapshot, false)
            result.executionSegments[index].note = transform(result.executionSegments[index].note, true)
        }
        for index in result.remoteRequests.indices {
            var lines = result.remoteRequests[index].prompt.components(separatedBy: "\n")
            lines[0] = transform(lines[0], false)
            for line in lines.indices.dropFirst() { lines[line] = transform(lines[line], true) }
            result.remoteRequests[index].prompt = lines.joined(separator: "\n")
            result.remoteRequests[index].result = result.remoteRequests[index].result.map { transform($0, true) }
        }
        return result
    }

    static func encodeRecordText(_ text: String, multiline: Bool) -> String {
        let scalars = Array(text.unicodeScalars)
        return scalars.enumerated().map { index, scalar in
            switch scalar.value {
            case 38: return "&amp;"
            case 60: return "&lt;"
            case 62: return "&gt;"
            case 13: return "&#13;"
            case 10 where !multiline: return "&#10;"
            default:
                if !multiline, (index == 0 || index == scalars.count - 1), CharacterSet.whitespaces.contains(scalar) {
                    return "&#\(scalar.value);"
                }
                return String(scalar)
            }
        }.joined()
    }

    static func decodeRecordText(_ text: String) -> String {
        let pattern = try! NSRegularExpression(pattern: "&(?:amp|lt|gt|#[0-9]+);")
        let result = NSMutableString(string: text)
        // Match the original text once so a literal '&amp;lt;' never becomes '<'.
        for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            let token = (text as NSString).substring(with: match.range)
            let replacement: String
            switch token {
            case "&amp;": replacement = "&"
            case "&lt;": replacement = "<"
            case "&gt;": replacement = ">"
            default:
                guard let value = UInt32(token.dropFirst(2).dropLast()), let scalar = UnicodeScalar(value) else { continue }
                replacement = String(scalar)
            }
            result.replaceCharacters(in: match.range, with: replacement)
        }
        return result as String
    }

    static func attribute(_ key: String, _ value: String?) -> String {
        guard let value else { return "\(key)=null" }
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\(key)=\"\(escaped)\""
    }

    static func inlineMarker(_ keyword: String, _ attributes: [String: String?]) -> String {
        "<!-- tough-trial:\(keyword) \(attributes.keys.sorted().map { attribute($0, attributes[$0] ?? nil) }.joined(separator: " ")) -->"
    }

    static func metadataMarker(_ keyword: String, _ attributes: [String: String?]) -> String {
        "<!-- tough-trial:\(keyword) \(attributes.keys.sorted().map { attribute($0, attributes[$0] ?? nil) }.joined(separator: " ")) -->"
    }

    static func contextIDAttributes(_ context: V2TaskContext) -> [String: String?] {
        [
            "id": context.id,
            "color": context.colorName,
            "created": encodeISO(context.createdAt),
            "updated": encodeISO(context.updatedAt),
            "archived": context.archivedAt.map(encodeISO)
        ]
    }

    static func taskAttributes(_ task: V2Task) -> [String: String?] {
        [
            "id": task.id,
            "context": task.contextID,
            "parent": task.parentID,
            "kind": task.kind?.rawValue,
            "status": task.status.rawValue,
            "created": encodeISO(task.createdAt),
            "updated": encodeISO(task.updatedAt),
            "completed": task.completedAt.map(encodeISO),
            "archived": task.archivedAt.map(encodeISO),
            "sourceKind": task.sourceReference?.kind.rawValue,
            "sourceKey": task.sourceReference?.key,
            "sourceLocation": task.sourceReference?.location,
            "sourceUpdated": task.sourceReference?.updatedAt.map(encodeISO)
        ]
    }

    static func planAttributes(_ item: V2PlanItem) -> [String: String?] {
        [
            "id": item.id,
            "task": item.taskID,
            "sourceDraft": item.sourceDraftID,
            "status": item.status.rawValue
        ]
    }

    static func executionAttributes(_ segment: V2ExecutionSegment) -> [String: String?] {
        [
            "id": segment.id,
            "session": segment.sessionID,
            "task": segment.taskID,
            "endReason": segment.endReason?.rawValue,
            "source": segment.source.rawValue,
            "plan": segment.createdFromPlanItemID
        ]
    }

    static func generatedID(_ prefix: String, seed: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return "\(prefix)-auto-\(String(hash, radix: 16))"
    }

    static func ensureUniqueIDs(_ ids: [String], collection: String) throws {
        var seen = Set<String>()
        for id in ids {
            guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw V2ScheduleMarkdownError.duplicateID("empty \(collection) id")
            }
            guard seen.insert(id).inserted else {
                throw V2ScheduleMarkdownError.duplicateID("\(collection):\(id)")
            }
        }
    }

    static func containsTaskCycle(_ tasks: [V2Task]) -> Bool {
        let parentByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0.parentID) })
        for task in tasks {
            var visited = Set<String>()
            var current = task.id
            while let parent = parentByID[current] ?? nil {
                guard visited.insert(current).inserted else { return true }
                current = parent
            }
        }
        return false
    }
}

extension V2ScheduleMarkdownError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .emptyDocument, .missingOwnedRegion, .duplicateOwnedMarker, .missingDocumentHeader, .invalidDocumentHeader:
            "这不是完整的 Tough Trial 日程文件。请检查文件内容，当前日程未被覆盖。"
        case .unsupportedVersion:
            "暂不支持这个日程文件版本，请更新应用后再读取。"
        case .invalidTimeZone:
            "文件中的时区无法识别，请检查后再读取。"
        case .duplicateID:
            "文件中有重复的条目标识，请检查重复行后再读取。"
        case .invalidReference, .invalidHierarchy:
            "文件中的任务关系不完整或存在循环，请检查关联条目。"
        case .invalidAttribute, .missingAttribute, .invalidVisibleValue, .malformedRecord:
            "文件中的日期、时间或条目格式不完整，请检查后再读取。"
        }
    }
}

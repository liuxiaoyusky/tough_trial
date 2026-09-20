import Foundation
import ToughTrialV2Core

func checkScheduleMarkdownPreservesLiteralProtocolText() throws {
    let cases = [
        ("协议备注", "第一行\n<!-- tough-trial:end owned -->\n不要删第二行"),
        ("记录协议\n保留细节", "含有 &lt; 与 &#10;，不能再次解码"),
        ("复制 <!-- tough-trial:task id=\"example\" --> 标记", "文本末尾\n")
    ]
    for (title, note) in cases {
        let engine = V2Engine()
        _ = try engine.createTask(title: title, note: note)
        let document = try engine.prepareScheduleDocument(timeZoneIdentifier: "Asia/Shanghai")
        let decoded = try V2ScheduleMarkdown.decode(V2ScheduleMarkdown.encode(document))
        require(decoded == document, "Literal protocol text and multiline titles must round-trip without changing content")
    }
}

func checkScheduleMarkdownRoundTripPreservesDocumentIdentity() throws {
    let document = V2ScheduleDocument(
        id: "schedule-test",
        timeZoneIdentifier: "Asia/Shanghai",
        taskContexts: [],
        tasks: [],
        planItems: [],
        executionSegments: [],
        preamble: "# 我的日程\n\n> 这是给人的说明。\n\n",
        postamble: "\n## 备注\n保留这段正文。"
    )

    let encoded = try V2ScheduleMarkdown.encode(document)
    let decoded = try V2ScheduleMarkdown.decode(encoded)

    require(decoded == document, "A minimal schedule document should round-trip exactly")
}

func checkScheduleMarkdownRoundTripPreservesAllOwnedFields() throws {
    let timeZone = TimeZone(identifier: "Asia/Shanghai")!
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let planDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 7))!
    let startAt = calendar.date(from: DateComponents(year: 2026, month: 9, day: 7, hour: 9, minute: 5))!
    let endAt = calendar.date(from: DateComponents(year: 2026, month: 9, day: 7, hour: 10, minute: 35))!
    let context = V2TaskContext(
        id: "context-home",
        title: "个人",
        note: "保留分类说明。",
        colorName: "violet",
        createdAt: Date(timeIntervalSince1970: 1_700_000_001),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_002),
        archivedAt: nil
    )
    let task = V2Task(
        id: "task-run",
        contextID: context.id,
        title: "跑步",
        note: "先热身\n不要超过 30 分钟。",
        kind: .commitment,
        status: .active,
        createdAt: Date(timeIntervalSince1970: 1_700_000_003),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_004),
        completedAt: nil,
        archivedAt: nil,
        sourceReference: V2TaskSourceReference(
            kind: .github,
            key: "schedule:task-run",
            location: "schedule.md",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_005)
        )
    )
    let child = V2Task(
        id: "task-shoes",
        contextID: context.id,
        parentID: task.id,
        title: "准备跑鞋",
        note: "",
        kind: .maintenance,
        status: .done,
        createdAt: Date(timeIntervalSince1970: 1_700_000_006),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_007),
        completedAt: Date(timeIntervalSince1970: 1_700_000_008),
        archivedAt: nil,
        sourceReference: nil
    )
    let plan = V2PlanItem(
        id: "plan-run",
        date: planDate,
        startAt: startAt,
        endAt: endAt,
        taskID: task.id,
        title: "跑步",
        sourceDraftID: "draft-1",
        status: .planned
    )
    let segment = V2ExecutionSegment(
        id: "segment-run",
        sessionID: "session-1",
        taskID: task.id,
        titleSnapshot: "跑步",
        startAt: startAt,
        endAt: endAt,
        endReason: .stopped,
        source: .normal,
        createdFromPlanItemID: plan.id,
        note: "完成一组。"
    )
    let document = V2ScheduleDocument(
        id: "schedule-test",
        timeZoneIdentifier: timeZone.identifier,
        taskContexts: [context],
        tasks: [task, child],
        planItems: [plan],
        executionSegments: [segment],
        preamble: "# 我的日程\n\n> 这是给人的说明。\n\n",
        postamble: "\n## 备注\n保留这段正文。"
    )

    let encoded = try V2ScheduleMarkdown.encode(document)
    let decoded = try V2ScheduleMarkdown.decode(encoded)

    require(decoded == document, "All owned schedule fields should round-trip exactly")
    require(encoded.contains("- [ ] 跑步"), "A non-completed task should remain an unchecked human row")
    require(encoded.contains("2026-09-07 09:05–10:35 | 跑步"), "Schedule date and time should stay visible")
    require(encoded.contains("先热身"), "Task notes should stay ordinary Markdown text")
    require(encoded.contains("sourceKind=\"github\""), "Source metadata should retain stable source identity")

    var literal = document
    literal.taskContexts[0].title = "分类\n<&>"
    literal.taskContexts[0].note = "分类说明\n<!-- tough-trial:end owned -->"
    literal.planItems[0].title = "排期\n不是 <!-- tough-trial:plan -->"
    literal.executionSegments[0].titleSnapshot = "执行\n<!-- tough-trial:execution -->"
    literal.executionSegments[0].note = "记录\r\n&lt; 与 &#10; 是文字\n"
    literal.remoteRequests = [.init(id: "literal-request", prompt: "  保留 &lt;\n<!-- tough-trial:begin owned -->\r\n",
        status: .processed, createdAt: startAt, processedAt: endAt, result: "结果\r\n<!-- tough-trial:end owned -->\n&lt;")]
    literal.preamble += "标记外的 &lt; 不变。\n"
    let literalText = try V2ScheduleMarkdown.encode(literal)
    let literalDecoded = try V2ScheduleMarkdown.decode(literalText)
    require(literalDecoded == literal,
        "All record text, request results, line endings and outside prose must round-trip unchanged")
    let humanEdit = literalText.replacingOccurrences(of: "排期&#10;", with: "人工修改&#10;")
    let humanDecoded = try V2ScheduleMarkdown.decode(humanEdit)
    require(humanDecoded.planItems[0].title == "人工修改\n不是 <!-- tough-trial:plan -->",
        "Escaped titles must remain editable without losing line breaks")
}

func checkScheduleMarkdownTextEncodingCompatibility() throws {
    let legacy = """
    <!-- tough-trial:begin owned -->
    <!-- tough-trial:document version="1" id="legacy-text" timezone="Asia/Shanghai" -->
    ## 任务
    - [ ] 保留 &lt; 与 &#10;
      &amp; 不解码
    <!-- tough-trial:end owned -->
    """
    let document = try V2ScheduleMarkdown.decode(legacy)
    require(document.tasks[0].title == "保留 &lt; 与 &#10;" && document.tasks[0].note == "&amp; 不解码",
        "Unmarked legacy documents must retain literal entity text")
    let encoded = try V2ScheduleMarkdown.encode(document)
    let decoded = try V2ScheduleMarkdown.decode(encoded)
    require(decoded == document, "Legacy text must survive re-export using explicit encoding")
    let unsupported = encoded.replacingOccurrences(of: "entities-v1", with: "future-encoding")
    do {
        _ = try V2ScheduleMarkdown.decode(unsupported)
        require(false, "Unknown text encoding must be rejected")
    } catch V2ScheduleMarkdownError.invalidAttribute("textEncoding") { }
    let emptyTitle = encoded.replacingOccurrences(of: "保留 &amp;lt; 与 &amp;#10;", with: "&#32;&#10;&#9;")
    do {
        _ = try V2ScheduleMarkdown.decode(emptyTitle)
        require(false, "Escaped whitespace must not bypass empty-title validation")
    } catch V2ScheduleMarkdownError.malformedRecord("empty task title") { }
}

func checkScheduleMarkdownHumanFieldsAreEditable() throws {
    let timeZone = TimeZone(identifier: "Asia/Shanghai")!
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: 7))!
    let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 7, hour: 9, minute: 0))!
    let end = calendar.date(from: DateComponents(year: 2026, month: 9, day: 7, hour: 10, minute: 0))!
    let context = V2TaskContext(
        id: "context-1",
        title: "个人",
        colorName: "blue",
        createdAt: .distantPast,
        updatedAt: .distantPast
    )
    let task = V2Task(
        id: "task-1",
        contextID: context.id,
        title: "跑步",
        note: "原说明",
        kind: .commitment,
        status: .active,
        createdAt: .distantPast,
        updatedAt: .distantPast
    )
    let plan = V2PlanItem(
        id: "plan-1",
        date: date,
        startAt: start,
        endAt: end,
        taskID: task.id,
        title: task.title
    )
    let document = V2ScheduleDocument(
        id: "schedule-1",
        timeZoneIdentifier: timeZone.identifier,
        taskContexts: [context],
        tasks: [task],
        planItems: [plan],
        executionSegments: []
    )

    let edited = try V2ScheduleMarkdown.encode(document)
        .replacingOccurrences(of: "- [ ] 跑步", with: "- [x] 完成晨跑")
        .replacingOccurrences(of: "原说明", with: "改后的说明")
        .replacingOccurrences(of: "2026-09-07 09:00–10:00 | 跑步", with: "2026-09-08 18:30–19:15 | 完成晨跑")
    let decoded = try V2ScheduleMarkdown.decode(edited)

    require(decoded.tasks.first?.id == task.id, "Human title edits must retain the hidden stable ID")
    require(decoded.tasks.first?.title == "完成晨跑", "Human task title edits should be imported")
    require(decoded.tasks.first?.status == .done, "The visible checkbox should control completion")
    require(decoded.tasks.first?.note == "改后的说明", "Human note edits should be imported")
    require(decoded.planItems.first?.title == "完成晨跑", "Human schedule title edits should be imported")
    require(decoded.planItems.first?.date == calendar.date(from: DateComponents(year: 2026, month: 9, day: 8)), "Human schedule date edits should be imported")
    require(decoded.planItems.first?.startAt == calendar.date(from: DateComponents(year: 2026, month: 9, day: 8, hour: 18, minute: 30)), "Human schedule start edits should be imported")
    require(decoded.planItems.first?.endAt == calendar.date(from: DateComponents(year: 2026, month: 9, day: 8, hour: 19, minute: 15)), "Human schedule end edits should be imported")
}

func checkScheduleMarkdownAssignsStableIDsToNewRows() throws {
    let markdown = """
    这段说明属于用户正文。
    <!-- tough-trial:begin owned -->
    <!-- tough-trial:document version=\"1\" id=\"schedule-1\" timezone=\"Asia/Shanghai\" -->
    ## 分类
    ## 任务
    - [ ] 新增任务
    ## 排期
    ## 执行记录
    <!-- tough-trial:end owned -->
    末尾说明也应保留。
    """

    let first = try V2ScheduleMarkdown.decode(markdown)
    let second = try V2ScheduleMarkdown.decode(markdown)
    let firstID = first.tasks.first?.id
    let encoded = try V2ScheduleMarkdown.encode(first)
    let roundTripped = try V2ScheduleMarkdown.decode(encoded)

    require(firstID != nil, "A task row without an ID should receive an ID")
    require(first == second, "Generated IDs should be deterministic for the same new row")
    require(roundTripped == first, "A generated ID should survive the next round trip")
}

func checkScheduleMarkdownRejectsBrokenDocumentsWithoutPartialResults() throws {
    let valid = """
    <!-- tough-trial:begin owned -->
    <!-- tough-trial:document version=\"1\" id=\"schedule-1\" timezone=\"Asia/Shanghai\" -->
    ## 分类
    - 个人 <!-- tough-trial:context id=\"context-1\" -->
    <!-- tough-trial:context-meta archived=null color=\"blue\" created=\"1970-01-01T00:00:00Z\" id=\"context-1\" updated=\"1970-01-01T00:00:00Z\" -->
    ## 任务
    - [ ] 任务一 <!-- tough-trial:task id=\"task-1\" -->
    <!-- tough-trial:task-meta archived=null completed=null context=\"context-1\" created=\"1970-01-01T00:00:00Z\" id=\"task-1\" kind=null parent=null sourceKey=null sourceKind=null sourceLocation=null sourceUpdated=null status=\"notStarted\" updated=\"1970-01-01T00:00:00Z\" -->
    ## 排期
    ## 执行记录
    <!-- tough-trial:end owned -->
    """

    func expectDecodeFailure(_ markdown: String, _ expected: V2ScheduleMarkdownError? = nil, _ message: String) {
        do {
            _ = try V2ScheduleMarkdown.decode(markdown)
            fatalError(message)
        } catch let error as V2ScheduleMarkdownError {
            if let expected { require(error == expected, message) }
        } catch {
            fatalError(message)
        }
    }

    expectDecodeFailure(
        valid.replacingOccurrences(of: "<!-- tough-trial:end owned -->", with: ""),
        .missingOwnedRegion,
        "A truncated owned region must be rejected"
    )
    let duplicateID = valid
        .replacingOccurrences(
            of: "## 排期",
            with: """
            - [ ] 任务二 <!-- tough-trial:task id=\"task-2\" -->
            <!-- tough-trial:task-meta archived=null completed=null context=\"context-1\" created=\"1970-01-01T00:00:00Z\" id=\"task-2\" kind=null parent=null sourceKey=null sourceKind=null sourceLocation=null sourceUpdated=null status=\"notStarted\" updated=\"1970-01-01T00:00:00Z\" -->
            ## 排期
            """
        )
        .replacingOccurrences(of: "task-2", with: "task-1")
    expectDecodeFailure(duplicateID, nil, "Duplicate IDs must be rejected")

    let brokenReference = valid.replacingOccurrences(of: "context=\"context-1\"", with: "context=\"missing\"")
    expectDecodeFailure(brokenReference, .invalidReference("task task-1 context missing"), "Broken references must be rejected")
}

func checkScheduleMergeCombinesIndependentEdits() throws {
    let baseTask = V2Task(
        id: "task-1",
        title: "原任务",
        note: "原备注",
        status: .notStarted,
        createdAt: .distantPast,
        updatedAt: .distantPast
    )
    let base = V2ScheduleDocument(
        id: "schedule-1",
        timeZoneIdentifier: "Asia/Shanghai",
        taskContexts: [],
        tasks: [baseTask],
        planItems: [],
        executionSegments: [],
        preamble: "说明",
        postamble: "尾注"
    )
    var localTask = baseTask
    localTask.title = "本地标题"
    var remoteTask = baseTask
    remoteTask.note = "远端备注"
    let local = V2ScheduleDocument(
        id: base.id,
        timeZoneIdentifier: base.timeZoneIdentifier,
        taskContexts: [],
        tasks: [localTask],
        planItems: [],
        executionSegments: [],
        preamble: base.preamble,
        postamble: base.postamble
    )
    let remote = V2ScheduleDocument(
        id: base.id,
        timeZoneIdentifier: base.timeZoneIdentifier,
        taskContexts: [],
        tasks: [remoteTask],
        planItems: [],
        executionSegments: [],
        preamble: base.preamble,
        postamble: base.postamble
    )

    let result = try V2ScheduleMerge.merge(base: base, local: local, remote: remote)

    require(result.conflicts.isEmpty, "Independent task fields should merge without conflict")
    require(result.document.tasks.first?.title == "本地标题", "Local task title edit should be retained")
    require(result.document.tasks.first?.note == "远端备注", "Remote task note edit should be retained")
}

func checkScheduleMergeRetainsConcurrentFieldCandidates() throws {
    let task = V2Task(
        id: "task-1",
        title: "原任务",
        note: "原备注",
        status: .notStarted,
        createdAt: .distantPast,
        updatedAt: .distantPast
    )
    let base = V2ScheduleDocument(
        id: "schedule-1",
        timeZoneIdentifier: "Asia/Shanghai",
        taskContexts: [],
        tasks: [task],
        planItems: [],
        executionSegments: []
    )
    var localTask = task
    localTask.title = "本地标题"
    var remoteTask = task
    remoteTask.title = "远端标题"
    let local = V2ScheduleDocument(
        id: base.id,
        timeZoneIdentifier: base.timeZoneIdentifier,
        taskContexts: [],
        tasks: [localTask],
        planItems: [],
        executionSegments: []
    )
    let remote = V2ScheduleDocument(
        id: base.id,
        timeZoneIdentifier: base.timeZoneIdentifier,
        taskContexts: [],
        tasks: [remoteTask],
        planItems: [],
        executionSegments: []
    )

    let result = try V2ScheduleMerge.merge(base: base, local: local, remote: remote)
    guard let conflict = result.conflicts.first(where: {
        $0.objectType == .task && $0.objectID == task.id && $0.field == "title"
    }) else {
        fatalError("Concurrent task title edits should produce a typed conflict")
    }

    require(conflict.base == .string("原任务"), "A conflict should retain the base candidate")
    require(conflict.local == .string("本地标题"), "A conflict should retain the local candidate")
    require(conflict.remote == .string("远端标题"), "A conflict should retain the remote candidate")
    require(result.document.tasks.first?.title == "本地标题", "The provisional document should use a deterministic local candidate")

    let data = try JSONEncoder().encode(conflict)
    let json = String(decoding: data, as: UTF8.self)
    require(json.contains("本地标题") && json.contains("远端标题"), "Conflict candidates should be JSON serializable")
}

func checkScheduleMergeRetainsMissingRowsAndAppendsExecutionFacts() throws {
    let task = V2Task(
        id: "task-1",
        title: "基础任务",
        status: .notStarted,
        createdAt: .distantPast,
        updatedAt: .distantPast
    )
    let base = V2ScheduleDocument(
        id: "schedule-1",
        timeZoneIdentifier: "Asia/Shanghai",
        taskContexts: [],
        tasks: [task],
        planItems: [],
        executionSegments: []
    )
    var archived = task
    archived.status = .archived
    archived.archivedAt = Date(timeIntervalSince1970: 1_700_000_100)
    let local = V2ScheduleDocument(
        id: base.id,
        timeZoneIdentifier: base.timeZoneIdentifier,
        taskContexts: [],
        tasks: [],
        planItems: [],
        executionSegments: []
    )
    let remote = V2ScheduleDocument(
        id: base.id,
        timeZoneIdentifier: base.timeZoneIdentifier,
        taskContexts: [],
        tasks: [archived],
        planItems: [],
        executionSegments: []
    )

    let retained = try V2ScheduleMerge.merge(base: base, local: local, remote: base)
    require(retained.document.tasks.count == 1, "A missing row must not be interpreted as deletion")
    require(retained.conflicts.isEmpty, "A missing row against an unchanged peer should not conflict")

    let explicitlyArchived = try V2ScheduleMerge.merge(base: base, local: remote, remote: base)
    require(explicitlyArchived.document.tasks.first?.status == .archived, "An explicit archive state should propagate as a removal intent")

    let segmentA = V2ExecutionSegment(
        id: "segment-a",
        taskID: task.id,
        titleSnapshot: task.title,
        startAt: Date(timeIntervalSince1970: 1_700_001_000),
        endAt: Date(timeIntervalSince1970: 1_700_001_060),
        endReason: .stopped,
        source: .normal
    )
    let segmentB = V2ExecutionSegment(
        id: "segment-b",
        taskID: task.id,
        titleSnapshot: task.title,
        startAt: Date(timeIntervalSince1970: 1_700_002_000),
        endAt: Date(timeIntervalSince1970: 1_700_002_060),
        endReason: .stopped,
        source: .normal
    )
    let localFacts = V2ScheduleDocument(
        id: base.id,
        timeZoneIdentifier: base.timeZoneIdentifier,
        taskContexts: [],
        tasks: [task],
        planItems: [],
        executionSegments: [segmentA]
    )
    let remoteFacts = V2ScheduleDocument(
        id: base.id,
        timeZoneIdentifier: base.timeZoneIdentifier,
        taskContexts: [],
        tasks: [task],
        planItems: [],
        executionSegments: [segmentB]
    )
    let facts = try V2ScheduleMerge.merge(base: base, local: localFacts, remote: remoteFacts)
    require(Set(facts.document.executionSegments.map(\.id)) == ["segment-a", "segment-b"], "Concurrent execution facts with different IDs should both append")
    require(facts.conflicts.isEmpty, "Independent execution facts should not conflict")
}

func checkScheduleMergeConflictsWhenExecutionFactChanges() throws {
    let task = V2Task(
        id: "task-1",
        title: "基础任务",
        status: .notStarted,
        createdAt: .distantPast,
        updatedAt: .distantPast
    )
    let baseSegment = V2ExecutionSegment(
        id: "segment-1",
        taskID: task.id,
        titleSnapshot: task.title,
        startAt: Date(timeIntervalSince1970: 1_700_001_000),
        endAt: Date(timeIntervalSince1970: 1_700_001_060),
        endReason: .stopped,
        source: .normal
    )
    let base = V2ScheduleDocument(
        id: "schedule-1",
        timeZoneIdentifier: "Asia/Shanghai",
        taskContexts: [],
        tasks: [task],
        planItems: [],
        executionSegments: [baseSegment]
    )
    var localSegment = baseSegment
    localSegment.note = "本地修订"
    var remoteSegment = baseSegment
    remoteSegment.note = "远端修订"
    let local = V2ScheduleDocument(
        id: base.id,
        timeZoneIdentifier: base.timeZoneIdentifier,
        taskContexts: [],
        tasks: [task],
        planItems: [],
        executionSegments: [localSegment]
    )
    let remote = V2ScheduleDocument(
        id: base.id,
        timeZoneIdentifier: base.timeZoneIdentifier,
        taskContexts: [],
        tasks: [task],
        planItems: [],
        executionSegments: [remoteSegment]
    )

    let result = try V2ScheduleMerge.merge(base: base, local: local, remote: remote)
    guard let conflict = result.conflicts.first(where: {
        $0.objectType == .executionSegment && $0.objectID == baseSegment.id && $0.field == "note"
    }) else {
        fatalError("Concurrent execution fact edits should produce a typed conflict")
    }
    require(conflict.base == .string(""), "Execution conflict should retain the original fact")
    require(conflict.local == .string("本地修订"), "Execution conflict should retain local fact candidate")
    require(conflict.remote == .string("远端修订"), "Execution conflict should retain remote fact candidate")
}

func checkScheduleMergeValidatesDocumentIdentityAndHierarchy() throws {
    let task = V2Task(
        id: "task-1",
        title: "基础任务",
        status: .notStarted,
        createdAt: .distantPast,
        updatedAt: .distantPast
    )
    let base = V2ScheduleDocument(
        id: "schedule-1",
        timeZoneIdentifier: "Asia/Shanghai",
        taskContexts: [],
        tasks: [task],
        planItems: [],
        executionSegments: []
    )
    let differentDocument = V2ScheduleDocument(
        id: "schedule-other",
        timeZoneIdentifier: base.timeZoneIdentifier,
        taskContexts: [],
        tasks: [task],
        planItems: [],
        executionSegments: []
    )
    do {
        _ = try V2ScheduleMerge.merge(base: base, local: differentDocument, remote: base)
        fatalError("Different document IDs must be rejected")
    } catch let error as V2ScheduleMergeError {
        require(
            error == .differentDocumentID(base: "schedule-1", local: "schedule-other", remote: "schedule-1"),
            "Different document IDs should report all three IDs"
        )
    }

    var first = task
    first.id = "task-a"
    first.parentID = "task-b"
    var second = task
    second.id = "task-b"
    second.parentID = "task-a"
    let cyclic = V2ScheduleDocument(
        id: base.id,
        timeZoneIdentifier: base.timeZoneIdentifier,
        taskContexts: [],
        tasks: [first, second],
        planItems: [],
        executionSegments: []
    )
    do {
        _ = try V2ScheduleMerge.merge(base: base, local: cyclic, remote: base)
        fatalError("Cyclic task hierarchy must be rejected")
    } catch let error as V2ScheduleMergeError {
        guard case .invalidDocument = error else {
            fatalError("Cyclic task hierarchy should report an invalid document")
        }
    }
}

func checkScheduleMergePreservesConcurrentUnknown正文() throws {
    let base = V2ScheduleDocument(
        id: "schedule-1",
        timeZoneIdentifier: "Asia/Shanghai",
        taskContexts: [],
        tasks: [],
        planItems: [],
        executionSegments: [],
        preamble: "共同说明",
        postamble: "共同尾注"
    )
    let local = V2ScheduleDocument(
        id: base.id,
        timeZoneIdentifier: base.timeZoneIdentifier,
        taskContexts: [],
        tasks: [],
        planItems: [],
        executionSegments: [],
        preamble: "本地说明",
        postamble: base.postamble
    )
    let remote = V2ScheduleDocument(
        id: base.id,
        timeZoneIdentifier: base.timeZoneIdentifier,
        taskContexts: [],
        tasks: [],
        planItems: [],
        executionSegments: [],
        preamble: "远端说明",
        postamble: base.postamble
    )

    let result = try V2ScheduleMerge.merge(base: base, local: local, remote: remote)
    require(result.conflicts.contains { $0.objectType == .preamble }, "Concurrent unknown preamble edits should be visible as a conflict")
    require(result.document.preamble.contains("本地说明"), "Provisional merged preamble should retain local unknown text")
    require(result.document.preamble.contains("远端说明"), "Provisional merged preamble should retain remote unknown text")
}

func checkScheduleMarkdownOvernightAndExecutionIntegrity() throws {
    let midnight = ISO8601DateFormatter().date(from: "2026-09-07T00:00:00Z")!
    let segment = V2ExecutionSegment(id: "fact", titleSnapshot: "真实执行", startAt: midnight,
        endAt: midnight.addingTimeInterval(60), endReason: .stopped, source: .normal)
    let base = V2ScheduleDocument(id: "integrity", timeZoneIdentifier: "UTC", taskContexts: [], tasks: [],
        planItems: [.init(id: "overnight", date: midnight, startAt: midnight.addingTimeInterval(22 * 3600),
            endAt: midnight.addingTimeInterval(24 * 3600), title: "跨午夜")], executionSegments: [segment])
    let text = try V2ScheduleMarkdown.encode(base)
    require(text.contains("22:00–00:00+1d"), "Next-day midnight must be explicit in editable Markdown")
    let decoded = try V2ScheduleMarkdown.decode(text)
    require(decoded == base, "Midnight must round-trip as the next day")
    var changed = base
    changed.executionSegments[0].endAt = midnight.addingTimeInterval(120)
    for local in [base, changed] {
        for remote in [base, changed] where local != base || remote != base {
            let result = try V2ScheduleMerge.merge(base: base, local: local, remote: remote)
            require(result.document.executionSegments[0] == segment, "Known completed execution facts must remain intact")
            require(result.conflicts.contains { $0.objectType == .executionSegment && $0.field == "endAt" }, "Even one-sided fact rewriting is a conflict")
        }
    }
    var missing = base
    missing.executionSegments = []
    let missingResult = try V2ScheduleMerge.merge(base: base, local: missing, remote: changed)
    require(missingResult.document.executionSegments == base.executionSegments && !missingResult.conflicts.isEmpty,
        "A missing row on one client must not bypass execution integrity checks")
    var open = base
    open.executionSegments[0].endAt = nil
    open.executionSegments[0].endReason = nil
    let closed = try V2ScheduleMerge.merge(base: open, local: open, remote: base)
    require(closed.conflicts.isEmpty && closed.document.executionSegments == base.executionSegments,
        "Closing a previously open execution is a valid new fact")
}

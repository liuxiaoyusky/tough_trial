import XCTest
@testable import ToughTrialV2Core

final class V2AssistantArchiveTests: XCTestCase {
    func testDuplicateSyncIsIdempotent() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let message = V2AgentMessage(
            id: "message-one",
            role: .user,
            parts: [.text("请帮我拆分任务")],
            createdAt: date,
            updatedAt: date
        )
        let session = V2AgentSession(
            id: "session-one",
            title: "拆分任务",
            createdAt: date,
            updatedAt: date,
            messages: [message]
        )

        let archive = V2AssistantArchive()
        try archive.sync(V2AgentWorkspace(sessions: [session]))
        try archive.sync(V2AgentWorkspace(sessions: [session]))

        XCTAssertEqual(try archive.readSession(id: session.id), [
            V2ArchiveMessage(id: message.id, role: .user, text: "请帮我拆分任务", createdAt: date)
        ])
    }

    func testPersistedRevisionUpdateIsReadableAfterRestartAndBoundedSearchReturnsNewest() throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let first = V2AgentMessage(id: "message-one", role: .user, parts: [.text("旧内容")], createdAt: base, updatedAt: base)
        let second = V2AgentMessage(id: "message-two", role: .agent, parts: [.text("中间结果")], createdAt: base.addingTimeInterval(1), updatedAt: base.addingTimeInterval(1))
        let third = V2AgentMessage(id: "message-three", role: .user, parts: [.text("新内容")], createdAt: base.addingTimeInterval(2), updatedAt: base.addingTimeInterval(2))
        let session = V2AgentSession(id: "session-one", title: "会话", createdAt: base, updatedAt: base.addingTimeInterval(2), messages: [first, second, third])

        let archive = V2AssistantArchive(rootURL: root)
        try archive.sync(V2AgentWorkspace(sessions: [session]))
        let updated = V2AgentMessage(id: first.id, role: .user, parts: [.text("已更新内容")], createdAt: base, updatedAt: base.addingTimeInterval(3))
        let updatedSession = V2AgentSession(id: session.id, title: session.title, createdAt: session.createdAt, updatedAt: updated.updatedAt, messages: [updated, second, third])
        try archive.sync(V2AgentWorkspace(sessions: [updatedSession]))

        let logURL = root.appendingPathComponent("sessions/session-one.jsonl")
        let lines = try String(decoding: Data(contentsOf: logURL), as: UTF8.self).split(separator: "\n")
        XCTAssertEqual(lines.count, 4)

        let restarted = V2AssistantArchive(rootURL: root)
        XCTAssertEqual(try restarted.readSession(id: session.id, limit: 2).map(\.id), ["message-two", "message-three"])
        XCTAssertEqual(try restarted.readSession(id: session.id, query: "更新", limit: 20).map(\.text), ["已更新内容"])
        XCTAssertEqual(try restarted.sessions().first?.messageCount, 3)
    }

    func testToolTextIsIncludedWhileScheduleBaselineIsOmittedAndCredentialsAreRedacted() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let result = V2ToolExecutionResult(
            toolID: "core.tasks.create",
            state: .applied,
            operationID: "operation-one",
            idempotencyKey: "key-one",
            summary: "已创建任务 token=sk-test-secret",
            entityReferences: ["task-one"]
        )
        let proposal = V2ScheduleProposal(summary: "安排任务", operations: [])
        let baselineTask = V2Task(
            id: "baseline-task",
            title: "baseline-secret-should-not-be-logged",
            createdAt: now,
            updatedAt: now
        )
        let card = V2AgentScheduleCard(
            requestID: "schedule-one",
            proposal: proposal,
            baseline: V2AppSnapshot(tasks: [baselineTask])
        )
        let message = V2AgentMessage(
            id: "message-one",
            role: .agent,
            parts: [.tool(result), .schedule(card)],
            createdAt: now
        )
        let session = V2AgentSession(id: "session-one", title: "会话", createdAt: now, messages: [message])

        let archive = V2AssistantArchive()
        try archive.sync(V2AgentWorkspace(sessions: [session]))
        let text = try XCTUnwrap(archive.readSession(id: session.id).first?.text)
        XCTAssertTrue(text.contains("已创建任务"))
        XCTAssertTrue(text.contains("task-one"))
        XCTAssertTrue(text.contains("安排任务"))
        XCTAssertFalse(text.contains("baseline-secret"))
        XCTAssertFalse(text.contains("sk-test-secret"))
    }

    func testCompactKeepsSourceIDsAndOriginalMessagesAndIsIdempotent() throws {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let messages = (0..<24).map { index in
            V2AgentMessage(
                id: "message-\(index)",
                role: index.isMultiple(of: 2) ? .user : .agent,
                parts: [.text("内容 \(index)：" + String(repeating: "详细上下文 ", count: 20))],
                createdAt: base.addingTimeInterval(Double(index))
            )
        }
        let session = V2AgentSession(id: "session-one", title: "会话", createdAt: base, messages: messages)
        let archive = V2AssistantArchive()
        try archive.sync(V2AgentWorkspace(sessions: [session]))

        let first = try archive.compact(session, at: base.addingTimeInterval(20), recentMessageLimit: 2, summaryCharacterLimit: 600)
        let second = try archive.compact(session, at: base.addingTimeInterval(21), recentMessageLimit: 2, summaryCharacterLimit: 600)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.revision, 1)
        XCTAssertTrue(first.didReduce)
        XCTAssertEqual(first.coveredMessageIDs, messages.dropLast(2).map(\.id))
        XCTAssertTrue(first.summary.contains("message-21"))
        XCTAssertTrue(first.summary.contains("内容 21"))
        XCTAssertLessThan(first.metrics.afterCharacterCount, first.metrics.beforeCharacterCount)
        XCTAssertLessThanOrEqual(first.metrics.afterTokenEstimate, first.metrics.beforeTokenEstimate)
        XCTAssertEqual(try archive.loadCompaction(sessionID: session.id), first)
        XCTAssertEqual(try archive.readSession(id: session.id, limit: 20).map(\.id), messages.suffix(20).map(\.id))
    }

    func testCompactWithoutPriorSyncStillPersistsRawMessages() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let messages = [
            V2AgentMessage.userText("旧消息", at: date),
            V2AgentMessage.agentText("近期消息", at: date.addingTimeInterval(1))
        ]
        let session = V2AgentSession(id: "session-one", title: "会话", createdAt: date, messages: messages)
        let archive = V2AssistantArchive()

        let compact = try archive.compact(session, at: date.addingTimeInterval(2), recentMessageLimit: 1)
        XCTAssertFalse(compact.didReduce)
        XCTAssertTrue(compact.noBenefitMessage?.contains("较短") == true)
        XCTAssertEqual(compact.coveredMessageIDs, [])
        XCTAssertEqual(try archive.readSession(id: session.id, limit: 20).map(\.id), messages.map(\.id))
        XCTAssertEqual(try archive.sessions().first?.messageCount, 2)
    }

    func testLongCompactionReducesEffectiveSizeAndPreservesTaskReference() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let source = V2AgentSourceTask(id: "task-current", title: "当前任务", note: "保留这项约束")
        let messages = (0..<24).map { index in
            V2AgentMessage(
                id: "message-\(index)",
                role: index.isMultiple(of: 2) ? .user : .agent,
                parts: [.text("用户请求与决定 \(index)：" + String(repeating: "细节", count: 160))],
                createdAt: date.addingTimeInterval(Double(index))
            )
        }
        let session = V2AgentSession(
            id: "session-long",
            title: "长会话",
            createdAt: date,
            messages: messages,
            sourceTask: source
        )
        let archive = V2AssistantArchive()

        let compact = try archive.compact(session, recentMessageLimit: 12, summaryCharacterLimit: 600)

        XCTAssertTrue(compact.didReduce)
        XCTAssertEqual(compact.coveredMessageIDs, messages.dropLast(12).map(\.id))
        XCTAssertEqual(compact.preservedReferenceIDs, [source.id])
        XCTAssertLessThan(compact.metrics.afterCharacterCount, compact.metrics.beforeCharacterCount)
        XCTAssertLessThan(compact.metrics.afterTokenEstimate, compact.metrics.beforeTokenEstimate)
        XCTAssertTrue(compact.summary.contains("message-11"))
        XCTAssertEqual(try archive.readSession(id: session.id, limit: 100).count, messages.count)
    }

    func testEffectiveContextMetricsAreExplicitlyEstimated() {
        let metrics = V2AssistantArchive.effectiveContextMetrics(
            conversation: [
                .init(role: .user, text: "今天整理任务"),
                .init(role: .assistant, text: "好的")
            ],
            compactSummary: "旧消息摘要",
            sourceTask: .init(id: "task-one", title: "任务"),
            memories: []
        )

        XCTAssertGreaterThan(metrics.characterCount, 0)
        XCTAssertGreaterThan(metrics.tokenEstimate, 0)
        XCTAssertEqual(metrics.messageCount, 2)
        XCTAssertEqual(metrics.compactSummaryCharacterCount, 5)
        XCTAssertTrue(metrics.tokenEstimateIsHeuristic)
    }

    func testLegacyCompactionDataRemainsReadableForRecomputation() throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let compactDirectory = root.appendingPathComponent("compact", isDirectory: true)
        try FileManager.default.createDirectory(at: compactDirectory, withIntermediateDirectories: true)
        let legacy = #"{"schemaVersion":1,"revision":3,"summary":"旧版本摘录","coveredMessageIDs":["message-old"],"createdAt":1700000000}"#
        try Data(legacy.utf8).write(to: compactDirectory.appendingPathComponent("session-one.json"))

        let loaded = try XCTUnwrap(V2AssistantArchive(rootURL: root).loadCompaction(sessionID: "session-one"))

        XCTAssertEqual(loaded.revision, 3)
        XCTAssertEqual(loaded.summary, "旧版本摘录")
        XCTAssertEqual(loaded.coveredMessageIDs, ["message-old"])
        XCTAssertEqual(loaded.metrics, .empty)
    }

    func testCompactionRefreshesEditedMessagesAndKeepsRecentDecisionsInBudget() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        var session = V2AgentSession(id: "session-edit", title: "会话", createdAt: date,
            messages: (0..<24).map { index in
                .init(id: "m\(index)", role: .user,
                    parts: [.text("决定\(index)：" + String(repeating: "详细内容", count: 100))],
                    createdAt: date.addingTimeInterval(Double(index)))
            })
        let archive = V2AssistantArchive()
        let first = try archive.compact(session, recentMessageLimit: 2, summaryCharacterLimit: 600)
        XCTAssertTrue(first.summary.contains("决定21"))
        XCTAssertLessThanOrEqual(first.summary.count, 600)
        session.messages[21].parts = [.text("修改后的决定")]
        session.messages[21].updatedAt = date.addingTimeInterval(100)
        let revised = try archive.compact(session, recentMessageLimit: 2, summaryCharacterLimit: 600)
        XCTAssertEqual(revised.revision, first.revision + 1)
        XCTAssertTrue(revised.summary.contains("修改后的决定"))
        XCTAssertEqual(try archive.readSession(id: session.id, limit: 100).count, 24)
    }

    func testDeletedSessionsRemoveLogsAndCompaction() throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let first = V2AgentSession(id: "session-one", title: "一", createdAt: date, messages: [V2AgentMessage.userText("一", at: date)])
        let second = V2AgentSession(id: "session-two", title: "二", createdAt: date, messages: [V2AgentMessage.userText("二", at: date)])
        let archive = V2AssistantArchive(rootURL: root)
        try archive.sync(V2AgentWorkspace(sessions: [first, second]))
        _ = try archive.compact(first, at: date, recentMessageLimit: 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("sessions/session-one.jsonl").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("compact/session-one.json").path))

        try archive.sync(V2AgentWorkspace(sessions: [second]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("sessions/session-one.jsonl").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("compact/session-one.json").path))
        XCTAssertEqual(try archive.sessions().map(\.id), [second.id])
    }

    func testInvalidPathAndCorruptTailFailClosedWithoutDroppingBytes() throws {
        let archive = V2AssistantArchive()
        XCTAssertThrowsError(try archive.readSession(id: "../escape"))

        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let message = V2AgentMessage.userText("保留的正文", at: date)
        let session = V2AgentSession(id: "session-one", title: "会话", createdAt: date, messages: [message])
        let persisted = V2AssistantArchive(rootURL: root)
        try persisted.sync(V2AgentWorkspace(sessions: [session]))
        let logURL = root.appendingPathComponent("sessions/session-one.jsonl")
        let original = try Data(contentsOf: logURL)
        try (original + Data(#"{"broken":"tail""#.utf8)).write(to: logURL)
        let corruptedBytes = try Data(contentsOf: logURL)
        XCTAssertThrowsError(try persisted.readSession(id: session.id))
        XCTAssertEqual(try Data(contentsOf: logURL), corruptedBytes)
    }

    func testMemoryProjectionAndTraceAreBoundedAndPersisted() throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let session = V2AgentSession(id: "session-one", title: "会话", createdAt: date)
        let archive = V2AssistantArchive(rootURL: root)
        try archive.sync(V2AgentWorkspace(sessions: [session]))
        let record = V2UserMemoryRecord(
            id: "memory-one",
            kind: .preference,
            statement: "不要记录 token=secret-value",
            origin: .explicitUser,
            createdAt: date,
            updatedAt: date
        )
        try archive.syncMemory([record])
        try archive.record(sessionID: session.id, kind: "context.request", requestID: "request-one", metadata: ["sourceTaskID": "task-one", "token": "secret-value"], at: date)

        let memory = try String(contentsOf: root.appendingPathComponent("memory/MEMORY.md"), encoding: .utf8)
        let summary = try String(contentsOf: root.appendingPathComponent("memory/memory_summary.md"), encoding: .utf8)
        XCTAssertTrue(memory.contains("memory-one"))
        XCTAssertTrue(summary.contains("1"))
        XCTAssertFalse(memory.contains("secret-value"))
        let traces = try archive.trace(sessionID: session.id)
        XCTAssertEqual(traces.count, 1)
        XCTAssertEqual(traces[0].requestID, "request-one")
        XCTAssertEqual(traces[0].metadata["sourceTaskID"], "task-one")
        XCTAssertFalse(traces[0].metadata.values.contains("secret-value"))
    }

    private func makeTemporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tough-trial-assistant-archive-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}

import Foundation
import ToughTrialV2Core

func checkAgentSessionsStayIsolated() {
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    var workspace = V2AgentWorkspace.empty
    let first = workspace.createSession(at: date)
    let second = workspace.createSession(at: date.addingTimeInterval(1))
    workspace.appendMessage(.userText("第一个会话", at: date), to: first.id)
    workspace.appendMessage(.userText("第二个会话", at: date), to: second.id)

    require(workspace.session(id: first.id)?.messages.count == 1, "First session must own one message")
    require(workspace.session(id: second.id)?.messages.count == 1, "Second session must own one message")
    require(workspace.session(id: first.id)?.messages.first?.plainText == "第一个会话", "Messages must not cross sessions")
}

func checkAgentBrowserStateRoundTrips() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ToughTrialAgentChecks-\(UUID().uuidString)", isDirectory: true)
    let store = V2AgentWorkspaceJSONStore(fileURL: directory.appendingPathComponent("workspace.json"))
    var workspace = V2AgentWorkspace.empty
    let session = workspace.createSession(at: Date())
    workspace.updateBrowserState(
        V2BrowserSessionState(
            id: "browser-1",
            sourceID: "source-1",
            lastURL: URL(string: "https://example.com/detail")!,
            isExpanded: true,
            scrollOffsetY: 428
        ),
        in: session.id
    )
    try store.save(workspace)
    let restored = try store.load()
    let browser = restored.session(id: session.id)?.browserSessions.first

    require(browser?.lastURL.absoluteString == "https://example.com/detail", "Browser URL must survive relaunch")
    require(browser?.isExpanded == true, "Expanded state must survive relaunch")
    require(browser?.scrollOffsetY == 428, "Scroll position must survive relaunch")
}

func checkAgentProviderStateStaysIsolatedAndPersists() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ToughTrialAgentProvider-\(UUID().uuidString)", isDirectory: true)
    let store = V2AgentWorkspaceJSONStore(fileURL: directory.appendingPathComponent("workspace.json"))
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    var workspace = V2AgentWorkspace.empty
    let first = workspace.createSession(at: date)
    let second = workspace.createSession(at: date.addingTimeInterval(1))

    workspace.updateProviderState(
        V2AgentProviderState(
            providerLabel: "Provider One",
            model: "model-one",
            remoteConversationID: "conversation-one",
            remoteResponseID: "response-one",
            updatedAt: date.addingTimeInterval(2)
        ),
        in: first.id
    )
    workspace.updateProviderState(
        V2AgentProviderState(
            providerLabel: "Provider Two",
            model: "model-two",
            remoteConversationID: "conversation-two",
            remoteResponseID: "response-two",
            updatedAt: date.addingTimeInterval(3)
        ),
        in: second.id
    )

    require(workspace.session(id: first.id)?.traces.isEmpty == true, "Provider state must not require a trace")
    require(workspace.session(id: second.id)?.traces.isEmpty == true, "Provider state must not require a trace")
    require(workspace.session(id: first.id)?.providerState?.model == "model-one", "First provider state must stay local")
    require(workspace.session(id: second.id)?.providerState?.model == "model-two", "Second provider state must stay local")

    try store.save(workspace)
    let restored = try store.load()
    require(
        restored.session(id: first.id)?.providerState == V2AgentProviderState(
            providerLabel: "Provider One",
            model: "model-one",
            remoteConversationID: "conversation-one",
            remoteResponseID: "response-one",
            updatedAt: date.addingTimeInterval(2)
        ),
        "First provider state must persist independently"
    )
    require(
        restored.session(id: second.id)?.providerState?.remoteConversationID == "conversation-two",
        "Second provider conversation state must persist independently"
    )
    require(restored.session(id: first.id)?.traces.isEmpty == true, "Provider state round-trip must not invent a trace")
}

func checkAgentTraceLayersAndRedactsCredentials() throws {
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let endedAt = date.addingTimeInterval(1.5)
    let trace = V2AgentTrace(
        id: "trace-1",
        summary: "Authorization: Bearer auth-secret",
        status: .succeeded,
        steps: [
            V2AgentTraceStep(
                id: "step-1",
                tool: .webRead,
                summary: "Cookie: cookie-secret",
                status: .succeeded,
                startedAt: date,
                endedAt: endedAt,
                metadata: [
                    "Authorization": "Bearer metadata-secret",
                    "normal": "Bearer inline-secret"
                ],
                parameters: [
                    "api-key": "api-secret",
                    "query": "token=token-secret"
                ],
                resultSummary: "access_token: result-secret"
            )
        ],
        startedAt: date,
        endedAt: endedAt,
        providerLabel: "Provider",
        model: "model",
        requestID: "request-1",
        responseID: "response-1",
        providerSessionID: "provider-session-1",
        metadata: ["Cookie": "session=cookie-metadata-secret"]
    )
    let summary = V2AgentTraceSummary(trace)
    require(summary.status == .succeeded, "User trace summary must use a typed status")
    require(summary.toolLabels == [.webRead], "User trace summary must use typed tool labels")
    require(summary.duration == 1.5, "User trace summary must carry a typed duration")

    var workspace = V2AgentWorkspace.empty
    let session = workspace.createSession(at: date)
    workspace.appendMessage(
        V2AgentMessage(
            role: .agent,
            parts: [.trace(summary)],
            createdAt: date
        ),
        to: session.id
    )
    workspace.sessions[0].traces.append(trace)

    let encodedPart = try JSONEncoder().encode(workspace.sessions[0].messages[0].parts[0])
    let encodedPartText = String(decoding: encodedPart, as: UTF8.self)
    require(!encodedPartText.contains("providerSessionID"), "User trace summary must not expose full trace metadata")
    require(!encodedPartText.contains("parameters"), "User trace summary must not expose full trace parameters")

    let fullTrace = workspace.sessions[0].traces[0]
    var traceStrings: [String] = [
        fullTrace.summary,
        fullTrace.providerLabel ?? "",
        fullTrace.model ?? "",
        fullTrace.requestID ?? "",
        fullTrace.responseID ?? "",
        fullTrace.providerSessionID ?? ""
    ]
    traceStrings.append(contentsOf: fullTrace.metadata.flatMap { [$0.key, $0.value] })
    for step in fullTrace.steps {
        traceStrings.append(step.summary)
        traceStrings.append(step.resultSummary ?? "")
        traceStrings.append(contentsOf: step.metadata.flatMap { [$0.key, $0.value] })
        traceStrings.append(contentsOf: step.parameters.flatMap { [$0.key, $0.value] })
    }
    for secret in [
        "auth-secret",
        "cookie-secret",
        "metadata-secret",
        "inline-secret",
        "api-secret",
        "token-secret",
        "result-secret",
        "cookie-metadata-secret"
    ] {
        require(!traceStrings.contains { $0.contains(secret) }, "Full Trace must redact \(secret)")
    }
    require(traceStrings.contains { $0.contains("[REDACTED]") }, "Full Trace must show redaction markers")

    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ToughTrialAgentTrace-\(UUID().uuidString)", isDirectory: true)
    let store = V2AgentWorkspaceJSONStore(fileURL: directory.appendingPathComponent("workspace.json"))
    try store.save(workspace)
    let restored = try store.load()
    require(restored.session(id: session.id)?.traces.count == 1, "Full Trace must persist in the Session boundary")
    require(restored.session(id: session.id)?.messages.first?.parts.first == .trace(summary), "Message must persist only the summary layer")
}

func checkWebSourceStringInitializerRejectsInvalidURL() {
    require(
        V2WebSource(id: "invalid", title: "Invalid", url: "not a URL") == nil,
        "Invalid source URL text must not become about:blank"
    )
    let valid = V2WebSource(id: "valid", title: "Valid", url: "https://example.com")
    require(valid?.url.absoluteString == "https://example.com", "Valid source URL text should be accepted")
}

func checkAgentWorkspaceTitleAndSelectionRules() {
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    var workspace = V2AgentWorkspace.empty
    let first = workspace.createSession(at: date)
    let second = workspace.createSession(at: date.addingTimeInterval(1))
    let longTitle = String(repeating: "字", count: 40)

    workspace.appendMessage(.userText("   \n", at: date), to: first.id)
    workspace.appendMessage(.userText(longTitle, at: date.addingTimeInterval(2)), to: first.id)
    require(workspace.session(id: first.id)?.title.count == 28, "Session title must be capped at 28 characters")

    workspace.appendMessage(.agentText("回复", at: date.addingTimeInterval(10)), to: second.id)
    workspace.selectSession(id: first.id)
    workspace.deleteSession(id: first.id)
    require(workspace.selectedSessionID == second.id, "Deletion must select the most recently updated remaining session")
}

func checkAgentWorkspaceCodableAndCorruptionBoundary() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ToughTrialAgentCorruption-\(UUID().uuidString)", isDirectory: true)
    let fileURL = directory.appendingPathComponent("workspace.json")
    let store = V2AgentWorkspaceJSONStore(fileURL: fileURL)
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let draft = V2PlanDraft(
        userPrompt: "安排学习",
        title: "学习计划",
        summary: "先完成一项",
        decisions: ["今晚"],
        scheduleItems: [
            V2PlanDraftScheduleItem(id: "item-1", date: date, title: "学习")
        ]
    )
    var workspace = V2AgentWorkspace.empty
    let session = workspace.createSession(at: date)
    workspace.appendMessage(
        V2AgentMessage(
            role: .agent,
            parts: [.plan(draft)],
            createdAt: date
        ),
        to: session.id
    )
    try store.save(workspace)
    let restored = try store.load()
    require(restored == workspace, "Workspace and pending plan must round-trip through JSON")

    let corruptData = Data("not-json".utf8)
    try corruptData.write(to: fileURL, options: .atomic)
    do {
        _ = try store.loadOrCreateEmpty()
        fatalError("Corrupt workspace JSON must fail to load")
    } catch {
        let preservedData = try Data(contentsOf: fileURL)
        require(preservedData == corruptData, "Corrupt workspace must not be overwritten")
    }
}

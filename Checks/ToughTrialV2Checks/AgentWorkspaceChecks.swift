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

func checkAgentTraceAPIShapeAndRoundTrips() throws {
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let trace = V2AgentTrace(
        id: "trace-1",
        status: .succeeded,
        steps: [
            V2AgentTraceStep(
                id: "step-search",
                tool: .webSearch,
                status: .succeeded,
                duration: 0.4,
                subject: .searchQuery("Authorization: Bearer auth-secret token=token-secret")
            ),
            V2AgentTraceStep(
                id: "step-source",
                tool: .webRead,
                status: .succeeded,
                duration: 1.1,
                subject: .sourceTitle("Cookie: cookie-secret")
            ),
            V2AgentTraceStep(
                id: "step-local",
                tool: .localSearch,
                status: .failed,
                duration: 0.2,
                subject: .localScope("api-key=api-secret"),
                error: V2AgentTraceError(category: .network, code: .invalidResponse)
            ),
            V2AgentTraceStep(
                id: "step-plan",
                tool: .plan,
                status: .succeeded,
                duration: 0.3,
                subject: .planTitle("Bearer plan-secret")
            )
        ],
        startedAt: date,
        endedAt: date.addingTimeInterval(2),
        providerLabel: "Provider",
        model: "model",
        providerSessionID: "provider-session-1",
        requestID: "request-1",
        responseID: "response-1",
        promptTokens: 12,
        completionTokens: 8,
        totalTokens: 20
    )
    let summary = V2AgentTraceSummary(trace)
    let typedTool: V2AgentTool = .webSearch
    require(typedTool == trace.steps[0].tool, "Trace steps must use the typed tool enum")
    require(summary.status == .succeeded, "User trace summary must use a typed status")
    require(summary.toolCount == 4, "User trace summary must derive its tool count")
    require(summary.duration == 2, "User trace summary must derive its duration")
    require(summary.displayText.contains("4 个步骤"), "User trace summary must expose computed display text")
    require(trace.steps[2].error == V2AgentTraceError(category: .network, code: .invalidResponse), "Trace errors must use typed category and code")

    let forbiddenFields = [
        "summary",
        "reasoning",
        "headers",
        "cookies",
        "authorization",
        "rawBody",
        "requestBody",
        "responseBody",
        "parameters",
        "results",
        "result",
        "metadata"
    ]
    func assertNoForbiddenFields<T>(_ value: T, context: String) {
        let labels = Set(Mirror(reflecting: value).children.compactMap(\.label))
        for field in forbiddenFields {
            require(!labels.contains(field), "\(context) must not expose a \(field) field")
        }
    }
    assertNoForbiddenFields(summary, context: "User trace summary")
    assertNoForbiddenFields(trace, context: "Full trace")
    assertNoForbiddenFields(trace.steps[0], context: "Trace step")

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
    require(encodedPartText.contains("toolCount"), "User trace summary must persist typed tool count")
    require(encodedPartText.contains("duration"), "User trace summary must persist typed duration")
    require(!encodedPartText.contains("providerSessionID"), "User trace summary must not expose full trace identifiers")
    require(!encodedPartText.contains("parameters"), "User trace summary must not expose arbitrary parameters")

    let encodedTrace = try JSONEncoder().encode(trace)
    let encodedTraceText = String(decoding: encodedTrace, as: UTF8.self)
    for field in forbiddenFields {
        require(!encodedTraceText.contains("\"\(field)\""), "Full trace JSON must not expose a \(field) field")
    }
    let decodedTrace = try JSONDecoder().decode(V2AgentTrace.self, from: encodedTrace)
    require(decodedTrace == trace, "Typed full trace must round-trip through JSON")

    var traceStrings = [
        trace.id,
        trace.providerLabel ?? "",
        trace.model ?? "",
        trace.providerSessionID ?? "",
        trace.requestID ?? "",
        trace.responseID ?? ""
    ]
    for step in trace.steps {
        switch step.subject {
        case let .searchQuery(query), let .sourceTitle(query), let .localScope(query), let .planTitle(query):
            traceStrings.append(query)
        case let .sourceURL(url):
            traceStrings.append(url.absoluteString)
        case nil:
            break
        }
    }
    for secret in [
        "auth-secret",
        "token-secret",
        "cookie-secret",
        "api-secret",
        "plan-secret"
    ] {
        require(!traceStrings.contains { $0.contains(secret) }, "Typed Trace subjects must redact \(secret)")
    }
    require(traceStrings.contains { $0.contains("[REDACTED]") }, "Credential-pattern tests must remain defense in depth")

    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ToughTrialAgentTrace-\(UUID().uuidString)", isDirectory: true)
    let store = V2AgentWorkspaceJSONStore(fileURL: directory.appendingPathComponent("workspace.json"))
    try store.save(workspace)
    let restored = try store.load()
    require(restored.session(id: session.id)?.traces == [trace], "Full Trace must persist in the Session boundary")
    require(restored.session(id: session.id)?.messages.first?.parts.first == .trace(summary), "Message must persist only the typed summary layer")
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

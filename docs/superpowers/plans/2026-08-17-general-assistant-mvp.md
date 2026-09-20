# Tough Trial General Assistant MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the single-purpose Plan page with a persistent, multi-session Assistant that supports real AI chat, automatic read-only tools, inline web sources, and confirmed plan artifacts.

**Architecture:** Add a platform-neutral Agent workspace model and JSON store in `ToughTrialV2Core`, then place provider-compatible model routing and read-only web tools behind protocols. A focused `V2AssistantStore` owns the turn loop and persistence, while SwiftUI renders message parts and a registry of stateful `WKWebView` controllers. Existing planning generation and acceptance remain the only durable-write path.

**Tech Stack:** Swift 6, SwiftUI, Foundation `URLSession`, WebKit `WKWebView`, existing OpenAI-compatible provider settings, existing executable check suites, XCTest UI tests.

## Global Constraints

- Minimum platforms remain iOS 17 and macOS 14; no new third-party dependency is introduced.
- The third root tab is titled `助手`; opening it presents a full-screen workspace without the root tab bar.
- New-session starters are prompts, not persistent modes.
- The Agent may search and read, but may not click, scroll, fill, log in, submit, download-and-run, or expose a JavaScript-to-native bridge.
- Any task or schedule write still requires an explicit `加入计划` action.
- Model reasoning and credentials never enter user or debug Trace.
- Model service and web-search service remain separate protocols.
- Existing Kimi, GLM, SiliconFlow, and custom OpenAI-compatible settings remain reusable without client-identity spoofing.

---

### Task 1: Persistent Agent Workspace Model

**Files:**
- Create: `Sources/ToughTrialV2Core/V2AgentModels.swift`
- Create: `Sources/ToughTrialV2Core/V2AgentWorkspaceStore.swift`
- Modify: `Sources/ToughTrialV2Core/V2Models.swift`
- Create: `Checks/ToughTrialV2Checks/AgentWorkspaceChecks.swift`
- Modify: `Checks/ToughTrialV2Checks/main.swift`

**Interfaces:**
- Produces: `V2AgentWorkspace`, `V2AgentSession`, `V2AgentMessage`, `V2AgentMessagePart`, `V2AgentTrace`, `V2AgentTraceStep`, `V2WebSource`, `V2BrowserSessionState`, and `V2AgentWorkspaceJSONStore`.
- Produces: pure mutating methods `createSession(at:sourceTask:)`, `selectSession(id:)`, `appendMessage(_:to:)`, `replaceMessage(_:in:)`, `updateBrowserState(_:in:)`, and `deleteSession(id:)`.
- Consumes: existing `V2PlanDraft`, made `Codable` so a pending plan artifact survives relaunch.

- [ ] **Step 1: Add failing workspace checks**

```swift
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
```

- [ ] **Step 2: Run checks and confirm missing-type failures**

Run: `swift run ToughTrialV2Checks`

Expected: compilation fails because `V2AgentWorkspace` and related types do not exist.

- [ ] **Step 3: Implement Codable models and pure workspace mutations**

Use an explicitly tagged message-part enum so persisted JSON remains stable:

```swift
public enum V2AgentMessagePart: Codable, Equatable, Sendable {
    case text(String)
    case trace(V2AgentTrace)
    case sources([V2WebSource])
    case plan(V2PlanDraft)
    case error(V2AgentMessageError)
}

public struct V2AgentSession: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var createdAt: Date
    public var updatedAt: Date
    public var messages: [V2AgentMessage]
    public var browserSessions: [V2BrowserSessionState]
    public var sourceTask: V2AgentSourceTask?
    public var pendingPlanPrompt: String?
}
```

Set the initial title from the first non-empty user message, cap it at 28 visible characters, and keep selection valid after deletion by selecting the most recently updated remaining Session.

- [ ] **Step 4: Implement atomic JSON persistence and corruption boundary**

`loadOrCreateEmpty()` returns `.empty` only when the file is absent. Decode failures propagate so the caller can preserve the original file and disable writes instead of overwriting it.

- [ ] **Step 5: Run focused and full core verification**

Run:

```bash
swift run ToughTrialV2Checks
swift run FocusTimelineCoreChecks
swift build
```

Expected: all commands pass.

- [ ] **Step 6: Commit the workspace boundary**

```bash
git add Sources/ToughTrialV2Core/V2AgentModels.swift Sources/ToughTrialV2Core/V2AgentWorkspaceStore.swift Sources/ToughTrialV2Core/V2Models.swift Checks/ToughTrialV2Checks/AgentWorkspaceChecks.swift Checks/ToughTrialV2Checks/main.swift
git commit -m "feat: add persistent assistant sessions"
```

---

### Task 2: Provider-Compatible Agent Decisions and Safe Trace

**Files:**
- Create: `Sources/ToughTrialV2Core/V2AgentClient.swift`
- Create: `Checks/ToughTrialV2Checks/AgentClientChecks.swift`
- Modify: `Checks/ToughTrialV2Checks/main.swift`
- Modify: `Sources/ToughTrialV2App/V2AIProviderSettings.swift`

**Interfaces:**
- Produces: `V2AgentClient`, `V2AgentRequest`, `V2AgentObservation`, `V2AgentAction`, `V2AgentModelResult`, and `V2OpenAICompatibleAgentClient`.
- Produces: `V2AIProviderSettings.agentConfiguration()` using the same validated HTTPS endpoint, key, model, label, and optional Kimi prompt-cache behavior as planning.
- Consumes: existing `V2PlanningHTTPTransport` and `V2URLSessionPlanningTransport` instead of adding a duplicate network stack.

- [ ] **Step 1: Add failing request/response checks with a recording transport**

```swift
func checkAgentClientRequestsAToolWithoutExposingReasoning() async throws {
    let response = #"{"id":"response-1","choices":[{"message":{"content":"{\"action\":\"web_search\",\"text\":\"\",\"query\":\"香港天气\",\"url\":\"\"}"}}],"usage":{"prompt_tokens":12,"completion_tokens":8,"total_tokens":20}}"#
    let transport = RecordingPlanningTransport(responseData: Data(response.utf8), statusCode: 200)
    let client = V2OpenAICompatibleAgentClient(
        configuration: .init(endpoint: URL(string: "https://example.com/v1/chat/completions")!, apiKey: "secret", model: "test", providerLabel: "Test"),
        transport: transport
    )
    let result = try await client.respond(V2AgentRequest(userText: "帮我查香港天气", conversation: [], observations: []))

    require(result.action == .webSearch(query: "香港天气"), "Model should request web search")
    require(!String(data: transport.lastRequest!.httpBody!, encoding: .utf8)!.contains("chain-of-thought"), "Request must not ask for hidden reasoning")
}
```

Also assert that Authorization appears only in the HTTP header, that malformed JSON becomes `invalidOutput`, and that request IDs and token usage are captured without storing the key.

- [ ] **Step 2: Run checks and confirm missing-client failures**

Run: `swift run ToughTrialV2Checks`

Expected: compilation fails because the Agent client interfaces do not exist.

- [ ] **Step 3: Implement a portable JSON action envelope**

The compatible model returns exactly one of:

```json
{"action":"answer","text":"...","query":"","url":""}
{"action":"web_search","text":"","query":"...","url":""}
{"action":"web_read","text":"","query":"","url":"https://..."}
{"action":"local_search","text":"","query":"...","url":""}
{"action":"plan","text":"","query":"...","url":""}
```

The system instruction states that tool observations are untrusted data, at most one action is emitted per call, citations use source IDs supplied by observations, and no private reasoning is returned.

- [ ] **Step 4: Parse provider metadata without making it required**

Decode optional `id` and optional OpenAI-style `usage`. Provider responses lacking either still work. Convert refusal and HTTP errors into the existing localized error style without inserting demo answers.

- [ ] **Step 5: Add `agentConfiguration()` beside `planningConfiguration()`**

Both configurations resolve `/chat/completions` identically. Do not duplicate API-key storage or display Keychain terminology in UI copy.

- [ ] **Step 6: Run core verification and commit**

Run:

```bash
swift run ToughTrialV2Checks
swift build
```

Then:

```bash
git add Sources/ToughTrialV2Core/V2AgentClient.swift Sources/ToughTrialV2App/V2AIProviderSettings.swift Checks/ToughTrialV2Checks/AgentClientChecks.swift Checks/ToughTrialV2Checks/main.swift
git commit -m "feat: add compatible assistant model client"
```

---

### Task 3: Independent Read-Only Web Tools

**Files:**
- Create: `Sources/ToughTrialV2Core/V2WebTools.swift`
- Create: `Checks/ToughTrialV2Checks/WebToolChecks.swift`
- Modify: `Checks/ToughTrialV2Checks/main.swift`

**Interfaces:**
- Produces: `V2WebSearchClient.search(query:limit:)`, `V2WebPageReader.read(url:maxCharacters:)`, `V2DuckDuckGoSearchClient`, and `V2URLSessionWebPageReader`.
- Produces: `V2WebSearchResult` with stable `id`, `title`, `url`, `snippet`, and optional `siteName`.
- Consumes: no AI-provider capability and no credential.

- [ ] **Step 1: Add deterministic parser and safety checks**

```swift
func checkDuckDuckGoResultsBecomeSources() throws {
    let html = """
    <a class="result__a" href="https://example.com/a">示例标题</a>
    <a class="result__snippet">这是摘要</a>
    """
    let results = try V2DuckDuckGoHTMLParser.parse(Data(html.utf8), limit: 5)
    require(results.count == 1, "One result should be parsed")
    require(results[0].url.absoluteString == "https://example.com/a", "Result URL should be preserved")
}

func checkWebReaderRejectsUnsafeSchemes() async {
    let reader = V2URLSessionWebPageReader(transport: RejectingWebTransport())
    do {
        _ = try await reader.read(url: URL(string: "file:///etc/passwd")!, maxCharacters: 10_000)
        fatalError("Reader must reject file URLs")
    } catch V2WebToolError.unsupportedURL {
    } catch {
        fatalError("Unexpected error: \(error)")
    }
}
```

Also cover HTML entity decoding, non-HTML responses, redirects to non-HTTP(S), result limits, and truncation.

- [ ] **Step 2: Run checks and confirm missing-tool failures**

Run: `swift run ToughTrialV2Checks`

Expected: compilation fails because web tool types do not exist.

- [ ] **Step 3: Implement search and page reading with strict bounds**

Search sends a percent-encoded HTTPS GET to DuckDuckGo HTML and returns at most 8 results. Page reading accepts only HTTP(S), uses a 15-second request timeout, accepts bounded HTML/text payloads, removes scripts/styles, normalizes whitespace, and returns at most 24,000 characters.

Search parsing is isolated behind `V2DuckDuckGoHTMLParser`; any upstream markup change fails as a visible tool error rather than producing invented sources.

- [ ] **Step 4: Run verification and commit**

Run:

```bash
swift run ToughTrialV2Checks
swift build
```

Then:

```bash
git add Sources/ToughTrialV2Core/V2WebTools.swift Checks/ToughTrialV2Checks/WebToolChecks.swift Checks/ToughTrialV2Checks/main.swift
git commit -m "feat: add read-only assistant web tools"
```

---

### Task 4: Assistant Turn Loop and Existing Plan Bridge

**Files:**
- Create: `Sources/ToughTrialV2App/V2AssistantStore.swift`
- Modify: `Sources/ToughTrialV2App/V2AppStore.swift`
- Modify: `Sources/ToughTrialV2App/V2AIProviderSettings.swift`
- Modify: `Sources/ToughTrialV2Core/V2PlanningClient.swift`
- Create: `Checks/ToughTrialV2Checks/AgentTurnChecks.swift`
- Modify: `Checks/ToughTrialV2Checks/main.swift`

**Interfaces:**
- Produces: `@MainActor V2AssistantStore` with `workspace`, `selectedSession`, `send(_:)`, `createSession()`, `selectSession(id:)`, `toggleBrowser(source:)`, `updateBrowserState(_:)`, `acceptPlan(_:)`, `retry(messageID:)`, and `cancelCurrentTurn()`.
- Produces: `V2AssistantDependencies` closures for model response, web search/read, local search, plan generation, plan acceptance, and provider/configuration status.
- Consumes: Task 1 workspace/store, Task 2 Agent client, Task 3 web tools, existing `V2PlanningClient`, `V2MemoryEngine`, and `V2Engine`.

- [ ] **Step 1: Add pure turn-policy checks**

Extract `V2AgentTurnPolicy` into core so executable checks can verify the loop limit and action handling:

```swift
func checkAgentTurnPolicyStopsAfterThreeTools() {
    var policy = V2AgentTurnPolicy(maximumToolCalls: 3)
    require(policy.registerToolCall(.webSearch(query: "a")), "First tool should run")
    require(policy.registerToolCall(.webRead(url: URL(string: "https://example.com")!)), "Second tool should run")
    require(policy.registerToolCall(.localSearch(query: "b")), "Third tool should run")
    require(!policy.registerToolCall(.webSearch(query: "c")), "Fourth tool must be rejected")
}
```

Also verify that `answer` does not consume a tool slot and that plan acceptance is never represented as an automatic action.

- [ ] **Step 2: Implement one cancellable turn loop**

For each user message:

1. Persist the user message immediately.
2. Call the model with conversation and accumulated observations.
3. Execute only `web_search`, `web_read`, `local_search`, or `plan`.
4. Append a sanitized Trace step after each observable result.
5. Repeat for at most three tool calls, then require an answer or emit a recoverable error.
6. Persist the final Agent message, Trace, sources, and optional plan artifact atomically.

Cancellation marks the pending Agent message as cancelled and keeps the user message.

- [ ] **Step 3: Build local search from bounded current app data**

Return only matching task titles/statuses, plan titles/dates, and active Memory statements. Cap each category and total character count before sending observations to the model. Never include API keys or unrelated records.

- [ ] **Step 4: Bridge planning without mutating the old single-page state**

Add an AppStore helper that creates a `V2PlanningRequest` from the selected Session context and returns `V2PlanningOutcome`. Keep `pendingPlanPrompt` in that Session across clarification. A proposal becomes `.plan(draft)`; only `acceptPlan(_:)` calls `engine.savePlanDraft` and `engine.acceptPlanDraft`.

- [ ] **Step 5: Initialize persistence with a fail-closed corruption boundary**

If the workspace JSON cannot decode, show a recoverable storage message and do not overwrite it. In UI-test mode, use a temporary deterministic workspace and deterministic model/web clients.

- [ ] **Step 6: Run verification and commit**

Run:

```bash
swift run ToughTrialV2Checks
swift run FocusTimelineCoreChecks
swift build
```

Then:

```bash
git add Sources/ToughTrialV2App/V2AssistantStore.swift Sources/ToughTrialV2App/V2AppStore.swift Sources/ToughTrialV2App/V2AIProviderSettings.swift Sources/ToughTrialV2Core/V2PlanningClient.swift Checks/ToughTrialV2Checks/AgentTurnChecks.swift Checks/ToughTrialV2Checks/main.swift
git commit -m "feat: orchestrate assistant tools and plan drafts"
```

---

### Task 5: Multi-Session SwiftUI Assistant

**Files:**
- Create: `Sources/ToughTrialV2App/V2AssistantView.swift`
- Create: `Sources/ToughTrialV2App/V2AssistantSessionViews.swift`
- Modify: `Sources/ToughTrialV2App/V2PlanAgentView.swift`
- Modify: `Sources/ToughTrialV2App/V2RootView.swift`
- Modify: `Sources/ToughTrialV2App/V2TasksView.swift`
- Modify: `Tests/ToughTrialUITests/ToughTrialUITests.swift`

**Interfaces:**
- Consumes: `V2AssistantStore`, Agent message parts, and existing plan-draft row/editor components.
- Produces: full-screen `V2AssistantView`, searchable Session sheet, Session detail/Trace sheet, quiet starter state, message-part renderer, and stable accessibility identifiers prefixed `assistant.`.

- [ ] **Step 1: Update UI tests to define the new visible contract**

Replace plan-tab assumptions with checks for:

```swift
app.tabBars.firstMatch.buttons["助手"].tap()
XCTAssertTrue(app.staticTexts["有什么想一起处理的？"].waitForExistence(timeout: 3))
XCTAssertTrue(app.buttons["assistant.starter.chat"].exists)
XCTAssertTrue(app.buttons["assistant.starter.web"].exists)
XCTAssertTrue(app.buttons["assistant.starter.local"].exists)
XCTAssertTrue(app.buttons["assistant.starter.plan"].exists)
XCTAssertFalse(app.tabBars.firstMatch.isHittable)
```

Add one test that creates two Sessions, sends distinct text in each, switches back, and verifies the first message remains while the second does not appear in that Session.

- [ ] **Step 2: Run the changed UI tests and verify failure**

Run:

```bash
/opt/homebrew/bin/xcodegen generate
xcodebuild test -project ToughTrial.xcodeproj -scheme ToughTrial -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:ToughTrialUITests/ToughTrialUITests/testPrimaryNavigationAndAssistantPresentation
```

Expected: failure because the tab and view still say Plan.

- [ ] **Step 3: Implement the quiet Assistant shell**

Header controls are Session list, concise current title, new Session, and more. Empty state displays the four starters and no persistent mode selector. Composer stays visible whenever AI is configured; otherwise the page shows a direct configuration action and no fake response.

- [ ] **Step 4: Render message parts progressively**

User text is compact and trailing. Agent text, one-line Trace disclosure, sources, plan artifact, and recoverable errors render in message order without wrapping every section in nested cards. `加入计划` calls explicit acceptance and changes the artifact to an accepted state only after the engine succeeds.

- [ ] **Step 5: Implement Session search, switching, and debug Trace**

Session search matches title and plain message text. The user-facing Trace shows query/tool/status/duration. Session details show provider/model/request IDs/usage and sanitized parameter/result summaries, with credentials absent by construction.

- [ ] **Step 6: Preserve task-context entry**

The task item `AI 计划` action opens a fresh or matching Assistant Session with `sourceTask` context. It does not force a Plan mode; the starter prompt may be prefilled, and all other Assistant abilities remain available.

- [ ] **Step 7: Run UI tests and commit**

Run the Assistant UI tests plus the existing Today, Tasks, and Recall smoke tests. Then:

```bash
git add Sources/ToughTrialV2App/V2AssistantView.swift Sources/ToughTrialV2App/V2AssistantSessionViews.swift Sources/ToughTrialV2App/V2PlanAgentView.swift Sources/ToughTrialV2App/V2RootView.swift Sources/ToughTrialV2App/V2TasksView.swift Tests/ToughTrialUITests/ToughTrialUITests.swift
git commit -m "feat: replace plan page with assistant workspace"
```

---

### Task 6: Stateful Inline and Full-Screen WebViews

**Files:**
- Create: `Sources/ToughTrialV2App/V2AssistantBrowserView.swift`
- Modify: `Sources/ToughTrialV2App/V2AssistantView.swift`
- Modify: `Tests/ToughTrialUITests/ToughTrialUITests.swift`

**Interfaces:**
- Produces: `V2AssistantBrowserRegistry`, one `V2AssistantBrowserController` per browser-session ID, `V2AssistantWebViewRepresentable`, inline browser toolbar, and full-screen browser presentation.
- Consumes: persisted `V2BrowserSessionState` and source-message location.

- [ ] **Step 1: Add deterministic inline-browser UI coverage**

Launch with a UI-test fixture containing two source rows. Verify both can expand, each has a fixed quarter-screen container, opening one full screen displays domain/back/minimize/system-browser controls, and minimizing returns the browser to the original source row.

Use accessibility identifiers:

```text
assistant.source.<source-id>
assistant.browser.inline.<browser-id>
assistant.browser.fullscreen
assistant.browser.minimize
assistant.browser.back
assistant.browser.openExternal
```

- [ ] **Step 2: Implement a controller registry that owns real WKWebViews**

Each controller retains one `WKWebView` across SwiftUI view reconstruction. The representable reparents that same view between inline and full-screen containers, preserving URL, navigation state, and scroll position. No script-message handler or native bridge is registered.

- [ ] **Step 3: Persist navigation and scroll updates**

On navigation finish and scroll end, update last URL and offset in the selected Session. Restore offset after the first successful load on relaunch. Keep complete in-process back/forward history in the retained `WKWebView`; relaunch history remains best effort.

- [ ] **Step 4: Enforce the selected gesture and presentation rules**

Inline height is `max(180, availableHeight * 0.25)`. The WebView owns gestures that begin inside its bounds; the outer SwiftUI scroll owns gestures that begin outside. Do not transfer a gesture at either scroll boundary. Multiple inline browsers may remain expanded, while the registry exposes only one full-screen ID at a time.

- [ ] **Step 5: Verify no autonomous browser path exists**

Search source for `evaluateJavaScript`, `WKScriptMessageHandler`, form submission, synthetic taps, and navigation automation. The only permitted JavaScript call is a fixed scroll restoration/readback expression whose content is never derived from a web page or model.

- [ ] **Step 6: Run simulator verification and commit**

Run:

```bash
/opt/homebrew/bin/xcodegen generate
xcodebuild test -project ToughTrial.xcodeproj -scheme ToughTrial -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:ToughTrialUITests/ToughTrialUITests/testAssistantSupportsMultipleInlineBrowsers
```

Capture screenshots for empty Session, two Sessions, source expansion, plan artifact, and full-screen browser. Then:

```bash
git add Sources/ToughTrialV2App/V2AssistantBrowserView.swift Sources/ToughTrialV2App/V2AssistantView.swift Tests/ToughTrialUITests/ToughTrialUITests.swift
git commit -m "feat: add stateful inline assistant browsing"
```

---

### Task 7: End-to-End Acceptance and Handoff

**Files:**
- Modify: `docs/superpowers/specs/2026-08-17-tough-trial-general-assistant-design-zh.md`
- Create: `docs/qa/2026-08-17-general-assistant-mvp-acceptance.md`

**Interfaces:**
- Consumes: all prior tasks.
- Produces: check evidence mapped to the 17 accepted first-version criteria and a short list of remaining device-only or provider-specific risks.

- [ ] **Step 1: Run all deterministic verification from a clean build state**

```bash
swift run ToughTrialV2Checks
swift run FocusTimelineCoreChecks
swift build
/opt/homebrew/bin/xcodegen generate
xcodebuild build -project ToughTrial.xcodeproj -scheme ToughTrial -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
xcodebuild test -project ToughTrial.xcodeproj -scheme ToughTrial -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

- [ ] **Step 2: Run a live-provider smoke test without recording credentials**

Using the already configured provider in the simulator or device:

1. Create Session A and ask a normal conversational question.
2. Ask for current web information and open one cited source inline.
3. Create Session B and request a plan artifact.
4. Return to Session A and verify its source/browser state remains isolated.
5. Accept the plan in Session B and verify only that explicit tap writes tasks/schedule.

Record provider label, model, timestamps, and pass/fail only. Do not export request headers, API keys, cookies, or local private content.

- [ ] **Step 3: Map evidence to all 17 spec criteria**

Mark each criterion `passed`, `blocked`, or `needs device/provider confirmation`. Automated checks do not claim WebView gesture quality or visual acceptance; those require simulator/device observation.

- [ ] **Step 4: Update spec status and commit final evidence**

Change spec status from `等待实施计划` to the exact implemented state, without deleting non-goals or future constraints.

```bash
git add docs/superpowers/specs/2026-08-17-tough-trial-general-assistant-design-zh.md docs/qa/2026-08-17-general-assistant-mvp-acceptance.md
git commit -m "docs: record assistant MVP acceptance"
```


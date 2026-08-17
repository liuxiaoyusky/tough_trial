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

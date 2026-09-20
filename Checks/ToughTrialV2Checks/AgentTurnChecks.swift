import Foundation
import ToughTrialV2Core

func checkAgentTurnPolicyStopsAfterThreeTools() {
    var policy = V2AgentTurnPolicy(maximumToolCalls: 3)
    require(policy.registerToolCall(.webSearch(query: "a")), "First tool should run")
    require(
        policy.registerToolCall(.webRead(url: URL(string: "https://example.com")!)),
        "Second tool should run"
    )
    require(policy.registerToolCall(.localSearch(query: "b")), "Third tool should run")
    require(!policy.registerToolCall(.webSearch(query: "c")), "Fourth tool must be rejected")
    require(policy.toolCallCount == 3, "Rejected tools must not increase the tool count")
}

func checkAgentTurnPolicyDoesNotChargeAnswers() {
    var policy = V2AgentTurnPolicy(maximumToolCalls: 1)
    require(policy.registerToolCall(.answer(text: "done")), "Answers should remain allowed")
    require(policy.toolCallCount == 0, "Answers must not consume a tool slot")
    require(policy.registerToolCall(.plan(query: "tomorrow")), "Plan draft generation should use the tool slot")
    require(policy.registerToolCall(.answer(text: "draft ready")), "An answer must remain allowed after the cap")
    require(!policy.registerToolCall(.webSearch(query: "extra")), "Another tool must be rejected after the cap")
}

func checkAgentAutomaticActionsCannotAcceptPlans() {
    require(
        V2AgentTurnPolicy.tool(for: .plan(query: "tomorrow")) == .planDraft,
        "The plan action must mean draft generation"
    )
    require(
        Set(V2AgentAutomaticTool.allCases) == [.webSearch, .webRead, .localSearch, .planDraft, .schedule],
        "Automatic tools include explicit schedule commands while plan remains a draft"
    )
    require(
        !V2AgentAutomaticTool.allCases.contains { $0.rawValue.lowercased().contains("accept") },
        "Plan acceptance must never be represented as an automatic action"
    )
}

func checkAgentPlanningRequestUsesSessionContext() {
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let task = V2PlanningTaskContext(id: "task-1", title: "写作", status: .active)
    var session = V2AgentSession(
        id: "session-1",
        createdAt: date,
        messages: [
            .userText("安排写作", at: date),
            .agentText("你希望哪天完成？", at: date)
        ],
        sourceTask: V2AgentSourceTask(id: "task-1", title: "写作")
    )

    let initial = V2PlanningRequest(
        agentSession: session,
        query: "安排写作",
        tasks: [task],
        memoryStatements: ["晚上适合专注"],
        referenceDate: date,
        timeZoneIdentifier: "Asia/Hong_Kong"
    )
    require(initial.userPrompt == "安排写作", "A new plan action should use its query as the planning prompt")
    require(initial.clarificationResponse == nil, "A new plan action must not invent a clarification response")
    require(initial.scope?.contains("task-1") == true, "The selected Session task should become planning scope")
    require(initial.conversation.count == 2, "Planning should receive the bounded Session conversation")

    session.pendingPlanPrompt = "安排写作"
    let clarification = V2PlanningRequest(
        agentSession: session,
        query: "明晚",
        tasks: [task],
        memoryStatements: [],
        referenceDate: date,
        timeZoneIdentifier: "Asia/Hong_Kong"
    )
    require(clarification.userPrompt == "安排写作", "Clarification must retain the original planning prompt")
    require(clarification.clarificationResponse == "明晚", "The new query should answer the pending clarification")

    session.pendingPlanPrompt = nil
    session.pendingPlan = V2PlanDraft(
        userPrompt: "安排写作",
        title: "写作计划",
        summary: "明晚完成",
        decisions: [],
        scheduleItems: []
    )
    let revision = V2PlanningRequest(
        agentSession: session,
        query: "改到后天",
        tasks: [task],
        memoryStatements: [],
        referenceDate: date,
        timeZoneIdentifier: "Asia/Hong_Kong"
    )
    require(revision.userPrompt == "安排写作", "Plan revisions must retain the draft's original prompt")
    require(revision.clarificationResponse == "改到后天", "Plan revisions should carry the requested adjustment")
    require(revision.currentDraft == session.pendingPlan, "Plan revisions must carry the Session draft")
}

func checkDirectCreationRoutingIsConservative() {
    for text in ["新增任务：买牛奶", "请帮我创建一个任务，明天取快递", "添加待办 买牛奶"] {
        require(V2AgentTurnPolicy.canDirectlyParseCreation(text), "Explicit create should skip routing: \(text)")
    }
    for text in ["新增任务：买牛奶，可以吗？", "不要新增任务：买牛奶", "如果新增任务：买牛奶", "新增任务有什么用", "新增任务：先不要做", "帮我想想任务", "把它改到明天", "新增任务：" + String(repeating: "长", count: 181)] {
        require(!V2AgentTurnPolicy.canDirectlyParseCreation(text), "Uncertain input should keep general routing: \(text)")
    }
}

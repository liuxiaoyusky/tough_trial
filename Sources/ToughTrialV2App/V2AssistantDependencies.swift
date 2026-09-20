import Foundation
import ToughTrialV2Core

enum V2AssistantStorageState: Equatable {
    case healthy
    case transientWriteFailure
    case corruptRead
    case unavailable
}

struct V2AssistantProviderStatus: Equatable, Sendable {
    var isConfigured: Bool
    var providerLabel: String
    var message: String?
}

struct V2AssistantProviderIdentity: Equatable, Sendable {
    var key: String
    var label: String
    var model: String
}

struct V2AssistantModelSnapshot: Sendable {
    var identity: V2AssistantProviderIdentity
    var respond: @MainActor @Sendable (V2AgentRequest) async throws -> V2AgentModelResult
    var generatePlan: @MainActor @Sendable (
        V2AgentSession,
        String,
        Date
    ) async throws -> V2PlanningOutcome
    var generateSchedule: @MainActor @Sendable (V2ScheduleRequest) async throws -> V2ScheduleOutcome = { _ in
        throw V2AssistantTurnError.scheduleUnavailable
    }
    var thinking: V2AIThinking? = nil
}

typealias V2AssistantToolExecutor = @MainActor @Sendable (V2AgentToolCall, V2ToolExecutionContext) async throws -> V2ToolExecutionResult

struct V2AssistantDependencies: Sendable {
    var selectedProviderStatus: (@MainActor @Sendable (V2AIProviderSelection) -> V2AssistantProviderStatus)? = nil
    var selectedModelSnapshot: (@MainActor @Sendable (V2AIProviderSelection) throws -> V2AssistantModelSnapshot)? = nil
    var toolExecutorForSnapshot: (@MainActor @Sendable (V2AssistantModelSnapshot) -> V2AssistantToolExecutor)? = nil
    var modelSnapshot: @MainActor @Sendable () throws -> V2AssistantModelSnapshot
    /// Builds the bounded tool directory for the current caller and module
    /// generations. The default keeps test fixtures and old integrations
    /// read-only until they explicitly wire a host catalog.
    var toolCatalog: @MainActor @Sendable () throws -> V2ToolCatalog = { .empty }
    /// Host-owned typed dispatch. The model provides only tool ID and
    /// validated arguments; this closure supplies operation identity and
    /// confirmation policy through `V2ToolExecutionContext`.
    var executeTool: @MainActor @Sendable (V2AgentToolCall, V2ToolExecutionContext) async throws -> V2ToolExecutionResult = { call, _ in
        throw V2ToolExecutionError.unsupported(call.toolID)
    }
    var confirmTool: @MainActor @Sendable (V2ToolExecutionResult) async throws -> V2ToolExecutionResult = { result in
        throw V2ToolExecutionError.unsupported(result.toolID)
    }
    var undoTool: @MainActor @Sendable (V2ToolExecutionResult) async throws -> V2ToolExecutionResult = { result in
        throw V2ToolExecutionError.unsupported(result.toolID)
    }
    var recoverToolOperations: @MainActor @Sendable (String) -> [V2ToolExecutionResult] = { _ in [] }
    var contextMemories: @MainActor @Sendable (V2AgentSourceTask?, Date) -> [V2UserMemoryRecord] = { _, _ in [] }
    var allMemoryRecords: @MainActor @Sendable () -> [V2UserMemoryRecord] = { [] }
    var webSearch: @MainActor @Sendable (String, Int) async throws -> [V2WebSearchResult]
    var webRead: @MainActor @Sendable (URL, Int) async throws -> String
    var localSearch: @MainActor @Sendable (String) async throws -> String
    var planAcceptance: @MainActor @Sendable (
        V2PlanDraft,
        Date
    ) throws -> V2PlanDraftRecord.Status
    var planDraftStatus: @MainActor @Sendable (String) -> V2PlanDraftRecord.Status?
    var providerStatus: @MainActor @Sendable () -> V2AssistantProviderStatus
    var toggleTaskCompletion: @MainActor @Sendable (String, String?, Date) throws -> Void = { _, _, _ in
        throw V2AssistantTurnError.scheduleUnavailable
    }
    var scheduleSnapshot: @MainActor @Sendable () -> V2AppSnapshot = { .empty }
    var applySchedule: @MainActor @Sendable (V2ScheduleProposal, V2AppSnapshot, String, Date) throws -> V2ScheduleReceipt = { _, _, _, _ in
        throw V2AssistantTurnError.scheduleUnavailable
    }
    var scheduleReceipt: @MainActor @Sendable (String) -> V2ScheduleReceipt? = { _ in nil }
    var undoSchedule: @MainActor @Sendable (String, Date) throws -> V2ScheduleReceipt = { _, _ in
        throw V2AssistantTurnError.scheduleUnavailable
    }
    var confirmsSchedule: @MainActor @Sendable () -> Bool = { false }
    var timeZoneIdentifier: @MainActor @Sendable () -> String = { TimeZone.current.identifier }
}

struct V2AssistantWorkspacePersistence {
    var isAvailable: Bool
    var load: @MainActor () throws -> V2AgentWorkspace
    var save: @MainActor (V2AgentWorkspace) throws -> Void

    init(
        isAvailable: Bool = true,
        load: @escaping @MainActor () throws -> V2AgentWorkspace,
        save: @escaping @MainActor (V2AgentWorkspace) throws -> Void
    ) {
        self.isAvailable = isAvailable
        self.load = load
        self.save = save
    }

    init(store: V2AgentWorkspaceJSONStore) {
        self.init(
            load: { try store.loadOrCreateEmpty() },
            save: { try store.save($0) }
        )
    }

    static var unavailable: Self {
        Self(
            isAvailable: false,
            load: { throw V2AssistantStorageError.unavailable },
            save: { _ in throw V2AssistantStorageError.unavailable }
        )
    }
}

enum V2AssistantStorageError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "助手存储位置不可用。"
        }
    }
}

enum V2AssistantTurnError: LocalizedError {
    case providerIdentityChanged
    case sessionUnavailable
    case persistenceUnavailable
    case toolLimitReached
    case scheduleUnavailable
    case planUnavailable
    case planDiscarded
    case toolUnavailable

    var errorDescription: String? {
        switch self {
        case .providerIdentityChanged:
            "AI 服务在本轮返回了不一致的供应商身份，请重试。"
        case .sessionUnavailable:
            "当前会话已不可用，请新建会话后重试。"
        case .persistenceUnavailable:
            "会话状态无法保存，已停止本次请求。"
        case .toolLimitReached:
            "本轮已达到 3 次工具调用上限，请缩小问题范围后重试。"
        case .scheduleUnavailable:
            "日程执行暂不可用，请稍后重试。"
        case .planUnavailable:
            "这份计划草稿已不存在，无法加入计划。"
        case .planDiscarded:
            "这份计划草稿已被丢弃，无法加入计划。"
        case .toolUnavailable:
            "这项 AI 操作当前不可用，原始请求已保留。"
        }
    }
}

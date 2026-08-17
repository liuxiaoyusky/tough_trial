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
}

struct V2AssistantDependencies: Sendable {
    var modelSnapshot: @MainActor @Sendable () throws -> V2AssistantModelSnapshot
    var webSearch: @MainActor @Sendable (String, Int) async throws -> [V2WebSearchResult]
    var webRead: @MainActor @Sendable (URL, Int) async throws -> String
    var localSearch: @MainActor @Sendable (String) async throws -> String
    var planAcceptance: @MainActor @Sendable (
        V2PlanDraft,
        Date
    ) throws -> V2PlanDraftRecord.Status
    var planDraftStatus: @MainActor @Sendable (String) -> V2PlanDraftRecord.Status?
    var providerStatus: @MainActor @Sendable () -> V2AssistantProviderStatus
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
    case planUnavailable
    case planDiscarded

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
        case .planUnavailable:
            "这份计划草稿已不存在，无法加入计划。"
        case .planDiscarded:
            "这份计划草稿已被丢弃，无法加入计划。"
        }
    }
}

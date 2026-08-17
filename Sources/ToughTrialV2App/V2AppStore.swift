import Foundation
import SwiftUI
import ToughTrialV2Core

@MainActor
final class V2AppStore: ObservableObject {
    @Published var state: V2PrototypeState
    @Published var isPlanPresented = false
    @Published var zenSession: V2ActiveSession?
    @Published private(set) var planningSourceTask: V2TaskNode?
    @Published var errorMessage: String?
    @Published private(set) var pendingPlanDrafts: [V2PlanDraftRecord] = []
    @Published private(set) var recallDate = Date()
    @Published private(set) var recallText = ""
    @Published private(set) var recallCandidates: [V2RecallReferenceCandidate] = []
    @Published private(set) var selectedRecallCandidateIDs = Set<String>()
    @Published private(set) var savedRecallEntry: V2RecallEntry?
    @Published private(set) var isRecallDirty = false
    @Published private(set) var isPlanning = false
    @Published private(set) var planningProviderLabel = "AI 未连接"
    @Published private(set) var planningSuggestedReplies: [String] = []
    @Published private(set) var planningFailureMessage: String?
    @Published private(set) var aiProviderSettings = V2AIProviderSettings.defaults
    @Published private(set) var aiModelCatalog = V2AIModelCatalogState()
    @Published private(set) var isRefreshingAIModels = false
    @Published private(set) var memoryRecords: [V2UserMemoryRecord] = []
    @Published private(set) var memoryIssueMessage: String?
    @Published private(set) var dreamingCandidates: [V2DreamingCandidate] = []
    @Published private(set) var noticeMessage: String?

    private let engine: V2Engine
    private var planningClient: any V2PlanningClient
    private let aiModelCatalogClient: any V2AIModelCatalogClient
    private let memoryEngine: V2MemoryEngine
    private let notificationService = V2NotificationService()
    private let liveActivityService = V2LiveActivityService()
    private let calendar: Calendar
    private let canWrite: Bool
    private let canWriteMemory: Bool
    private let allowsPlanningWithoutSavedAIService: Bool
    private let startupErrorMessage: String?
    private var aiProviderProfiles: [V2AIProviderPreset: V2AIProviderSettings]
    private var focusedSessionID: String?
    private var zenSessionID: String?
    private var baseRecallReferences = V2RecallReferences()
    private var recallWorkingDrafts: [Date: V2RecallWorkingDraft] = [:]
    private var activePlanningPrompt: String?
    private var activePlanningConversationID = UUID().uuidString

    init(
        engine injectedEngine: V2Engine? = nil,
        planningClient injectedPlanningClient: (any V2PlanningClient)? = nil,
        aiModelCatalogClient injectedAIModelCatalogClient: (any V2AIModelCatalogClient)? = nil,
        memoryEngine injectedMemoryEngine: V2MemoryEngine? = nil,
        initialState: V2PrototypeState = .empty(),
        calendar: Calendar = .current
    ) {
        let environment = ProcessInfo.processInfo.environment
        let isEmptyUITestMode = environment["TOUGH_TRIAL_UI_TEST_EMPTY"] == "1"
        let isUITestMode =
            isEmptyUITestMode
            || environment["TOUGH_TRIAL_UI_TESTING"] == "1"
        let isPlanningFailureUITest = environment["TOUGH_TRIAL_UI_TEST_PLANNING_FAILURE"] == "1"
        let requiresAIConfigurationUITest =
            environment["TOUGH_TRIAL_UI_TEST_REQUIRE_AI_CONFIGURATION"] == "1"
        #if DEBUG
        let hasDebugAIConfiguration = !(environment["TOUGH_TRIAL_AI_API_KEY"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        #else
        let hasDebugAIConfiguration = false
        #endif
        self.state = initialState
        self.calendar = calendar
        self.allowsPlanningWithoutSavedAIService =
            injectedPlanningClient != nil
            || (isUITestMode && !requiresAIConfigurationUITest)
            || hasDebugAIConfiguration
        let loadedAISettings = isUITestMode
            ? V2AIProviderSettings.defaults
            : V2AIProviderSettingsStore.load()
        self.aiProviderProfiles = Dictionary(
            uniqueKeysWithValues: V2AIProviderPreset.allCases.map { provider in
                let settings = isUITestMode
                    ? provider.defaultSettings()
                    : V2AIProviderSettingsStore.loadProfile(for: provider)
                return (provider, settings)
            }
        )
        self.aiProviderProfiles[loadedAISettings.provider] = loadedAISettings
        self.aiProviderSettings = loadedAISettings
        self.aiModelCatalog = isUITestMode
            ? V2AIModelCatalogState()
            : V2AIModelCatalogStore.load()
        self.aiModelCatalogClient = injectedAIModelCatalogClient
            ?? (isUITestMode
                ? V2UITestAIModelCatalogClient()
                : V2SiliconFlowModelCatalogClient())
        let basePlanningClient = injectedPlanningClient
            ?? (isPlanningFailureUITest
                ? V2UnavailablePlanningClient(message: "测试服务暂时不可用")
                : (isUITestMode
                    ? V2DeterministicPlanningClient()
                    : Self.configuredPlanningClient(settings: loadedAISettings)))
        let resolvedPlanningClient = V2ValidatedPlanningClient(client: basePlanningClient)
        self.planningClient = resolvedPlanningClient
        self.planningProviderLabel = resolvedPlanningClient.providerLabel
        self.activePlanningPrompt = initialState.planMessages.first(where: { $0.role == .user })?.text

        if let injectedEngine {
            self.engine = injectedEngine
            self.canWrite = true
            self.startupErrorMessage = nil
            self.errorMessage = nil
        } else if isEmptyUITestMode {
            self.engine = V2Engine()
            self.canWrite = true
            self.startupErrorMessage = nil
            self.errorMessage = nil
        } else {
            do {
                let url = try V2JSONSnapshotStore.defaultFileURL()
                self.engine = try V2Engine.load(from: V2JSONSnapshotStore(fileURL: url))
                self.canWrite = true
                self.startupErrorMessage = nil
                self.errorMessage = nil
            } catch {
                let message = "本地数据无法读取，原文件已保留。修复前不会写入新数据。"
                self.engine = V2Engine()
                self.canWrite = false
                self.startupErrorMessage = message
                self.errorMessage = message
            }
        }

        if let injectedMemoryEngine {
            self.memoryEngine = injectedMemoryEngine
            self.canWriteMemory = true
            self.memoryIssueMessage = nil
        } else if isEmptyUITestMode {
            self.memoryEngine = V2MemoryEngine()
            self.canWriteMemory = true
            self.memoryIssueMessage = nil
        } else {
            do {
                let url = try V2MemoryJSONStore.defaultFileURL()
                self.memoryEngine = try V2MemoryEngine.load(from: V2MemoryJSONStore(fileURL: url))
                self.canWriteMemory = true
                self.memoryIssueMessage = nil
            } catch {
                self.memoryEngine = V2MemoryEngine()
                self.canWriteMemory = false
                self.memoryIssueMessage = "记忆数据无法读取，原文件已保留。修复前不会覆盖。"
            }
        }
        self.memoryRecords = self.memoryEngine.activeRecords()

        refreshProjection(at: Date())
        loadRecallDay(Date(), now: Date())
        syncLiveActivityForFocusedSession()
    }

    func openPlanAgent() {
        if planningSourceTask != nil || state.planConversationPhase == .complete {
            resetPlanConversation()
        }
        planningSourceTask = nil
        isPlanPresented = true
    }

    func openPlanAgent(for task: V2TaskNode) {
        if planningSourceTask?.id != task.id || state.planConversationPhase == .complete {
            resetPlanConversation()
        }
        state.selectedTaskID = task.id
        planningSourceTask = task
        isPlanPresented = true
    }

    func closePlanAgent() {
        isPlanPresented = false
    }

    func startNewPlanConversation() {
        planningSourceTask = nil
        resetPlanConversation()
    }

    func resumePlanDraft(_ record: V2PlanDraftRecord) {
        let draft = record.editableDraft()
        planningSourceTask = nil
        activePlanningPrompt = draft.userPrompt
        activePlanningConversationID = "plan-draft-\(record.id)"
        planningSuggestedReplies = []
        planningFailureMessage = nil
        state.planScope = nil
        state.currentPlanDraft = draft
        state.planConversationPhase = .reviewingDraft
        state.planMessages = [
            V2PlanMessage(
                id: "plan-user-restored-\(record.id)",
                role: .user,
                text: draft.userPrompt
            ),
            V2PlanMessage(
                id: "plan-agent-restored-\(record.id)",
                role: .agent,
                text: "已恢复这份未完成的计划。你可以直接修改，或者继续告诉我怎么调整。"
            ),
        ]
    }

    func updateCurrentPlanScheduleItem(
        _ updatedItem: V2PlanDraftScheduleItem,
        at date: Date = Date()
    ) {
        guard var draft = state.currentPlanDraft,
              let index = draft.scheduleItems.firstIndex(where: { $0.id == updatedItem.id })
        else { return }

        draft.scheduleItems[index] = updatedItem
        state.currentPlanDraft = draft
        saveCurrentPlanDraft(at: date)
    }

    var visibleAIModels: [V2AIModel] {
        guard isUsingSiliconFlow else { return [] }
        return aiModelCatalog.visibleModels
    }

    var selectedAIModelID: String? {
        guard isUsingSiliconFlow else {
            return aiProviderSettings.isEnabled ? aiProviderSettings.model : nil
        }
        return aiModelCatalog.isSelectedModelAvailable
            ? aiModelCatalog.selectedModelID
            : nil
    }

    var hasConnectedAIService: Bool {
        let hasKey = !aiProviderSettings.apiKey
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        if isUsingSiliconFlow {
            return hasLoadedSiliconFlowModels
                && aiProviderSettings.isEnabled
                && aiModelCatalog.isSelectedModelAvailable
        }
        return hasKey && aiProviderSettings.isEnabled
    }

    var hasLoadedSiliconFlowModels: Bool {
        let hasKey = !aiProviderSettings.apiKey
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        return isUsingSiliconFlow
            && hasKey
            && aiModelCatalog.lastSuccessfulSyncAt != nil
            && !aiModelCatalog.models.isEmpty
    }

    var canUsePlanningAI: Bool {
        hasConnectedAIService || allowsPlanningWithoutSavedAIService
    }

    var isUsingSiliconFlow: Bool {
        aiProviderSettings.provider == .siliconFlow
    }

    func aiProviderProfile(for provider: V2AIProviderPreset) -> V2AIProviderSettings {
        aiProviderProfiles[provider] ?? provider.defaultSettings()
    }

    func updatePlanningSettings(_ settings: V2AIProviderSettings) throws {
        let basePlanningClient = try Self.makePlanningClient(settings: settings)
        try V2AIProviderSettingsStore.save(settings)
        let resolvedPlanningClient = V2ValidatedPlanningClient(client: basePlanningClient)
        aiProviderSettings = settings
        aiProviderProfiles[settings.provider] = settings
        planningClient = resolvedPlanningClient
        planningProviderLabel = resolvedPlanningClient.providerLabel
        planningFailureMessage = nil
        errorMessage = nil
    }

    func connectSiliconFlow(apiKey: String, at date: Date = Date()) async throws {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw V2AIModelCatalogClientError.missingAPIKey
        }
        guard !isRefreshingAIModels else { return }

        isRefreshingAIModels = true
        defer { isRefreshingAIModels = false }

        let models = try await aiModelCatalogClient.fetchModels(apiKey: key)
        var catalog = aiModelCatalog
        catalog.applySuccessfulSync(models: models, at: date)

        var settings = aiProviderProfile(for: .siliconFlow)
        let previousModel = settings.model
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if catalog.selectedModelID == nil,
           models.contains(where: { $0.id == previousModel }) {
            try catalog.selectModel(id: previousModel)
        }

        settings.apiKey = key
        settings.provider = .siliconFlow
        settings.baseURL = V2AIProviderSettings.siliconFlowBaseURL
        if catalog.isSelectedModelAvailable, let selectedModelID = catalog.selectedModelID {
            settings.model = selectedModelID
            settings.isEnabled = true
        } else {
            settings.isEnabled = false
        }

        let basePlanningClient = try Self.makePlanningClient(settings: settings)
        try V2AIProviderSettingsStore.save(settings)
        try V2AIModelCatalogStore.save(catalog)

        aiProviderSettings = settings
        aiProviderProfiles[settings.provider] = settings
        aiModelCatalog = catalog
        let resolvedPlanningClient = V2ValidatedPlanningClient(client: basePlanningClient)
        planningClient = resolvedPlanningClient
        planningProviderLabel = resolvedPlanningClient.providerLabel
        planningFailureMessage = nil
        errorMessage = nil
    }

    func refreshSiliconFlowModels(at date: Date = Date()) async throws {
        try await connectSiliconFlow(
            apiKey: aiProviderProfile(for: .siliconFlow).apiKey,
            at: date
        )
    }

    func selectAIModel(id: String) throws {
        var catalog = aiModelCatalog
        try catalog.selectModel(id: id)

        var settings = aiProviderProfile(for: .siliconFlow)
        settings.isEnabled = true
        settings.provider = .siliconFlow
        settings.baseURL = V2AIProviderSettings.siliconFlowBaseURL
        settings.model = id

        let basePlanningClient = try Self.makePlanningClient(settings: settings)
        try V2AIProviderSettingsStore.save(settings)
        try V2AIModelCatalogStore.save(catalog)

        aiProviderSettings = settings
        aiProviderProfiles[settings.provider] = settings
        aiModelCatalog = catalog
        let resolvedPlanningClient = V2ValidatedPlanningClient(client: basePlanningClient)
        planningClient = resolvedPlanningClient
        planningProviderLabel = resolvedPlanningClient.providerLabel
        planningFailureMessage = nil
        errorMessage = nil
    }

    func setAIModelVisible(id: String, isVisible: Bool) throws {
        var catalog = aiModelCatalog
        try catalog.setModelHidden(id: id, isHidden: !isVisible)
        try V2AIModelCatalogStore.save(catalog)
        aiModelCatalog = catalog
    }

    func disconnectAIService() throws {
        let settings = aiProviderSettings.provider.defaultSettings()
        let basePlanningClient = try Self.makePlanningClient(settings: settings)
        try V2AIProviderSettingsStore.save(settings)
        aiProviderSettings = settings
        aiProviderProfiles[settings.provider] = settings
        let resolvedPlanningClient = V2ValidatedPlanningClient(client: basePlanningClient)
        planningClient = resolvedPlanningClient
        planningProviderLabel = resolvedPlanningClient.providerLabel
        planningFailureMessage = nil
        errorMessage = nil
    }

    func submitPlanPrompt(_ prompt: String, at date: Date = Date()) async {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isPlanning else { return }
        guard canUsePlanningAI else {
            planningFailureMessage = "请先配置 AI 服务。"
            return
        }

        if state.planConversationPhase == .complete {
            resetPlanConversation()
        }

        if let draft = state.currentPlanDraft {
            await requestPlan(
                visibleUserText: trimmed,
                userPrompt: draft.userPrompt,
                clarificationResponse: trimmed,
                currentDraft: draft,
                at: date
            )
            return
        }

        activePlanningPrompt = trimmed
        await requestPlan(
            visibleUserText: trimmed,
            userPrompt: trimmed,
            clarificationResponse: nil,
            currentDraft: nil,
            at: date
        )
    }

    func submitPlanClarification(_ response: String, at date: Date = Date()) async {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isPlanning else { return }
        guard canUsePlanningAI else {
            planningFailureMessage = "请先配置 AI 服务。"
            return
        }
        guard let prompt = activePlanningPrompt
            ?? state.planMessages.first(where: { $0.role == .user })?.text
        else {
            errorMessage = "找不到这次规划的原始输入，请重新开始。"
            return
        }

        await requestPlan(
            visibleUserText: trimmed,
            userPrompt: prompt,
            clarificationResponse: trimmed,
            currentDraft: state.currentPlanDraft,
            at: date
        )
    }

    func saveCurrentPlanDraft(at date: Date = Date()) {
        guard let draft = state.currentPlanDraft else { return }
        let record = draft.durableRecord(at: date)
        guard mutate(at: date, {
            try engine.savePlanDraft(record, at: date, calendar: calendar)
        }) != nil else {
            return
        }
        state.saveCurrentPlanDraft()
    }

    func acceptCurrentPlanDraft(at date: Date = Date()) {
        guard let draft = state.currentPlanDraft else { return }
        let record = draft.durableRecord(at: date)
        guard let acceptance = mutate(at: date, {
            _ = try engine.savePlanDraft(record, at: date, calendar: calendar)
            return try engine.acceptPlanDraft(id: record.id, at: date, calendar: calendar)
        }) else {
            return
        }
        state.completeCurrentPlanDraftAcceptance()
        Task {
            do {
                _ = try await notificationService.scheduleIfAuthorized(
                    planItems: acceptance.createdPlanItems,
                    now: date,
                    calendar: calendar
                )
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
        }
    }

    func makeAssistantDependencies() -> V2AssistantDependencies {
        let environment = ProcessInfo.processInfo.environment
        let isUITestMode = environment["TOUGH_TRIAL_UI_TEST_EMPTY"] == "1"
            || environment["TOUGH_TRIAL_UI_TESTING"] == "1"

        if isUITestMode {
            return V2AssistantDependencies(
                modelSnapshot: {
                    V2AssistantModelSnapshot(
                        identity: V2AssistantProviderIdentity(
                            key: "ui-test-agent",
                            label: "UI 测试 Agent",
                            model: "deterministic-ui-test"
                        ),
                        respond: { request in
                            let action: V2AgentAction
                            if let observation = request.observations.last(where: { $0.tool == .plan }) {
                                action = .answer(text: observation.summary)
                            } else if !request.observations.isEmpty {
                                action = .answer(text: "测试回复已根据工具结果生成。")
                            } else if request.userText.contains("网页") || request.userText.contains("搜索") {
                                action = .webSearch(query: "Tough Trial 测试搜索")
                            } else if request.userText.contains("资料") {
                                action = .localSearch(query: request.userText)
                            } else if request.userText.contains("计划") || request.userText.contains("安排") {
                                action = .plan(query: request.userText)
                            } else {
                                action = .answer(text: "测试回复：\(request.userText)")
                            }
                            return V2AgentModelResult(
                                action: action,
                                providerLabel: "UI 测试 Agent",
                                model: "deterministic-ui-test"
                            )
                        }
                    )
                },
                webSearch: { _, limit in
                    Array([
                        V2WebSearchResult(
                            title: "Tough Trial 测试来源",
                            url: URL(string: "https://example.com/tough-trial")!,
                            snippet: "仅用于 UI 自动化的确定性搜索结果。",
                            siteName: "example.com"
                        )
                    ].prefix(limit))
                },
                webRead: { url, maxCharacters in
                    String("UI 自动化读取：\(url.host ?? "example.com")".prefix(maxCharacters))
                },
                localSearch: { [weak self] query in
                    self?.assistantLocalSearchSummary(query: query) ?? "未找到相关本地资料。"
                },
                planGeneration: { [weak self] session, query, date in
                    guard let self else { throw V2AssistantAppStoreError.storeUnavailable }
                    return try await self.assistantPlanningOutcome(
                        session: session,
                        query: query,
                        at: date
                    )
                },
                planAcceptance: { [weak self] draft, date in
                    guard let self else { throw V2AssistantAppStoreError.storeUnavailable }
                    return try self.acceptAssistantPlan(draft, at: date)
                },
                planDraftStatus: { [weak self] id in self?.assistantPlanDraftStatus(id: id) },
                providerStatus: {
                    V2AssistantProviderStatus(
                        isConfigured: true,
                        providerLabel: "UI 测试 Agent",
                        message: nil
                    )
                }
            )
        }

        let searchClient = V2DuckDuckGoSearchClient()
        let pageReader = V2URLSessionWebPageReader()
        return V2AssistantDependencies(
            modelSnapshot: { [weak self] in
                guard let self else { throw V2AssistantAppStoreError.storeUnavailable }
                let settings = self.aiProviderSettings
                let client = try settings.agentClient()
                let model = settings.model.trimmingCharacters(in: .whitespacesAndNewlines)
                let baseURL = settings.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                return V2AssistantModelSnapshot(
                    identity: V2AssistantProviderIdentity(
                        key: "\(settings.provider.rawValue)|\(baseURL)|\(model)",
                        label: client.providerLabel,
                        model: model
                    ),
                    respond: { request in try await client.respond(request) }
                )
            },
            webSearch: { query, limit in
                try await searchClient.search(query: query, limit: limit)
            },
            webRead: { url, maxCharacters in
                try await pageReader.read(url: url, maxCharacters: maxCharacters)
            },
            localSearch: { [weak self] query in
                self?.assistantLocalSearchSummary(query: query) ?? "未找到相关本地资料。"
            },
            planGeneration: { [weak self] session, query, date in
                guard let self else { throw V2AssistantAppStoreError.storeUnavailable }
                return try await self.assistantPlanningOutcome(
                    session: session,
                    query: query,
                    at: date
                )
            },
            planAcceptance: { [weak self] draft, date in
                guard let self else { throw V2AssistantAppStoreError.storeUnavailable }
                return try self.acceptAssistantPlan(draft, at: date)
            },
            planDraftStatus: { [weak self] id in self?.assistantPlanDraftStatus(id: id) },
            providerStatus: { [weak self] in
                guard let self else {
                    return V2AssistantProviderStatus(
                        isConfigured: false,
                        providerLabel: "AI 未连接",
                        message: "助手状态不可用。"
                    )
                }
                return V2AssistantProviderStatus(
                    isConfigured: self.hasConnectedAIService,
                    providerLabel: self.hasConnectedAIService
                        ? self.planningProviderLabel
                        : "AI 未连接",
                    message: self.hasConnectedAIService ? nil : "请先配置 AI 服务。"
                )
            }
        )
    }

    func assistantPlanningOutcome(
        session: V2AgentSession,
        query: String,
        at date: Date = Date()
    ) async throws -> V2PlanningOutcome {
        guard canUsePlanningAI else {
            throw V2AssistantAppStoreError.aiNotConfigured
        }
        let request = V2PlanningRequest(
            agentSession: session,
            query: query,
            tasks: assistantPlanningTasks(session: session, query: query),
            memoryStatements: assistantPlanningMemories(session: session, query: query, at: date),
            referenceDate: date,
            timeZoneIdentifier: calendar.timeZone.identifier
        )
        return try await planningClient.generate(request)
    }

    func assistantPlanDraftStatus(id: String) -> V2PlanDraftRecord.Status? {
        engine.snapshot.planDrafts.first(where: { $0.id == id })?.status
    }

    @discardableResult
    func acceptAssistantPlan(
        _ draft: V2PlanDraft,
        at date: Date = Date()
    ) throws -> V2PlanDraftRecord.Status {
        guard canWrite else {
            throw V2AssistantAppStoreError.storageUnavailable(
                startupErrorMessage ?? "本地数据当前不可写。"
            )
        }
        if let status = assistantPlanDraftStatus(id: draft.id) {
            switch status {
            case .accepted:
                return .accepted
            case .discarded:
                throw V2AssistantTurnError.planDiscarded
            case .draft:
                break
            }
        }
        let record = draft.durableRecord(at: date)
        _ = try engine.savePlanDraft(record, at: date, calendar: calendar)
        let acceptance = try engine.acceptPlanDraft(id: record.id, at: date, calendar: calendar)
        errorMessage = nil
        refreshProjection(at: date)
        Task {
            do {
                _ = try await notificationService.scheduleIfAuthorized(
                    planItems: acceptance.createdPlanItems,
                    now: date,
                    calendar: calendar
                )
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
        }
        return .accepted
    }

    func assistantPlanningTasks(
        session: V2AgentSession,
        query: String
    ) -> [V2PlanningTaskContext] {
        let activeTasks = engine.snapshot.tasks.filter { $0.status != .archived }
        let byID = Dictionary(uniqueKeysWithValues: activeTasks.map { ($0.id, $0) })
        var selected: [V2Task] = []
        var selectedIDs = Set<String>()

        func append(_ task: V2Task?) {
            guard let task, selectedIDs.insert(task.id).inserted, selected.count < 24 else { return }
            selected.append(task)
        }

        if let sourceID = session.sourceTask?.id, let source = byID[sourceID] {
            append(source)
            var parentID = source.parentID
            while let id = parentID, let parent = byID[id], selected.count < 12 {
                append(parent)
                parentID = parent.parentID
            }
            activeTasks.filter { $0.parentID == source.id }
                .sorted { $0.updatedAt > $1.updatedAt }
                .prefix(6)
                .forEach { append($0) }
            if let parentID = source.parentID {
                activeTasks.filter { $0.parentID == parentID && $0.id != source.id }
                    .sorted { $0.updatedAt > $1.updatedAt }
                    .prefix(4)
                    .forEach { append($0) }
            }
        }

        let terms = Self.assistantSpecificTerms(query)
        activeTasks.filter { task in
            guard !selectedIDs.contains(task.id) else { return false }
            let value = "\(task.title) \(Self.assistantStatusLabel(task.status))".lowercased()
            return terms.contains(where: value.contains)
        }
        .sorted { $0.updatedAt > $1.updatedAt }
        .forEach { append($0) }

        return selected.prefix(24).map {
            V2PlanningTaskContext(
                id: $0.id,
                title: $0.title,
                parentID: $0.parentID,
                contextID: $0.contextID,
                kind: $0.kind,
                status: $0.status
            )
        }
    }

    func assistantPlanningMemories(
        session: V2AgentSession,
        query: String,
        at date: Date
    ) -> [String] {
        let normalized = query.lowercased()
        let terms = Self.assistantSpecificTerms(query)
        let asksForSchedule = ["安排", "计划", "时间", "日程", "空闲", "routine", "schedule", "plan"]
            .contains(where: normalized.contains)
        let constraintTerms = ["可用", "时间", "工作日", "周末", "每天", "每周", "习惯", "例行", "通常",
                               "available", "availability", "weekday", "weekend", "daily", "weekly", "routine"]

        var selected: [String] = []
        var selectedIDs = Set<String>()
        let records = memoryEngine.activeRecords(at: date)
        func append(_ record: V2UserMemoryRecord) {
            guard selected.count < 12, selectedIDs.insert(record.id).inserted else { return }
            selected.append(String(record.statement.prefix(500)))
        }

        if let source = session.sourceTask {
            records.filter { record in
                (record.scope == .task && record.scopeID == source.id)
                    || (record.scope == .context && record.scopeID == source.contextID)
            }
            .forEach { append($0) }
        }
        records.filter { record in
            let value = record.statement.lowercased()
            if terms.contains(where: value.contains) { return true }
            return asksForSchedule && constraintTerms.contains(where: value.contains)
        }
        .forEach { append($0) }
        return selected
    }

    static func assistantSpecificTerms(_ query: String) -> [String] {
        let genericTerms = [
            "查找", "搜索", "看看", "告诉我", "显示", "列出", "我的", "相关", "资料", "记录",
            "有哪些", "是什么", "怎么样", "一下", "任务", "计划", "记忆", "状态", "安排",
            "show", "list", "find", "what", "which", "are", "is", "my", "me",
            "task", "tasks", "plan", "plans", "memory", "schedule"
        ]
        let normalized = genericTerms.reduce(query.lowercased()) {
            $0.replacingOccurrences(of: $1, with: " ")
        }
        return normalized
            .split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    func assistantLocalSearchSummary(
        query: String,
        at date: Date = Date()
    ) -> String {
        let normalizedQuery = query.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return "未找到相关本地资料。" }

        let genericTerms = [
            "查找", "搜索", "看看", "告诉我", "显示", "列出", "我的", "相关", "资料", "记录",
            "有哪些", "是什么", "怎么样", "一下", "任务", "计划", "记忆", "状态",
            "show", "list", "find", "what", "which", "are", "is", "my", "me",
            "task", "tasks", "plan", "plans", "memory"
        ]
        let specificQuery = genericTerms.reduce(normalizedQuery) {
            $0.replacingOccurrences(of: $1, with: " ")
        }
        let terms = specificQuery
            .split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
            .map(String.init)
            .filter { !$0.isEmpty }
        func matches(_ value: String, categoryTerms: [String]) -> Bool {
            let candidate = value.lowercased()
            if !terms.isEmpty {
                return terms.contains(where: candidate.contains)
            }
            return categoryTerms.contains(where: normalizedQuery.contains)
        }

        let taskLines = engine.snapshot.tasks
            .filter {
                $0.status != .archived
                    && matches(
                        "\($0.title) \(Self.assistantStatusLabel($0.status))",
                        categoryTerms: ["任务", "task"]
                    )
            }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(5)
            .map { "- \(String($0.title.prefix(180))) [\(Self.assistantStatusLabel($0.status))]" }

        let planLines = engine.snapshot.planItems
            .filter {
                $0.status != .canceled
                    && matches(
                        "\($0.title) \(Self.assistantDateLabel($0.date, calendar: calendar))",
                        categoryTerms: ["计划", "plan"]
                    )
            }
            .sorted { $0.date > $1.date }
            .prefix(5)
            .map {
                "- \(String($0.title.prefix(180))) [\(Self.assistantDateLabel($0.date, calendar: calendar))]"
            }

        let memoryLines = memoryEngine.activeStatements(at: date)
            .filter { matches($0, categoryTerms: ["记忆", "memory", "资料"]) }
            .prefix(5)
            .map { "- \(String($0.prefix(240)))" }

        var sections: [String] = []
        if !taskLines.isEmpty { sections.append("任务\n" + taskLines.joined(separator: "\n")) }
        if !planLines.isEmpty { sections.append("计划\n" + planLines.joined(separator: "\n")) }
        if !memoryLines.isEmpty { sections.append("Memory\n" + memoryLines.joined(separator: "\n")) }
        guard !sections.isEmpty else { return "未找到相关本地资料。" }
        return String(sections.joined(separator: "\n\n").prefix(4_000))
    }

    @discardableResult
    func addMemory(
        statement: String,
        kind: V2UserMemoryRecord.Kind,
        isTemporary: Bool,
        availability: V2WeeklyAvailability? = nil,
        at date: Date = Date()
    ) -> Bool {
        let result = mutateMemory(at: date) {
            try memoryEngine.add(
                statement: statement,
                kind: kind,
                origin: isTemporary ? .temporaryContext : .explicitUser,
                expiresAt: isTemporary
                    ? calendar.date(byAdding: .day, value: 7, to: date)
                    : nil,
                availability: availability,
                at: date
            )
        }
        return result != nil
    }

    @discardableResult
    func correctMemory(
        id: String,
        statement: String,
        kind: V2UserMemoryRecord.Kind,
        isTemporary: Bool,
        availability: V2WeeklyAvailability? = nil,
        at date: Date = Date()
    ) -> Bool {
        let result = mutateMemory(at: date) {
            try memoryEngine.correct(
                id: id,
                statement: statement,
                kind: kind,
                origin: isTemporary ? .temporaryContext : .explicitUser,
                expiresAt: isTemporary
                    ? calendar.date(byAdding: .day, value: 7, to: date)
                    : nil,
                availability: availability,
                at: date
            )
        }
        return result != nil
    }

    @discardableResult
    func forgetMemory(id: String, at date: Date = Date()) -> Bool {
        let result: Void? = mutateMemory(at: date) {
            try memoryEngine.forget(id: id)
        }
        return result != nil
    }

    func openDreamingCandidate(_ candidate: V2DreamingCandidate) {
        activePlanningPrompt = candidate.draft.userPrompt
        state.currentPlanDraft = candidate.draft
        state.planConversationPhase = .reviewingDraft
        appendPlanAgentMessage(
            "\(candidate.summary)\n\n我先把它放成草稿；只有你点“加入计划”后才会保存。"
        )
    }

    func selectRecallDate(_ date: Date, now: Date = Date()) {
        cacheCurrentRecallWork()
        loadRecallDay(date, now: now)
    }

    func updateRecallText(_ text: String) {
        recallText = text
        isRecallDirty = true
    }

    func refreshRecallEvidence(now: Date = Date()) {
        cacheCurrentRecallWork()
        loadRecallDay(recallDate, now: now)
    }

    func toggleRecallReference(_ candidate: V2RecallReferenceCandidate) {
        if selectedRecallCandidateIDs.contains(candidate.id) {
            selectedRecallCandidateIDs.remove(candidate.id)
        } else {
            selectedRecallCandidateIDs.insert(candidate.id)
        }
        isRecallDirty = true
    }

    func isRecallReferenceSelected(_ candidate: V2RecallReferenceCandidate) -> Bool {
        selectedRecallCandidateIDs.contains(candidate.id)
    }

    @discardableResult
    func saveRecall(hasHandwriting: Bool = false, at date: Date = Date()) -> Bool {
        let references = selectedRecallReferences()
        guard let entry = mutate(at: date, {
            try engine.saveRecallEntry(
                date: recallDate,
                text: recallText,
                hasHandwriting: hasHandwriting,
                references: references,
                at: date,
                calendar: calendar
            )
        }) else {
            return false
        }
        savedRecallEntry = entry
        baseRecallReferences = Self.subtract(
            V2RecallReferences(
                taskIDs: entry.referencedTaskIDs,
                segmentIDs: entry.referencedSegmentIDs,
                planItemIDs: entry.referencedPlanItemIDs
            ),
            referencesFromSelectedRecallCandidates()
        )
        isRecallDirty = false
        cacheCurrentRecallWork()
        return true
    }

    func runClock() async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return
            }
            refreshProjection(at: Date())
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    func dismissNotice() {
        noticeMessage = nil
    }

    func enablePlanReminders(at date: Date = Date()) async {
        do {
            let count = try await notificationService.requestAndSchedule(
                planItems: engine.snapshot.planItems,
                now: date,
                calendar: calendar
            )
            noticeMessage = count == 0
                ? "通知已开启；当前没有带具体时间的未来计划。"
                : "已为 \(count) 个带具体时间的计划开启提醒。"
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func selectTodayItem(_ item: V2TimelineItem) {
        state.selectedTaskID = item.kind == .task ? item.taskID : nil
        state.selectedTimelineItemID = item.kind == .task ? item.id : nil
    }

    func clearTodaySelection() {
        state.selectedTaskID = nil
        state.selectedTimelineItemID = nil
    }

    func focusSession(_ id: String) {
        focusedSessionID = id
        if let session = state.activeSessions.first(where: { $0.id == id }) {
            state.selectedTaskID = session.taskID
            state.selectedTimelineItemID = state.timelineItems.first {
                if let planItemID = session.planItemID {
                    return $0.planItemID == planItemID
                }
                return $0.taskID == session.taskID
            }?.id
        }
        refreshProjection(at: Date())
        syncLiveActivityForFocusedSession()
    }

    @discardableResult
    func quickAddTodayTask(title: String, at date: Date = Date()) -> Bool {
        guard let created = mutate(at: date, {
            try engine.quickInsertTodayTask(title: title, at: date, calendar: calendar)
        }) else {
            return false
        }
        state.selectedTaskID = created.task.id
        state.selectedTimelineItemID = created.planItem.id
        return true
    }

    @discardableResult
    func quickAddScheduledTask(title: String, on date: Date) -> Bool {
        guard let created = mutate(at: Date(), {
            try engine.quickInsertScheduledTask(title: title, on: date, calendar: calendar)
        }) else {
            return false
        }
        state.selectedTaskID = created.task.id
        return true
    }

    @discardableResult
    func createTaskFromTasks(
        title: String,
        parentTaskID: String?,
        at date: Date = Date()
    ) -> Bool {
        guard let task = mutate(at: date, {
            try engine.createTask(
                title: title,
                parentID: parentTaskID,
                at: date
            )
        }) else {
            return false
        }
        state.selectedTaskID = task.id
        return true
    }

    func startTodayItem(
        _ item: V2TimelineItem,
        source: V2ExecutionSegment.Source = .normal,
        at date: Date = Date()
    ) {
        guard item.kind == .task else { return }
        guard let segment = mutate(at: date, {
            try engine.startExecution(
                taskID: item.taskID,
                title: item.title,
                source: source,
                at: date,
                createdFromPlanItemID: item.planItemID
            )
        }) else {
            return
        }
        focusedSessionID = segment.logicalSessionID
        state.selectedTaskID = item.taskID
        state.selectedTimelineItemID = item.id
        refreshProjection(at: date)
        syncLiveActivityForFocusedSession()
    }

    func toggleSession(_ id: String, at date: Date = Date()) {
        guard let session = state.activeSessions.first(where: { $0.id == id }) else { return }
        switch session.status {
        case .running:
            _ = mutate(at: date) {
                try engine.pauseExecutionSession(sessionID: id, at: date)
            }
        case .paused:
            _ = mutate(at: date) {
                try engine.resumeExecutionSession(sessionID: id, at: date)
            }
        }
        syncLiveActivityForFocusedSession()
    }

    @discardableResult
    func endSession(_ id: String, at date: Date = Date()) -> Bool {
        let endingSession = state.activeSessions.first(where: { $0.id == id })
        let result: Void? = mutate(at: date) {
            try engine.stopExecutionSession(sessionID: id, at: date)
        }
        if let endingSession, result != nil {
            Task {
                await liveActivityService.end(session: endingSession)
                if let nextSession = state.activeSessions.first {
                    try? await liveActivityService.sync(session: nextSession)
                }
            }
        }
        return result != nil
    }

    func completeTodayItem(_ item: V2TimelineItem, at date: Date = Date()) {
        guard item.kind == .task else { return }
        _ = mutate(at: date) {
            try engine.completeTodayItem(
                planItemID: item.planItemID,
                taskID: item.taskID,
                at: date
            )
        }
    }

    func restoreTodayItem(_ item: V2TimelineItem, at date: Date = Date()) {
        guard item.kind == .task else { return }
        _ = mutate(at: date) {
            try engine.restoreTodayItem(
                planItemID: item.planItemID,
                taskID: item.taskID,
                at: date
            )
        }
        state.selectedTaskID = item.taskID
        state.selectedTimelineItemID = item.id
    }

    func startZen(
        planItemID: String? = nil,
        taskID: String?,
        title: String,
        at date: Date = Date()
    ) {
        if let existing = state.activeSessions.first(where: {
            if let planItemID {
                return $0.planItemID == planItemID
            }
            if let taskID {
                return $0.taskID == taskID
            }
            return $0.planItemID == nil
                && $0.taskID == nil
                && $0.title == title
        }) {
            focusedSessionID = existing.id
            zenSessionID = existing.id
            zenSession = existing
            syncLiveActivityForFocusedSession()
            return
        }

        guard let segment = mutate(at: date, {
            try engine.startExecution(
                taskID: taskID,
                title: title,
                source: .zen,
                at: date,
                createdFromPlanItemID: planItemID
            )
        }) else {
            return
        }
        focusedSessionID = segment.logicalSessionID
        zenSessionID = segment.logicalSessionID
        refreshProjection(at: date)
        syncLiveActivityForFocusedSession()
    }

    func finishZen(at date: Date = Date()) {
        guard let zenSessionID else { return }
        guard endSession(zenSessionID, at: date) else { return }
        self.zenSessionID = nil
        zenSession = nil
    }

    func toggleZenSession(at date: Date = Date()) {
        guard let zenSessionID else { return }
        toggleSession(zenSessionID, at: date)
    }

    func closeZen() {
        zenSessionID = nil
        zenSession = nil
    }

    private func syncLiveActivityForFocusedSession() {
        guard let session = state.activeSessions.first else { return }
        Task {
            do {
                try await liveActivityService.sync(session: session)
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
        }
    }

    private func refreshProjection(at now: Date) {
        let today = engine.todaySnapshot(date: now, now: now, calendar: calendar)
        pendingPlanDrafts = engine.snapshot.planDrafts
            .filter { $0.status == .draft }
            .sorted { $0.updatedAt > $1.updatedAt }
        var next = state
        next.tasks = projectedTasks(through: now)
        next.timelineItems = today.items.map { item in
            V2TimelineItem(
                id: item.id,
                kind: item.kind == .task ? .task : .executionRecord,
                planItemID: item.planItemID,
                timeLabel: item.plannedAt.map(Self.shortTime) ?? "今天",
                title: item.title,
                detail: Self.todayDetail(for: item),
                taskID: item.taskID,
                isDone: item.isDone
            )
        }
        next.scheduledTasks = projectedSchedule()

        var sessions = today.sessions.map { session in
            let currentSeconds = max(0, Int(session.currentDuration.rounded(.down)))
            let totalSeconds = max(0, Int(session.totalDuration.rounded(.down)))
            return V2ActiveSession(
                id: session.id,
                planItemID: session.planItemID,
                taskID: session.taskID,
                title: session.title,
                startedAtLabel: Self.shortTime(session.startedAt),
                currentElapsed: currentSeconds / 60,
                totalElapsed: totalSeconds / 60,
                currentElapsedSeconds: currentSeconds,
                totalElapsedSeconds: totalSeconds,
                status: session.status == .running ? .running : .paused
            )
        }
        if let focusedSessionID,
           let focusedIndex = sessions.firstIndex(where: { $0.id == focusedSessionID }) {
            let focused = sessions.remove(at: focusedIndex)
            sessions.insert(focused, at: 0)
        } else {
            focusedSessionID = sessions.first?.id
        }
        next.activeSessions = sessions

        if let selectedTaskID = next.selectedTaskID,
           !next.flattenTasks().contains(where: { $0.id == selectedTaskID }) {
            next.selectedTaskID = nil
        }
        if let selectedTimelineItemID = next.selectedTimelineItemID,
           !next.timelineItems.contains(where: { $0.id == selectedTimelineItemID }) {
            next.selectedTimelineItemID = nil
        }
        state = next
        refreshDreaming(at: now)

        if let zenSessionID {
            zenSession = sessions.first(where: { $0.id == zenSessionID })
            if zenSession == nil {
                self.zenSessionID = nil
            }
        }
    }

    private func loadRecallDay(_ date: Date, now: Date) {
        let day = calendar.startOfDay(for: date)
        recallDate = day
        let evidence = engine.recallEvidence(date: recallDate, now: now, calendar: calendar)
        recallCandidates = engine.recallReferenceCandidates(
            date: recallDate,
            now: now,
            calendar: calendar
        )
        savedRecallEntry = evidence.savedEntry

        if let working = recallWorkingDrafts[day] {
            recallText = working.text
            selectedRecallCandidateIDs = working.selectedCandidateIDs.intersection(
                Set(recallCandidates.map(\.id))
            )
            baseRecallReferences = working.baseReferences
            isRecallDirty = working.isDirty
            return
        }

        recallText = evidence.savedEntry?.text ?? ""
        let selectedIDs = Set(
            recallCandidates
                .filter { candidate in
                    guard let entry = evidence.savedEntry else { return false }
                    return Self.references(candidate.references, areIncludedIn: entry)
                }
                .map(\.id)
        )
        selectedRecallCandidateIDs = selectedIDs
        let savedReferences = V2RecallReferences(
            taskIDs: evidence.savedEntry?.referencedTaskIDs ?? [],
            segmentIDs: evidence.savedEntry?.referencedSegmentIDs ?? [],
            planItemIDs: evidence.savedEntry?.referencedPlanItemIDs ?? []
        )
        baseRecallReferences = Self.subtract(
            savedReferences,
            referencesFromSelectedRecallCandidates()
        )
        isRecallDirty = false
        cacheCurrentRecallWork()
    }

    private func selectedRecallReferences() -> V2RecallReferences {
        let selected = referencesFromSelectedRecallCandidates()
        return V2RecallReferences(
            taskIDs: Self.unique(baseRecallReferences.taskIDs + selected.taskIDs),
            segmentIDs: Self.unique(baseRecallReferences.segmentIDs + selected.segmentIDs),
            planItemIDs: Self.unique(baseRecallReferences.planItemIDs + selected.planItemIDs)
        )
    }

    private func referencesFromSelectedRecallCandidates() -> V2RecallReferences {
        let selected = recallCandidates.filter { selectedRecallCandidateIDs.contains($0.id) }
        return V2RecallReferences(
            taskIDs: Self.unique(selected.flatMap(\.references.taskIDs)),
            segmentIDs: Self.unique(selected.flatMap(\.references.segmentIDs)),
            planItemIDs: Self.unique(selected.flatMap(\.references.planItemIDs))
        )
    }

    private func cacheCurrentRecallWork() {
        let day = calendar.startOfDay(for: recallDate)
        recallWorkingDrafts[day] = V2RecallWorkingDraft(
            text: recallText,
            selectedCandidateIDs: selectedRecallCandidateIDs,
            baseReferences: baseRecallReferences,
            isDirty: isRecallDirty
        )
    }

    private func projectedTasks(through now: Date) -> [V2TaskNode] {
        let tasks = engine.snapshot.tasks.filter { $0.status != .archived }
        let contextByID = Dictionary(uniqueKeysWithValues: engine.snapshot.taskContexts.map { ($0.id, $0) })
        let roots = tasks.filter { task in
            guard let parentID = task.parentID else { return true }
            return !tasks.contains(where: { $0.id == parentID })
        }

        func node(_ task: V2Task, visited: Set<String>) -> V2TaskNode {
            let context = task.contextID.flatMap { contextByID[$0] }
            let children: [V2TaskNode]
            if visited.contains(task.id) {
                children = []
            } else {
                let nextVisited = visited.union([task.id])
                children = tasks
                    .filter { $0.parentID == task.id }
                    .sorted { $0.createdAt < $1.createdAt }
                    .map { node($0, visited: nextVisited) }
            }
            return V2TaskNode(
                id: task.id,
                title: task.title,
                subtitle: task.note,
                goal: context?.title ?? "未归类",
                colorName: context?.colorName ?? "teal",
                status: Self.prototypeStatus(task.status),
                spentMinutes: Int(engine.spentDuration(taskID: task.id, through: now) / 60),
                children: children
            )
        }

        return roots
            .sorted { $0.createdAt < $1.createdAt }
            .map { node($0, visited: []) }
    }

    private func projectedSchedule() -> [V2ScheduledTask] {
        let taskByID = Dictionary(uniqueKeysWithValues: engine.snapshot.tasks.map { ($0.id, $0) })
        return engine.snapshot.planItems.compactMap { item in
            guard item.status != .canceled else { return nil }
            let task = item.taskID.flatMap { taskByID[$0] }
            let placement: V2SchedulePlacement
            if let startAt = item.startAt {
                let components = calendar.dateComponents([.hour, .minute], from: startAt)
                let startMinute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
                let duration = item.endAt.map {
                    max(15, Int($0.timeIntervalSince(startAt) / 60))
                } ?? 30
                placement = .timed(startMinute: startMinute, durationMinutes: duration)
            } else {
                placement = .allDay
            }
            return V2ScheduledTask(
                id: item.id,
                title: item.title,
                detail: item.startAt == nil ? "仅确定日期，时间可以之后再安排。" : "已放在时间轴。",
                taskID: item.taskID,
                date: item.date,
                placement: placement,
                isDone: task?.status == .done
            )
        }
    }

    private func mutate<Result>(at date: Date, _ operation: () throws -> Result) -> Result? {
        guard canWrite else {
            errorMessage = startupErrorMessage
            return nil
        }
        do {
            let result = try operation()
            errorMessage = nil
            refreshProjection(at: date)
            return result
        } catch {
            errorMessage = Self.message(for: error)
            return nil
        }
    }

    private func requestPlan(
        visibleUserText: String,
        userPrompt: String,
        clarificationResponse: String?,
        currentDraft: V2PlanDraft?,
        at date: Date
    ) async {
        let previousPhase = state.planConversationPhase
        state.planMessages.append(
            V2PlanMessage(
                id: "plan-user-\(state.planMessages.count + 1)-\(UUID().uuidString)",
                role: .user,
                text: visibleUserText
            )
        )
        if previousPhase == .empty || previousPhase == .complete {
            state.planConversationPhase = .clarifying
        }
        planningSuggestedReplies = []
        planningFailureMessage = nil
        isPlanning = true
        defer { isPlanning = false }

        let request = V2PlanningRequest(
            userPrompt: userPrompt,
            clarificationResponse: clarificationResponse,
            scope: planningRequestScope,
            conversationIdentifier: activePlanningConversationID,
            referenceDate: date,
            timeZoneIdentifier: calendar.timeZone.identifier,
            tasks: engine.snapshot.tasks
                .filter { $0.status != .archived }
                .prefix(100)
                .map {
                    V2PlanningTaskContext(
                        id: $0.id,
                        title: $0.title,
                        parentID: $0.parentID,
                        contextID: $0.contextID,
                        kind: $0.kind,
                        status: $0.status
                    )
                },
            memoryStatements: memoryEngine.activeStatements(at: date),
            conversation: state.planMessages.suffix(40).map {
                V2PlanningConversationMessage(role: $0.role, text: $0.text)
            },
            currentDraft: currentDraft
        )

        do {
            let outcome = try await planningClient.generate(request)
            switch outcome {
            case .clarification(let clarification):
                state.currentPlanDraft = nil
                state.planConversationPhase = .clarifying
                planningSuggestedReplies = clarification.suggestedReplies
                appendPlanAgentMessage(clarification.question)
            case .proposal(let proposal):
                state.currentPlanDraft = proposal.draft
                state.planConversationPhase = .reviewingDraft
                planningSuggestedReplies = []
                appendPlanAgentMessage(proposal.message)
                saveCurrentPlanDraft(at: date)
            }
            planningFailureMessage = nil
            errorMessage = nil
        } catch {
            state.planConversationPhase = previousPhase == .empty ? .complete : previousPhase
            planningSuggestedReplies = []
            planningFailureMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    private var planningRequestScope: String? {
        guard let task = planningSourceTask else {
            return state.planScope
        }
        return "聚焦任务：\(task.title)（task_id: \(task.id)）"
    }

    private func appendPlanAgentMessage(_ text: String) {
        state.planMessages.append(
            V2PlanMessage(
                id: "plan-agent-\(state.planMessages.count + 1)-\(UUID().uuidString)",
                role: .agent,
                text: text
            )
        )
    }

    private func resetPlanConversation() {
        activePlanningPrompt = nil
        activePlanningConversationID = UUID().uuidString
        planningSuggestedReplies = []
        planningFailureMessage = nil
        state.planMessages = []
        state.planConversationPhase = .empty
        state.planScope = nil
        state.currentPlanDraft = nil
    }

    private static func configuredPlanningClient(
        settings: V2AIProviderSettings
    ) -> any V2PlanningClient {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if let apiKey = environment["TOUGH_TRIAL_AI_API_KEY"], !apiKey.isEmpty {
            let endpoint: URL
            if let value = environment["TOUGH_TRIAL_AI_ENDPOINT"] {
                guard let configuredURL = URL(string: value) else {
                    return V2UnavailablePlanningClient(message: "TOUGH_TRIAL_AI_ENDPOINT 不是有效 URL")
                }
                endpoint = configuredURL
            } else {
                endpoint = URL(string: "https://api.openai.com/v1/responses")!
            }

            let configuration = V2RemotePlanningConfiguration(
                endpoint: endpoint,
                apiKey: apiKey,
                model: environment["TOUGH_TRIAL_AI_MODEL"] ?? "gpt-5-mini"
            )
            return V2RemotePlanningClient(configuration: configuration)
        }
        #endif

        do {
            return try makePlanningClient(settings: settings)
        } catch {
            return V2UnavailablePlanningClient(
                message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            )
        }
    }

    private static func makePlanningClient(
        settings: V2AIProviderSettings
    ) throws -> any V2PlanningClient {
        guard settings.isEnabled else {
            return V2UnavailablePlanningClient(message: "请先配置 AI 服务")
        }
        return V2OpenAICompatiblePlanningClient(
            configuration: try settings.planningConfiguration()
        )
    }

    private func mutateMemory<Result>(
        at date: Date,
        _ operation: () throws -> Result
    ) -> Result? {
        guard canWriteMemory else {
            errorMessage = memoryIssueMessage
            return nil
        }
        do {
            let result = try operation()
            memoryRecords = memoryEngine.activeRecords(at: date)
            refreshDreaming(at: date)
            memoryIssueMessage = nil
            errorMessage = nil
            return result
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }

    private func refreshDreaming(at date: Date) {
        dreamingCandidates = V2DreamingEngine.candidates(
            snapshot: engine.snapshot,
            memoryRecords: memoryEngine.activeRecords(at: date),
            now: date,
            calendar: calendar
        )
    }

    private static func prototypeStatus(_ status: V2Task.Status) -> V2TaskNode.Status {
        switch status {
        case .notStarted, .archived:
            .planned
        case .active:
            .active
        case .paused:
            .paused
        case .done:
            .done
        }
    }

    private static func assistantStatusLabel(_ status: V2Task.Status) -> String {
        switch status {
        case .notStarted:
            "未开始"
        case .active:
            "进行中"
        case .paused:
            "已暂停"
        case .done:
            "已完成"
        case .archived:
            "已归档"
        }
    }

    private static func assistantDateLabel(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private static func shortTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private static func durationText(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration.rounded(.down)))
        if seconds >= 3_600 {
            return "\(seconds / 3_600)小时\((seconds % 3_600) / 60)分钟"
        }
        if seconds >= 60 {
            return "\(seconds / 60)分钟"
        }
        return "\(seconds)秒"
    }

    private static func unique(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }

    private static func subtract(
        _ references: V2RecallReferences,
        _ removed: V2RecallReferences
    ) -> V2RecallReferences {
        let removedTaskIDs = Set(removed.taskIDs)
        let removedSegmentIDs = Set(removed.segmentIDs)
        let removedPlanItemIDs = Set(removed.planItemIDs)
        return V2RecallReferences(
            taskIDs: references.taskIDs.filter { !removedTaskIDs.contains($0) },
            segmentIDs: references.segmentIDs.filter { !removedSegmentIDs.contains($0) },
            planItemIDs: references.planItemIDs.filter { !removedPlanItemIDs.contains($0) }
        )
    }

    private static func references(
        _ references: V2RecallReferences,
        areIncludedIn entry: V2RecallEntry
    ) -> Bool {
        let hasReference = !references.taskIDs.isEmpty ||
            !references.segmentIDs.isEmpty ||
            !references.planItemIDs.isEmpty
        guard hasReference else { return false }
        return Set(references.taskIDs).isSubset(of: Set(entry.referencedTaskIDs)) &&
            Set(references.segmentIDs).isSubset(of: Set(entry.referencedSegmentIDs)) &&
            Set(references.planItemIDs).isSubset(of: Set(entry.referencedPlanItemIDs))
    }

    private static func todayDetail(for item: V2TodayItemSnapshot) -> String {
        switch item.kind {
        case .task where item.spentDuration > 0:
            return "今天已记录 \(durationText(item.spentDuration))。"
        case .task:
            return "今天要处理的任务。"
        case .executionRecord:
            return "记录了 \(durationText(item.spentDuration)) 的执行时间。"
        }
    }

    private static func message(for error: Error) -> String {
        switch error {
        case V2EngineError.taskCompleted(_):
            return "这个任务已经完成，恢复后才能再次开始。"
        case V2EngineError.taskAlreadyRunning(_):
            return "这个任务已经在计时。"
        case V2EngineError.blankTitle:
            return "任务名称不能为空。"
        case V2EngineError.blankRecallText:
            return "写下一点内容或手写后再完成。"
        default:
            return "操作没有保存，请稍后再试。"
        }
    }
}

private enum V2AssistantAppStoreError: LocalizedError {
    case aiNotConfigured
    case storageUnavailable(String)
    case storeUnavailable

    var errorDescription: String? {
        switch self {
        case .aiNotConfigured:
            "请先配置 AI 服务。"
        case let .storageUnavailable(message):
            message
        case .storeUnavailable:
            "助手依赖的 App 状态已不可用。"
        }
    }
}

private struct V2RecallWorkingDraft {
    var text: String
    var selectedCandidateIDs: Set<String>
    var baseReferences: V2RecallReferences
    var isDirty: Bool
}

private struct V2UITestAIModelCatalogClient: V2AIModelCatalogClient {
    func fetchModels(apiKey: String) async throws -> [V2AIModel] {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw V2AIModelCatalogClientError.missingAPIKey
        }
        return [
            V2AIModel(id: "Qwen/Qwen3-32B"),
            V2AIModel(id: "deepseek-ai/DeepSeek-V3"),
            V2AIModel(id: "moonshotai/Kimi-K2"),
        ]
    }
}

private struct V2UnavailablePlanningClient: V2PlanningClient {
    let providerLabel = "AI 配置错误"
    let message: String

    func generate(_ request: V2PlanningRequest) async throws -> V2PlanningOutcome {
        throw V2PlanningClientError.invalidConfiguration(message)
    }
}

import SwiftUI
import ToughTrialV2Core

struct V2AIProviderSettingsView: View {
    @ObservedObject var store: V2AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedProvider: V2AIProviderPreset
    @State private var profiles: [V2AIProviderPreset: V2AIProviderSettings]
    @State private var errorMessage: String?
    @StateObject private var connectionTest: V2AIConnectionTest
    @State private var connectionTask: Task<Void, Never>?
    @State private var draftCatalog: V2AIModelCatalogState
    @State private var isLoadingCatalog = false
    @FocusState private var isEditingField: Bool

    init(store: V2AppStore) {
        self.store = store
        let activeSettings = store.aiProviderSettings
        var loadedProfiles = Dictionary(
            uniqueKeysWithValues: V2AIProviderPreset.allCases.map {
                ($0, store.aiProviderProfile(for: $0))
            }
        )
        loadedProfiles[activeSettings.provider] = activeSettings
        _draftCatalog = State(initialValue: store.aiModelCatalog)
        let isUITesting = ProcessInfo.processInfo.environment["TOUGH_TRIAL_UI_TESTING"] == "1"
        _connectionTest = StateObject(wrappedValue: isUITesting ? V2AIConnectionTest(probe: { _ in
            if ProcessInfo.processInfo.environment["TOUGH_TRIAL_UI_CONNECTION_FAILURE"] == "1" {
                throw V2AgentClientError.requestFailed(statusCode: 401, message: "Synthetic auth failure")
            }
        }) : V2AIConnectionTest())
        _selectedProvider = State(initialValue: activeSettings.provider)
        _profiles = State(initialValue: loadedProfiles)
    }

    var body: some View {
        NavigationStack {
            Form {
                providerSection
                Section {
                    NavigationLink("语音输入") { V2SpeechSettingsView() }
                        .accessibilityIdentifier("ai.settings.speech")
                }

                switch selectedProvider {
                case .siliconFlow:
                    siliconFlowSection
                    if hasLoadedSiliconFlowModels {
                        modelSection
                    }
                case .kimiCoding, .glmCoding, .miniMax:
                    codingPlanSection
                case .custom:
                    customProviderSection
                }
                thinkingSection
                connectionSection
            }
            .navigationTitle("AI 服务")
            .v2InlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .alert("AI 服务未更新", isPresented: errorBinding) {
                Button("知道了") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "请稍后再试。")
            }
        }
        .presentationDetents([.large])
        .onChange(of: currentProfile) { _, _ in
            connectionTask?.cancel()
            connectionTest.invalidate()
        }
        .onDisappear {
            connectionTask?.cancel()
            connectionTest.invalidate()
        }
    }

    private var providerSection: some View {
        Section {
            Picker("AI 服务", selection: $selectedProvider) {
                ForEach(V2AIProviderPreset.allCases) { provider in
                    Text(provider.title).tag(provider)
                }
            }
            .v2NavigationPicker()
            .accessibilityIdentifier("ai.settings.provider")

            if store.hasConnectedAIService {
                Label(
                    "已保存：\(store.aiProviderSettings.provider.title)",
                    systemImage: "checkmark.circle.fill"
                )
                .foregroundStyle(V2Theme.mint)
            }
        } header: {
            Text("提供商")
        }
    }

    private var siliconFlowSection: some View {
        Section {
            if store.hasConnectedAIService && store.isUsingSiliconFlow {
                Label {
                    Text("已保存 · \(draftCatalog.models.count) 个聊天模型")
                        .accessibilityIdentifier("ai.settings.connected")
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(V2Theme.mint)
                }
            } else if hasLoadedSiliconFlowModels {
                Label {
                    Text("已读取 \(draftCatalog.models.count) 个模型，请选择模型")
                        .accessibilityIdentifier("ai.settings.catalogLoaded")
                } icon: {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(V2Theme.blue)
                }
            }

            SecureField("粘贴 API Key", text: profileBinding(\.apiKey))
                .v2Autocapitalization(.never)
                .autocorrectionDisabled()
                .focused($isEditingField)
                .submitLabel(.done)
                .accessibilityIdentifier("ai.settings.apiKey")

            Button {
                connectSiliconFlow()
            } label: {
                HStack(spacing: 8) {
                    if isLoadingCatalog {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(hasLoadedSiliconFlowModels ? "更新可选模型" : "读取可选模型")
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(isLoadingCatalog || !hasAPIKey)
            .accessibilityIdentifier("ai.settings.connect")
        } header: {
            Text("SiliconFlow")
        } footer: {
            Text("读取模型仅用于选择，不会保存配置；选好后请测试连接。")
        }
    }

    private var codingPlanSection: some View {
        Section {
            if selectedProvider == .miniMax {
                Picker("账号地区", selection: profileBinding(\.baseURL)) {
                    Text("海外 · Coding Plan / API").tag("https://api.minimax.io/v1")
                    Text("国内").tag("https://api.minimax.cn/v1")
                    if !["https://api.minimax.io/v1", "https://api.minimax.cn/v1"].contains(currentProfile.baseURL) {
                        Text("已保存的地址").tag(currentProfile.baseURL)
                    }
                }
                .v2NavigationPicker()
                .accessibilityIdentifier("ai.settings.minimaxRegion")
            }

            SecureField("粘贴 API Key", text: profileBinding(\.apiKey))
                .v2Autocapitalization(.never)
                .autocorrectionDisabled()
                .focused($isEditingField)
                .submitLabel(.done)
                .accessibilityIdentifier("ai.settings.apiKey")

            Menu {
                ForEach(selectedProvider.models, id: \.self) { model in
                    Button {
                        updateProfile(\.model, to: model)
                    } label: {
                        if model == currentProfile.model {
                            Label(model, systemImage: "checkmark")
                        } else {
                            Text(model)
                        }
                    }
                }
            } label: {
                HStack {
                    Text("模型")
                    Spacer()
                    Text(currentProfile.model)
                        .foregroundStyle(V2Theme.secondary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(V2Theme.tertiary)
                }
            }
            .accessibilityLabel("模型 \(currentProfile.model)")
            .accessibilityIdentifier("ai.settings.presetModel")

            if selectedProvider == .glmCoding || selectedProvider == .miniMax {
                Button("使用快速推荐：\(selectedProvider.defaultModel)") { updateProfile(\.model, to: selectedProvider.defaultModel) }
                    .accessibilityIdentifier("ai.settings.fastModel")
            }

            if isEditingActiveProvider {
                Button("移除此 API Key", role: .destructive) {
                    disconnect()
                }
            }
        } header: {
            Text(selectedProvider.title)
        } footer: {
            Text(codingPlanFooter)
        }
    }

    private var customProviderSection: some View {
        Section {
            TextField("服务地址", text: profileBinding(\.baseURL))
                .v2Autocapitalization(.never)
                .v2KeyboardType(.URL)
                .autocorrectionDisabled()
                .focused($isEditingField)
                .submitLabel(.done)
                .accessibilityIdentifier("ai.settings.baseURL")

            TextField("模型名称", text: profileBinding(\.model))
                .v2Autocapitalization(.never)
                .autocorrectionDisabled()
                .focused($isEditingField)
                .submitLabel(.done)
                .accessibilityIdentifier("ai.settings.model")

            SecureField("粘贴 API Key", text: profileBinding(\.apiKey))
                .v2Autocapitalization(.never)
                .autocorrectionDisabled()
                .focused($isEditingField)
                .submitLabel(.done)
                .accessibilityIdentifier("ai.settings.apiKey")

            if isEditingActiveProvider {
                Button("移除此 API Key", role: .destructive) {
                    disconnect()
                }
            }
        } header: {
            Text("其他 OpenAI 兼容服务")
        } footer: {
            Text("适用于提供 /v1/chat/completions 的兼容服务。")
        }
    }

    private var thinkingSection: some View {
        let capability = currentProfile.thinkingCapability
        return Section {
            if capability.options.count > 1 || !capability.supports(currentProfile.thinking) {
                Picker("思考强度", selection: thinkingBinding(capability: capability)) {
                    ForEach(capability.options, id: \.self) { option in
                        Text(option.title).tag(option)
                    }
                }
                .accessibilityIdentifier("ai.settings.thinking")
            } else {
                LabeledContent("思考强度", value: capability.options.first?.title ?? "未声明")
                    .accessibilityIdentifier("ai.settings.thinking")
            }

            Text(capability.note)
                .font(.footnote)
                .foregroundStyle(V2Theme.secondary)

            if !capability.supports(currentProfile.thinking) {
                Label(
                    "当前模型不支持已保存的“\(currentProfile.thinking.title)”设置，请重新选择",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.footnote)
                .foregroundStyle(V2Theme.orange)
            }
        } header: {
            Text("Thinking")
        }
    }

    private var modelSection: some View {
        Section {
            NavigationLink {
                V2AIModelSelectionView(
                    models: draftCatalog.visibleModels,
                    selectedModelID: siliconFlowSelectedModelID,
                    onSelect: selectModel
                )
            } label: {
                HStack {
                    Text("当前模型")
                        .foregroundStyle(V2Theme.ink)
                    Spacer()
                    Text(siliconFlowSelectedModelID ?? "选择模型")
                        .foregroundStyle(V2Theme.secondary)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(V2Theme.tertiary)
                }
            }
            .accessibilityLabel("当前模型 \(siliconFlowSelectedModelID ?? "未选择")")
            .accessibilityIdentifier("ai.settings.currentModel")

            if draftCatalog.selectedModelID != nil,
               !draftCatalog.isSelectedModelAvailable {
                Label("原模型已不可用，请手动选择新模型", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(V2Theme.orange)
            }

            NavigationLink {
                V2AIModelManagementView(catalog: $draftCatalog)
            } label: {
                Label("管理模型", systemImage: "slider.horizontal.3")
            }
            .accessibilityIdentifier("ai.settings.manageModels")

            Button("更新模型列表") {
                connectSiliconFlow()
            }
            .disabled(isLoadingCatalog)

            if isEditingActiveProvider {
                Button("移除 API Key", role: .destructive) {
                    disconnect()
                }
            }
        } header: {
            Text("模型")
        } footer: {
            Text("新发现的模型默认显示；只有你手动隐藏的模型会继续隐藏。")
        }
    }

    private var currentProfile: V2AIProviderSettings {
        profiles[selectedProvider] ?? selectedProvider.defaultSettings()
    }

    private var hasAPIKey: Bool {
        !currentProfile.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canSaveCurrentProfile: Bool {
        hasAPIKey
            && !currentProfile.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !currentProfile.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && currentProfile.thinkingCapability.supports(currentProfile.thinking)
    }

    private var hasLoadedSiliconFlowModels: Bool {
        hasAPIKey
            && draftCatalog.lastSuccessfulSyncAt != nil
            && !draftCatalog.models.isEmpty
    }

    private var siliconFlowSelectedModelID: String? {
        draftCatalog.isSelectedModelAvailable
            ? draftCatalog.selectedModelID
            : nil
    }

    private var isEditingActiveProvider: Bool {
        store.aiProviderSettings.provider == selectedProvider
            && !store.aiProviderSettings.apiKey
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
    }

    private var codingPlanFooter: String {
        switch selectedProvider {
        case .kimiCoding:
            "请使用 Kimi Code 控制台生成的 API Key；它与开放平台 Key 不通用。"
        case .glmCoding:
            "Coding Plan 仅保证在供应商支持的编码工具中可用；若请求被拒绝，请改用智谱普通 API。"
        case .miniMax:
            "海外 Coding Plan 请选“海外”，填入订阅专用 Key。国内、海外 Key 不通用；模型须在套餐支持范围内。已保存的 Key 会保留，不需要重复填写。"
        case .siliconFlow, .custom:
            ""
        }
    }

    private func profileBinding<Value>(
        _ keyPath: WritableKeyPath<V2AIProviderSettings, Value>
    ) -> Binding<Value> {
        Binding(
            get: { currentProfile[keyPath: keyPath] },
            set: { updateProfile(keyPath, to: $0) }
        )
    }

    private func updateProfile<Value>(
        _ keyPath: WritableKeyPath<V2AIProviderSettings, Value>,
        to value: Value
    ) {
        var profile = currentProfile
        profile[keyPath: keyPath] = value
        profiles[selectedProvider] = profile
    }

    private func thinkingBinding(
        capability: V2AIThinkingCapability
    ) -> Binding<V2AIThinking> {
        Binding(
            get: {
                capability.supports(currentProfile.thinking)
                    ? currentProfile.thinking
                    : capability.options.first ?? .automatic
            },
            set: { updateProfile(\.thinking, to: $0) }
        )
    }

    private func connectSiliconFlow() {
        guard !isLoadingCatalog else { return }
        isEditingField = false
        let settings = currentProfile
        isLoadingCatalog = true
        Task { @MainActor in
            defer { isLoadingCatalog = false }
            do {
                let models = try await store.fetchConfigurationModels(apiKey: settings.apiKey)
                guard currentProfile == settings else { return }
                draftCatalog.applySuccessfulSync(models: models, at: Date())
            } catch {
                errorMessage = Self.message(for: error)
            }
        }
    }

    private func selectModel(_ id: String) -> Bool {
        do {
            try draftCatalog.selectModel(id: id)
            updateProfile(\.model, to: id)
            return true
        } catch {
            errorMessage = Self.message(for: error)
            return false
        }
    }

    private var connectionSection: some View {
        Section {
            Button {
                isEditingField = false
                let settings = currentProfile
                connectionTask?.cancel()
                connectionTask = Task { await connectionTest.run(settings) }
            } label: {
                HStack {
                    if connectionTest.isRunning { ProgressView() }
                    Text(connectionTest.isRunning ? "正在测试…" : "测试连接")
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(!canSaveCurrentProfile || connectionTest.isRunning)
            .accessibilityIdentifier("ai.settings.testConnection")

            if let message = connectionTest.message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(connectionTest.succeeded ? V2Theme.mint : V2Theme.orange)
                    .accessibilityIdentifier("ai.settings.testResult")
            }
            Button("保存配置") {
                guard connectionTest.canSave(currentProfile) else { return }
                var settings = currentProfile
                settings.isEnabled = true
                saveAndDismiss(settings)
            }
            .frame(maxWidth: .infinity)
            .disabled(!connectionTest.canSave(currentProfile))
            .accessibilityIdentifier("ai.settings.usePreset")
        } footer: {
            Text("测试仅发送一条独立测试消息，不包含你的聊天或记录，可能消耗少量服务额度。通过后再保存；修改配置需要重新测试。")
        }
    }

    private func saveAndDismiss(_ settings: V2AIProviderSettings) {
        do {
            try store.updatePlanningSettings(settings)
            if settings.provider == .siliconFlow { try store.saveConfigurationCatalog(draftCatalog) }
            profiles[settings.provider] = store.aiProviderSettings
            dismiss()
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    private func disconnect() {
        do {
            let provider = store.aiProviderSettings.provider
            try store.disconnectAIService()
            profiles[provider] = store.aiProviderSettings
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    errorMessage = nil
                }
            }
        )
    }

    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

private struct V2AIModelSelectionView: View {
    let models: [V2AIModel]
    let selectedModelID: String?
    let onSelect: (String) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    var body: some View {
        List(filteredModels, id: \.id) { model in
            Button {
                if onSelect(model.id) {
                    dismiss()
                }
            } label: {
                HStack(spacing: 12) {
                    Text(model.id)
                        .foregroundStyle(V2Theme.ink)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 12)
                    if model.id == selectedModelID {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(V2Theme.blue)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.id)
            .accessibilityIdentifier("ai.settings.modelOption.\(model.id)")
        }
        .navigationTitle("选择模型")
        .v2InlineNavigationTitle()
        .searchable(text: $searchText, prompt: "搜索模型")
    }

    private var filteredModels: [V2AIModel] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return models }
        return models.filter { $0.id.localizedCaseInsensitiveContains(query) }
    }
}

private struct V2AIModelManagementView: View {
    @Binding var catalog: V2AIModelCatalogState
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                ForEach(catalog.models, id: \.id) { model in
                    Toggle(
                        model.id,
                        isOn: Binding(
                            get: { !catalog.hiddenModelIDs.contains(model.id) },
                            set: { isVisible in
                                do {
                                    try catalog.setModelHidden(id: model.id, isHidden: !isVisible)
                                } catch {
                                    errorMessage = (error as? LocalizedError)?.errorDescription
                                        ?? error.localizedDescription
                                }
                            }
                        )
                    )
                    .disabled(model.id == catalog.selectedModelID)
                    .accessibilityIdentifier("ai.model.visible.\(model.id)")
                }
            } footer: {
                Text("当前使用的模型不能隐藏。")
            }
        }
        .navigationTitle("管理模型")
        .v2InlineNavigationTitle()
        .alert("模型没有更新", isPresented: errorBinding) {
            Button("知道了") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "请稍后再试。")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    errorMessage = nil
                }
            }
        )
    }
}

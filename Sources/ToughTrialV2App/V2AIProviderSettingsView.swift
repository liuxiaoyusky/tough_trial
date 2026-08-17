import SwiftUI

struct V2AIProviderSettingsView: View {
    @ObservedObject var store: V2AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedProvider: V2AIProviderPreset
    @State private var profiles: [V2AIProviderPreset: V2AIProviderSettings]
    @State private var errorMessage: String?

    init(store: V2AppStore) {
        self.store = store
        let activeSettings = store.aiProviderSettings
        var loadedProfiles = Dictionary(
            uniqueKeysWithValues: V2AIProviderPreset.allCases.map {
                ($0, store.aiProviderProfile(for: $0))
            }
        )
        loadedProfiles[activeSettings.provider] = activeSettings
        _selectedProvider = State(initialValue: activeSettings.provider)
        _profiles = State(initialValue: loadedProfiles)
    }

    var body: some View {
        NavigationStack {
            Form {
                providerSection

                switch selectedProvider {
                case .siliconFlow:
                    siliconFlowSection
                    if hasLoadedSiliconFlowModels {
                        modelSection
                    }
                case .kimiCoding, .glmCoding:
                    codingPlanSection
                case .custom:
                    customProviderSection
                }
            }
            .navigationTitle("AI 服务")
            .navigationBarTitleDisplayMode(.inline)
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
        .presentationDetents([.medium, .large])
    }

    private var providerSection: some View {
        Section {
            Menu {
                ForEach(V2AIProviderPreset.allCases) { provider in
                    Button {
                        selectedProvider = provider
                    } label: {
                        if provider == selectedProvider {
                            Label(provider.title, systemImage: "checkmark")
                        } else {
                            Text(provider.title)
                        }
                    }
                }
            } label: {
                HStack {
                    Text("AI 服务")
                    Spacer()
                    Text(selectedProvider.title)
                        .foregroundStyle(V2Theme.secondary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(V2Theme.tertiary)
                }
            }
            .accessibilityLabel("AI 服务 \(selectedProvider.title)")
            .accessibilityIdentifier("ai.settings.provider")

            if store.hasConnectedAIService {
                Label(
                    "正在使用 \(store.aiProviderSettings.provider.title)",
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
                    Text("已连接 · \(store.aiModelCatalog.models.count) 个聊天模型")
                        .accessibilityIdentifier("ai.settings.connected")
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(V2Theme.mint)
                }
            } else if hasLoadedSiliconFlowModels {
                Label {
                    Text("已读取 \(store.aiModelCatalog.models.count) 个模型，请选择模型")
                        .accessibilityIdentifier("ai.settings.catalogLoaded")
                } icon: {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(V2Theme.blue)
                }
            }

            SecureField("粘贴 API Key", text: profileBinding(\.apiKey))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("ai.settings.apiKey")

            Button {
                connectSiliconFlow()
            } label: {
                HStack(spacing: 8) {
                    if store.isRefreshingAIModels {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(hasLoadedSiliconFlowModels ? "重新连接并更新模型" : "连接并更新模型")
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(store.isRefreshingAIModels || !hasAPIKey)
            .accessibilityIdentifier("ai.settings.connect")
        } header: {
            Text("SiliconFlow")
        } footer: {
            Text("连接时会验证 Key 并读取可用模型。规划内容只在你发送请求时交给所选服务。")
        }
    }

    private var codingPlanSection: some View {
        Section {
            SecureField("粘贴 API Key", text: profileBinding(\.apiKey))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
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

            Button("使用此服务") {
                saveCodingPlanProvider()
            }
            .frame(maxWidth: .infinity)
            .disabled(!canSaveCurrentProfile)
            .accessibilityIdentifier("ai.settings.usePreset")

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
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .accessibilityIdentifier("ai.settings.baseURL")

            TextField("模型名称", text: profileBinding(\.model))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("ai.settings.model")

            SecureField("粘贴 API Key", text: profileBinding(\.apiKey))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("ai.settings.apiKey")

            Button("使用此服务") {
                saveCustomProvider()
            }
            .frame(maxWidth: .infinity)
            .disabled(!canSaveCurrentProfile)

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

    private var modelSection: some View {
        Section {
            Menu {
                ForEach(store.aiModelCatalog.visibleModels, id: \.id) { model in
                    Button {
                        selectModel(model.id)
                    } label: {
                        if model.id == siliconFlowSelectedModelID {
                            Label(model.id, systemImage: "checkmark")
                        } else {
                            Text(model.id)
                        }
                    }
                    .accessibilityLabel(model.id)
                }
            } label: {
                HStack {
                    Text("当前模型")
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

            if store.aiModelCatalog.selectedModelID != nil,
               !store.aiModelCatalog.isSelectedModelAvailable {
                Label("原模型已不可用，请手动选择新模型", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(V2Theme.orange)
            }

            NavigationLink {
                V2AIModelManagementView(store: store)
            } label: {
                Label("管理模型", systemImage: "slider.horizontal.3")
            }
            .accessibilityIdentifier("ai.settings.manageModels")

            Button("更新模型列表") {
                connectSiliconFlow()
            }
            .disabled(store.isRefreshingAIModels)

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
    }

    private var hasLoadedSiliconFlowModels: Bool {
        hasAPIKey
            && store.aiModelCatalog.lastSuccessfulSyncAt != nil
            && !store.aiModelCatalog.models.isEmpty
    }

    private var siliconFlowSelectedModelID: String? {
        store.aiModelCatalog.isSelectedModelAvailable
            ? store.aiModelCatalog.selectedModelID
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

    private func connectSiliconFlow() {
        Task { @MainActor in
            do {
                try await store.connectSiliconFlow(apiKey: currentProfile.apiKey)
                profiles[.siliconFlow] = store.aiProviderSettings
            } catch {
                errorMessage = Self.message(for: error)
            }
        }
    }

    private func selectModel(_ id: String) {
        do {
            try store.selectAIModel(id: id)
            profiles[.siliconFlow] = store.aiProviderSettings
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    private func saveCodingPlanProvider() {
        var settings = currentProfile
        settings.provider = selectedProvider
        settings.baseURL = selectedProvider.baseURL
        settings.isEnabled = true
        saveAndDismiss(settings)
    }

    private func saveCustomProvider() {
        var settings = currentProfile
        settings.provider = .custom
        settings.isEnabled = true
        saveAndDismiss(settings)
    }

    private func saveAndDismiss(_ settings: V2AIProviderSettings) {
        do {
            try store.updatePlanningSettings(settings)
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

private struct V2AIModelManagementView: View {
    @ObservedObject var store: V2AppStore
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                ForEach(store.aiModelCatalog.models, id: \.id) { model in
                    Toggle(
                        model.id,
                        isOn: Binding(
                            get: { !store.aiModelCatalog.hiddenModelIDs.contains(model.id) },
                            set: { isVisible in
                                do {
                                    try store.setAIModelVisible(
                                        id: model.id,
                                        isVisible: isVisible
                                    )
                                } catch {
                                    errorMessage = (error as? LocalizedError)?.errorDescription
                                        ?? error.localizedDescription
                                }
                            }
                        )
                    )
                    .disabled(model.id == store.aiModelCatalog.selectedModelID)
                    .accessibilityIdentifier("ai.model.visible.\(model.id)")
                }
            } footer: {
                Text("当前使用的模型不能隐藏。")
            }
        }
        .navigationTitle("管理模型")
        .navigationBarTitleDisplayMode(.inline)
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

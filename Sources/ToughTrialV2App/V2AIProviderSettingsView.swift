import SwiftUI

struct V2AIProviderSettingsView: View {
    @ObservedObject var store: V2AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey: String
    @State private var customBaseURL: String
    @State private var customModel: String
    @State private var showsCustomProvider = false
    @State private var errorMessage: String?

    init(store: V2AppStore) {
        self.store = store
        let settings = store.aiProviderSettings
        _apiKey = State(initialValue: settings.apiKey)
        _customBaseURL = State(initialValue: settings.baseURL)
        _customModel = State(initialValue: settings.model)
    }

    var body: some View {
        NavigationStack {
            Form {
                siliconFlowSection

            if isSiliconFlowConnected {
                modelSection
            }

                Section {
                    DisclosureGroup(
                        "其他 OpenAI 兼容服务",
                        isExpanded: $showsCustomProvider
                    ) {
                        TextField("服务地址", text: $customBaseURL)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("ai.settings.baseURL")

                        TextField("模型名称", text: $customModel)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("ai.settings.model")

                        SecureField("API Key", text: $apiKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        Button("使用此服务") {
                            saveCustomProvider()
                        }
                        .disabled(!canSaveCustomProvider)
                    }
                } footer: {
                    Text("适用于提供 /v1/chat/completions 的兼容服务。")
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

    private var siliconFlowSection: some View {
        Section {
            if isSiliconFlowConnected {
                Label {
                    Text("已连接 · \(store.aiModelCatalog.models.count) 个聊天模型")
                        .accessibilityIdentifier("ai.settings.connected")
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(V2Theme.mint)
                }
            }

            SecureField("粘贴 API Key", text: $apiKey)
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
                    Text(isSiliconFlowConnected ? "重新连接并更新模型" : "连接并更新模型")
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(
                store.isRefreshingAIModels
                    || apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
            .accessibilityIdentifier("ai.settings.connect")
        } header: {
            Text("SiliconFlow")
        } footer: {
            Text("连接时会验证 Key 并读取可用模型。规划内容只在你发送请求时交给所选服务。")
        }
    }

    private var modelSection: some View {
        Section {
            Menu {
                ForEach(store.visibleAIModels, id: \.id) { model in
                    Button {
                        selectModel(model.id)
                    } label: {
                        if model.id == store.selectedAIModelID {
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
                    Text(store.selectedAIModelID ?? "选择模型")
                        .foregroundStyle(V2Theme.secondary)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(V2Theme.tertiary)
                }
            }
            .accessibilityLabel("当前模型 \(store.selectedAIModelID ?? "未选择")")
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
                refreshModels()
            }
            .disabled(store.isRefreshingAIModels)

            Button("移除 API Key", role: .destructive) {
                disconnect()
            }
        } header: {
            Text("模型")
        } footer: {
            Text("新发现的模型默认显示；只有你手动隐藏的模型会继续隐藏。")
        }
    }

    private var canSaveCustomProvider: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !customBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !customModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isSiliconFlowConnected: Bool {
        store.hasConnectedAIService && store.isUsingSiliconFlow
    }

    private func connectSiliconFlow() {
        Task { @MainActor in
            do {
                try await store.connectSiliconFlow(apiKey: apiKey)
                apiKey = store.aiProviderSettings.apiKey
            } catch {
                errorMessage = Self.message(for: error)
            }
        }
    }

    private func refreshModels() {
        Task { @MainActor in
            do {
                try await store.refreshSiliconFlowModels()
            } catch {
                errorMessage = Self.message(for: error)
            }
        }
    }

    private func selectModel(_ id: String) {
        do {
            try store.selectAIModel(id: id)
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    private func saveCustomProvider() {
        do {
            try store.updatePlanningSettings(
                V2AIProviderSettings(
                    isEnabled: true,
                    baseURL: customBaseURL,
                    model: customModel,
                    apiKey: apiKey
                )
            )
            dismiss()
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    private func disconnect() {
        do {
            try store.disconnectAIService()
            apiKey = ""
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

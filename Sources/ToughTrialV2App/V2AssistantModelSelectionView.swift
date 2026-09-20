import SwiftUI
import ToughTrialV2Core

struct V2AssistantModelSelectionView: View {
    @ObservedObject var store: V2AssistantStore
    @ObservedObject var appStore: V2AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var provider: V2AIProviderPreset
    @State private var model: String
    @State private var thinking: V2AIThinking
    @State private var useAsDefault = false
    @State private var error: String?
    @State private var showServices = false
    private let sessionID: String?

    init(store: V2AssistantStore, appStore: V2AppStore) {
        self.store = store; self.appStore = appStore
        sessionID = store.selectedSession?.id
        let selection = store.selectedSession?.modelSelection
        let settings = appStore.aiProviderSettings
        _provider = State(initialValue: selection.flatMap { V2AIProviderPreset(rawValue: $0.providerID) } ?? settings.provider)
        _model = State(initialValue: selection?.model ?? settings.model)
        _thinking = State(initialValue: selection?.thinking ?? settings.thinking)
    }

    private var settings: V2AIProviderSettings {
        var profile = appStore.aiProviderProfile(for: provider)
        profile.model = model; profile.thinking = thinking; profile.isEnabled = true
        return profile
    }
    private var models: [String] {
        var values = provider.models
        if provider == .siliconFlow { values = appStore.aiModelCatalog.visibleModels.map(\.id) }
        if !model.isEmpty && !values.contains(model) { values.insert(model, at: 0) }
        return values
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("本次会话") {
                    Picker("服务 / Coding Plan", selection: $provider) {
                        ForEach(V2AIProviderPreset.allCases) { Text($0.title).tag($0) }
                    }.accessibilityIdentifier("assistant.model.provider")
                    if provider == .custom {
                        TextField("模型 ID", text: $model).v2Autocapitalization(.never).autocorrectionDisabled()
                    } else {
                        Picker("模型", selection: $model) { ForEach(models, id: \.self) { Text($0).tag($0) } }
                            .accessibilityIdentifier("assistant.model.type")
                    }
                    Picker("思考", selection: $thinking) {
                        ForEach(settings.thinkingCapability.options, id: \.self) { Text($0.title).tag($0) }
                    }.accessibilityIdentifier("assistant.model.thinking")
                    Text(settings.thinkingCapability.note).font(.caption).foregroundStyle(.secondary)
                    Text("切换从下一条消息生效；正在进行的回复继续使用原设置。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Toggle("同时用于新会话", isOn: $useAsDefault)
                    Button("恢复默认设置") {
                        if let sessionID, store.selectModel(nil, in: sessionID) { dismiss() }
                    }
                    Button("配置服务与密钥") { showServices = true }
                }
                if settings.apiKey.isEmpty { Text("请先配置这个服务，再用于对话。").foregroundStyle(.orange) }
                if let error { Text(error).foregroundStyle(.orange) }
            }
            .navigationTitle("模型设置")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("应用") {
                        do {
                            _ = try settings.agentConfiguration()
                            guard let sessionID else { return }
                            if useAsDefault { try appStore.updatePlanningSettings(settings) }
                            guard store.selectModel(.init(providerID: provider.rawValue, model: model, thinking: thinking), in: sessionID) else {
                                error = store.storageIssueMessage; return
                            }
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }.disabled(settings.apiKey.isEmpty || model.isEmpty)
                }
            }
            .onChange(of: provider) { _, value in
                let profile = appStore.aiProviderProfile(for: value)
                model = profile.model; thinking = profile.thinking
                normalizeThinking()
            }
            .onChange(of: model) { _, _ in normalizeThinking() }
            .v2Sheet(isPresented: $showServices) { V2AIProviderSettingsView(store: appStore) }
        }
    }

    private func normalizeThinking() {
        if !settings.thinkingCapability.supports(thinking) { thinking = .automatic }
    }
}

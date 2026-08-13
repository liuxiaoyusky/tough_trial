import SwiftUI

struct V2AIProviderSettingsView: View {
    @ObservedObject var store: V2AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var settings: V2AIProviderSettings
    @State private var errorMessage: String?

    init(store: V2AppStore) {
        self.store = store
        _settings = State(initialValue: V2AIProviderSettingsStore.load())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("使用在线规划", isOn: $settings.isEnabled)
                        .accessibilityIdentifier("ai.settings.enabled")
                } footer: {
                    Text("关闭后使用本地基础规划。")
                }

                if settings.isEnabled {
                    Section {
                        TextField("服务地址", text: $settings.baseURL)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("ai.settings.baseURL")

                        TextField("模型名称", text: $settings.model)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("ai.settings.model")

                        SecureField("API Key", text: $settings.apiKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("ai.settings.apiKey")
                    } header: {
                        Text("OpenAI 兼容服务")
                    } footer: {
                        Text("已预填硅基流动地址。也可以填写其他兼容 /v1/chat/completions 的服务；API Key 只保存在本机 Keychain。规划时，输入、相关任务和已启用记忆会发送给该服务。")
                    }
                }
            }
            .navigationTitle("AI 服务")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        do {
                            try store.updatePlanningSettings(settings)
                            dismiss()
                        } catch {
                            errorMessage = (error as? LocalizedError)?.errorDescription
                                ?? error.localizedDescription
                        }
                    }
                    .disabled(!canSave)
                }
            }
            .alert("无法保存", isPresented: errorBinding) {
                Button("知道了") {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "请检查设置。")
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var canSave: Bool {
        guard settings.isEnabled else { return true }
        return !settings.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !settings.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

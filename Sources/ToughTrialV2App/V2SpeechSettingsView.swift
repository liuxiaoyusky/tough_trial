import SwiftUI

enum V2SpeechProvider: String, CaseIterable {
    case funASR, apple
    var title: String { self == .apple ? "苹果原生" : "阿里云 FunASR" }
}

// Separate credential: changing the chat model must not change speech recognition.
enum V2SpeechSettings {
    static let providerKey = "speech.recognition.provider"
    static var provider: V2SpeechProvider {
        V2SpeechProvider(rawValue: UserDefaults.standard.string(forKey: providerKey) ?? "") ?? .funASR
    }
    static let account = "bailian-realtime-speech"
    static func loadKey() throws -> String { try V2AIProviderKeychain.load(account: account) }
    static func saveKey(_ value: String) throws { try V2AIProviderKeychain.save(value, account: account) }
}

struct V2SpeechSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(V2SpeechSettings.providerKey) private var provider = V2SpeechProvider.funASR
    @State private var preparation: Task<Void, Never>?
    @State private var modelStatus = ""
    @State private var isPreparing = false
    @State private var apiKey = ""
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("识别方式") {
                Picker("语音识别", selection: $provider) {
                    ForEach(V2SpeechProvider.allCases, id: \.self) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("speech.settings.provider")
            }
            if provider == .apple {
                Section {
                    Text("边说边显示文字。任务中完成后可编辑保存；助手中完成后交给 AI。")
                    Button(isPreparing ? "正在准备中文模型…" : "准备中文模型") { prepareApple() }
                        .disabled(isPreparing)
                        .accessibilityIdentifier("speech.settings.prepareApple")
                    if !modelStatus.isEmpty { Text(modelStatus).font(.footnote) }
                } header: {
                    Text("苹果原生 · 设备端识别")
                } footer: {
                    Text("需要 iOS 26 / macOS 26 及支持的设备。首次使用可能需要下载中文模型，无需语音 API Key。音频在本机转写。任务表单先回填草稿，由你保存；助手中点完成会将文字提交给当前会话。")
                }
            } else {
                Section {
                    SecureField("粘贴百炼 API Key", text: $apiKey)
                        .v2Autocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("speech.settings.apiKey")
                    Button("保存") { save() }
                        .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("speech.settings.save")
                    Button("移除语音密钥", role: .destructive) {
                        apiKey = ""
                        save()
                    }
                } header: {
                    Text("FunASR · 录完后转写")
                } footer: {
                    Text("使用百炼北京区 API Key，与聊天模型独立。单段最多 5 分钟，点完成后才上传至阿里云转写，按服务用量计费。录音只在当前页面临时保留；离开或放弃后清除。")
                }
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
        }
        .navigationTitle("语音输入")
        .v2InlineNavigationTitle()
        .onDisappear { preparation?.cancel() }
        .onAppear {
            do { apiKey = try V2SpeechSettings.loadKey() }
            catch { errorMessage = "无法读取语音配置，请稍后重试。" }
        }
    }

    private func prepareApple() {
        isPreparing = true
        modelStatus = "正在检查设备与中文模型…"
        preparation = Task {
            defer { isPreparing = false }
            do {
                if #available(iOS 26.0, macOS 26.0, *) {
                    try await V2AppleSpeechBackend.prepareModel { modelStatus = $0 }
                    modelStatus = "中文模型已就绪，可以返回输入框开始听写。"
                } else {
                    modelStatus = "此功能需要 iOS 26 / macOS 26 或更新版本，可选择阿里云 FunASR。"
                }
            } catch is CancellationError { }
            catch { modelStatus = error.localizedDescription }
        }
    }

    private func save() {
        do {
            try V2SpeechSettings.saveKey(apiKey)
            dismiss()
        } catch {
            errorMessage = "语音配置未保存，请稍后重试。"
        }
    }
}

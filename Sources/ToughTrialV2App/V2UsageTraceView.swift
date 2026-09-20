import SwiftUI
import ToughTrialV2Core

@MainActor
final class V2UsageTrace: ObservableObject {
    static let shared = V2UsageTrace()
    @Published private(set) var events: [V2UsageEvent] = []
    @Published private(set) var issue: String?
    @Published var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: "usageTrace.enabled")
            store.isEnabled = isEnabled
        }
    }
    private let store: V2UsageTraceStore
    private let defaults: UserDefaults

    private init() {
        let testing = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.environment["TOUGH_TRIAL_UI_TESTING"] == "1"
            || ProcessInfo.processInfo.environment["TOUGH_TRIAL_UI_TEST_EMPTY"] == "1"
        defaults = testing ? UserDefaults(suiteName: "trace-tests-\(ProcessInfo.processInfo.processIdentifier)")! : .standard
        let enabled = defaults.object(forKey: "usageTrace.enabled") as? Bool ?? true
        isEnabled = enabled
        let directory = testing ? FileManager.default.temporaryDirectory.appendingPathComponent("trace-tests-\(ProcessInfo.processInfo.processIdentifier)")
            : V2PlatformStorage.root
        store = V2UsageTraceStore(fileURL: directory.appendingPathComponent("v2-usage-trace.json"), isEnabled: enabled)
        events = store.events
        if store.hasStorageError { issue = "记录文件无法读取，原文件已保留。可清空记录后重新开始。" }
    }

    func record(_ event: V2UsageEvent) {
        guard V2PluginStore.shared.enabled("trace") else { return }
        do {
            try store.record(event)
            events = store.events
        } catch { issue = "使用记录暂时无法保存，日程操作仍可继续。" }
    }

    func export() -> String? {
        do { return try store.exportJSON() }
        catch { issue = "无法导出使用记录。"; return nil }
    }

    func clear() {
        do { try store.clear(); events = []; issue = nil }
        catch { issue = "无法清空使用记录，请稍后重试。" }
    }
}

struct V2UsageTraceView: View {
    @ObservedObject private var plugins = V2PluginStore.shared
    @ObservedObject private var trace = V2UsageTrace.shared
    @Environment(\.dismiss) private var dismiss
    @State private var exportText: String?
    @State private var confirmsClear = false

    var body: some View {
        Form {
            Section {
                Toggle("记录使用过程", isOn: Binding(get: { plugins.enabled("trace") && trace.isEnabled }, set: { plugins.setEnabled("trace", $0) }))
                    .accessibilityIdentifier("trace.enabled")
                Text("仅保存在本机，保留最近 30 天、最多 2000 条。记录操作、耗时和字数，不保存输入正文、录音或密钥。")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("已保存 \(trace.events.count) 条")
                    .accessibilityIdentifier("trace.count")
            }
            if let issue = trace.issue { Section { Text(issue).foregroundStyle(.orange) } }
            Section {
                Button("预览导出内容") { exportText = trace.export() }
                    .accessibilityIdentifier("trace.export")
                Button("清空记录", role: .destructive) { confirmsClear = true }
                    .accessibilityIdentifier("trace.clear")
            }
            Section("最近记录") {
                ForEach(trace.events.suffix(50).reversed()) { event in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.kind.label)
                        HStack {
                            Text(event.at, style: .time)
                            if let duration = event.duration { Text(String(format: "%.2f 秒", duration)) }
                            if let count = event.characterCount { Text("\(count) 字") }
                        }.font(.caption).foregroundStyle(.secondary)
                        if let context = event.context {
                            Text("\(context.requestKind) · \(context.referenceState == .available ? "已携带引用" : context.referenceState == .missing ? "引用不可用" : "无引用") · \(context.memoryIDs.count) 条记忆 · 摘要 \(context.compactRevision.map(String.init) ?? "无")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("使用记录")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } }
        .confirmationDialog("清空本机使用记录？", isPresented: $confirmsClear, titleVisibility: .visible) {
            Button("清空记录", role: .destructive) { trace.clear(); exportText = nil }
                .accessibilityIdentifier("trace.confirmClear")
        }
        .v2Sheet(isPresented: Binding(get: { exportText != nil }, set: { if !$0 { exportText = nil } })) {
            NavigationStack {
                ScrollView {
                    Text(exportText ?? "").font(.caption.monospaced()).textSelection(.enabled).padding()
                        .accessibilityIdentifier("trace.export.json")
                }
                    .navigationTitle("导出预览")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("关闭") { exportText = nil } }
                        ToolbarItem(placement: .primaryAction) {
                            if let exportText { ShareLink("分享", item: exportText) }
                        }
                    }
            }
        }
    }
}

private extension V2UsageEvent.Kind {
    var label: String {
        switch self {
        case .contextPrepared: "请求上下文已准备"
        case .moduleChanged: "功能状态变更"
        case .jobFinished: "后续处理完成"
        case .jobDeferred: "后续处理待重试"
        case .commandProposed: "操作等待确认"
        case .commandUndone: "操作已撤销"
        case .commandApplied: "操作已保存"
        case .commandBlocked: "操作被阻止"
        case .migrationFinished: "数据格式已升级"
        case .inputSubmitted: "提交输入"
        case .speechStarted: "开始语音输入"
        case .speechFinished: "语音定稿"
        case .speechCancelled: "取消语音输入"
        case .speechFailed: "语音输入失败"
        case .transcriptEdited: "修正转写"
        case .assistantFinished: "助手完成"
        case .assistantFailed: "助手失败"
        case .assistantCancelled: "取消助手请求"
        case .scheduleProposed: "生成日程修改"
        case .scheduleApplied: "执行日程修改"
        case .scheduleConfirmed: "确认日程修改"
        case .scheduleUndone: "撤销日程修改"
        case .manualEdit: "手动调整"
        case .syncFinished: "同步完成"
        case .syncFailed: "同步失败"
        case .conflictResolved: "解决同步冲突"
        case .financeChanged: "理账计划已修改"
        case .financeFailed: "理账计划修改失败"
        case .importRecognized: "导入识别完成"
        case .importRecognitionFailed: "导入识别失败"
        case .captureStage: "随手记整理"
        case .categoryMerged: "合并账单分类"
        case .categoryUndone: "撤销分类调整"
        }
    }
}

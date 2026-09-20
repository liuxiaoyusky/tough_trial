import SwiftUI
import ToughTrialV2Core

struct V2AssistantContextView: View {
    @ObservedObject var store: V2AssistantStore
    @ObservedObject var appStore: V2AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var context = V2AssistantContext()
    @State private var compaction: V2AssistantCompaction?
    @State private var messages: [V2ArchiveMessage] = []
    @State private var query = ""
    @State private var message: String?
    @State private var showMemory = false
    @State private var showTrace = false

    var body: some View {
        Form {
            Section("当前引用") {
                if let source = context.sourceTask {
                    Label(source.title, systemImage: "link")
                    Text("任务 ID：\(source.id)").font(.caption).textSelection(.enabled)
                    Text(context.referenceState == .available ? "会随每次聊天和任务整理请求一起发送。" : "引用暂不可用，请重新选择任务。")
                        .font(.caption).foregroundStyle(.secondary)
                } else { Text("当前会话没有引用任务").foregroundStyle(.secondary) }
                if let quotedMessages = context.quotedMessages, !quotedMessages.isEmpty {
                    Text("本轮消息引用 \(quotedMessages.count) 条原文，按消息 ID 独立传入。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let attachmentSources = context.attachmentSources, !attachmentSources.isEmpty {
                    Text("本轮附件 \(attachmentSources.count) 个，按原件引用传入。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("长期记忆") {
                Text("本会话可参考 \(context.memories.count) 条记忆。摘要不会自动变成长期记忆。")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(context.memories.prefix(6)) { memory in Text(memory.statement) }
                Button("管理长期记忆") { showMemory = true }
                    .disabled(!V2PluginStore.shared.enabled("notes"))
            }
            Section("上下文整理") {
                Text("以下比较实际发送的会话正文与摘要；不包含本轮输入、工具结果及固定上下文。token 为估算值。")
                    .font(.caption).foregroundStyle(.secondary)
                if let compaction {
                    if compaction.didReduce {
                        Text("已压缩 · 版本 \(compaction.revision)")
                        Text("有效字符 \(compaction.metrics.beforeCharacterCount) → \(compaction.metrics.afterCharacterCount)")
                        Text("估算 token \(compaction.metrics.beforeTokenEstimate) → \(compaction.metrics.afterTokenEstimate)（本地估算）")
                        Text("覆盖 \(compaction.metrics.coveredMessageCount) 条，保留近期 \(compaction.metrics.retainedMessageCount) 条；原文仍保留。")
                            .font(.caption).foregroundStyle(.secondary)
                        if !compaction.preservedReferenceIDs.isEmpty {
                            Text("保留引用 ID：\(compaction.preservedReferenceIDs.joined(separator: ", "))")
                                .font(.caption).textSelection(.enabled)
                        }
                    } else {
                        Text("本次无需整理")
                        Text(compaction.noBenefitMessage ?? "没有减少有效上下文，继续使用原文。")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("当前有效字符 \(compaction.metrics.beforeCharacterCount)，估算 token \(compaction.metrics.beforeTokenEstimate)（本地估算）")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Text("正在使用会话原文")
                }
                Text("长会话会自动整理旧消息。原始记录继续保留，AI 可按需回看；当前引用与近期消息不会被摘要替代。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("压缩旧消息（Compact）") {
                    if let result = store.compactSelectedSessionResult() {
                        compaction = result
                        message = result.didReduce
                            ? "已减少有效上下文，原文仍保留。"
                            : (result.noBenefitMessage ?? "本次没有减少有效上下文，继续使用原文。")
                    }
                    reload()
                }.disabled(store.isRunningTurn).accessibilityIdentifier("assistant.context.compact")
                if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
                if let summary = compaction?.summary, !summary.isEmpty {
                    DisclosureGroup("查看摘要及来源") { Text(summary).font(.caption).textSelection(.enabled) }
                }
            }
            Section("原始会话") {
                TextField("搜索本会话原文", text: $query).onSubmit(reload)
                    .accessibilityIdentifier("assistant.context.search")
                ForEach(messages, id: \.id) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(describing: item.role) == "user" ? "你" : "助手").font(.caption).foregroundStyle(.secondary)
                        Text(item.text).font(.callout).textSelection(.enabled)
                    }
                }
                if messages.isEmpty { Text("没有匹配的消息").foregroundStyle(.secondary) }
            }
            Section {
                Button("查看 Trace 使用记录") { showTrace = true }
                    .disabled(!V2PluginStore.shared.enabled("trace"))
                if let issue = store.contextIssueMessage { Text(issue).foregroundStyle(.orange) }

            }
        }
        .navigationTitle("记忆与上下文")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        .onAppear(perform: reload)
        .v2Sheet(isPresented: $showMemory, onDismiss: reload) { V2MemorySheet(store: appStore) }
        .v2Sheet(isPresented: $showTrace) { NavigationStack { V2UsageTraceView() } }
    }

    private func reload() {
        guard let session = store.selectedSession else { return }
        store.syncContextArchive()
        context = store.requestContext(for: session, at: Date())
        // requestContext may create or refresh a useful compaction for a long
        // session; read it after that bounded projection has been evaluated so
        // the diagnostics view reflects the effective context actually sent.
        compaction = try? store.contextArchive.loadCompaction(sessionID: session.id)
        do { messages = try store.contextArchive.readSession(id: session.id, query: query, limit: 20) }
        catch { message = "原文读取暂不可用；会话文件已保留。" }
    }
}

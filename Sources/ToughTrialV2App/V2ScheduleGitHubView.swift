import SwiftUI
import ToughTrialV2Core

struct V2ScheduleGitHubView: View {
    @ObservedObject var store: V2AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var repository = ""
    @State private var branch = "main"
    @State private var path = "schedule.md"
    @State private var credential = ""
    @State private var didLoad = false
    @State private var conflictGuidance = ""
    @State private var configurationError: String?

    private var github: V2ScheduleGitHubState? { store.engine.snapshot.scheduleDocumentState?.github }
    private var pending: Bool {
        guard let state = store.engine.snapshot.scheduleDocumentState, let github = state.github else { return false }
        return github.requiresRetry || github.baseline != store.engine.snapshot.scheduleDocument(using: state.document)
    }
    private var configurationMatches: Bool {
        guard let location = github?.location else { return false }
        return repository == "\(location.owner)/\(location.repository)" && branch == location.branch && path == location.path && credential.isEmpty
    }

    var body: some View {
        Form {
            Section("同步到 GitHub") {
                TextField("仓库：owner/repository", text: $repository)
                    .accessibilityIdentifier("schedule.github.repository")
                TextField("分支", text: $branch)
                    .accessibilityIdentifier("schedule.github.branch")
                TextField("日程文件路径", text: $path)
                    .accessibilityIdentifier("schedule.github.path")
                SecureField(github == nil ? "GitHub 访问凭据" : "更换凭据（留空保留）", text: $credential)
                    .accessibilityIdentifier("schedule.github.credential")
                Button("保存配置", action: save)
                    .accessibilityIdentifier("schedule.github.save")
            }
            .v2Autocapitalization(.never)
            .autocorrectionDisabled()
            Section {
                if github != nil {
                    Toggle("使用 App 时自动同步", isOn: Binding(
                        get: { github?.automaticSyncEnabled != false },
                        set: { store.setScheduleAutomaticSync($0) }
                    ))
                    .accessibilityIdentifier("schedule.github.automatic")
                    Label(pending ? "有内容待同步" : "已同步", systemImage: pending ? "arrow.triangle.2.circlepath" : "checkmark.icloud")
                    if let date = github?.lastSyncedAt {
                        Text("最近同步：\(date.formatted(date: .abbreviated, time: .shortened))")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Button("立即同步") { Task { await store.synchronizeConfiguredSchedule() } }
                        .disabled(!configurationMatches)
                        .accessibilityIdentifier("schedule.github.sync")
                    if github?.lastFailure != nil {
                        Text("上次同步未完成，本地修改已保留。检查网络与凭据后可以重试。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if store.isScheduleSyncing { ProgressView("正在同步…") }
                if let message = store.scheduleSyncMessage { Text(message).accessibilityIdentifier("schedule.github.status") }
                if let error = configurationError ?? store.scheduleSyncError {
                    Text(error).foregroundStyle(.red).accessibilityIdentifier("schedule.github.error")
                }
            } footer: {
                Text("请选择用于个人日程的私有仓库。凭据需要该仓库的 Contents 读写权限，只保存在本机钥匙串。首次点击同步后，可在使用 App 时自动同步；离线时继续编辑，恢复连接后重试。应用退到后台时暂停自动同步。")
            }
            if let pending = store.pendingScheduleConflict {
                V2ScheduleConflictPreview(store: store, pending: pending)
            }
            if let versions = store.engine.snapshot.scheduleDocumentState?.versions,
               let latest = versions.last(where: { $0.source == .conflictResolution }),
               !versions.contains(where: { $0.restoredVersionID == latest.id }) {
                Section {
                    Text("AI 已应用冲突处理，相关任务已高亮。")
                    Button("撤销本次处理") { store.undoScheduleConflict(id: latest.id) }
                        .accessibilityIdentifier("schedule.github.conflict.undo")
                }
            }
            if let conflict = github?.conflict {
                Section("需要处理的内容") {
                    Button("让 AI 处理") { Task { await store.resolveConfiguredScheduleConflict() } }
                        .accessibilityIdentifier("schedule.github.conflict.resolve")
                    TextField("补充你的处理要求", text: $conflictGuidance, axis: .vertical)
                        .accessibilityIdentifier("schedule.github.conflict.guidance")
                    Button("按我的要求处理") {
                        let guidance = conflictGuidance
                        Task { await store.resolveConfiguredScheduleConflict(guidance: guidance) }
                    }
                    .disabled(conflictGuidance.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("schedule.github.conflict.answer")
                    ForEach(conflict.conflicts) { item in
                        DisclosureGroup(conflictTitle(item, in: conflict)) {
                            Text("本地：\(display(item.local))")
                            Text("远端：\(display(item.remote))")
                        }
                    }
                }
            }
        }
        .disabled(store.isScheduleSyncing || !store.canWrite)
        .navigationTitle("GitHub 同步")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            if let location = github?.location {
                repository = "\(location.owner)/\(location.repository)"
                branch = location.branch
                path = location.path
            }
        }
    }

    private func save() {
        do {
            let parts = repository.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "/", omittingEmptySubsequences: false)
            guard parts.count == 2 else { throw V2GitHubScheduleError.invalidLocation }
            let location = V2GitHubScheduleLocation(owner: String(parts[0]), repository: String(parts[1]),
                branch: branch.trimmingCharacters(in: .whitespacesAndNewlines), path: path.trimmingCharacters(in: .whitespacesAndNewlines))
            try store.configureScheduleSync(location: location, newCredential: credential)
            repository = "\(location.owner)/\(location.repository)"; branch = location.branch; path = location.path
            credential = ""
            configurationError = nil
        } catch { configurationError = error.localizedDescription }
    }

    private func conflictTitle(_ item: V2ScheduleConflict, in conflict: V2ScheduleSyncConflict) -> String {
        let title = conflict.local.tasks.first { $0.id == item.objectID }?.title
            ?? conflict.remote.tasks.first { $0.id == item.objectID }?.title ?? "日程内容"
        let field = ["title": "标题", "note": "备注", "startAt": "开始时间", "endAt": "结束时间", "date": "日期", "status": "状态"][item.field] ?? "内容"
        return "\(title) · \(field)"
    }

    private func display(_ value: V2SchedulePrimitive) -> String {
        switch value {
        case .null: "未设置"
        case let .string(text): text
        case let .number(number): String(number)
        case let .boolean(flag): flag ? "是" : "否"
        }
    }
}

extension V2AppStore {
    static func githubCredentialAccount(_ location: V2GitHubScheduleLocation) -> String {
        "github-schedule.\(location.owner.lowercased())/\(location.repository.lowercased())"
    }

    func configureScheduleSync(location: V2GitHubScheduleLocation, newCredential: String) throws {
        guard canWrite else { throw V2ScheduleDocumentError.stale }
        let account = Self.githubCredentialAccount(location)
        let token = newCredential.isEmpty ? try V2AIProviderKeychain.load(account: account) : newCredential
        _ = try V2GitHubScheduleClient(location: location, token: token).makeReadRequest()
        _ = try engine.prepareScheduleDocument(timeZoneIdentifier: calendar.timeZone.identifier)
        if !newCredential.isEmpty { try V2AIProviderKeychain.save(newCredential, account: account) }
        try engine.configureScheduleGitHub(location)
        scheduleSyncError = nil
        scheduleSyncMessage = "配置已保存，点击同步后连接该仓库。"
        refreshProjection(at: Date())
    }

    func synchronizeConfiguredSchedule(automaticallyResolve: Bool = true) async {
        guard V2PluginStore.shared.enabled("sync") else { scheduleSyncError = "请先在功能与插件中开启日程同步。"; return }
        guard !isScheduleSyncing, let location = engine.snapshot.scheduleDocumentState?.github?.location else { return }
        do {
            let ticket = try V2PluginStore.shared.ticket(["sync"])
            let token = try V2AIProviderKeychain.load(account: Self.githubCredentialAccount(location))
            await synchronizeSchedule(using: V2GitHubScheduleClient(location: location, token: token))
            try V2PluginStore.shared.validate(ticket)
            if automaticallyResolve, engine.snapshot.scheduleDocumentState?.github?.conflict != nil,
               pendingScheduleConflict == nil {
                await resolveConfiguredScheduleConflict()
            }
        } catch { scheduleSyncError = "无法读取 GitHub 凭据，请重新保存授权。" }
    }

    func synchronizeSchedule<Transport: V2PlanningHTTPTransport>(using client: V2GitHubScheduleClient<Transport>) async {
        guard V2PluginStore.shared.enabled("sync") else { scheduleSyncError = "请先在功能与插件中开启日程同步。"; return }
        guard !isScheduleSyncing, canWrite else { return }
        guard let ticket = try? V2PluginStore.shared.ticket(["sync"]) else { return }
        isScheduleSyncing = true
        scheduleSyncError = nil
        scheduleSyncMessage = nil
        defer { isScheduleSyncing = false }
        var attempt: V2ScheduleSyncAttempt?
        let started = Date()
        do {
            let currentAttempt = try engine.beginScheduleSync()
            attempt = currentAttempt
            let result = try await V2ScheduleSynchronizer.synchronize(currentAttempt, using: client, preflight: {
                try await MainActor.run { try V2PluginStore.shared.validate(ticket) }
            })
            try V2PluginStore.shared.validate(ticket)
            try engine.acceptScheduleSync(result, attempt: currentAttempt)
            refreshAfterScheduleFileChange()
            let pending = engine.snapshot.scheduleDocumentState?.github?.requiresRetry == true
            if engine.snapshot.scheduleDocumentState?.github?.conflict != nil {
                scheduleSyncMessage = "发现内容冲突，双方版本已保存。"
            } else {
                scheduleSyncMessage = pending ? "本轮已同步，期间的新修改仍待同步。" : "日程已同步。"
            }
            V2UsageTrace.shared.record(.init(kind: .syncFinished, source: .sync, operationID: currentAttempt.id, duration: Date().timeIntervalSince(started)))
        } catch {
            guard (try? V2PluginStore.shared.validate(ticket)) != nil else { scheduleSyncMessage = "同步已停止，旧结果未写入本机。"; return }
            if let attempt {
                let failure: V2ScheduleGitHubState.Failure
                switch error {
                case V2GitHubScheduleError.unauthorized, V2GitHubScheduleError.missingCredential: failure = .authorization
                case V2GitHubScheduleError.conflict: failure = .concurrentChange
                case is V2ScheduleMarkdownError, is V2ScheduleMergeError: failure = .invalidDocument
                case is URLError: failure = .network
                default: failure = .other
                }
                do { try engine.failScheduleSync(attempt, failure: failure) }
                catch { scheduleSyncError = "本地日程已保留，但同步状态暂时无法保存。" }
            }
            if scheduleSyncError == nil { scheduleSyncError = error.localizedDescription }
            refreshProjection(at: Date())
            V2UsageTrace.shared.record(.init(kind: .syncFailed, source: .sync, operationID: attempt?.id, duration: Date().timeIntervalSince(started)))
        }
    }
}

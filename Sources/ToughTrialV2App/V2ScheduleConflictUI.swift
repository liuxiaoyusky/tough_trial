import SwiftUI
import ToughTrialV2Core

struct V2PendingScheduleConflict {
    let conflict: V2ScheduleSyncConflict
    let resolutions: [V2ScheduleConflictResolution]
    let document: V2ScheduleDocument
    var moduleTicket: V2ModuleTicket? = nil
}

struct V2ScheduleConflictPreview: View {
    @ObservedObject var store: V2AppStore
    let pending: V2PendingScheduleConflict
    var body: some View {
        Section("待确认的 AI 处理") {
            ForEach(pending.conflict.conflicts) { item in
                if let resolution = pending.resolutions.first(where: { $0.id == item.id }) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(pending.conflict.local.tasks.first { $0.id == item.objectID }?.title ?? "日程内容").font(.headline)
                        Text("原内容：\(text(item.local))").font(.footnote).foregroundStyle(.secondary)
                        Text("处理后：\(chosen(resolution, item: item))").font(.footnote)
                    }
                }
            }
            Button("确认应用") { Task { await store.confirmScheduleConflict() } }
                .accessibilityIdentifier("schedule.github.conflict.confirm")
            Button("取消", role: .cancel) { store.pendingScheduleConflict = nil }
                .accessibilityIdentifier("schedule.github.conflict.cancel")
        }
    }
    private func chosen(_ resolution: V2ScheduleConflictResolution, item: V2ScheduleConflict) -> String {
        switch resolution.choice {
        case .local: text(item.local)
        case .remote: text(item.remote)
        case .base: text(item.base)
        case .mergeText: resolution.text ?? ""
        }
    }
    private func text(_ value: V2SchedulePrimitive) -> String {
        switch value {
        case .null: "未设置"
        case let .string(value): value
        case let .number(value): String(value)
        case let .boolean(value): value ? "是" : "否"
        }
    }
}

extension V2AppStore {
    func resolveConfiguredScheduleConflict(guidance: String? = nil) async {
        guard !isScheduleSyncing, let ticket = try? V2PluginStore.shared.ticket(["sync", "assistant"]) else { return }
        do {
            let client = V2OpenAICompatibleConflictClient(configuration: try aiProviderSettings.agentConfiguration(), guidance: guidance)
            let applied = await resolveScheduleConflict(using: client, requiresConfirmation: V2ScheduleSettings.requiresConfirmation)
            try V2PluginStore.shared.validate(ticket)
            if applied { await synchronizeConfiguredSchedule(automaticallyResolve: false) }
        } catch { scheduleSyncError = "请先配置助手 AI 服务，再处理这些冲突。双方内容已保留。" }
    }

    @discardableResult
    func resolveScheduleConflict<Client: V2ScheduleConflictClient>(using client: Client, requiresConfirmation: Bool) async -> Bool {
        guard !isScheduleSyncing, canWrite else { return false }
        guard let ticket = try? V2PluginStore.shared.ticket(["sync", "assistant"]) else { scheduleSyncError = "请先开启日程同步和助手。"; return false }
        isScheduleSyncing = true
        scheduleSyncError = nil
        scheduleSyncMessage = nil
        pendingScheduleConflict = nil
        defer { isScheduleSyncing = false }
        do {
            guard let conflict = try engine.refreshScheduleSyncConflict() else {
                scheduleSyncMessage = "当前修改已消除冲突，可以重新同步。"
                return false
            }
            let outcome = try await client.resolve(conflict)
            try Task.checkCancellation()
            try V2PluginStore.shared.validate(ticket)
            switch outcome {
            case let .clarification(question):
                scheduleSyncMessage = question
                return false
            case let .resolution(resolutions):
                let candidate = try V2ScheduleConflictResolver.resolve(conflict, using: resolutions)
                let pending = V2PendingScheduleConflict(conflict: conflict, resolutions: resolutions, document: candidate, moduleTicket: ticket)
                if requiresConfirmation {
                    pendingScheduleConflict = pending
                    scheduleSyncMessage = "AI 已整理处理方案，请检查后确认。"
                    return false
                }
                try applyScheduleConflict(pending)
                return true
            }
        } catch {
            scheduleSyncError = error.localizedDescription
            return false
        }
    }

    func applyScheduleConflict(_ pending: V2PendingScheduleConflict) throws {
        try V2PluginStore.shared.require(["sync", "assistant"])
        if let ticket = pending.moduleTicket { try V2PluginStore.shared.validate(ticket) }
        let before = engine.snapshot
        try engine.applyScheduleConflictResolution(conflictID: pending.conflict.id, resolutions: pending.resolutions)
        highlightedScheduleIDs = Set(engine.snapshot.tasks.filter { task in before.tasks.first { $0.id == task.id } != task }.map(\.id))
            .union(engine.snapshot.planItems.filter { item in before.planItems.first { $0.id == item.id } != item }.map(\.id))
        pendingScheduleConflict = nil
        scheduleSyncMessage = "AI 已处理冲突，改动已应用，可撤销本次处理。"
        refreshAfterScheduleFileChange()
        V2UsageTrace.shared.record(.init(kind: .conflictResolved, source: .sync, operationID: pending.conflict.id))
    }

    func confirmScheduleConflict() async {
        guard !isScheduleSyncing, let pending = pendingScheduleConflict else { return }
        do {
            try applyScheduleConflict(pending)
            await synchronizeConfiguredSchedule(automaticallyResolve: false)
        } catch { scheduleSyncError = error.localizedDescription }
    }

    func undoScheduleConflict(id: String) {
        do {
            _ = try engine.restoreScheduleDocumentVersion(id: id)
            highlightedScheduleIDs = []
            scheduleSyncMessage = "已撤销本次处理，本地更改等待同步。"
            refreshAfterScheduleFileChange()
            V2UsageTrace.shared.record(.init(kind: .scheduleUndone, source: .sync, operationID: id))
        } catch { scheduleSyncError = error.localizedDescription }
    }
}

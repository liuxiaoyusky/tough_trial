import SwiftUI
import ToughTrialV2Core
import UniformTypeIdentifiers

struct V2ScheduleFilesView: View {
    @ObservedObject var store: V2AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var showImporter = false
    @State private var showExporter = false
    @State private var exportFile: V2ScheduleExportFile?
    @State private var exportLease: V2ModuleLease?
    @State private var exportedDocument: V2ScheduleDocument?
    @State private var isBusy = false
    @State private var message: String?
    @State private var failure: String?
    @State private var restoreVersion: V2ScheduleDocumentVersion?

    private var fileState: V2ScheduleDocumentState? { store.engine.snapshot.scheduleDocumentState }
    private var hasPendingChanges: Bool {
        guard let state = fileState, let baseline = state.fileBaseline else { return false }
        return store.engine.snapshot.scheduleDocument(using: state.document) != baseline
    }

    var body: some View {
        Form {
            Section {
                if let name = fileState?.fileName {
                    Label(name, systemImage: "doc.text")
                    Text(hasPendingChanges ? "有本地更改待写回" : "已与最近读取的文件一致")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text("选择一个 Markdown 文件，让手机和电脑都能编辑你的日程。")
                }
                Button("选择并读取已有文件") { showImporter = true }
                    .accessibilityIdentifier("schedule.file.import")
                Button("导出为新文件", action: prepareExport)
                    .accessibilityIdentifier("schedule.file.export")
                if fileState?.bookmark != nil {
                    Button("重新读取") { synchronize(writeBack: false) }
                        .accessibilityIdentifier("schedule.file.read")
                    Button("合并并写回") { synchronize(writeBack: true) }
                        .accessibilityIdentifier("schedule.file.write")
                }
            } footer: {
                Text("读取时合并双方修改。缺少的行不会当作删除；格式错误或内容冲突时保留原数据。")
            }
            if isBusy { ProgressView("正在处理文件…") }
            if let message { Text(message).foregroundStyle(.secondary).accessibilityIdentifier("schedule.file.status") }
            if let failure { Text(failure).foregroundStyle(.red).accessibilityIdentifier("schedule.file.error") }
            if let versions = fileState?.versions, !versions.isEmpty {
                Section("恢复记录") {
                    ForEach(versions.reversed()) { version in
                        Button {
                            restoreVersion = version
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(version.source == .restore ? "恢复操作" : "文件变更")
                                Text(version.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("schedule.file.version.\(version.id)")
                    }
                }
            }
        }
        .disabled(isBusy || !store.canWrite)
        .navigationTitle("日程文件")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.text], allowsMultipleSelection: false) { result in
            switch result {
            case let .success(urls): if let url = urls.first { importFile(url) }
            case let .failure(error): failure = error.localizedDescription
            }
        }
        .fileExporter(isPresented: $showExporter, document: exportFile,
            contentType: UTType(filenameExtension: "md") ?? .plainText, defaultFilename: "日程.md") { result in
            switch result {
            case let .success(url): finishExport(url)
            case let .failure(error): failure = error.localizedDescription
            }
        }
        .confirmationDialog("恢复这次变更之前的内容？", isPresented: Binding(
            get: { restoreVersion != nil }, set: { if !$0 { restoreVersion = nil } }
        )) {
            Button("恢复此前内容") {
                guard let version = restoreVersion else { return }
                restoreVersion = nil
                perform(operationID: version.id, successKind: .scheduleUndone) { _, _ in
                    _ = try store.engine.restoreScheduleDocumentVersion(id: version.id)
                    store.refreshAfterScheduleFileChange()
                    message = "已恢复此前内容，可写回文件。"
                }
            }
        } message: {
            Text("保留后来的执行记录和无关任务。相关任务若已有后续修改，会停止恢复并说明。")
        }
    }

    private func prepareExport() {
        do {
            exportLease = try V2PluginStore.shared.runtime.lease(for: ["core.sync"])
            let document = try store.engine.prepareScheduleDocument(timeZoneIdentifier: store.calendar.timeZone.identifier)
            exportedDocument = document
            exportFile = .init(text: try V2ScheduleMarkdown.encode(document), lease: exportLease)
            showExporter = true
            failure = nil
        } catch { failure = error.localizedDescription }
    }

    private func finishExport(_ url: URL) {
        guard let document = exportedDocument, let exportLease else { return }
        perform { _, lease in
            try exportLease.validate()
            let read = try await Task.detached { try V2ScheduleFileIO.read(url: url) }.value
            try lease.validate()
            try exportLease.validate()
            // The user may have edited the exported file before this callback completed.
            guard read.data == Data(try V2ScheduleMarkdown.encode(document).utf8) else { throw V2ScheduleFileIO.FileError.changed }
            try store.engine.recordScheduleFileWrite(document, bookmark: read.bookmark, fileName: url.lastPathComponent)
            store.refreshAfterScheduleFileChange()
            message = "文件已导出并绑定。"
        }
    }

    private func importFile(_ url: URL) {
        let expected = store.engine.snapshot
        perform { operationID, lease in
            let read = try await Task.detached { try V2ScheduleFileIO.read(url: url) }.value
            try lease.validate()
            let document = try V2ScheduleMarkdown.decode(String(decoding: read.data, as: UTF8.self))
            _ = try store.engine.importScheduleDocument(document, expectedSnapshot: expected, requestID: operationID,
                bookmark: read.bookmark, fileName: url.lastPathComponent, replacingBinding: true)
            store.refreshAfterScheduleFileChange()
            message = "已读取并绑定文件。"
        }
    }

    private func synchronize(writeBack: Bool) {
        guard let bookmark = fileState?.bookmark else { return }
        let expected = store.engine.snapshot
        perform { operationID, lease in
            let read = try await Task.detached {
                try V2ScheduleFileIO.read(url: V2ScheduleFileIO.resolve(bookmark))
            }.value
            try lease.validate()
            let incoming = try V2ScheduleMarkdown.decode(String(decoding: read.data, as: UTF8.self))
            let merged = try store.engine.importScheduleDocument(incoming, expectedSnapshot: expected,
                requestID: operationID, bookmark: read.bookmark)
            store.refreshAfterScheduleFileChange()
            if writeBack {
                let data = Data(try V2ScheduleMarkdown.encode(merged).utf8)
                try await Task.detached { try V2ScheduleFileIO.write(data, replacing: read, preflight: { try lease.validate() }) }.value
                try lease.validate()
                try store.engine.recordScheduleFileWrite(merged)
                store.refreshAfterScheduleFileChange()
            }
            message = writeBack ? "已合并并写回文件。" : "已读取文件中的更改。"
        }
    }

    private func perform(
        operationID: String = UUID().uuidString,
        successKind: V2UsageEvent.Kind = .syncFinished,
        _ operation: @escaping @MainActor (String, V2ModuleLease) async throws -> Void
    ) {
        guard !isBusy else { return }
        let lease: V2ModuleLease
        do { lease = try V2PluginStore.shared.runtime.lease(for: ["core.sync"]) }
        catch { failure = error.localizedDescription; return }
        let startedAt = Date()
        isBusy = true
        failure = nil
        message = nil
        Task { @MainActor in
            defer { isBusy = false }
            do {
                try lease.validate()
                try await operation(operationID, lease)
                try lease.validate()
                V2UsageTrace.shared.record(.init(kind: successKind, source: .manual,
                    operationID: operationID, duration: Date().timeIntervalSince(startedAt)))
            } catch {
                failure = error.localizedDescription
                V2UsageTrace.shared.record(.init(kind: .syncFailed, source: .manual,
                    operationID: operationID, duration: Date().timeIntervalSince(startedAt)))
            }
        }
    }
}

extension V2AppStore {
    func refreshAfterScheduleFileChange() {
        refreshProjection(at: Date())
        let affected = Set(engine.snapshot.planItems.map(\.id)).union(
            engine.snapshot.scheduleDocumentState?.versions.flatMap { $0.before.planItems.map(\.id) + $0.after.planItems.map(\.id) } ?? []
        )
        let previous = scheduleReminderTask
        scheduleReminderTask = Task { @MainActor [weak self] in
            await previous?.value
            guard let self else { return }
            let snapshot = engine.snapshot
            let taskIDs = Set(snapshot.tasks.filter { $0.status != .done && $0.status != .archived }.map(\.id))
            let eligible = snapshot.planItems.filter { $0.taskID == nil || taskIDs.contains($0.taskID!) }
            do {
                try await notificationService.replaceIfAuthorized(planItems: eligible, affectedIDs: affected, now: Date(), calendar: calendar)
            } catch { errorMessage = "日程已保存，提醒暂时未能更新。" }
        }
    }
}

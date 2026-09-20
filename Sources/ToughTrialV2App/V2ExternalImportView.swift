import SwiftUI
import UniformTypeIdentifiers
import ToughTrialV2Core

/// File recognition stays local; organizing is a separate, explicit AI action.
struct V2ExternalImportView: View {
    @ObservedObject var captureStore: V2CaptureStore
    var onOrganize: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var picking = false
    @State private var loading = false
    @State private var hint = V2ImportKind.mixed
    @State private var preview: V2ImportPreview?
    @State private var original = Data()
    @State private var selected = Set<String>()
    @State private var issue: String?
    @State private var saved: [V2CaptureEntry] = []
    @State private var importTicket: V2ModuleTicket?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("先识别，再整理").font(.headline)
                        Text("先在本机预览、保存原文。点击 AI 整理后，才发送给所选服务并生成任务或账单。")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Picker("内容类型", selection: $hint) {
                        Text("自动识别").tag(V2ImportKind.mixed)
                        Text("日历").tag(V2ImportKind.calendar)
                        Text("日记").tag(V2ImportKind.journal)
                        Text("账单").tag(V2ImportKind.ledger)
                    }.disabled(loading)
                    Button("选择文件", systemImage: "doc.badge.plus") {
                        do { importTicket = try V2PluginStore.shared.ticket(["imports"]); picking = true }
                        catch { issue = error.localizedDescription }
                    }
                        .disabled(loading).accessibilityIdentifier("import.choose")
                    if loading { ProgressView("正在本机识别…") }
                } footer: {
                    Text("支持 ICS、CSV、TSV、XLSX、TXT、Markdown、JSON；每次一个文件，最大 10 MB、500 条。日历 ZIP 请先解压并选择 ICS。")
                }
                if let issue { Section { Text(issue).foregroundStyle(.red).accessibilityIdentifier("import.error") } }
                if let preview {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(preview.fileName).font(.headline)
                            Text("\(preview.format) · \(preview.records.count) 条记录 · 已选 \(selected.count) 条")
                                .font(.caption).foregroundStyle(.secondary)
                            ForEach(Array(preview.warnings.enumerated()), id: \.offset) { _, warning in
                                Label(warning, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        HStack {
                            Button("全选") { selected = Set(preview.records.map(\.id)); saved = [] }
                            if preview.records.count > 10 {
                                Button("前 10 条") { selected = Set(preview.records.prefix(10).map(\.id)); saved = [] }
                            }
                            Spacer()
                            Button("清空选择") { selected = []; saved = [] }
                        }
                    }
                    Section("识别预览") {
                        ForEach(preview.records) { record in
                            VStack(alignment: .leading) {
                                Toggle(isOn: Binding(get: { selected.contains(record.id) }, set: { value in
                                    if value { selected.insert(record.id) } else { selected.remove(record.id) }; saved = []
                                })) { Text(record.title).lineLimit(3) }
                                DisclosureGroup("查看原文与提示") {
                                    Text(record.text).font(.caption).textSelection(.enabled)
                                    ForEach(Array(record.warnings.enumerated()), id: \.offset) { _, warning in
                                        Text(warning).font(.caption).foregroundStyle(.orange)
                                    }
                                }
                            }
                        }
                    }

                }
                if let imports = captureStore.state.imports, !imports.isEmpty {
                    Section("已保留的原文件") {
                        ForEach(imports.reversed()) { receipt in
                            if let asset = captureStore.state.assets.first(where: { $0.id == receipt.fileAssetID }),
                               let url = try? captureStore.assets.url(for: asset) {
                                ShareLink(item: url) { Label(receipt.fileName, systemImage: "doc") }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden).background(V2Theme.page)
            .safeAreaInset(edge: .bottom) {
                if preview != nil {
                    VStack(spacing: 8) {
                        HStack(spacing: 12) {
                            Button("保存原文（\(selected.count)）") { save(organize: false) }
                                .buttonStyle(.bordered).disabled(selected.isEmpty || loading)
                                .accessibilityIdentifier("import.save")
                            Button("AI 整理") { save(organize: true) }
                                .buttonStyle(.borderedProminent)
                                .disabled(selected.isEmpty || selected.count > 10 || loading || captureStore.isOrganizing)
                                .accessibilityIdentifier("import.organize")
                        }
                        if !saved.isEmpty {
                            Text("已保存 \(saved.count) 条原文，重复导入不会重复创建。")
                                .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("import.saved")
                            Button("打开第一条记录") { captureStore.open(saved[0]); dismiss() }.font(.subheadline)
                        } else {
                            Text(selected.count > 10 ? "每轮最多整理 10 条；也可先保存全部原文。" : "先保存原文，或交给 AI 整理。账单分类仍需确认。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.frame(maxWidth: .infinity).padding().background(.regularMaterial)
                }
            }
            .navigationTitle("导入资料").v2InlineNavigationTitle()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } }
            .fileImporter(isPresented: $picking, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls): if let url = urls.first { recognize(url) }
                case .failure: issue = "未能打开文件，请重新选择。"
                }
            }
            .onChange(of: hint) { _, _ in
                if let preview { saved = []; accept(original, name: preview.fileName) }
            }
            .onAppear {
                #if DEBUG
                if ProcessInfo.processInfo.environment["TOUGH_TRIAL_UI_TESTING"] == "1",
                   ProcessInfo.processInfo.environment["TOUGH_TRIAL_UI_TEST_IMPORT"] == "1", preview == nil {
                    accept(Data("日期,金额,币种,备注\n2026-09-01,28,CNY,午餐\n2026-09-02,12,HKD,交通\n".utf8), name: "测试账单.csv")
                }
                #endif
            }
        }
    }

    private func recognize(_ url: URL) {
        loading = true; issue = nil; preview = nil; saved = []; selected = []
        let kind = hint
        let started = Date()
        Task {
            do {
                guard let importTicket else { throw V2CaptureError.invalidSchema }
                try V2PluginStore.shared.validate(importTicket)
                let (data, result) = try await Task.detached {
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let handle = try FileHandle(forReadingFrom: url)
                    defer { try? handle.close() }
                    let data = try handle.read(upToCount: 10 * 1024 * 1024 + 1) ?? Data()
                    return (data, try V2ExternalImportParser.recognize(data: data, fileName: url.lastPathComponent, hint: kind))
                }.value
                try V2PluginStore.shared.validate(importTicket)
                original = data; preview = result; selected = Set(result.records.map(\.id))
                V2UsageTrace.shared.record(.init(kind: .importRecognized, operationID: result.fingerprint, duration: Date().timeIntervalSince(started)))
            } catch {
                issue = error.localizedDescription
                V2UsageTrace.shared.record(.init(kind: .importRecognitionFailed, duration: Date().timeIntervalSince(started)))
            }
            loading = false
        }
    }
    private func accept(_ data: Data, name: String) {
        do {
            importTicket = try V2PluginStore.shared.ticket(["imports"])
            let result = try V2ExternalImportParser.recognize(data: data, fileName: name, hint: hint)
            original = data; preview = result; selected = Set(result.records.map(\.id))
        } catch { issue = error.localizedDescription }
    }
    private func save(organize: Bool) {
        guard let preview else { return }
        do {
            guard let importTicket else { throw V2CaptureError.invalidSchema }
            try V2PluginStore.shared.validate(importTicket)
        } catch { issue = "导入功能已变更，请重新选择文件；已保存的原文仍保留。"; return }
        guard let entries = captureStore.importRecords(preview, selectedIDs: selected, data: original) else {
            issue = captureStore.issue ?? "保存失败，请重试。"; return
        }
        saved = entries
        if organize { onOrganize(); captureStore.organizeImported(entries); dismiss() }
    }
}

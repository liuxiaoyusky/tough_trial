import SwiftUI
import ToughTrialV2Core

struct V2ExtensionFieldsView: View {
    @ObservedObject var appStore: V2AppStore
    @ObservedObject private var plugins = V2PluginStore.shared
    @State private var domain = "core.notes"
    @State private var name = ""
    @State private var type = V2PluginFieldType.text
    @State private var options = ""
    @State private var issue: String?
    @State private var editingRecord: V2FieldRecordProjection?

    private var definitions: [V2FieldDefinition] { appStore.engine.snapshot.extensionFields.definitions.filter { $0.domain == domain } }
    var body: some View {
        Form {
            Section {
                Picker("功能", selection: $domain) {
                    ForEach(V2ModuleDescriptor.builtins.filter { V2Engine.extensionFieldDomains.contains($0.id) }) { Text($0.name).tag($0.id) }
                }
                Text("给记录增加自己的信息，例如项目、心情、报销状态。停用字段后，已填写的内容仍保留。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let issue { Section { Text(issue).foregroundStyle(.orange) } }
            Section("已有字段") {
                if definitions.isEmpty { Text("还没有自定义字段").foregroundStyle(.secondary) }
                ForEach(definitions) { field in
                    Toggle(isOn: Binding(get: { field.enabled }, set: { enabled in
                        save(.init(id: field.id, domain: field.domain, type: field.type, displayName: field.displayName,
                                   constraints: field.constraints, enums: field.enums, multiple: field.multiple,
                                   enabled: enabled, revision: field.revision + 1), previous: field.revision)
                    })) {
                        VStack(alignment: .leading) { Text(field.displayName); Text(field.type.displayName).font(.caption).foregroundStyle(.secondary) }
                    }.disabled(!plugins.enabled(domain))
                }
            }
            Section("添加字段") {
                TextField("名称，例如报销状态", text: $name).accessibilityIdentifier("fields.name")
                Picker("内容类型", selection: $type) {
                    ForEach([V2PluginFieldType.text, .decimal, .boolean, .date, .enumID, .recordRef], id: \.rawValue) { Text($0.displayName).tag($0) }
                }
                if type == .enumID { TextField("选项，用逗号分隔", text: $options) }
                Button("确认添加") {
                    let values = options.replacingOccurrences(of: "，", with: ",").split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                    save(.init(id: "\(domain).custom.f\(UUID().uuidString.lowercased())", domain: domain,
                               type: type, displayName: name, enums: type == .enumID ? values : []), previous: nil)
                    if issue == nil { name = ""; options = "" }
                }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !plugins.enabled(domain))
                    .accessibilityIdentifier("fields.create")
            }
            Section("填写记录") {
                ForEach(appStore.engine.snapshot.fieldRecords(domainID: domain)) { record in
                    Button(record.title.isEmpty ? "附件记录" : record.title) { editingRecord = record }
                }
            }
        }.navigationTitle("自定义字段")
        .v2Sheet(item: $editingRecord) { record in
            V2RecordFieldsEditor(appStore: appStore, domainID: domain, record: record)
        }
    }

    private func save(_ field: V2FieldDefinition, previous: Int?) {
        guard appStore.canWrite else { issue = "本机存储暂不可写。"; return }
        do {
            try appStore.engine.saveExtensionField(field, expectedRevision: previous, confirmed: true)
            issue = nil; appStore.refreshAfterCapture()
        } catch { issue = error.localizedDescription }
    }
}

private struct V2RecordFieldsEditor: View {
    @ObservedObject var appStore: V2AppStore
    let domainID: String
    let record: V2FieldRecordProjection
    @Environment(\.dismiss) private var dismiss
    @State private var values: [String: String] = [:]
    @State private var definitionsRevision = 0
    @State private var recordRevision = 0
    @State private var issue: String?
    @State private var loaded = false
    private var definitions: [V2FieldDefinition] { appStore.engine.snapshot.extensionFields.definitions.filter { $0.domain == domainID } }

    var body: some View {
        NavigationStack {
            Form {
                Section { Text(record.title) }
                ForEach(definitions) { field in
                    Section(field.displayName + (field.enabled ? "" : " · 已停用")) {
                        if field.enabled && !field.multiple {
                            fieldInput(field)
                        } else {
                            let old = appStore.engine.snapshot.extensionFields.records.first { $0.domainID == domainID && $0.recordID == record.id }
                            ForEach(Array((old?.values.filter { $0.fieldID == field.id } ?? []).enumerated()), id: \.offset) { _, value in
                                Text(display(value.value)).textSelection(.enabled)
                            }
                        }
                    }
                }
                if let issue { Text(issue).foregroundStyle(.orange) }
            }.navigationTitle("补充信息")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("保存") { save() }.disabled(!V2PluginStore.shared.enabled(domainID)) }
                }
                .onAppear {
                    guard !loaded else { return }; loaded = true
                    let state = appStore.engine.snapshot.extensionFields
                    definitionsRevision = state.revision
                    let old = state.records.first { $0.domainID == domainID && $0.recordID == record.id }
                    recordRevision = old?.revision ?? 0
                    for attribute in old?.values ?? [] { values[attribute.fieldID] = display(attribute.value) }
                }
        }
    }

    @ViewBuilder private func fieldInput(_ field: V2FieldDefinition) -> some View {
        let value = Binding(get: { values[field.id] ?? "" }, set: { values[field.id] = $0 })
        switch field.type {
        case .boolean: Picker("选择", selection: value) { Text("未填写").tag(""); Text("是").tag("true"); Text("否").tag("false") }
        case .enumID: Picker("选择", selection: value) { Text("未填写").tag(""); ForEach(field.enums, id: \.self) { Text($0).tag($0) } }
        case .recordRef:
            Picker("关联记录", selection: value) {
                Text("未填写").tag("")
                ForEach(appStore.engine.snapshot.fieldRecords(domainID: domainID)) { Text($0.title).tag(domainID + ":" + $0.id) }
            }
        default: TextField(field.type == .date ? "YYYY-MM-DD" : field.displayName, text: value)
        }
    }

    private func display(_ value: V2TypedFieldValue) -> String {
        switch value {
        case .text(let value), .decimal(let value), .date(let value), .enumID(let value): value
        case .boolean(let value): value ? "true" : "false"
        case .recordRef(let domain, let id): domain + ":" + id
        }
    }

    private func save() {
        guard appStore.canWrite else { issue = "本机存储暂不可写。"; return }
        do {
            let old = appStore.engine.snapshot.extensionFields.records.first { $0.domainID == domainID && $0.recordID == record.id }
            var attributes = (old?.values ?? []).filter { attribute in definitions.contains { $0.id == attribute.fieldID && $0.enabled && $0.multiple } }
            for field in definitions where field.enabled && !field.multiple {
                guard let text = values[field.id], !text.isEmpty else { continue }
                let value: V2TypedFieldValue
                switch field.type {
                case .text: value = .text(text)
                case .decimal: value = .decimal(text)
                case .boolean: value = .boolean(text == "true")
                case .date: value = .date(text)
                case .enumID: value = .enumID(text)
                case .recordRef:
                    let parts = text.split(separator: ":", maxSplits: 1).map(String.init)
                    guard parts.count == 2 else { throw V2ExtensionFieldError.invalidValue }
                    value = .recordRef(domain: parts[0], id: parts[1])
                }
                attributes.append(.init(fieldID: field.id, value: value))
            }
            try appStore.engine.setRecordAttributes(domainID: domainID, recordID: record.id, values: attributes,
                expectedDefinitionsRevision: definitionsRevision, expectedRecordRevision: recordRevision)
            appStore.refreshAfterCapture(); dismiss()
        } catch { issue = error.localizedDescription }
    }
}

private extension V2PluginFieldType {
    var displayName: String {
        switch self {
        case .text: "文字"
        case .decimal: "数字"
        case .boolean: "是或否"
        case .date: "日期"
        case .enumID: "固定选项"
        case .recordRef: "关联记录"
        }
    }
}

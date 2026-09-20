import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif
import ToughTrialV2Core

enum V2TaskEditorMode {
    case create(location: String, identifier: String = "tasks.capture")
    case edit(taskID: String)
    case quick
    case proposal

    var title: String {
        switch self {
        case .create, .quick: "新增任务"
        case .edit: "编辑任务"
        case .proposal: "编辑待办"
        }
    }
    var identifier: String {
        switch self {
        case .create(_, let identifier): identifier
        case .edit: "tasks.editor"
        case .quick: "quick.task"
        case .proposal: "schedule.task"
        }
    }
    var saveIdentifier: String {
        switch self { case .quick, .proposal: identifier + ".save"; default: identifier + ".submit" }
    }
    var cancelIdentifier: String {
        switch self { case .proposal: identifier + ".cancelEditing"; default: identifier + ".cancel" }
    }
    var location: String? {
        switch self {
        case .create(let location, _): location
        case .quick: "任务列表 · 暂不安排日期"
        default: nil
        }
    }
    var ownerModuleID: String {
        switch self { case .proposal: "core.assistant"; default: "core.tasks" }
    }
}

/// 页面提供领域提交与额外字段，组件只管理本次展示的草稿生命周期。
struct V2TaskEditor<AdditionalFields: View>: View {
    typealias Mode = V2TaskEditorMode
    let mode: Mode
    let initialTitle: String
    let initialNote: String
    let additionalDirty: Bool
    let additionalFields: AdditionalFields
    let onSave: (String, String) -> String?
    let onCancel: () -> Void
    @State private var document: String
    @State private var selection: NSRange
    @State private var isFocused = false
    @ObservedObject private var plugins = V2PluginStore.shared
    @State private var issue: String?
    @State private var confirmDiscard = false
    @State private var isDictating = false

    init(mode: Mode, title: String = "", note: String = "", additionalDirty: Bool = false,
         onSave: @escaping (String, String) -> String?, onCancel: @escaping () -> Void,
         @ViewBuilder additionalFields: () -> AdditionalFields) {
        self.mode = mode
        initialTitle = title; initialNote = note
        self.additionalDirty = additionalDirty
        self.additionalFields = additionalFields()
        self.onSave = onSave; self.onCancel = onCancel
        let text = V2TaskDocumentContent.join(title: title, note: note)
        _document = State(initialValue: text)
        _selection = State(initialValue: NSRange(location: (text as NSString).length, length: 0))
    }

    private var initialDocument: String { V2TaskDocumentContent.join(title: initialTitle, note: initialNote) }
    private var fields: (title: String, note: String) {
        document == initialDocument ? (initialTitle, initialNote) : V2TaskDocumentContent.split(document)
    }
    private var isDirty: Bool { document != initialDocument || additionalDirty }
    private var isEmpty: Bool { V2TaskDocumentContent.split(document).title.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button("取消") {
                    if isDirty || isDictating { confirmDiscard = true } else { onCancel() }
                }
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityIdentifier(mode.cancelIdentifier)
                Spacer()
                Text(mode.title).font(V2Theme.TypeRole.labelMedium).foregroundStyle(V2Theme.secondary)
                Spacer()
                Button("保存") {
                    // Commit the current IME composition before reading the draft.
                    V2Platform.endEditing()
                    isFocused = false
                    issue = onSave(fields.title, fields.note)
                }
                    .font(V2Theme.TypeRole.labelLarge)
                    .padding(.horizontal, 18).frame(minHeight: 44)
                    .foregroundStyle(isEmpty || isDictating ? V2Theme.tertiary : V2Theme.ColorRole.onPrimary)
                    .background(isEmpty || isDictating ? V2Theme.ColorRole.surfaceMuted : V2Theme.blue,
                                in: RoundedRectangle(cornerRadius: 12))
                    .disabled(isEmpty || isDictating)
                    .accessibilityIdentifier(mode.saveIdentifier)
            }
            .font(V2Theme.TypeRole.labelLarge).buttonStyle(.plain)
            .padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 16)
            if let location = mode.location {
                Text(location).font(V2Theme.TypeRole.labelSmall).foregroundStyle(V2Theme.secondary)
                    .padding(.horizontal, 24).padding(.bottom, 8)
                    .accessibilityIdentifier(mode.identifier + ".location")
            }
            if isEmpty && !document.isEmpty {
                Text("第一行写下要做的事，即可保存。")
                    .font(.footnote).foregroundStyle(V2Theme.secondary)
                    .padding(.horizontal, 24).padding(.bottom, 8)
                    .accessibilityIdentifier(mode.identifier + ".validation")
            }
            if let issue {
                Text(issue).font(.footnote).foregroundStyle(V2Theme.ColorRole.destructive)
                    .padding(.horizontal, 24).padding(.bottom, 8)
                    .accessibilityIdentifier("tasks.editor.error")
            }
            V2TaskFields(text: $document, selection: $selection, isFocused: $isFocused,
                         isEnabled: !isDictating, identifierPrefix: mode.identifier)
                .padding(.horizontal, 24)
            additionalFields.disabled(isDictating)
                .padding(.horizontal, 24).padding(.bottom, 8)
            HStack(alignment: .bottom, spacing: 8) {
                if plugins.enabled("speech") {
                    V2DictationControl(text: $document, isActive: $isDictating, selection: $selection,
                        ownerModuleID: mode.ownerModuleID, identifierPrefix: mode.identifier + ".speech")
                } else { Spacer() }
                #if os(iOS)
                if isFocused {
                    Button { isFocused = false } label: {
                        Image(systemName: "keyboard.chevron.compact.down").frame(width: 44, height: 44)
                    }.accessibilityLabel("收起键盘").accessibilityIdentifier(mode.identifier + ".dismissKeyboard")
                }
                #endif
            }
            .font(V2Theme.TypeRole.labelLarge).foregroundStyle(V2Theme.secondary)
            .padding(.horizontal, 20).padding(.vertical, 8)
            .background(V2Theme.ColorRole.surfaceMuted.opacity(0.55))
        }
        .background(V2Theme.page).foregroundStyle(V2Theme.ink).tint(V2Theme.blue)
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .interactiveDismissDisabled(isDirty || isDictating)
        .onAppear {
            if document.isEmpty { isFocused = true }
            if case .edit = mode { isFocused = true }
        }
        .onChange(of: isDictating) { _, active in if active { isFocused = false } }
        .alert("放弃未保存的修改？", isPresented: $confirmDiscard) {
            Button("放弃修改", role: .destructive, action: onCancel)
            Button("继续编辑", role: .cancel) {}
        }
    }

}

extension V2TaskEditor where AdditionalFields == EmptyView {
    init(mode: Mode, title: String = "", note: String = "",
         onSave: @escaping (String, String) -> String?, onCancel: @escaping () -> Void) {
        self.init(mode: mode, title: title, note: note, onSave: onSave, onCancel: onCancel) { EmptyView() }
    }
}

/// Optional classification controls for an existing task document.
///
/// Task contexts are structural groupings and remain outside this type picker.
struct V2TaskClassificationFields: View {
    @Binding var kind: V2Task.Kind?
    let identifierPrefix: String

    @State private var isExpanded = false

    private var kindSelection: Binding<String> {
        Binding(
            get: { kind?.rawValue ?? "" },
            set: { kind = V2Task.Kind(rawValue: $0) }
        )
    }

    private var kindSummary: String {
        switch kind {
        case .goal: "目标"
        case .commitment: "承诺"
        case .maintenance: "维护"
        case nil: "未分类"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { isExpanded.toggle() } label: {
                HStack(spacing: 8) {
                    Label("分类（可选）", systemImage: "tag")
                        .font(V2Theme.TypeRole.labelLarge)
                    Spacer(minLength: 8)
                    Text(kindSummary)
                        .font(V2Theme.TypeRole.bodySmall)
                        .foregroundStyle(V2Theme.secondary)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded ? "已展开" : "已收起")
            .accessibilityIdentifier(identifierPrefix)

            if isExpanded {
                Picker("任务类型", selection: kindSelection) {
                    Text("未分类").tag("")
                    Text("目标").tag(V2Task.Kind.goal.rawValue)
                    Text("承诺").tag(V2Task.Kind.commitment.rawValue)
                    Text("维护").tag(V2Task.Kind.maintenance.rawValue)
                }
                .pickerStyle(.menu)
                .frame(minHeight: 44)
                .accessibilityIdentifier(identifierPrefix + ".kind")
            }
        }
        .tint(V2Theme.blue)
        .foregroundStyle(V2Theme.ink)
    }
}

#Preview("新任务") {
    NavigationStack { V2TaskEditor(mode: .create(location: "结构 / 新建根任务"), onSave: { _, _ in nil }, onCancel: {}) }
}

#Preview("编辑失败") {
    NavigationStack {
        V2TaskEditor(mode: .edit(taskID: "preview"), title: "整理学习笔记", note: "保留原始资料",
                     onSave: { _, _ in "保存失败，请重试。" }, onCancel: {})
    }
}

import SwiftUI
import UniformTypeIdentifiers
import ToughTrialV2Core

struct V2PluginsView: View {
    @ObservedObject var appStore: V2AppStore
    @ObservedObject private var plugins = V2PluginStore.shared
    @State private var importing = false
    @State private var preview: V2PluginManifest?
    @State private var packagePreview: V2PluginInstallPreview?
    @State private var uninstallID: String?
    @State private var issue: String?

    var body: some View {
        List {
            Section("功能开关") {
                Text("停用后会阻止新的操作并停止在途处理，已有数据保留。")
                    .font(.subheadline).foregroundStyle(.secondary)
                ForEach(V2ModuleDescriptor.builtins) { module in
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle(module.name, isOn: Binding(get: { plugins.requested(module.id) },
                            set: { plugins.setEnabled(module.id, $0) }))
                            .accessibilityIdentifier("plugin.toggle.\(V2PluginStore.legacyID(module.id))")
                        if let reason = plugins.reason(module.id) {
                            Text(reason).font(.caption).foregroundStyle(.secondary)
                        }
                        if plugins.preferences.migrationHolds.contains(module.id) {
                            Button("恢复此功能") { plugins.setEnabled(module.id, true) }
                        }
                    }
                }
                if plugins.enabled("notes") {
                NavigationLink("笔记与灵感") { V2NotesView(appStore: appStore) }
                    .accessibilityIdentifier("plugin.open.notes")
            }
            if plugins.enabled("ledger") {
                    NavigationLink("打开理账") { V2LedgerView(appStore: appStore) }
                        .accessibilityIdentifier("plugin.open.ledger")
                }
                NavigationLink("自定义字段") { V2ExtensionFieldsView(appStore: appStore) }
                    .accessibilityIdentifier("plugin.open.fields")
                if plugins.enabled("finance") || plugins.enabled("budget") {
                    NavigationLink("打开订阅、还款与预算") { V2FinanceView(captureStore: V2CaptureStore(appStore: appStore)) }
                        .accessibilityIdentifier("plugin.open.finance")
                }
            }
            if let problem = plugins.issue { Text(problem).foregroundStyle(.orange) }
            if !appStore.engine.snapshot.outbox.isEmpty {
                Section("后续处理") {
                    Text("内容已保存，提醒或同步待重试（\(appStore.engine.snapshot.outbox.count)）")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button("重试") {
                        Task { await appStore.retryModuleOutbox() }
                    }
                    .accessibilityIdentifier("plugin.outbox.retry")
                }
            }
            Section("扩展插件") {
                Button("从文件安装插件", systemImage: "puzzlepiece.extension") { importing = true }
                    .accessibilityIdentifier("plugin.import")
                Text("支持 v1/v2 声明式 JSON 表单与模板。安装前会校验版本、权限和链接域名，不执行第三方脚本。")
                    .font(.caption).foregroundStyle(.secondary)

                ForEach(plugins.manifests) { manifest in
                    V1ManifestRow(manifest: manifest, appStore: appStore, plugins: plugins)
                }
                ForEach(plugins.packages) { package in
                    V2PackageRow(package: package, appStore: appStore, plugins: plugins) {
                        uninstallID = package.id
                    }
                }
                ForEach(plugins.retained) { record in
                    VStack(alignment: .leading, spacing: 4) {
                        Label("已卸载：\(record.name)", systemImage: "archivebox")
                        Text(record.retainedDataDescription).font(.caption).foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("plugin.retained.\(record.id)")
                }
            }
            if let preview {
                Section("确认安装 v1") {
                    Text(preview.name).font(.headline)
                    Text(preview.summary)
                    Text("能力：显示输入表单、保存随手记" + (preview.link == nil ? "" : "、打开指定网页"))
                    if let link = preview.link { Text(link).font(.caption).textSelection(.enabled) }
                    Button("安装 / 更新") {
                        do { try plugins.install(preview); self.preview = nil }
                        catch { issue = error.localizedDescription }
                    }
                    Button("取消") { self.preview = nil }
                }
            }
            if let packagePreview {
                Section("确认安装 v2") {
                    Text(packagePreview.package.name).font(.headline)
                    Text("版本 \(packagePreview.package.version) · \(packagePreview.isUpdate ? "更新" : "首次安装")")
                    if packagePreview.delta.isEmpty {
                        Text("权限没有变化，不需要再次确认。")
                    } else {
                        Text("本次权限变化").font(.subheadline.weight(.semibold))
                        if !packagePreview.delta.addedPermissions.isEmpty {
                            Text("新增：" + packagePreview.delta.addedPermissions.map { "\($0.capability)（\($0.scope)）" }.joined(separator: "、"))
                                .foregroundStyle(.orange)
                        }
                        if !packagePreview.delta.removedPermissions.isEmpty {
                            Text("移除：" + packagePreview.delta.removedPermissions.map { "\($0.capability)（\($0.scope)）" }.joined(separator: "、"))
                                .foregroundStyle(.secondary)
                        }
                        if !packagePreview.delta.addedLinkDomains.isEmpty {
                            Text("新增链接域名：" + packagePreview.delta.addedLinkDomains.joined(separator: "、"))
                                .foregroundStyle(.orange)
                        }
                    }
                    Text(packagePreview.retainedDataDescription).font(.caption).foregroundStyle(.secondary)
                    Button(packagePreview.delta.requiresConfirmation ? "确认权限并安装" : "安装 / 更新") {
                        do {
                            try plugins.install(packagePreview, confirmed: true)
                            self.packagePreview = nil
                        } catch { issue = error.localizedDescription }
                    }
                    .accessibilityIdentifier("plugin.package.confirm")
                    Button("取消") { self.packagePreview = nil }
                }
            }
            if let issue { Text(issue).foregroundStyle(.red) }
        }
        .scrollContentBackground(.hidden).background(V2Theme.page)
        .navigationTitle("功能与插件").v2InlineNavigationTitle()
        .onReceive(NotificationCenter.default.publisher(for: .v2ModulesChanged)) { _ in
            guard let current = packagePreview else { return }
            do {
                packagePreview = try plugins.preview(current.package)
            } catch {
                packagePreview = nil
                issue = error.localizedDescription
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
                let document = try V2PluginDocument.decode(try handle.read(upToCount: 64 * 1024 + 1) ?? Data())
                switch document {
                case .v1(let manifest):
                    preview = manifest; packagePreview = nil
                case .v2(let package):
                    packagePreview = try plugins.preview(package); preview = nil
                }
                issue = nil
            } catch { issue = error.localizedDescription }
        }
        .confirmationDialog("卸载这个插件？已生成的随手记和附件会保留。", isPresented: Binding(get: { uninstallID != nil }, set: { if !$0 { uninstallID = nil } }), titleVisibility: .visible) {
            Button("卸载", role: .destructive) {
                if let id = uninstallID {
                    do { _ = try plugins.uninstall(id) }
                    catch { issue = error.localizedDescription }
                }
                uninstallID = nil
            }
            Button("取消", role: .cancel) { uninstallID = nil }
        }
    }
}

private struct V1ManifestRow: View {
    let manifest: V2PluginManifest
    let appStore: V2AppStore
    @ObservedObject var plugins: V2PluginStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(manifest.name, isOn: Binding(get: { plugins.requested(manifest.id) }, set: { plugins.setEnabled(manifest.id, $0) }))
            Text("v1 · \(manifest.summary)").font(.caption).foregroundStyle(.secondary)
            if let reason = plugins.reason(manifest.id) { Text(reason).font(.caption).foregroundStyle(.secondary) }
            if plugins.enabled(manifest.id), plugins.enabled("capture"),
               let context = try? plugins.legacyFormContext(manifestID: manifest.id, appStore: appStore) {
                NavigationLink("打开插件") { V1PluginFormView(context: context, link: manifest.link) }
            }
        }
    }
}

private struct V2PackageRow: View {
    @Environment(\.openURL) private var openURL
    let package: V2PluginPackage
    let appStore: V2AppStore
    @ObservedObject var plugins: V2PluginStore
    let onUninstall: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(package.name, isOn: Binding(get: { plugins.requested(package.id) }, set: { plugins.setEnabled(package.id, $0) }))
            Text("v2 · \(package.version)").font(.caption).foregroundStyle(.secondary)
            if let reason = plugins.reason(package.id) { Text(reason).font(.caption).foregroundStyle(.secondary) }
            ForEach(package.contributions.forms) { form in
                if plugins.enabled(package.id), plugins.enabled("capture"), let context = try? plugins.formContext(packageID: package.id, formID: form.id, appStore: appStore) {
                    NavigationLink(form.title ?? form.id) { V2PluginFormView(context: context) }
                }
            }
            if plugins.enabled(package.id) {
                ForEach(package.contributions.links, id: \.self) { rawLink in
                    if let url = URL(string: rawLink) {
                        Button("打开关联页面 · \(url.host ?? "网页")") {
                            do { openURL(try plugins.authorizedLink(package: package, rawURL: rawLink)) }
                            catch { plugins.issue = error.localizedDescription }
                        }
                    }
                }
            }
            Button("卸载插件", role: .destructive, action: onUninstall)
                .accessibilityIdentifier("plugin.uninstall.\(package.id)")
        }
    }
}

private struct V1PluginFormView: View {
    @Environment(\.openURL) private var openURL
    @State private var context: V2PluginFormContext
    let link: String?
    init(context: V2PluginFormContext, link: String?) {
        _context = State(initialValue: context); self.link = link
    }
    @State private var values: [String: String] = [:]
    @State private var message: String?
    @State private var saved = false

    var body: some View {
        Form {
            ForEach(context.form.fields) { field in
                TextField(field.displayTitle + (field.required ? " *" : ""), text: Binding(get: { values[field.id] ?? "" }, set: { values[field.id] = $0; saved = false }), axis: .vertical)
            }
            Button(saved ? "已保存" : "保存到随手记") {
                do {
                    _ = try context.submit(values: values)
                    saved = true; message = "原文已保存，可在随手记中继续整理。"
                } catch { message = error.localizedDescription }
            }.disabled(saved)
            if link != nil {
                Button("打开关联页面") {
                    do { openURL(try context.linkURL()) }
                    catch { message = error.localizedDescription }
                }
            }
            if let message { Text(message).font(.caption) }
        }.navigationTitle(context.form.title ?? context.formID)
    }
}

private struct V2PluginFormView: View {
    @State private var context: V2PluginFormContext
    init(context: V2PluginFormContext) { _context = State(initialValue: context) }
    @State private var values: [String: String] = [:]
    @State private var message: String?
    @State private var saved = false

    var body: some View {
        Form {
            ForEach(context.form.fields) { field in
                TextField(field.displayTitle + (field.required ? " *" : ""), text: Binding(get: { values[field.id] ?? "" }, set: { values[field.id] = $0; saved = false }), axis: .vertical)
            }
            Button(saved ? "已保存" : "保存到随手记") {
                do {
                    _ = try context.submit(values: values)
                    saved = true; message = "原文已保存，可在随手记中继续整理。"
                } catch { message = error.localizedDescription }
            }.disabled(saved).accessibilityIdentifier("plugin.form.submit.\(context.formID)")
            if let message { Text(message).font(.caption) }
        }.navigationTitle(context.form.title ?? context.formID)
    }
}

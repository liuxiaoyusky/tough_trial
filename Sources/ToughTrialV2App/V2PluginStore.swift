import Foundation
import SwiftUI
import ToughTrialV2Core

/// Storage for the package envelope is intentionally injectable. Production
/// uses an atomic file under Application Support; tests can use UserDefaults
/// or an in-memory implementation without changing the package protocol.
protocol V2PluginPackageStorage {
    func load() throws -> Data?
    func save(_ data: Data) throws
}

private struct V2PluginFileStorage: V2PluginPackageStorage {
    let url: URL

    func load() throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    func save(_ data: Data) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

private struct V2PluginDefaultsStorage: V2PluginPackageStorage {
    let defaults: UserDefaults
    let key: String

    func load() throws -> Data? { defaults.data(forKey: key) }
    func save(_ data: Data) throws { defaults.set(data, forKey: key) }
}

struct V2PluginPackageRecord: Codable, Equatable, Sendable {
    let package: V2PluginPackage
    let installedAt: Date
    let updatedAt: Date

    init(package: V2PluginPackage, installedAt: Date = Date(), updatedAt: Date = Date()) {
        self.package = package
        self.installedAt = installedAt
        self.updatedAt = updatedAt
    }
}

struct V2PluginGrantRecord: Codable, Equatable, Sendable {
    static let maximumRevision = 1_000_000
    let pluginID: String
    let permissionKeys: Set<String>
    let linkDomains: Set<String>
    let revision: Int

    init(pluginID: String, permissionKeys: Set<String>, linkDomains: Set<String>, revision: Int = 1) {
        self.pluginID = pluginID
        self.permissionKeys = permissionKeys
        self.linkDomains = linkDomains
        self.revision = revision
    }
}

struct V2PluginRetentionRecord: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let version: String
    let removedAt: Date
    let retainedDataDescription: String

    init(id: String, name: String, version: String, removedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.version = version
        self.removedAt = removedAt
        self.retainedDataDescription = "已生成的随手记、附件及其历史引用仍保留在本机；重新安装同一插件不会删除这些资料。"
    }
}

struct V2PluginPackageEnvelope: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1
    let schemaVersion: Int
    let packages: [V2PluginPackageRecord]
    let grants: [V2PluginGrantRecord]
    let retained: [V2PluginRetentionRecord]

    init(packages: [V2PluginPackageRecord] = [], grants: [V2PluginGrantRecord] = [], retained: [V2PluginRetentionRecord] = []) {
        self.schemaVersion = Self.currentSchemaVersion
        self.packages = packages
        self.grants = grants
        self.retained = retained
    }

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= 256 * 1024,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys).isSubset(of: ["schemaVersion", "packages", "grants", "retained"]) else {
            throw V2PluginError.invalidManifest
        }
        func objectValue(_ value: Any) -> [String: Any]? { value as? [String: Any] }
        func requireKeys(_ value: Any, _ keys: Set<String>) throws -> [String: Any] {
            guard let object = objectValue(value), Set(object.keys) == keys else { throw V2PluginError.invalidManifest }
            return object
        }
        guard let packageValues = object["packages"] as? [Any],
              let grantValues = object["grants"] as? [Any],
              let retainedValues = object["retained"] as? [Any] else {
            throw V2PluginError.invalidManifest
        }
        for packageValue in packageValues {
            let record = try requireKeys(packageValue, ["package", "installedAt", "updatedAt"])
            guard let packageObject = record["package"],
                  let packageData = try? JSONSerialization.data(withJSONObject: packageObject),
                  (try? V2PluginPackage.decode(packageData)) != nil else {
                throw V2PluginError.invalidManifest
            }
        }
        for grantValue in grantValues {
            _ = try requireKeys(grantValue, ["pluginID", "permissionKeys", "linkDomains", "revision"])
        }
        for retainedValue in retainedValues {
            _ = try requireKeys(retainedValue, ["id", "name", "version", "removedAt", "retainedDataDescription"])
        }
        let result = try JSONDecoder().decode(Self.self, from: data)
        guard result.schemaVersion == Self.currentSchemaVersion,
              result.packages.count <= 50,
              result.grants.count <= 50,
              result.retained.count <= 200,
              Set(result.packages.map { $0.package.id }).count == result.packages.count,
              Set(result.grants.map(\.pluginID)).count == result.grants.count,
              Set(result.grants.map(\.pluginID)).isSubset(of: Set(result.packages.map { $0.package.id })),
              result.grants.allSatisfy({ (1...V2PluginGrantRecord.maximumRevision).contains($0.revision) }) else {
            throw V2PluginError.invalidManifest
        }
        for record in result.packages { try record.package.validate() }
        return result
    }
}

struct V2PluginPermissionDelta: Equatable, Sendable {
    let addedPermissions: [V2PluginPermission]
    let removedPermissions: [V2PluginPermission]
    let addedLinkDomains: [String]
    let removedLinkDomains: [String]

    var requiresConfirmation: Bool { !addedPermissions.isEmpty || !addedLinkDomains.isEmpty }
    var isEmpty: Bool { addedPermissions.isEmpty && removedPermissions.isEmpty && addedLinkDomains.isEmpty && removedLinkDomains.isEmpty }
}

struct V2PluginInstallPreview: Equatable, Sendable {
    let package: V2PluginPackage
    let isUpdate: Bool
    let delta: V2PluginPermissionDelta
    let retainedDataDescription: String
    /// The store revision observed when this preview was produced. A preview
    /// is consumed only if the package/grant state is still exactly the state
    /// the user saw in the confirmation UI.
    let stateRevision: UInt64
}

enum V2PluginStoreError: Error, LocalizedError, Equatable {
    case permissionConfirmationRequired(V2PluginPermissionDelta)
    case downgrade(current: String, requested: String)
    case packageNotFound
    case packageCollision
    case storageUnavailable
    case storageRecoveryRequired
    case stalePreview
    case grantUnavailable
    case stopped

    var errorDescription: String? {
        switch self {
        case .permissionConfirmationRequired: "此更新新增了数据或链接权限，请先确认权限范围。"
        case let .downgrade(current, requested): "插件版本不能回退（已安装 " + current + "，收到 " + requested + "）。"
        case .packageNotFound: "找不到这个插件。"
        case .packageCollision: "插件 ID 与已有插件冲突。"
        case .storageUnavailable: "插件清单无法保存，原有安装保持不变。"
        case .storageRecoveryRequired: "插件清单需要先恢复；原文件已保留，暂不覆盖。"
        case .stalePreview: "插件状态已经变化，请重新打开安装确认。"
        case .grantUnavailable: "插件授权记录缺失或已失效，请重新安装并确认权限。"
        case .stopped: "插件已停用，表单结果未写入。"
        }
    }
}

/// The only object a declarative form receives. It contains no AppStore and no
/// arbitrary Engine reference; the host binds the package, generation and
/// Capture command before constructing it.
@MainActor
struct V2PluginFormContext {
    let pluginID: String
    let formID: String
    let operationID: String
    let form: V2PluginForm
    private let submitCapture: @MainActor @Sendable ([String: String], String) throws -> V2CaptureEntry
    private let didSave: @MainActor @Sendable () -> Void
    private let authorizeLink: @MainActor @Sendable () throws -> URL

    init(pluginID: String, formID: String, operationID: String, form: V2PluginForm,
         submitCapture: @escaping @MainActor @Sendable ([String: String], String) throws -> V2CaptureEntry,
         didSave: @escaping @MainActor @Sendable () -> Void = {},
         authorizeLink: @escaping @MainActor @Sendable () throws -> URL = { throw V2PluginStoreError.grantUnavailable }) {
        self.pluginID = pluginID
        self.formID = formID
        self.operationID = operationID
        self.form = form
        self.submitCapture = submitCapture
        self.didSave = didSave
        self.authorizeLink = authorizeLink
    }

    func submit(values: [String: String]) throws -> V2CaptureEntry {
        let entry = try submitCapture(values, operationID)
        didSave()
        return entry
    }

    func linkURL() throws -> URL { try authorizeLink() }
}

@MainActor
final class V2PluginStore: ObservableObject {
    static let shared = V2PluginStore()
    @Published private(set) var preferences: V2ModulePreferences
    @Published private(set) var manifests: [V2PluginManifest]
    @Published private(set) var packages: [V2PluginPackage]
    @Published private(set) var retained: [V2PluginRetentionRecord]
    @Published var issue: String?
    let runtime: V2ModuleRuntime
    private let defaults: UserDefaults
    private let packageStorage: V2PluginPackageStorage
    private var packageRecords: [V2PluginPackageRecord]
    private var grants: [V2PluginGrantRecord]
    /// A package may be present in the durable envelope while its separate
    /// grant record is missing or does not match the package declaration. Such
    /// packages remain visible for recovery, but never become active.
    private var grantBlockedIDs: Set<String> = []
    /// Invalid package bytes are kept intact and block all package mutations.
    /// Otherwise the next install could accidentally replace the only recovery
    /// copy with a newly encoded, incomplete envelope.
    private var packageStorageRecoveryRequired = false
    private var packageStateRevision: UInt64 = 0
    /// Idempotency is scoped to this host/store lifetime. The key contains only
    /// a stable digest of the submitted form, never the raw content.
    private var submittedForms: [String: V2CaptureEntry] = [:]
    private var stopGuards: [UUID: (moduleID: String, guard: @MainActor () throws -> Void)] = [:]

    static let surfaces = [
        ("today", "今天"), ("tasks", "任务"), ("assistant", "助手"),
        ("capture", "随手记"), ("recall", "回想")
    ]

    static func moduleID(_ id: String) -> String {
        switch id {
        case "today", "tasks": "core.tasks"
        case "trace": "core.traceViewer"
        default: id.hasPrefix("core.") || id.hasPrefix("community.") ? id : "core." + id
        }
    }

    static func legacyID(_ id: String) -> String {
        id == "core.traceViewer" ? "trace" : id.replacingOccurrences(of: "core.", with: "")
    }

    var disabled: Set<String> {
        Set(V2FeatureModule.builtins.map(\.id).filter { !enabled($0) })
            .union(manifests.map(\.id).filter { !enabled($0) })
            .union(packages.map(\.id).filter { !enabled($0) })
    }

    init(defaults: UserDefaults? = nil, packageStorage injectedStorage: V2PluginPackageStorage? = nil) {
        let testing = ProcessInfo.processInfo.environment["TOUGH_TRIAL_UI_TESTING"] == "1"
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let storageDefaults = defaults ?? (testing ? UserDefaults(suiteName: "plugins-ui-\(UUID().uuidString)")! : .standard)
        self.defaults = storageDefaults
        let selectedPackageStorage: V2PluginPackageStorage
        if let injectedStorage {
            selectedPackageStorage = injectedStorage
        } else if defaults != nil || testing {
            selectedPackageStorage = V2PluginDefaultsStorage(defaults: storageDefaults, key: "plugins.packages.v2")
        } else {
            let directory = V2PlatformStorage.root
            selectedPackageStorage = V2PluginFileStorage(url: directory.appendingPathComponent("plugins-v2.json"))
        }
        self.packageStorage = selectedPackageStorage

        let storedManifests = storageDefaults.data(forKey: "plugins.manifests")
            .flatMap { try? JSONDecoder().decode([V2PluginManifest].self, from: $0) } ?? []
        let validatedManifests: [V2PluginManifest] = storedManifests.compactMap { value in
            guard let data = try? JSONEncoder().encode(value) else { return nil }
            return try? V2PluginManifest.decode(data)
        }

        var loadedRecords: [V2PluginPackageRecord] = []
        var loadedGrants: [V2PluginGrantRecord] = []
        var loadedRetention: [V2PluginRetentionRecord] = []
        var loadIssue: String?
        var packageStorageNeedsRecovery = false
        do {
            if let data = try selectedPackageStorage.load() {
                let envelope = try V2PluginPackageEnvelope.decode(data)
                loadedRecords = envelope.packages
                loadedGrants = envelope.grants
                loadedRetention = envelope.retained
            }
        } catch {
            packageStorageNeedsRecovery = true
            loadIssue = "插件清单无法读取，原文件已保留。请先恢复清单，再安装或更新扩展。"
            if let data = try? selectedPackageStorage.load() {
                storageDefaults.set(data, forKey: "plugins.packages.v2.invalidBackup")
            }
        }

        var validRecords: [V2PluginPackageRecord] = []
        for record in loadedRecords {
            guard (try? record.package.validate()) != nil,
                  !validatedManifests.contains(where: { $0.id == record.package.id }) else {
                packageStorageNeedsRecovery = true
                loadIssue = "插件 ID 冲突，原文件已保留。请先恢复清单，再安装或更新扩展。"
                continue
            }
            validRecords.append(record)
        }
        loadedGrants = loadedGrants.filter { grant in validRecords.contains { $0.package.id == grant.pluginID } }
        var blockedGrantIDs = Set<String>()
        for record in validRecords {
            guard let grant = loadedGrants.first(where: { $0.pluginID == record.package.id }),
                  grant.revision > 0,
                  grant.permissionKeys == record.package.permissionKeys,
                  grant.linkDomains == record.package.linkDomains else {
                blockedGrantIDs.insert(record.package.id)
                continue
            }
        }

        let settings: V2ModulePreferences
        if let data = storageDefaults.data(forKey: "plugins.runtime.v2") {
            if let decoded = try? JSONDecoder().decode(V2ModulePreferences.self, from: data), decoded.schemaVersion == 2 {
                settings = decoded
            } else {
                settings = .init(disabled: Set(V2ModuleDescriptor.builtins.map(\.id))
                    .union(validatedManifests.map(\.id)).union(validRecords.map { $0.package.id }))
                loadIssue = loadIssue ?? "功能设置无法读取，原文件已保留。功能暂时停用，可逐项重新开启。"
                if storageDefaults.data(forKey: "plugins.runtime.invalidBackup") == nil { storageDefaults.set(data, forKey: "plugins.runtime.invalidBackup") }
            }
        } else {
            let legacy = storageDefaults.stringArray(forKey: "plugins.disabled") ?? []
            settings = .migrate(legacyDisabled: Set(legacy), traceEnabled: storageDefaults.object(forKey: "usageTrace.enabled") as? Bool,
                                communityIDs: Set(validatedManifests.map(\.id) + validRecords.map { $0.package.id }))
            storageDefaults.set(legacy, forKey: "plugins.disabled.v1Backup")
            if let data = try? JSONEncoder().encode(settings) { storageDefaults.set(data, forKey: "plugins.runtime.v2") }
        }

        let initialPackages = validRecords.map(\.package)
        self.manifests = validatedManifests
        self.packageRecords = validRecords
        self.packages = initialPackages
        self.grants = loadedGrants
        self.grantBlockedIDs = blockedGrantIDs
        self.packageStorageRecoveryRequired = packageStorageNeedsRecovery
        self.retained = loadedRetention
        self.preferences = settings
        self.issue = loadIssue
        self.runtime = V2ModuleRuntime(preferences: settings, descriptors: Self.descriptors(validatedManifests, initialPackages))
    }

    private static func descriptors(_ manifests: [V2PluginManifest], _ packages: [V2PluginPackage]) -> [V2ModuleDescriptor] {
        V2ModuleDescriptor.builtins
            + manifests.map { .init(id: $0.id, name: $0.name, dependencies: ["core.capture"]) }
            + packages.map { .init(id: $0.id, name: $0.name, dependencies: ["core.capture"]) }
    }

    func enabled(_ id: String) -> Bool {
        let module = Self.moduleID(id)
        guard !grantBlockedIDs.contains(module) else { return false }
        return runtime.availability(module).isActive
    }
    func requested(_ id: String) -> Bool { !preferences.disabled.contains(Self.moduleID(id)) }
    func visible(_ surface: String) -> Bool { enabled(surface) && !preferences.hiddenSurfaces.contains(surface) }
    func package(id: String) -> V2PluginPackage? { packages.first { $0.id == id } }

    func reason(_ id: String) -> String? {
        let module = Self.moduleID(id)
        let state = runtime.availability(module)
        if grantBlockedIDs.contains(module) {
            return "插件授权记录缺失或与当前定义不一致，已暂停；请重新安装并确认权限。"
        }
        guard !state.isActive else { return nil }
        if preferences.migrationHolds.contains(module) { return "升级前已暂停，可点击恢复继续使用。" }
        if preferences.disabled.contains(module) { return "已停用，已有数据仍保留。" }
        let dependencies = state.blockedBy.filter { $0 != module }.compactMap { runtime.registry.descriptor($0)?.name }
        return dependencies.isEmpty ? state.reason : "请先开启：" + dependencies.joined(separator: "、")
    }

    func require(_ ids: [String]) throws { try runtime.require(ids.map(Self.moduleID)) }
    func ticket(_ ids: [String]) throws -> V2ModuleTicket { try runtime.ticket(for: ids.map(Self.moduleID)) }
    func validate(_ ticket: V2ModuleTicket) throws { try runtime.validate(ticket) }

    /// Registers a synchronous save guard. The caller owns the returned token
    /// and must remove it when its editor disappears.
    @discardableResult
    func registerStopGuard(moduleID: String, guard closure: @escaping @MainActor () throws -> Void) -> UUID {
        let token = UUID()
        stopGuards[token] = (Self.moduleID(moduleID), closure)
        return token
    }

    func removeStopGuard(_ id: UUID) { stopGuards.removeValue(forKey: id) }

    func setVisible(_ surface: String, _ value: Bool) {
        guard Self.surfaces.contains(where: { $0.0 == surface }) else { return }
        var next = preferences
        if value { next.hiddenSurfaces.remove(surface) } else { next.hiddenSurfaces.insert(surface) }
        apply(next)
    }

    func setEnabled(_ id: String, _ value: Bool) {
        do { try setEnabledThrowing(id, value) }
        catch { issue = error.localizedDescription }
    }

    private func setEnabledThrowing(_ id: String, _ value: Bool) throws {
        let module = Self.moduleID(id)
        guard Self.descriptors(manifests, packages).contains(where: { $0.id == module }) else { return }
        if value && grantBlockedIDs.contains(module) { throw V2PluginStoreError.grantUnavailable }
        if !value {
            for entry in stopGuards.values where affectedByDisabling(entry.moduleID, target: module) {
                try entry.guard()
            }
        }
        var next = preferences
        if value { next.disabled.remove(module); next.migrationHolds.remove(module) }
        else { next.disabled.insert(module) }
        try applyThrowing(next)
        if module == "core.traceViewer" { V2UsageTrace.shared.isEnabled = value }
        V2UsageTrace.shared.record(.init(kind: .manualEdit, operationID: "plugin-\(module)-\(value ? "on" : "off")", moduleID: module))
    }

    private func affectedByDisabling(_ candidate: String, target: String) -> Bool {
        guard candidate != target else { return true }
        var seen = Set<String>()
        func depends(_ id: String) -> Bool {
            guard seen.insert(id).inserted, let descriptor = runtime.registry.descriptor(id) else { return false }
            return descriptor.dependencies.contains(target) || descriptor.dependencies.contains(where: depends)
        }
        return depends(candidate)
    }

    private func apply(_ next: V2ModulePreferences) {
        do { try applyThrowing(next) }
        catch { issue = "功能设置暂未保存，请重试。" }
    }

    private func applyThrowing(_ next: V2ModulePreferences) throws {
        let data = try JSONEncoder().encode(next)
        defaults.set(data, forKey: "plugins.runtime.v2")
        runtime.update(preferences: next, descriptors: Self.descriptors(manifests, packages))
        preferences = next
        NotificationCenter.default.post(name: .v2ModulesChanged, object: self)
    }

    /// v1 installation keeps its original API and storage semantics.
    func install(_ manifest: V2PluginManifest) throws {
        guard !packageStorageRecoveryRequired else { throw V2PluginStoreError.storageRecoveryRequired }
        let validated = try V2PluginManifest.decode(JSONEncoder().encode(manifest))
        guard !packages.contains(where: { $0.id == validated.id }) else { throw V2PluginStoreError.packageCollision }
        let isUpdate = manifests.contains(where: { $0.id == validated.id })
        var next = manifests
        if let index = next.firstIndex(where: { $0.id == validated.id }) { next[index] = validated }
        else { next.append(validated) }
        guard next.count <= 50 else { throw V2PluginError.invalidManifest }
        let data = try JSONEncoder().encode(next)
        defaults.set(data, forKey: "plugins.manifests")
        manifests = next
        packageStateRevision &+= 1
        // A replacement must retain an explicitly disabled preference. Only a
        // first install opts into the module by default.
        if !isUpdate {
            try setEnabledThrowing(validated.id, true)
        } else {
            runtime.update(preferences: preferences, descriptors: Self.descriptors(manifests, packages))
        }
        invalidateRuntime(for: validated.id)
    }

    func preview(_ package: V2PluginPackage) throws -> V2PluginInstallPreview {
        try package.validate()
        guard !manifests.contains(where: { $0.id == package.id }) else { throw V2PluginStoreError.packageCollision }
        if let existing = packages.first(where: { $0.id == package.id }),
           V2PluginPackage.compareVersions(package.version, existing.version) == .orderedAscending {
            throw V2PluginStoreError.downgrade(current: existing.version, requested: package.version)
        }
        let existingGrant = grantBlockedIDs.contains(package.id) ? nil : grants.first(where: { $0.pluginID == package.id })
        let priorPermissions = existingGrant?.permissionKeys ?? []
        let priorDomains = existingGrant?.linkDomains ?? []
        let requestedPermissions = package.permissionKeys
        let addedKeys = requestedPermissions.subtracting(priorPermissions)
        let removedKeys = priorPermissions.subtracting(requestedPermissions)
        let permissionByKey = Dictionary(uniqueKeysWithValues: package.permissions.map { ($0.key, $0) })
        let existing = packages.first(where: { $0.id == package.id })
        let removedPermissionByKey = Dictionary(uniqueKeysWithValues: (existing?.permissions ?? []).map { ($0.key, $0) })
        let delta = V2PluginPermissionDelta(
            addedPermissions: addedKeys.sorted().compactMap { permissionByKey[$0] },
            removedPermissions: removedKeys.sorted().compactMap { removedPermissionByKey[$0] },
            addedLinkDomains: package.linkDomains.subtracting(priorDomains).sorted(),
            removedLinkDomains: priorDomains.subtracting(package.linkDomains).sorted()
        )
        let retainedDescription = retained.first(where: { $0.id == package.id })?.retainedDataDescription
            ?? "更新只替换插件定义与授权记录，已生成的随手记和附件继续保留。"
        return .init(package: package, isUpdate: existing != nil, delta: delta, retainedDataDescription: retainedDescription,
                     stateRevision: packageStateRevision)
    }

    func install(_ package: V2PluginPackage, confirmed: Bool = false) throws {
        let preview = try preview(package)
        try install(preview, confirmed: confirmed)
    }

    /// Consumes the exact confirmation preview shown to the user. Callers
    /// holding an older preview must refresh it after any package/grant change.
    func install(_ installPreview: V2PluginInstallPreview, confirmed: Bool = false) throws {
        guard installPreview.stateRevision == packageStateRevision else { throw V2PluginStoreError.stalePreview }
        // Re-check the package against the current store so a caller cannot
        // mutate a value-type preview's package or use it after an update.
        let currentPreview = try preview(installPreview.package)
        guard currentPreview == installPreview else { throw V2PluginStoreError.stalePreview }
        guard !packageStorageRecoveryRequired else { throw V2PluginStoreError.storageRecoveryRequired }
        guard !installPreview.delta.requiresConfirmation || confirmed else {
            throw V2PluginStoreError.permissionConfirmationRequired(installPreview.delta)
        }
        let now = Date()
        var nextRecords = packageRecords
        if let index = nextRecords.firstIndex(where: { $0.package.id == installPreview.package.id }) {
            nextRecords[index] = .init(package: installPreview.package, installedAt: nextRecords[index].installedAt, updatedAt: now)
        } else {
            guard nextRecords.count < 50 else { throw V2PluginError.invalidManifest }
            nextRecords.append(.init(package: installPreview.package, installedAt: now, updatedAt: now))
        }
        var nextGrants = grants.filter { $0.pluginID != installPreview.package.id }
        let priorRevision = grants.first { $0.pluginID == installPreview.package.id }?.revision ?? 0
        guard priorRevision >= 0, priorRevision < V2PluginGrantRecord.maximumRevision else {
            throw V2PluginStoreError.storageRecoveryRequired
        }
        nextGrants.append(.init(pluginID: installPreview.package.id, permissionKeys: installPreview.package.permissionKeys, linkDomains: installPreview.package.linkDomains,
                                revision: priorRevision + 1))
        let envelope = V2PluginPackageEnvelope(packages: nextRecords, grants: nextGrants, retained: retained)
        try persist(envelope)
        packageRecords = nextRecords
        packages = nextRecords.map(\.package)
        grants = nextGrants
        grantBlockedIDs.remove(installPreview.package.id)
        packageStateRevision &+= 1
        var nextPreferences = preferences
        if !installPreview.isUpdate {
            nextPreferences.disabled.remove(installPreview.package.id)
            nextPreferences.migrationHolds.remove(installPreview.package.id)
        }
        try applyThrowing(nextPreferences)
        invalidateRuntime(for: installPreview.package.id)
        V2UsageTrace.shared.record(.init(kind: .manualEdit, source: .manual, operationID: "plugin-install-\(installPreview.package.id)-\(installPreview.package.version)", moduleID: installPreview.package.id))
    }

    @discardableResult
    func uninstall(_ id: String) throws -> V2PluginRetentionRecord {
        guard !packageStorageRecoveryRequired else { throw V2PluginStoreError.storageRecoveryRequired }
        if let index = packageRecords.firstIndex(where: { $0.package.id == id }) {
            let package = packageRecords[index].package
            let record = V2PluginRetentionRecord(id: package.id, name: package.name, version: package.version)
            let nextRecords = packageRecords.filter { $0.package.id != id }
            let nextGrants = grants.filter { $0.pluginID != id }
            let nextRetained = [record] + Array(retained.filter { $0.id != id }.prefix(199))
            try persist(.init(packages: nextRecords, grants: nextGrants, retained: nextRetained))
            packageRecords = nextRecords
            packages = nextRecords.map(\.package)
            grants = nextGrants
            retained = nextRetained
            grantBlockedIDs.remove(id)
            packageStateRevision &+= 1
            var next = preferences
            next.disabled.remove(id); next.hiddenSurfaces.remove(id); next.migrationHolds.remove(id)
            try applyThrowing(next)
            invalidateRuntime(for: id)
            V2UsageTrace.shared.record(.init(kind: .manualEdit, source: .manual, operationID: "plugin-uninstall-\(id)", moduleID: id))
            return record
        }

        // v1 definitions use the same retention marker so uninstalling an old
        // manifest also keeps the Capture/assets data discoverable. The v1
        // manifest itself remains on its legacy UserDefaults key until this
        // durable retention write succeeds.
        guard let index = manifests.firstIndex(where: { $0.id == id }) else { throw V2PluginStoreError.packageNotFound }
        let manifest = manifests[index]
        let record = V2PluginRetentionRecord(id: manifest.id, name: manifest.name, version: "1")
        let nextManifests = manifests.filter { $0.id != id }
        let nextRetained = [record] + Array(retained.filter { $0.id != id }.prefix(199))
        try persist(.init(packages: packageRecords, grants: grants, retained: nextRetained))
        defaults.set(try JSONEncoder().encode(nextManifests), forKey: "plugins.manifests")
        manifests = nextManifests
        retained = nextRetained
        packageStateRevision &+= 1
        var next = preferences
        next.disabled.remove(id); next.hiddenSurfaces.remove(id); next.migrationHolds.remove(id)
        try applyThrowing(next)
        invalidateRuntime(for: id)
        V2UsageTrace.shared.record(.init(kind: .manualEdit, source: .manual, operationID: "plugin-uninstall-\(id)", moduleID: id))
        return record
    }

    private func persist(_ envelope: V2PluginPackageEnvelope) throws {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try packageStorage.save(encoder.encode(envelope))
        } catch { throw V2PluginStoreError.storageUnavailable }
    }

    /// Bump leases even when a package's descriptor (name/dependencies) did
    /// not change, while preserving the preference and descriptor state.
    private func invalidateRuntime(for id: String) {
        let module = Self.moduleID(id)
        guard runtime.registry.descriptor(module) != nil else { return }
        runtime.invalidate(moduleID: module)
    }

    /// Construct a restricted host adapter for one v2 form. The form receives
    /// only a Capture facade, a generation ticket and the grant revision that
    /// authorized this host operation. It never retains the complete AppStore.
    func formContext(packageID: String, formID: String, appStore: V2AppStore, submissionID: String? = nil) throws -> V2PluginFormContext {
        guard let package = package(id: packageID), let form = package.form(id: formID) else { throw V2PluginStoreError.packageNotFound }
        guard appStore.canWrite else { throw V2CaptureError.persistenceFailure }
        guard let grant = grants.first(where: { $0.pluginID == packageID }),
              !grantBlockedIDs.contains(packageID),
              grant.revision > 0,
              grant.permissionKeys == package.permissionKeys,
              grant.linkDomains == package.linkDomains,
              grant.permissionKeys.contains("capture.create:submitted-form"),
              enabled(packageID), enabled("capture") else {
            throw V2ModuleRuntimeError.unavailable(id: Self.moduleID(packageID), availability: runtime.availability(Self.moduleID(packageID)))
        }
        let ticket = try self.ticket([packageID, "capture"])
        let grantRevision = grant.revision
        let operationID = submissionID ?? "plugin:\(packageID):\(formID):\(UUID().uuidString)"
        let engine = appStore.engine
        let canWrite: @MainActor @Sendable () -> Bool = { [weak appStore] in appStore?.canWrite == true }
        let didSave: @MainActor @Sendable () -> Void = { [weak appStore] in appStore?.refreshAfterCapture() }
        return V2PluginFormContext(pluginID: packageID, formID: formID, operationID: operationID, form: form, submitCapture: { [weak self] values, _ in
            guard let self else { throw V2PluginStoreError.stopped }
            guard canWrite(),
                  self.grantStillAllows(packageID: packageID, package: package, revision: grantRevision) else {
                throw V2PluginStoreError.grantUnavailable
            }
            guard self.enabled(packageID), self.enabled("capture") else { throw V2PluginStoreError.stopped }
            try self.validate(ticket)
            guard Set(values.keys).isSubset(of: Set(form.fields.map(\.id))) else { throw V2PluginError.invalidInput }
            let text = try form.render(values)
            let fingerprint = Self.formSubmissionFingerprint(packageID: packageID, packageVersion: package.version,
                                                              formID: formID, form: form, values: values)
            let cacheKey = "\(operationID)|\(fingerprint)"
            if let existing = self.submittedForms[cacheKey] { return existing }
            // This is the final synchronous pre-commit check. No ticket check
            // happens after save: once the host has committed, a concurrent
            // lifecycle event must not turn a successful write into a false
            // failure and cause a retry duplicate.
            try self.validate(ticket)
            let stableOperationID = "\(operationID):\(fingerprint)"
            // Use the host operation ID as the Capture identity as well. This
            // lets a fresh form context refind the exact durable entry after a
            // process restart, while the rendered-content check below prevents
            // an accidental ID collision from being treated as success.
            if let existing = engine.snapshot.capture.latestEntries.first(where: { $0.id == stableOperationID }) {
                guard existing.text == text else { throw V2CaptureError.staleTarget }
                self.submittedForms[cacheKey] = existing
                return existing
            }
            let entry = try engine.saveCapture(text: text, newSourceID: stableOperationID)
            self.submittedForms[cacheKey] = entry
            V2UsageTrace.shared.record(.init(kind: .manualEdit, source: .manual, operationID: stableOperationID,
                characterCount: text.count, moduleID: packageID, commandID: form.submit.command))
            return entry
        }, didSave: didSave)
    }

    /// v1 forms are adapted to the same restricted Capture context. Keeping
    /// this path separate preserves the v1 manifest/storage API while avoiding
    /// the old global-store and full-AppStore references inside the form view.
    func legacyFormContext(manifestID: String, appStore: V2AppStore, submissionID: String? = nil) throws -> V2PluginFormContext {
        guard let manifest = manifests.first(where: { $0.id == manifestID }) else { throw V2PluginStoreError.packageNotFound }
        guard appStore.canWrite, enabled(manifestID), enabled("capture") else {
            throw V2ModuleRuntimeError.unavailable(id: Self.moduleID(manifestID), availability: runtime.availability(Self.moduleID(manifestID)))
        }
        let form = V2PluginForm(
            id: "legacy",
            title: manifest.name,
            fields: manifest.fields.map { .init(id: $0.id, title: $0.title, required: $0.required) },
            submit: .init(template: manifest.template)
        )
        let ticket = try self.ticket([manifestID, "capture"])
        let operationID = submissionID ?? "plugin:\(manifestID):legacy:\(UUID().uuidString)"
        let engine = appStore.engine
        let canWrite: @MainActor @Sendable () -> Bool = { [weak appStore] in appStore?.canWrite == true }
        let didSave: @MainActor @Sendable () -> Void = { [weak appStore] in appStore?.refreshAfterCapture() }
        return V2PluginFormContext(pluginID: manifestID, formID: form.id, operationID: operationID, form: form, submitCapture: { [weak self] values, _ in
            guard let self else { throw V2PluginStoreError.stopped }
            guard canWrite(), self.enabled(manifestID), self.enabled("capture") else { throw V2PluginStoreError.stopped }
            try self.validate(ticket)
            guard Set(values.keys).isSubset(of: Set(form.fields.map(\.id))) else { throw V2PluginError.invalidInput }
            let text = try form.render(values)
            let fingerprint = Self.formSubmissionFingerprint(packageID: manifestID, packageVersion: "1",
                                                              formID: form.id, form: form, values: values)
            let cacheKey = "\(operationID)|\(fingerprint)"
            if let existing = self.submittedForms[cacheKey] { return existing }
            try self.validate(ticket)
            let stableOperationID = "\(operationID):\(fingerprint)"
            if let existing = engine.snapshot.capture.latestEntries.first(where: { $0.id == stableOperationID }) {
                guard existing.text == text else { throw V2CaptureError.staleTarget }
                self.submittedForms[cacheKey] = existing
                return existing
            }
            let entry = try engine.saveCapture(text: text, newSourceID: stableOperationID)
            self.submittedForms[cacheKey] = entry
            V2UsageTrace.shared.record(.init(kind: .manualEdit, source: .manual, operationID: stableOperationID,
                                              characterCount: text.count, moduleID: manifestID, commandID: form.submit.command))
            return entry
        }, didSave: didSave, authorizeLink: { [weak self] in
            guard let self, self.enabled(manifestID), self.enabled("capture") else { throw V2PluginStoreError.stopped }
            try self.validate(ticket)
            guard self.manifests.first(where: { $0.id == manifestID }) == manifest,
                  let link = manifest.link, let url = URL(string: link) else { throw V2PluginStoreError.grantUnavailable }
            return url
        })
    }

    func authorizedLink(package: V2PluginPackage, rawURL: String) throws -> URL {
        guard enabled(package.id) else { throw V2PluginStoreError.stopped }
        guard self.package(id: package.id) == package,
              let grant = grants.first(where: { $0.pluginID == package.id }),
              grantStillAllows(packageID: package.id, package: package, revision: grant.revision),
              package.contributions.links.contains(rawURL), let url = URL(string: rawURL) else {
            throw V2PluginStoreError.grantUnavailable
        }
        return url
    }

    private func grantStillAllows(packageID: String, package: V2PluginPackage, revision: Int) -> Bool {
        guard let grant = grants.first(where: { $0.pluginID == packageID }) else { return false }
        return !grantBlockedIDs.contains(packageID)
            && grant.revision == revision
            && grant.permissionKeys == package.permissionKeys
            && grant.linkDomains == package.linkDomains
    }

    private static func formSubmissionFingerprint(
        packageID: String,
        packageVersion: String,
        formID: String,
        form: V2PluginForm,
        values: [String: String]
    ) -> String {
        // Length-prefix every component so separators in user text cannot
        // create collisions in the canonical request representation.
        func component(_ value: String) -> String { "\(value.utf8.count):\(value)" }
        let renderedFields = form.fields.map { field in
            component(field.id) + component(values[field.id] ?? "")
        }.joined()
        let canonical = component(packageID) + component(packageVersion) + component(formID)
            + component(form.submit.command) + component(form.submit.template) + renderedFields
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in canonical.utf8 { hash ^= UInt64(byte); hash &*= 1_099_511_628_211 }
        return String(hash, radix: 16)
    }
}

extension Notification.Name { static let v2ModulesChanged = Self("v2ModulesChanged") }

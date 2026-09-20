import Foundation

public struct V2ModuleDescriptor: Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let dependencies: [String]
    public let version: Int
    public let hostAPIMajor: Int
    public let required: Bool
    public let optionalDependencies: [String]
    public let contributionIDs: [String]
    public let platform: String

    public init(
        id: String,
        name: String,
        dependencies: [String] = [],
        version: Int = 1,
        hostAPIMajor: Int = 1,
        required: Bool = false,
        optionalDependencies: [String] = [],
        contributionIDs: [String] = [],
        platform: String = "iOS"
    ) {
        self.id = id
        self.name = name
        self.dependencies = dependencies
        self.version = version
        self.hostAPIMajor = hostAPIMajor
        self.required = required
        self.optionalDependencies = optionalDependencies
        self.contributionIDs = contributionIDs
        self.platform = platform
    }

    public init(
        stableID: String,
        name: String,
        version: Int = 1,
        hostAPIMajor: Int = 1,
        platform: String = "iOS",
        requiredDependencies: [String] = [],
        optionalDependencies: [String] = [],
        required: Bool = false,
        contributionIDs: [String] = []
    ) {
        self.init(
            id: stableID,
            name: name,
            dependencies: requiredDependencies,
            version: version,
            hostAPIMajor: hostAPIMajor,
            required: required,
            optionalDependencies: optionalDependencies,
            contributionIDs: contributionIDs,
            platform: platform
        )
    }

    public var stableID: String { id }
    public var hostAPI: Int { hostAPIMajor }
    public var requiredDependencies: [String] { dependencies }

    public static let builtins: [Self] = [
        .init(id: "core.tasks", name: "任务"),
        .init(id: "core.capture", name: "随手记"),
        .init(id: "core.ledger", name: "理账"),
        .init(id: "core.finance", name: "订阅与还款", dependencies: ["core.ledger"]),
        .init(id: "core.budget", name: "预算", dependencies: ["core.ledger"]),
        .init(id: "core.recall", name: "回想"),
        .init(id: "core.notes", name: "灵感与收纳"),
        .init(id: "core.assistant", name: "助手"),
        .init(id: "core.web", name: "网页搜索", dependencies: ["core.assistant"]),
        .init(id: "core.imports", name: "外部文件导入", dependencies: ["core.capture"]),
        .init(id: "core.speech", name: "语音输入"),
        .init(id: "core.sync", name: "日程同步", dependencies: ["core.tasks"]),
        .init(id: "core.traceViewer", name: "使用记录"),
        .init(id: "core.attachments", name: "附件输入")
    ]
}

public struct V2ModulePreferences: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2
    public var schemaVersion: Int
    public var disabled: Set<String>
    public var hiddenSurfaces: Set<String>
    public var migrationHolds: Set<String>

    public init(
        schemaVersion: Int = V2ModulePreferences.currentSchemaVersion,
        disabled: Set<String> = [],
        hiddenSurfaces: Set<String> = [],
        migrationHolds: Set<String> = []
    ) {
        self.schemaVersion = schemaVersion
        self.disabled = disabled
        self.hiddenSurfaces = hiddenSurfaces
        self.migrationHolds = migrationHolds
    }

    public static func migrate(
        legacyDisabled: Set<String>,
        traceEnabled: Bool?,
        communityIDs: Set<String>
    ) -> Self {
        let legacyModules = [
            "capture", "ledger", "finance", "budget", "assistant", "recall",
            "imports", "speech", "sync", "attachments"
        ]
        let oldDependencies: [String: [String]] = [
            "ledger": ["capture"],
            "finance": ["ledger"],
            "budget": ["ledger"],
            "imports": ["capture"],
            "attachments": ["capture"]
        ]

        func oldID(_ name: String) -> String { "core.\(name)" }
        func isDisabled(_ name: String) -> Bool {
            legacyDisabled.contains(name) || legacyDisabled.contains(oldID(name))
        }

        var result = Self()
        if isDisabled("today") { result.hiddenSurfaces.insert("today") }
        if isDisabled("tasks") { result.hiddenSurfaces.insert("tasks") }
        if isDisabled("assistant") { result.hiddenSurfaces.insert("assistant") }
        if isDisabled("capture") { result.hiddenSurfaces.insert("capture") }
        if isDisabled("recall") { result.hiddenSurfaces.insert("recall") }

        // Today and Tasks were two entry points into one domain.
        if isDisabled("today") && isDisabled("tasks") {
            result.disabled.insert(oldID("tasks"))
        }
        for name in legacyModules where isDisabled(name) {
            result.disabled.insert(oldID(name))
        }
        if isDisabled("trace") || isDisabled("traceViewer") || traceEnabled == false {
            result.disabled.insert(oldID("traceViewer"))
        }
        let knownLegacyIDs = Set(
            ["today", "tasks", "trace", "traceViewer"] + legacyModules
                + (legacyModules + ["today", "tasks", "trace", "traceViewer"]).map(oldID)
        )
        // Installed community IDs are retained even if their package is no
        // longer available; all other unknown IDs remain diagnostic blockers.
        result.disabled.formUnion(legacyDisabled.filter {
            communityIDs.contains($0) || !knownLegacyIDs.contains($0)
        })

        // Preserve modules that were only inactive because an old dependency
        // was disabled. The hold prevents the decoupled graph from silently
        // reactivating their requested preference during migration.
        func oldEffective(_ name: String, visiting: Set<String> = []) -> Bool {
            guard !isDisabled(name) else { return false }
            guard !visiting.contains(name) else { return false }
            return (oldDependencies[name] ?? []).allSatisfy {
                oldEffective($0, visiting: visiting.union([name]))
            }
        }
        for name in oldDependencies.keys where !isDisabled(name) && !oldEffective(name) {
            result.migrationHolds.insert(oldID(name))
        }
        return result
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, disabled, hiddenSurfaces, migrationHolds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        disabled = try container.decodeIfPresent(Set<String>.self, forKey: .disabled) ?? []
        hiddenSurfaces = try container.decodeIfPresent(Set<String>.self, forKey: .hiddenSurfaces) ?? []
        migrationHolds = try container.decodeIfPresent(Set<String>.self, forKey: .migrationHolds) ?? []
    }
}

public struct V2ModuleAvailability: Equatable, Sendable {
    public let isActive: Bool
    public let blockedBy: [String]
    public let reason: String?

    public init(isActive: Bool, blockedBy: [String] = [], reason: String? = nil) {
        self.isActive = isActive
        self.blockedBy = blockedBy
        self.reason = reason
    }
}

public struct V2ModuleRegistry: Equatable, Sendable {
    public private(set) var descriptors: [String: V2ModuleDescriptor]

    public init(communityDescriptors: [V2ModuleDescriptor] = []) {
        self.init(descriptors: V2ModuleDescriptor.builtins + communityDescriptors, includeBuiltins: false)
    }

    public init(descriptors: [V2ModuleDescriptor], includeBuiltins: Bool = true) {
        var values: [String: V2ModuleDescriptor] = [:]
        for descriptor in (includeBuiltins ? V2ModuleDescriptor.builtins : []) + descriptors {
            values[descriptor.id] = descriptor
        }
        self.descriptors = values
    }

    public init(_ descriptors: [V2ModuleDescriptor]) {
        self.init(descriptors: descriptors)
    }

    public var allDescriptors: [V2ModuleDescriptor] {
        descriptors.values.sorted { $0.id < $1.id }
    }

    public func descriptor(_ id: String) -> V2ModuleDescriptor? { descriptors[id] }

    public func availability(_ id: String, preferences: V2ModulePreferences) -> V2ModuleAvailability {
        var memo: [String: V2ModuleAvailability] = [:]
        return resolve(id, preferences: preferences, path: [], memo: &memo)
    }

    private func resolve(
        _ id: String,
        preferences: V2ModulePreferences,
        path: [String],
        memo: inout [String: V2ModuleAvailability]
    ) -> V2ModuleAvailability {
        if let cached = memo[id], !path.contains(id) { return cached }
        guard let descriptor = descriptors[id] else {
            let result = V2ModuleAvailability(isActive: false, blockedBy: [id], reason: "未知模块")
            if !path.contains(id) { memo[id] = result }
            return result
        }
        if let cycleStart = path.firstIndex(of: id) {
            let cycle = Array(path[cycleStart...])
            return V2ModuleAvailability(isActive: false, blockedBy: cycle.sorted(), reason: "依赖存在循环")
        }
        if preferenceContains(preferences.disabled, id: id) {
            let result = V2ModuleAvailability(isActive: false, blockedBy: [id], reason: "模块已停用")
            memo[id] = result
            return result
        }
        if preferenceContains(preferences.migrationHolds, id: id) {
            let result = V2ModuleAvailability(isActive: false, blockedBy: [id], reason: "迁移状态保持停用")
            memo[id] = result
            return result
        }

        var blocked: [String] = []
        for dependency in descriptor.dependencies {
            let dependencyAvailability = resolve(
                dependency,
                preferences: preferences,
                path: path + [id],
                memo: &memo
            )
            if !dependencyAvailability.isActive {
                blocked.append(dependency)
                blocked.append(contentsOf: dependencyAvailability.blockedBy)
            }
        }
        if !blocked.isEmpty {
            let result = V2ModuleAvailability(
                isActive: false,
                blockedBy: Array(Set(blocked)).sorted(),
                reason: "必要依赖不可用"
            )
            memo[id] = result
            return result
        }
        let result = V2ModuleAvailability(isActive: true)
        memo[id] = result
        return result
    }

    private func preferenceContains(_ values: Set<String>, id: String) -> Bool {
        values.contains(id) || (id.hasPrefix("core.") && values.contains(String(id.dropFirst(5))))
    }
}

public struct V2ModuleTicket: Equatable, Sendable {
    public let generations: [String: UInt64]
    public let commandGenerations: [String: UInt64]

    public init(generations: [String: UInt64], commandGenerations: [String: UInt64] = [:]) {
        self.generations = generations
        self.commandGenerations = commandGenerations
    }
}

/// A thread-safe, immutable capability handle for callbacks that outlive the
/// serialized runtime caller. The runtime invalidates it when its ticket would
/// become stale; validation itself never reads mutable runtime state.
public final class V2ModuleLease: @unchecked Sendable {
    public let generations: [String: UInt64]
    private let lock = NSLock()
    private var staleError: V2ModuleRuntimeError?

    fileprivate init(ticket: V2ModuleTicket) {
        generations = ticket.generations
    }

    public func validate() throws {
        lock.lock()
        let error = staleError
        lock.unlock()
        if let error { throw error }
    }

    fileprivate func invalidate(id: String, expected: UInt64, actual: UInt64?) {
        lock.lock()
        if staleError == nil {
            staleError = .stale(id: id, expected: expected, actual: actual)
        }
        lock.unlock()
    }

    fileprivate func invalidateIfNeeded(_ affected: Set<String>, generations: [String: UInt64]) {
        guard let id = self.generations.keys.filter({ affected.contains($0) }).sorted().first,
              let expected = self.generations[id] else { return }
        invalidate(id: id, expected: expected, actual: generations[id])
    }
}

public enum V2ModuleRuntimeError: Error, LocalizedError, Equatable, Sendable {
    case unavailable(id: String, availability: V2ModuleAvailability)
    case stale(id: String, expected: UInt64, actual: UInt64?)
    case commandNotRegistered(String)
    case commandModuleMismatch(commandID: String, moduleID: String)
    case queryNotRegistered(String)
    case invalidQueryLimit(Int)

    public var errorDescription: String? {
        switch self {
        case let .unavailable(id, availability):
            let detail = availability.reason ?? "状态未满足"
            let blocked = availability.blockedBy.isEmpty ? "" : "（阻塞：\(availability.blockedBy.joined(separator: "、"))）"
            return "模块 \(id) 当前不可用：\(detail)\(blocked)"
        case let .stale(id, expected, actual):
            let current = actual.map(String.init) ?? "不存在"
            return "模块 \(id) 的调用凭证已过期（期望 generation \(expected)，当前 \(current)），请重新获取。"
        case let .commandNotRegistered(id):
            return "命令 \(id) 未注册，已拒绝执行。"
        case let .commandModuleMismatch(commandID, moduleID):
            return "命令 \(commandID) 不属于模块 \(moduleID)，已拒绝执行。"
        case let .queryNotRegistered(id):
            return "查询 \(id) 未注册，已拒绝执行。"
        case let .invalidQueryLimit(limit):
            return "查询条数无效：\(limit)。"
        }
    }
}

private final class V2WeakModuleLease {
    weak var value: V2ModuleLease?

    init(_ value: V2ModuleLease) {
        self.value = value
    }
}

public final class V2ModuleRuntime: @unchecked Sendable {
    public private(set) var registry: V2ModuleRegistry
    public private(set) var preferences: V2ModulePreferences
    public private(set) var commandRegistry: V2NativeCommandRegistry
    public private(set) var queryRegistry: V2NativeQueryRegistry
    private var generations: [String: UInt64]
    private var commandGenerations: [String: UInt64]
    private var leases: [ObjectIdentifier: V2WeakModuleLease] = [:]
    private var contributions: [String: [String: V2ContributionToken]] = [:]
    private var jobs: [String: [String: V2ContributionToken]] = [:]
    /// The app calls the runtime from its serialized MainActor coordinator,
    /// while a ModuleContext may outlive that turn. The recursive lock keeps
    /// those small capability checks and contribution mutations coherent.
    private let stateLock = NSRecursiveLock()

    public init(
        preferences: V2ModulePreferences = .init(),
        descriptors: [V2ModuleDescriptor] = [],
        commands: [V2NativeCommandDescriptor] = V2NativeCommandDescriptor.builtins,
        queries: [V2NativeQueryDescriptor] = V2NativeQueryDescriptor.builtins
    ) {
        self.registry = V2ModuleRegistry(descriptors: descriptors)
        self.preferences = preferences
        self.commandRegistry = V2NativeCommandRegistry(descriptors: commands)
        self.queryRegistry = V2NativeQueryRegistry(descriptors: queries)
        self.generations = Dictionary(uniqueKeysWithValues: self.registry.descriptors.keys.map { ($0, 0) })
        self.commandGenerations = Dictionary(uniqueKeysWithValues: self.commandRegistry.descriptors.keys.map { ($0, 0) })
    }

    public init(
        preferences: V2ModulePreferences = .init(),
        registry: V2ModuleRegistry,
        commands: [V2NativeCommandDescriptor] = V2NativeCommandDescriptor.builtins,
        queries: [V2NativeQueryDescriptor] = V2NativeQueryDescriptor.builtins
    ) {
        self.registry = registry
        self.preferences = preferences
        self.commandRegistry = V2NativeCommandRegistry(descriptors: commands)
        self.queryRegistry = V2NativeQueryRegistry(descriptors: queries)
        self.generations = Dictionary(uniqueKeysWithValues: registry.descriptors.keys.map { ($0, 0) })
        self.commandGenerations = Dictionary(uniqueKeysWithValues: self.commandRegistry.descriptors.keys.map { ($0, 0) })
    }

    /// Invalidate outstanding capabilities after a package/grant update even
    /// when its name and dependency graph did not change.
    public func invalidate(moduleID: String) {
        stateLock.lock(); defer { stateLock.unlock() }
        var affected: Set<String> = [moduleID]
        var expanded = true
        while expanded {
            expanded = false
            for descriptor in registry.descriptors.values where !affected.contains(descriptor.id) {
                if descriptor.dependencies.contains(where: affected.contains) { affected.insert(descriptor.id); expanded = true }
            }
        }
        for id in affected { generations[id, default: 0] &+= 1 }
        pruneLeases()
        for box in leases.values { box.value?.invalidateIfNeeded(affected, generations: generations) }
        cancelOwnedWork(for: affected)
    }

    public func availability(_ id: String) -> V2ModuleAvailability {
        withStateLock { registry.availability(id, preferences: preferences) }
    }

    public func require(_ ids: [String]) throws {
        try withStateLock {
            for id in ids {
                let state = registry.availability(id, preferences: preferences)
                guard state.isActive else { throw V2ModuleRuntimeError.unavailable(id: id, availability: state) }
            }
        }
    }

    /// The receiver-side command gate. Callers never get to opt out by
    /// supplying their own actor, generation, or confirmation flags.
    public func requireCommand(_ commandID: String, modules: [String] = []) throws {
        try withStateLock {
            guard let descriptor = commandRegistry.descriptor(commandID) else {
                throw V2ModuleRuntimeError.commandNotRegistered(commandID)
            }
            let requested = Set(modules)
            if !requested.isEmpty, !requested.contains(descriptor.moduleID) {
                throw V2ModuleRuntimeError.commandModuleMismatch(commandID: commandID, moduleID: requested.sorted().joined(separator: ","))
            }
            try require(Array(Set(descriptor.requiredModules + modules)).sorted())
        }
    }

    public func requireQuery(_ queryID: String, limit: Int = 100) throws -> V2NativeQueryDescriptor {
        try withStateLock {
            guard let descriptor = queryRegistry.descriptor(queryID) else {
                throw V2ModuleRuntimeError.queryNotRegistered(queryID)
            }
            guard (1...descriptor.maxPageSize).contains(limit) else {
                throw V2ModuleRuntimeError.invalidQueryLimit(limit)
            }
            try require([descriptor.moduleID])
            return descriptor
        }
    }

    /// Receiver-side validation for a typed read request.  Filtering never
    /// expands a query's projection or date window; it can only narrow the
    /// already registered bounds.
    public func requireQuery(_ request: V2NativeQueryRequest, now: Date = Date()) throws -> V2NativeQueryDescriptor {
        try withStateLock {
            let descriptor = try requireQuery(request.id, limit: request.limit)
            for field in request.fields where !descriptor.allowedFields.contains(field) {
                throw V2NativeQueryError.unsupportedField(field)
            }
            if let from = request.from {
                let to = request.to ?? now
                guard to >= from else { throw V2NativeQueryError.invalidDateRange }
                if let maxDays = descriptor.maxDays,
                   to.timeIntervalSince(from) > Double(maxDays) * 86_400 {
                    throw V2NativeQueryError.invalidDateRange
                }
            }
            return descriptor
        }
    }

    public func ticket(for ids: [String]) throws -> V2ModuleTicket {
        try withStateLock {
            try require(ids)
            var required = Set<String>()
            for id in ids { collectDependencies(of: id, into: &required) }
            return V2ModuleTicket(generations: required.reduce(into: [:]) { $0[$1] = generations[$1] ?? 0 })
        }
    }

    public func ticket(forCommand commandID: String) throws -> V2ModuleTicket {
        try withStateLock {
            guard let descriptor = commandRegistry.descriptor(commandID) else {
                throw V2ModuleRuntimeError.commandNotRegistered(commandID)
            }
            let base = try ticket(for: descriptor.requiredModules)
            return V2ModuleTicket(
                generations: base.generations,
                commandGenerations: [commandID: commandGenerations[commandID] ?? 0]
            )
        }
    }

    public func ticket(forQuery queryID: String, limit: Int = 100) throws -> V2ModuleTicket {
        try withStateLock {
            let descriptor = try requireQuery(queryID, limit: limit)
            return try ticket(for: [descriptor.moduleID])
        }
    }

    public func lease(for ids: [String]) throws -> V2ModuleLease {
        pruneLeases()
        let lease = V2ModuleLease(ticket: try ticket(for: ids))
        leases[ObjectIdentifier(lease)] = V2WeakModuleLease(lease)
        return lease
    }

    public func validate(_ ticket: V2ModuleTicket) throws {
        try withStateLock {
            for id in ticket.generations.keys.sorted() {
                let expected = ticket.generations[id] ?? 0
                let actual = generations[id]
                guard actual == expected else {
                    throw V2ModuleRuntimeError.stale(id: id, expected: expected, actual: actual)
                }
                guard registry.descriptor(id) != nil else {
                    throw V2ModuleRuntimeError.stale(id: id, expected: expected, actual: actual)
                }
            }
            for commandID in ticket.commandGenerations.keys.sorted() {
                let expected = ticket.commandGenerations[commandID] ?? 0
                let actual = commandGenerations[commandID]
                guard actual == expected, commandRegistry.descriptor(commandID) != nil else {
                    throw V2ModuleRuntimeError.stale(id: commandID, expected: expected, actual: actual)
                }
            }
        }
    }

    public func update(
        preferences: V2ModulePreferences,
        descriptors: [V2ModuleDescriptor]? = nil,
        commands: [V2NativeCommandDescriptor]? = nil,
        queries: [V2NativeQueryDescriptor]? = nil
    ) {
        update(
            preferences: preferences,
            registry: descriptors.map { V2ModuleRegistry(descriptors: $0) } ?? registry,
            commands: commands.map(V2NativeCommandRegistry.init(descriptors:)),
            queries: queries.map(V2NativeQueryRegistry.init(descriptors:))
        )
    }

    public func update(
        preferences: V2ModulePreferences,
        registry nextRegistry: V2ModuleRegistry,
        commands nextCommands: V2NativeCommandRegistry? = nil,
        queries nextQueries: V2NativeQueryRegistry? = nil
    ) {
        stateLock.lock()
        defer { stateLock.unlock() }
        let oldRegistry = registry
        let oldPreferences = self.preferences
        let oldCommands = commandRegistry
        let nextCommandRegistry = nextCommands ?? oldCommands
        let nextQueryRegistry = nextQueries ?? queryRegistry
        var ids = Set(oldRegistry.descriptors.keys)
        ids.formUnion(nextRegistry.descriptors.keys)

        var seeds = Set<String>()
        for id in ids {
            if oldRegistry.descriptor(id) != nextRegistry.descriptor(id) {
                seeds.insert(id)
                continue
            }
            if oldRegistry.availability(id, preferences: oldPreferences)
                != nextRegistry.availability(id, preferences: preferences) {
                seeds.insert(id)
            }
        }

        var affected = seeds
        var changed = true
        while changed {
            changed = false
            for id in ids where !affected.contains(id) {
                let oldDependencies = oldRegistry.descriptor(id)?.dependencies ?? []
                let newDependencies = nextRegistry.descriptor(id)?.dependencies ?? []
                if (oldDependencies + newDependencies).contains(where: affected.contains) {
                    affected.insert(id)
                    changed = true
                }
            }
        }

        var changedCommands = Set(oldCommands.descriptors.keys)
        changedCommands.formUnion(nextCommandRegistry.descriptors.keys)
        var nextCommandGenerations = commandGenerations
        for commandID in changedCommands where oldCommands.descriptor(commandID) != nextCommandRegistry.descriptor(commandID) {
            nextCommandGenerations[commandID, default: 0] &+= 1
            if let descriptor = oldCommands.descriptor(commandID) { affected.insert(descriptor.moduleID) }
            if let descriptor = nextCommandRegistry.descriptor(commandID) { affected.insert(descriptor.moduleID) }
        }

        var changedQueries = Set(queryRegistry.descriptors.keys)
        changedQueries.formUnion(nextQueryRegistry.descriptors.keys)
        for queryID in changedQueries where queryRegistry.descriptor(queryID) != nextQueryRegistry.descriptor(queryID) {
            if let descriptor = queryRegistry.descriptor(queryID) { affected.insert(descriptor.moduleID) }
            if let descriptor = nextQueryRegistry.descriptor(queryID) { affected.insert(descriptor.moduleID) }
        }

        var nextGenerations = generations
        for id in nextRegistry.descriptors.keys where nextGenerations[id] == nil { nextGenerations[id] = 0 }
        for id in affected { nextGenerations[id, default: 0] &+= 1 }
        pruneLeases()
        for box in leases.values { box.value?.invalidateIfNeeded(affected, generations: nextGenerations) }
        cancelOwnedWork(for: affected)
        registry = nextRegistry
        self.preferences = preferences
        commandRegistry = nextCommandRegistry
        queryRegistry = nextQueryRegistry
        generations = nextGenerations
        commandGenerations = nextCommandGenerations
    }

    public func lifecycleState(_ id: String) -> V2NativeModuleState {
        withStateLock {
            guard registry.descriptor(id) != nil else { return .blocked }
            if preferences.disabled.contains(id) || (id.hasPrefix("core.") && preferences.disabled.contains(String(id.dropFirst(5)))) {
                return .disabled
            }
            if preferences.migrationHolds.contains(id) || (id.hasPrefix("core.") && preferences.migrationHolds.contains(String(id.dropFirst(5)))) {
                return .blocked
            }
            return registry.availability(id, preferences: preferences).isActive ? .active : .blocked
        }
    }

    public var lifecycleStates: [String: V2NativeModuleState] {
        withStateLock {
            Dictionary(uniqueKeysWithValues: registry.descriptors.keys.map { ($0, lifecycleState($0)) })
        }
    }

    public var nativeDefinitions: [V2NativeModuleDefinition] {
        withStateLock {
            registry.allDescriptors.map { descriptor in
                V2NativeModuleDefinition(
                    descriptor: descriptor,
                    commands: commandRegistry.allDescriptors.filter { $0.moduleID == descriptor.id },
                    queries: queryRegistry.allDescriptors.filter { $0.moduleID == descriptor.id }
                )
            }
        }
    }

    /// Snapshot of the currently executable native command directory. It is
    /// intentionally rebuilt from the registry and effective module state so
    /// callers never retain a stale disabled command list.
    public var commandCatalog: [V2NativeCommandDescriptor] {
        withStateLock {
            commandRegistry.allDescriptors.filter { lifecycleState($0.moduleID) == .active }
        }
    }

    public func commandDescriptor(_ id: String) -> V2NativeCommandDescriptor? {
        withStateLock {
            guard let descriptor = commandRegistry.descriptor(id), lifecycleState(descriptor.moduleID) == .active else {
                return nil
            }
            return descriptor
        }
    }

    public func queryCatalog(for moduleIDs: Set<String>? = nil) -> [V2NativeQueryDescriptor] {
        withStateLock {
            queryRegistry.allDescriptors.filter { descriptor in
                lifecycleState(descriptor.moduleID) == .active && (moduleIDs == nil || moduleIDs!.contains(descriptor.moduleID))
            }
        }
    }

    /// Register a route/tool/event contribution owned by a module. The token
    /// is also usable by tests and host adapters to stop a single contribution.
    @discardableResult
    public func registerContribution(
        moduleID: String,
        contributionID: String,
        cleanup: @escaping @Sendable () -> Void = {}
    ) throws -> V2ContributionToken {
        stateLock.lock()
        defer { stateLock.unlock() }
        try require([moduleID])
        let registrationID = UUID().uuidString
        let token = V2ContributionToken(moduleID: moduleID, contributionID: contributionID) { [weak self] in
            cleanup()
            if let self {
                self.contributions[moduleID]?.removeValue(forKey: registrationID)
            }
        }
        contributions[moduleID, default: [:]][registrationID] = token
        return token
    }

    @discardableResult
    public func registerJob(
        moduleID: String,
        jobID: String,
        cancel: @escaping @Sendable () -> Void
    ) throws -> V2ContributionToken {
        stateLock.lock()
        defer { stateLock.unlock() }
        try require([moduleID])
        let registrationID = UUID().uuidString
        let token = V2ContributionToken(moduleID: moduleID, contributionID: jobID) { [weak self] in
            cancel()
            if let self {
                self.jobs[moduleID]?.removeValue(forKey: registrationID)
            }
        }
        jobs[moduleID, default: [:]][registrationID] = token
        return token
    }

    public func cancelOwnedWork(for moduleIDs: Set<String>) {
        stateLock.lock()
        defer { stateLock.unlock() }
        let selected = moduleIDs
        for moduleID in selected {
            let ownedContributions = contributions[moduleID].map { Array($0.values) } ?? []
            let ownedJobs = jobs[moduleID].map { Array($0.values) } ?? []
            for token in ownedContributions { token.cancel() }
            for token in ownedJobs { token.cancel() }
            contributions[moduleID] = nil
            jobs[moduleID] = nil
        }
    }

    public func makeContext(
        for moduleID: String,
        assets: V2NativeAssetScope = .init(),
        send: @escaping @Sendable (V2NativeCommandEnvelope) throws -> V2NativeOperationReceipt,
        read: @escaping @Sendable (String, Int) throws -> Data,
        emitTrace: @escaping @Sendable (V2NativeTraceEvent) -> Void = { _ in },
        readRequest: (@Sendable (V2NativeQueryRequest) throws -> Data)? = nil
    ) throws -> V2ModuleContext {
        stateLock.lock()
        defer { stateLock.unlock() }
        try require([moduleID])
        let lease = try lease(for: [moduleID])
        let generation = lease.generations[moduleID] ?? 0
        let commandSnapshot = commandRegistry
        let querySnapshot = queryRegistry
        return V2ModuleContext(
            moduleID: moduleID,
            generation: generation,
            commands: V2NativeCommandClient(send: { [weak self] envelope in
                try lease.validate()
                guard envelope.callerModuleID == moduleID else {
                    throw V2ModuleRuntimeError.commandModuleMismatch(commandID: envelope.commandID, moduleID: envelope.callerModuleID)
                }
                guard let descriptor = commandSnapshot.descriptor(envelope.commandID), descriptor.moduleID == moduleID else {
                    throw V2ModuleRuntimeError.commandNotRegistered(envelope.commandID)
                }
                guard envelope.actor == "host", envelope.commandVersion == descriptor.version,
                      envelope.contractDigest == descriptor.contractDigest, envelope.moduleGeneration == generation,
                      !envelope.operationID.isEmpty, !envelope.idempotencyKey.isEmpty,
                      envelope.operationID.count <= 256, envelope.idempotencyKey.count <= 256,
                      envelope.grantRevision == 0 else { throw V2ModuleRuntimeError.commandNotRegistered(envelope.commandID) }
                guard let self else { throw V2ModuleRuntimeError.stale(id: moduleID, expected: generation, actual: nil) }
                try self.requireCommand(descriptor.id, modules: [moduleID])
                return try send(envelope)
            }),
            queries: V2NativeQueryClient(request: { [weak self] request in
                try lease.validate()
                guard let descriptor = querySnapshot.descriptor(request.id), descriptor.moduleID == moduleID,
                      (1...descriptor.maxPageSize).contains(request.limit) else {
                    throw V2ModuleRuntimeError.queryNotRegistered(request.id)
                }
                guard let self else { throw V2ModuleRuntimeError.stale(id: moduleID, expected: generation, actual: nil) }
                _ = try self.requireQuery(request)
                if let readRequest {
                    return try readRequest(request)
                }
                return try read(request.id, request.limit)
            }),
            assets: assets,
            registerJob: { [weak self] jobID, cancel in
                try lease.validate()
                guard let self else { throw V2ModuleRuntimeError.stale(id: moduleID, expected: generation, actual: nil) }
                return try self.registerJob(moduleID: moduleID, jobID: jobID, cancel: cancel)
            },
            emitTrace: emitTrace
        )
    }

    private func withStateLock<Result>(_ body: () throws -> Result) rethrows -> Result {
        stateLock.lock()
        defer { stateLock.unlock() }
        return try body()
    }

    private func pruneLeases() {
        leases = leases.filter { $0.value.value != nil }
    }

    private func collectDependencies(of id: String, into result: inout Set<String>) {
        guard result.insert(id).inserted, let descriptor = registry.descriptor(id) else { return }
        for dependency in descriptor.dependencies { collectDependencies(of: dependency, into: &result) }
    }
}

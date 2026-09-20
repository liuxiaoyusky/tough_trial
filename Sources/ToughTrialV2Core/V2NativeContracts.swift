import Foundation

/// The small, host-owned vocabulary shared by native modules and the dynamic
/// assistant catalog.  These types deliberately describe capabilities rather
/// than exposing an Engine or a mutable snapshot to a module.
public enum V2NativeConfirmationPolicy: String, Codable, Equatable, Sendable {
    case none
    case optionalStrict
    case humanAlways
}

public enum V2NativeAtomicity: String, Codable, Equatable, Sendable {
    case single
    case batch
    case crossModule
}

public enum V2NativeIdempotency: String, Codable, Equatable, Sendable {
    case none
    case request
    case sourceRevision
}

public enum V2NativeFieldType: String, Codable, Equatable, Sendable {
    case text
    case decimal
    case integer
    case boolean
    case date
    case enumID
    case recordRef
}

public struct V2NativeFieldConstraint: Codable, Equatable, Hashable, Sendable {
    public var minLength: Int?
    public var maxLength: Int?
    public var minimum: Decimal?
    public var maximum: Decimal?
    public var enumIDs: [String]
    public var multiple: Bool

    public init(
        minLength: Int? = nil,
        maxLength: Int? = nil,
        minimum: Decimal? = nil,
        maximum: Decimal? = nil,
        enumIDs: [String] = [],
        multiple: Bool = false
    ) {
        self.minLength = minLength
        self.maxLength = maxLength
        self.minimum = minimum
        self.maximum = maximum
        self.enumIDs = enumIDs
        self.multiple = multiple
    }
}

/// A schema field is namespaced by the domain and immutable ID.  Disabling a
/// field keeps old values readable; changing its type requires a new ID.
public struct V2NativeFieldDefinition: Codable, Equatable, Hashable, Sendable {
    public var id: String
    public var domainID: String
    public var type: V2NativeFieldType
    public var displayName: String
    public var constraints: V2NativeFieldConstraint
    public var required: Bool
    public var enabled: Bool
    public var revision: Int

    public init(
        id: String,
        domainID: String,
        type: V2NativeFieldType,
        displayName: String,
        constraints: V2NativeFieldConstraint = .init(),
        required: Bool = false,
        enabled: Bool = true,
        revision: Int = 1
    ) {
        self.id = id
        self.domainID = domainID
        self.type = type
        self.displayName = displayName
        self.constraints = constraints
        self.required = required
        self.enabled = enabled
        self.revision = revision
    }
}

public struct V2NativeCommandDescriptor: Codable, Equatable, Hashable, Sendable {
    public var id: String
    public var moduleID: String
    public var version: Int
    public var summary: String
    public var inputFields: [V2NativeFieldDefinition]
    public var requiredModules: [String]
    public var confirmation: V2NativeConfirmationPolicy
    public var atomicity: V2NativeAtomicity
    public var idempotency: V2NativeIdempotency
    public var undoable: Bool

    public init(
        id: String,
        moduleID: String,
        version: Int = 1,
        summary: String,
        inputFields: [V2NativeFieldDefinition] = [],
        requiredModules: [String]? = nil,
        confirmation: V2NativeConfirmationPolicy = .none,
        atomicity: V2NativeAtomicity = .single,
        idempotency: V2NativeIdempotency = .request,
        undoable: Bool = false
    ) {
        self.id = id
        self.moduleID = moduleID
        self.version = version
        self.summary = summary
        self.inputFields = inputFields
        self.requiredModules = requiredModules ?? [moduleID]
        self.confirmation = confirmation
        self.atomicity = atomicity
        self.idempotency = idempotency
        self.undoable = undoable
    }

    public var contractDigest: String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(self)) ?? Data()
        return data.map { String(format: "%02x", $0) }.joined()
    }

    public var commandID: String { id }
    public var inputSchema: [V2NativeFieldDefinition] { inputFields }
}

public struct V2NativeQueryDescriptor: Codable, Equatable, Hashable, Sendable {
    public var id: String
    public var moduleID: String
    public var summary: String
    public var projection: String
    public var maxPageSize: Int
    public var maxDays: Int?
    public var allowedFields: Set<String>

    public init(
        id: String,
        moduleID: String,
        summary: String,
        projection: String,
        maxPageSize: Int = 100,
        maxDays: Int? = nil,
        allowedFields: Set<String> = []
    ) {
        self.id = id
        self.moduleID = moduleID
        self.summary = summary
        self.projection = projection
        self.maxPageSize = max(1, min(maxPageSize, 500))
        self.maxDays = maxDays.map { max(1, min($0, 366)) }
        self.allowedFields = allowedFields
    }

    public var queryID: String { id }
}

public enum V2NativeRegistryError: Error, Equatable, LocalizedError, Sendable {
    case duplicateCommand(String)
    case duplicateQuery(String)
    case invalidCommandModule(commandID: String, moduleID: String)

    public var errorDescription: String? {
        switch self {
        case let .duplicateCommand(id): "命令 ID 重复：\(id)"
        case let .duplicateQuery(id): "查询 ID 重复：\(id)"
        case let .invalidCommandModule(commandID, moduleID): "命令 \(commandID) 的模块不存在：\(moduleID)"
        }
    }
}

/// The registry is value typed so it can be rebuilt atomically during module
/// activation. Duplicate IDs are rejected before a new directory is exposed.
public struct V2NativeCommandRegistry: Equatable, Sendable {
    public private(set) var descriptors: [String: V2NativeCommandDescriptor]

    public init(descriptors: [V2NativeCommandDescriptor] = V2NativeCommandDescriptor.builtins) {
        var values: [String: V2NativeCommandDescriptor] = [:]
        for descriptor in descriptors where values[descriptor.id] == nil {
            values[descriptor.id] = descriptor
        }
        self.descriptors = values
    }

    public init(validating descriptors: [V2NativeCommandDescriptor], knownModules: Set<String>) throws {
        var values: [String: V2NativeCommandDescriptor] = [:]
        for descriptor in descriptors {
            guard knownModules.contains(descriptor.moduleID) else {
                throw V2NativeRegistryError.invalidCommandModule(commandID: descriptor.id, moduleID: descriptor.moduleID)
            }
            guard values[descriptor.id] == nil else { throw V2NativeRegistryError.duplicateCommand(descriptor.id) }
            values[descriptor.id] = descriptor
        }
        self.descriptors = values
    }

    public var allDescriptors: [V2NativeCommandDescriptor] {
        descriptors.values.sorted { $0.id < $1.id }
    }

    public func descriptor(_ id: String) -> V2NativeCommandDescriptor? {
        descriptors[id]
    }

    public func descriptors(for modules: Set<String>) -> [V2NativeCommandDescriptor] {
        allDescriptors.filter { modules.contains($0.moduleID) || !Set($0.requiredModules).isDisjoint(with: modules) }
    }
}

public struct V2NativeQueryRegistry: Equatable, Sendable {
    public private(set) var descriptors: [String: V2NativeQueryDescriptor]

    public init(descriptors: [V2NativeQueryDescriptor] = V2NativeQueryDescriptor.builtins) {
        var values: [String: V2NativeQueryDescriptor] = [:]
        for descriptor in descriptors where values[descriptor.id] == nil {
            values[descriptor.id] = descriptor
        }
        self.descriptors = values
    }

    public init(validating descriptors: [V2NativeQueryDescriptor], knownModules: Set<String>) throws {
        var values: [String: V2NativeQueryDescriptor] = [:]
        for descriptor in descriptors {
            guard knownModules.contains(descriptor.moduleID) else {
                throw V2NativeRegistryError.invalidCommandModule(commandID: descriptor.id, moduleID: descriptor.moduleID)
            }
            guard values[descriptor.id] == nil else { throw V2NativeRegistryError.duplicateQuery(descriptor.id) }
            values[descriptor.id] = descriptor
        }
        self.descriptors = values
    }

    public var allDescriptors: [V2NativeQueryDescriptor] {
        descriptors.values.sorted { $0.id < $1.id }
    }

    public func descriptor(_ id: String) -> V2NativeQueryDescriptor? {
        descriptors[id]
    }
}

public struct V2NativeCommandEnvelope: Codable, Equatable, Sendable {
    public var operationID: String
    public var idempotencyKey: String
    /// Bound by the host, never trusted from model JSON. Module contexts must
    /// use their own module ID; assistant and importer calls use `host`.
    public var callerModuleID: String
    public var actor: String
    public var commandID: String
    public var commandVersion: Int
    public var contractDigest: String
    public var sourceReferences: [String]
    public var expectedRevisions: [String: Int]
    public var moduleGeneration: UInt64
    public var grantRevision: UInt64

    private enum CodingKeys: String, CodingKey {
        case operationID, idempotencyKey, callerModuleID, actor, commandID, commandVersion
        case contractDigest, sourceReferences, expectedRevisions, moduleGeneration, grantRevision
    }

    public init(
        operationID: String = UUID().uuidString,
        idempotencyKey: String,
        callerModuleID: String = "host",
        actor: String = "host",
        commandID: String,
        commandVersion: Int,
        contractDigest: String,
        sourceReferences: [String] = [],
        expectedRevisions: [String: Int] = [:],
        moduleGeneration: UInt64 = 0,
        grantRevision: UInt64 = 0
    ) {
        self.operationID = operationID
        self.idempotencyKey = idempotencyKey
        self.callerModuleID = callerModuleID
        self.actor = actor
        self.commandID = commandID
        self.commandVersion = commandVersion
        self.contractDigest = contractDigest
        self.sourceReferences = sourceReferences
        self.expectedRevisions = expectedRevisions
        self.moduleGeneration = moduleGeneration
        self.grantRevision = grantRevision
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        operationID = try container.decodeIfPresent(String.self, forKey: .operationID) ?? UUID().uuidString
        idempotencyKey = try container.decode(String.self, forKey: .idempotencyKey)
        callerModuleID = try container.decodeIfPresent(String.self, forKey: .callerModuleID) ?? "host"
        actor = try container.decodeIfPresent(String.self, forKey: .actor) ?? "host"
        commandID = try container.decode(String.self, forKey: .commandID)
        commandVersion = try container.decodeIfPresent(Int.self, forKey: .commandVersion) ?? 1
        contractDigest = try container.decodeIfPresent(String.self, forKey: .contractDigest) ?? ""
        sourceReferences = try container.decodeIfPresent([String].self, forKey: .sourceReferences) ?? []
        expectedRevisions = try container.decodeIfPresent([String: Int].self, forKey: .expectedRevisions) ?? [:]
        moduleGeneration = try container.decodeIfPresent(UInt64.self, forKey: .moduleGeneration) ?? 0
        grantRevision = try container.decodeIfPresent(UInt64.self, forKey: .grantRevision) ?? 0
    }
}

public enum V2NativeOperationStatus: String, Codable, Equatable, Sendable {
    case applied
    case pendingConfirmation
    case needsInformation
    case blocked
    case conflict
    case failed
    case cancelled
}

public struct V2NativeOperationReceipt: Codable, Equatable, Sendable {
    public var operationID: String
    public var idempotencyKey: String
    public var commandID: String
    public var status: V2NativeOperationStatus
    public var changedIDs: [String]
    public var undoRef: String?
    public var traceID: String?
    public var message: String?

    public init(
        operationID: String,
        idempotencyKey: String,
        commandID: String,
        status: V2NativeOperationStatus,
        changedIDs: [String] = [],
        undoRef: String? = nil,
        traceID: String? = nil,
        message: String? = nil
    ) {
        self.operationID = operationID
        self.idempotencyKey = idempotencyKey
        self.commandID = commandID
        self.status = status
        self.changedIDs = changedIDs
        self.undoRef = undoRef
        self.traceID = traceID
        self.message = message
    }
}

public enum V2NativeModuleState: String, Codable, Equatable, Sendable {
    case installed
    case validating
    case ready
    case active
    case stopping
    case disabled
    case blocked
    case failed
    case updating
}

public struct V2NativeTraceEvent: Codable, Equatable, Sendable {
    public var traceID: String
    public var moduleID: String
    public var commandID: String?
    public var phase: String
    public var resultCode: String?
    public var durationMilliseconds: Int?

    public init(
        traceID: String = UUID().uuidString,
        moduleID: String,
        commandID: String? = nil,
        phase: String,
        resultCode: String? = nil,
        durationMilliseconds: Int? = nil
    ) {
        self.traceID = traceID
        self.moduleID = moduleID
        self.commandID = commandID
        self.phase = phase
        self.resultCode = resultCode
        self.durationMilliseconds = durationMilliseconds
    }
}

public struct V2NativeAssetScope: Equatable, Sendable {
    public var assetIDs: Set<String>
    public init(assetIDs: Set<String> = []) { self.assetIDs = assetIDs }
    public func contains(_ id: String) -> Bool { assetIDs.contains(id) }
}

/// A bounded read request shared by the host and native module adapters.  A
/// query ID is still checked against the active registry by the receiver; the
/// request only carries filtering and pagination information and cannot grant
/// access to another domain.
public struct V2NativeQueryRequest: Codable, Equatable, Sendable {
    public var id: String
    public var limit: Int
    public var from: Date?
    public var to: Date?
    public var fields: Set<String>

    public init(
        id: String,
        limit: Int = 100,
        from: Date? = nil,
        to: Date? = nil,
        fields: Set<String> = []
    ) {
        self.id = id
        self.limit = limit
        self.from = from
        self.to = to
        self.fields = fields
    }
}

public enum V2NativeQueryError: Error, Equatable, LocalizedError, Sendable {
    case invalidDateRange
    case unsupportedField(String)
    case unsupportedProjection(String)

    public var errorDescription: String? {
        switch self {
        case .invalidDateRange: "查询日期范围无效或超出限制。"
        case let .unsupportedField(field): "查询字段未注册：\(field)。"
        case let .unsupportedProjection(id): "查询投影未提供：\(id)。"
        }
    }
}

// These read models are the stable, typed boundary used by UI and assistant
// adapters.  They intentionally contain only bounded projections, so an
// adapter never needs a mutable Engine or the complete app snapshot.
public struct V2NativeTasksTodayRead: Codable, Equatable, Sendable {
    public var date: Date
    public var planItems: [V2PlanItem]
    public var tasks: [V2Task]

    public init(date: Date, planItems: [V2PlanItem], tasks: [V2Task]) {
        self.date = date; self.planItems = planItems; self.tasks = tasks
    }
}

public struct V2NativeTasksWorkspaceRead: Codable, Equatable, Sendable {
    public var contexts: [V2TaskContext]
    public var tasks: [V2Task]
    public var planDrafts: [V2PlanDraftRecord]
    public var planItems: [V2PlanItem]

    public init(contexts: [V2TaskContext], tasks: [V2Task], planDrafts: [V2PlanDraftRecord], planItems: [V2PlanItem]) {
        self.contexts = contexts; self.tasks = tasks; self.planDrafts = planDrafts; self.planItems = planItems
    }
}

public struct V2NativeExecutionRead: Codable, Equatable, Sendable {
    public var segments: [V2ExecutionSegment]
    public init(segments: [V2ExecutionSegment]) { self.segments = segments }
}

public struct V2NativeCaptureRead: Codable, Equatable, Sendable {
    public var entries: [V2CaptureEntry]
    public var batches: [V2CaptureBatch]
    public var receipts: [V2CaptureReceipt]

    public init(entries: [V2CaptureEntry], batches: [V2CaptureBatch], receipts: [V2CaptureReceipt]) {
        self.entries = entries; self.batches = batches; self.receipts = receipts
    }
}

public struct V2NativeLedgerRead: Codable, Equatable, Sendable {
    public var entries: [V2LedgerEntry]
    public var categories: [V2LedgerCategory]

    public init(entries: [V2LedgerEntry], categories: [V2LedgerCategory]) {
        self.entries = entries; self.categories = categories
    }
}

public struct V2NativeFinanceRead: Codable, Equatable, Sendable {
    public var plans: [V2FinancePlan]
    public var payments: [V2FinancePayment]

    public init(plans: [V2FinancePlan], payments: [V2FinancePayment]) {
        self.plans = plans; self.payments = payments
    }
}

public struct V2NativeBudgetProgressRead: Codable, Equatable, Sendable {
    public var budgets: [V2Budget]
    public var progress: [V2BudgetProgress]

    public init(budgets: [V2Budget], progress: [V2BudgetProgress]) {
        self.budgets = budgets; self.progress = progress
    }
}

public struct V2NativeRecallRead: Codable, Equatable, Sendable {
    public var entries: [V2RecallEntry]
    public init(entries: [V2RecallEntry]) { self.entries = entries }
}

public struct V2NativeNotesRead: Codable, Equatable, Sendable {
    public var entries: [V2CaptureNote]
    public init(entries: [V2CaptureNote]) { self.entries = entries }
}

public struct V2NativeImportRead: Codable, Equatable, Sendable {
    public var receipts: [V2ExternalImportReceipt]
    public init(receipts: [V2ExternalImportReceipt]) { self.receipts = receipts }
}

public struct V2NativeAssetRead: Codable, Equatable, Sendable {
    public var assets: [V2CaptureAsset]
    public init(assets: [V2CaptureAsset]) { self.assets = assets }
}

public struct V2NativeFieldRead: Codable, Equatable, Sendable {
    public var definitions: [V2NativeFieldDefinition]
    public init(definitions: [V2NativeFieldDefinition]) { self.definitions = definitions }
}

public struct V2NativeTraceRead: Codable, Equatable, Sendable {
    public var events: [V2UsageEvent]
    public init(events: [V2UsageEvent]) { self.events = events }
}

public struct V2NativeCommandClient: Sendable {
    private let send: @Sendable (V2NativeCommandEnvelope) throws -> V2NativeOperationReceipt

    public init(send: @escaping @Sendable (V2NativeCommandEnvelope) throws -> V2NativeOperationReceipt) {
        self.send = send
    }

    public func invoke(_ envelope: V2NativeCommandEnvelope) throws -> V2NativeOperationReceipt {
        try send(envelope)
    }
}

public struct V2NativeQueryClient: Sendable {
    private let read: @Sendable (V2NativeQueryRequest) throws -> Data

    public init(read: @escaping @Sendable (String, Int) throws -> Data) {
        self.read = { request in try read(request.id, request.limit) }
    }

    public init(request: @escaping @Sendable (V2NativeQueryRequest) throws -> Data) {
        self.read = request
    }

    public func query(id: String, limit: Int = 100) throws -> Data {
        try read(.init(id: id, limit: limit))
    }

    public func query(_ request: V2NativeQueryRequest) throws -> Data {
        try read(request)
    }
}

/// Module code receives this restricted context. It cannot obtain the host
/// Engine, the complete snapshot, Keychain values, arbitrary paths, or a
/// general-purpose executor.
public struct V2ModuleContext: Sendable {
    public let moduleID: String
    public let generation: UInt64
    public let commands: V2NativeCommandClient
    public let queries: V2NativeQueryClient
    public let assets: V2NativeAssetScope
    public let registerJob: @Sendable (String, @escaping @Sendable () -> Void) throws -> V2ContributionToken
    public let emitTrace: @Sendable (V2NativeTraceEvent) -> Void

    public init(
        moduleID: String,
        generation: UInt64,
        commands: V2NativeCommandClient,
        queries: V2NativeQueryClient,
        assets: V2NativeAssetScope = .init(),
        registerJob: @escaping @Sendable (String, @escaping @Sendable () -> Void) throws -> V2ContributionToken,
        emitTrace: @escaping @Sendable (V2NativeTraceEvent) -> Void = { _ in }
    ) {
        self.moduleID = moduleID
        self.generation = generation
        self.commands = commands
        self.queries = queries
        self.assets = assets
        self.registerJob = registerJob
        self.emitTrace = emitTrace
    }
}

/// Every route/tool/event/job registered by a module is tied to this token.
/// Stopping a module invalidates the token and executes its cleanup exactly
/// once, which prevents old callbacks from reappearing after re-enable.
public final class V2ContributionToken: @unchecked Sendable {
    public let moduleID: String
    public let contributionID: String
    let registrationID = UUID().uuidString
    private let lock = NSLock()
    private var cleanup: (@Sendable () -> Void)?

    init(moduleID: String, contributionID: String, cleanup: @escaping @Sendable () -> Void) {
        self.moduleID = moduleID
        self.contributionID = contributionID
        self.cleanup = cleanup
    }

    public var isActive: Bool {
        lock.lock(); defer { lock.unlock() }
        return cleanup != nil
    }

    public func cancel() {
        lock.lock()
        let action = cleanup
        cleanup = nil
        lock.unlock()
        action?()
    }

    deinit { cancel() }
}

public struct V2NativeModuleDefinition: Equatable, Sendable {
    public var descriptor: V2ModuleDescriptor
    public var commands: [V2NativeCommandDescriptor]
    public var queries: [V2NativeQueryDescriptor]

    public init(
        descriptor: V2ModuleDescriptor,
        commands: [V2NativeCommandDescriptor] = [],
        queries: [V2NativeQueryDescriptor] = []
    ) {
        self.descriptor = descriptor
        self.commands = commands
        self.queries = queries
    }
}

public extension V2NativeCommandDescriptor {
    private static func field(
        _ id: String,
        _ domainID: String,
        _ type: V2NativeFieldType = .text,
        required: Bool = false,
        multiple: Bool = false
    ) -> V2NativeFieldDefinition {
        .init(
            id: id,
            domainID: domainID,
            type: type,
            displayName: id,
            constraints: .init(multiple: multiple),
            required: required
        )
    }

    static let builtins: [Self] = [
        .init(id: "core.tasks.createContext", moduleID: "core.tasks", summary: "创建任务上下文", inputFields: [field("title", "core.tasks", required: true), field("note", "core.tasks")], idempotency: .request),
        .init(id: "core.tasks.create", moduleID: "core.tasks", summary: "创建任务", inputFields: [field("title", "core.tasks", required: true), field("note", "core.tasks"), field("parentID", "core.tasks"), field("contextID", "core.tasks")], idempotency: .sourceRevision),
        .init(id: "core.tasks.update", moduleID: "core.tasks", summary: "修改任务", inputFields: [field("id", "core.tasks", required: true), field("title", "core.tasks", required: true), field("note", "core.tasks"), field("parentID", "core.tasks"), field("contextID", "core.tasks")], idempotency: .sourceRevision),
        .init(id: "core.tasks.archive", moduleID: "core.tasks", summary: "归档任务", idempotency: .request),
        .init(id: "core.tasks.schedule", moduleID: "core.tasks", summary: "安排任务到某天", inputFields: [field("taskID", "core.tasks", required: true), field("date", "core.tasks", .date, required: true), field("startMinute", "core.tasks"), field("durationMinutes", "core.tasks")], atomicity: .batch, idempotency: .sourceRevision, undoable: true),
        .init(id: "core.tasks.undoSchedule", moduleID: "core.tasks", summary: "撤销任务排期", atomicity: .batch, idempotency: .request),
        .init(id: "core.tasks.complete", moduleID: "core.tasks", summary: "完成任务", idempotency: .request),
        .init(id: "core.tasks.restore", moduleID: "core.tasks", summary: "恢复任务", idempotency: .request),
        .init(id: "core.tasks.startExecution", moduleID: "core.tasks", summary: "开始执行任务", idempotency: .request),
        .init(id: "core.tasks.pauseExecution", moduleID: "core.tasks", summary: "暂停任务执行", idempotency: .request),
        .init(id: "core.tasks.endExecution", moduleID: "core.tasks", summary: "结束任务执行", idempotency: .request),
        .init(id: "core.tasks.resumeExecution", moduleID: "core.tasks", summary: "恢复任务执行", idempotency: .request),
        .init(id: "core.tasks.stopExecution", moduleID: "core.tasks", summary: "停止任务执行", idempotency: .request),
        .init(id: "core.tasks.planDraft.save", moduleID: "core.tasks", summary: "保存计划草稿", idempotency: .sourceRevision),
        .init(id: "core.tasks.planDraft.accept", moduleID: "core.tasks", summary: "接受计划草稿", atomicity: .batch, idempotency: .request),
        .init(id: "core.tasks.planDraft.discard", moduleID: "core.tasks", summary: "丢弃计划草稿", idempotency: .request),
        .init(id: "core.tasks.import", moduleID: "core.tasks", summary: "导入任务", atomicity: .batch, idempotency: .sourceRevision),
        .init(id: "core.capture.create", moduleID: "core.capture", summary: "保存原始随手记", inputFields: [field("text", "core.capture", required: true), field("assetIDs", "core.capture", .recordRef, multiple: true)], idempotency: .sourceRevision),
        .init(id: "core.capture.stage", moduleID: "core.capture", summary: "保存整理候选", idempotency: .sourceRevision),
        .init(id: "core.capture.reviseCandidate", moduleID: "core.capture", summary: "修订账单整理候选", inputFields: [field("batchID", "core.capture", .recordRef, required: true), field("candidateID", "core.capture", .recordRef, required: true), field("sourceRevision", "core.capture", .integer, required: true), field("draft", "core.capture", required: true)], idempotency: .sourceRevision),
        .init(id: "core.capture.confirmLedgerCandidate", moduleID: "core.capture", summary: "确认修正并写入账单", inputFields: [field("batchID", "core.capture", .recordRef, required: true), field("candidateID", "core.capture", .recordRef, required: true), field("sourceRevision", "core.capture", .integer, required: true), field("draft", "core.capture", required: true)], requiredModules: ["core.capture", "core.ledger"], confirmation: .humanAlways, atomicity: .crossModule, idempotency: .sourceRevision, undoable: true),
        .init(id: "core.capture.apply", moduleID: "core.capture", summary: "应用整理候选", atomicity: .crossModule, idempotency: .sourceRevision, undoable: true),
        .init(id: "core.capture.replace", moduleID: "core.capture", summary: "替换整理结果", confirmation: .humanAlways, atomicity: .crossModule, idempotency: .sourceRevision),
        .init(id: "core.capture.reject", moduleID: "core.capture", summary: "拒绝整理候选", idempotency: .request),
        .init(id: "core.capture.undo", moduleID: "core.capture", summary: "撤销整理结果", atomicity: .crossModule, idempotency: .request),
        .init(id: "core.attachments.save", moduleID: "core.attachments", summary: "保存用户选择的附件", idempotency: .sourceRevision),
        .init(id: "core.speech.save", moduleID: "core.speech", summary: "保存语音原件", idempotency: .sourceRevision),
        .init(id: "core.imports.saveAsset", moduleID: "core.imports", summary: "保存导入原件", idempotency: .sourceRevision),
        .init(id: "core.ledger.createPending", moduleID: "core.ledger", summary: "创建待确认账单", inputFields: [field("amount", "core.ledger", .decimal, required: true), field("currency", "core.ledger", required: true), field("text", "core.ledger", required: true), field("direction", "core.ledger", .enumID, required: true), field("localDate", "core.ledger", .date)], idempotency: .sourceRevision),
        .init(id: "core.ledger.createCategory", moduleID: "core.ledger", summary: "创建账单分类", confirmation: .humanAlways, idempotency: .request),
        .init(id: "core.ledger.proposeCategory", moduleID: "core.ledger", summary: "提出账单分类建议", inputFields: [field("ledgerID", "core.ledger", required: true), field("categoryName", "core.ledger", required: true)], confirmation: .humanAlways, idempotency: .sourceRevision),
        .init(id: "core.ledger.confirmCategory", moduleID: "core.ledger", summary: "确认账单分类", confirmation: .humanAlways, idempotency: .sourceRevision, undoable: true),
        .init(id: "core.ledger.mergeCategories", moduleID: "core.ledger", summary: "合并账单分类", confirmation: .humanAlways, idempotency: .request, undoable: true),
        .init(id: "core.ledger.undoCategory", moduleID: "core.ledger", summary: "撤销分类变更", confirmation: .humanAlways, idempotency: .request),
        .init(id: "core.finance.createPlan", moduleID: "core.finance", summary: "创建订阅或还款计划", inputFields: [field("title", "core.finance", required: true), field("kind", "core.finance", .enumID, required: true), field("amount", "core.finance", .decimal, required: true), field("currency", "core.finance", required: true), field("dueDate", "core.finance", .date, required: true), field("recurrence", "core.finance", .enumID)], idempotency: .sourceRevision),
        .init(id: "core.finance.setPlanActive", moduleID: "core.finance", summary: "启用或停用财务计划", idempotency: .sourceRevision),
        .init(id: "core.finance.markPaid", moduleID: "core.finance", summary: "确认计划已支付", inputFields: [field("planID", "core.finance", required: true), field("dueDate", "core.finance", .date, required: true)], confirmation: .humanAlways, atomicity: .crossModule, idempotency: .sourceRevision, undoable: true),
        .init(id: "core.finance.undoPayment", moduleID: "core.finance", summary: "撤销支付记录", confirmation: .humanAlways, atomicity: .crossModule, idempotency: .request),
        .init(id: "core.budget.set", moduleID: "core.budget", summary: "设置预算", inputFields: [field("id", "core.budget", required: true), field("amount", "core.budget", .decimal, required: true), field("currency", "core.budget", required: true), field("month", "core.budget", required: true), field("categoryID", "core.budget")], idempotency: .sourceRevision),
        .init(id: "core.budget.remove", moduleID: "core.budget", summary: "删除预算", idempotency: .request),
        .init(id: "core.recall.append", moduleID: "core.recall", summary: "追加当天回想", inputFields: [field("text", "core.recall", required: true), field("date", "core.recall", .date, required: true)], idempotency: .sourceRevision),
        .init(id: "core.recall.update", moduleID: "core.recall", summary: "修改当天回想", idempotency: .sourceRevision),
        .init(id: "core.notes.create", moduleID: "core.notes", summary: "保存灵感或收纳内容", inputFields: [field("text", "core.notes", required: true), field("title", "core.notes")], idempotency: .sourceRevision),
        .init(id: "core.notes.update", moduleID: "core.notes", summary: "修改灵感或收纳内容", idempotency: .sourceRevision),
        .init(id: "core.notes.delete", moduleID: "core.notes", summary: "删除灵感或收纳内容", idempotency: .request),
        .init(id: "core.assistant.session.save", moduleID: "core.assistant", summary: "保存助手会话回合", idempotency: .request),
        .init(id: "core.web.open", moduleID: "core.web", summary: "打开用户选择的网页", idempotency: .request),
        .init(id: "core.speech.transcribe", moduleID: "core.speech", summary: "转写用户选择的语音", idempotency: .sourceRevision),
        .init(id: "core.traceViewer.export", moduleID: "core.traceViewer", summary: "导出不含正文的诊断记录", idempotency: .request),
        .init(id: "core.tasks.fields.define", moduleID: "core.tasks", summary: "定义任务扩展字段", confirmation: .humanAlways, idempotency: .request),
        .init(id: "core.tasks.attributes.set", moduleID: "core.tasks", summary: "填写任务扩展字段", confirmation: .optionalStrict, idempotency: .sourceRevision),
        .init(id: "core.capture.fields.define", moduleID: "core.capture", summary: "定义随手记扩展字段", confirmation: .humanAlways, idempotency: .request),
        .init(id: "core.capture.attributes.set", moduleID: "core.capture", summary: "填写随手记扩展字段", confirmation: .optionalStrict, idempotency: .sourceRevision),
        .init(id: "core.ledger.fields.define", moduleID: "core.ledger", summary: "定义账单扩展字段", confirmation: .humanAlways, idempotency: .request),
        .init(id: "core.ledger.attributes.set", moduleID: "core.ledger", summary: "填写账单扩展字段", confirmation: .optionalStrict, idempotency: .sourceRevision),
        .init(id: "core.finance.fields.define", moduleID: "core.finance", summary: "定义财务扩展字段", confirmation: .humanAlways, idempotency: .request),
        .init(id: "core.finance.attributes.set", moduleID: "core.finance", summary: "填写财务扩展字段", confirmation: .optionalStrict, idempotency: .sourceRevision),
        .init(id: "core.budget.fields.define", moduleID: "core.budget", summary: "定义预算扩展字段", confirmation: .humanAlways, idempotency: .request),
        .init(id: "core.budget.attributes.set", moduleID: "core.budget", summary: "填写预算扩展字段", confirmation: .optionalStrict, idempotency: .sourceRevision),
        .init(id: "core.recall.fields.define", moduleID: "core.recall", summary: "定义回想扩展字段", confirmation: .humanAlways, idempotency: .request),
        .init(id: "core.recall.attributes.set", moduleID: "core.recall", summary: "填写回想扩展字段", confirmation: .optionalStrict, idempotency: .sourceRevision),
        .init(id: "core.notes.fields.define", moduleID: "core.notes", summary: "定义收纳扩展字段", confirmation: .humanAlways, idempotency: .request),
        .init(id: "core.notes.attributes.set", moduleID: "core.notes", summary: "填写收纳扩展字段", confirmation: .optionalStrict, idempotency: .sourceRevision),
        .init(id: "core.imports.create", moduleID: "core.imports", summary: "导入外部记录", atomicity: .batch, idempotency: .sourceRevision),
        .init(id: "core.sync.prepare", moduleID: "core.sync", summary: "准备日程同步文档", idempotency: .request),
        .init(id: "core.sync.import", moduleID: "core.sync", summary: "导入日程同步文档", atomicity: .batch, idempotency: .sourceRevision),
        .init(id: "core.sync.write", moduleID: "core.sync", summary: "记录日程文件写入", idempotency: .sourceRevision),
        .init(id: "core.sync.configure", moduleID: "core.sync", summary: "配置日程同步", idempotency: .sourceRevision),
        .init(id: "core.sync.begin", moduleID: "core.sync", summary: "开始日程同步", idempotency: .request),
        .init(id: "core.sync.accept", moduleID: "core.sync", summary: "接受同步结果", atomicity: .batch, idempotency: .sourceRevision, undoable: true),
        .init(id: "core.sync.fail", moduleID: "core.sync", summary: "记录同步失败", idempotency: .request),
        .init(id: "core.sync.refreshConflict", moduleID: "core.sync", summary: "刷新同步冲突", idempotency: .sourceRevision),
        .init(id: "core.sync.resolveConflict", moduleID: "core.sync", summary: "应用同步冲突解决", confirmation: .optionalStrict, atomicity: .batch, idempotency: .sourceRevision, undoable: true)
    ]
}

public extension V2NativeQueryDescriptor {
    static let builtins: [Self] = [
        .init(id: "core.tasks.today", moduleID: "core.tasks", summary: "读取指定日期的执行项", projection: "today.items", maxPageSize: 100, maxDays: 1),
        .init(id: "core.tasks.workspace", moduleID: "core.tasks", summary: "读取有限任务规划工作区", projection: "planning.workspace", maxPageSize: 200),
        .init(id: "core.tasks.execution", moduleID: "core.tasks", summary: "读取执行证据", projection: "execution.segments", maxPageSize: 200, maxDays: 31),
        .init(id: "core.capture.recent", moduleID: "core.capture", summary: "读取最近原始记录", projection: "capture.entries", maxPageSize: 100, maxDays: 30),
        .init(id: "core.ledger.recent", moduleID: "core.ledger", summary: "读取最近账单", projection: "ledger.entries", maxPageSize: 100, maxDays: 31),
        .init(id: "core.finance.plans", moduleID: "core.finance", summary: "读取订阅与还款计划", projection: "finance.plans", maxPageSize: 100),
        .init(id: "core.budget.queryProgress", moduleID: "core.budget", summary: "读取预算进度", projection: "budget.progress", maxPageSize: 100),
        .init(id: "core.recall.recent", moduleID: "core.recall", summary: "读取近期回想", projection: "recall.entries", maxPageSize: 31, maxDays: 31),
        .init(id: "core.notes.recent", moduleID: "core.notes", summary: "读取近期灵感与收纳", projection: "notes.entries", maxPageSize: 100, maxDays: 90),
        .init(id: "core.imports.recent", moduleID: "core.imports", summary: "读取外部导入记录", projection: "imports.receipts", maxPageSize: 100, maxDays: 90),
        .init(id: "core.attachments.recent", moduleID: "core.attachments", summary: "读取附件索引", projection: "attachments.assets", maxPageSize: 100),
        .init(id: "core.tasks.fields", moduleID: "core.tasks", summary: "读取任务扩展字段定义", projection: "fields.tasks", maxPageSize: 100),
        .init(id: "core.capture.fields", moduleID: "core.capture", summary: "读取随手记扩展字段定义", projection: "fields.capture", maxPageSize: 100),
        .init(id: "core.ledger.fields", moduleID: "core.ledger", summary: "读取账单扩展字段定义", projection: "fields.ledger", maxPageSize: 100),
        .init(id: "core.finance.fields", moduleID: "core.finance", summary: "读取财务扩展字段定义", projection: "fields.finance", maxPageSize: 100),
        .init(id: "core.budget.fields", moduleID: "core.budget", summary: "读取预算扩展字段定义", projection: "fields.budget", maxPageSize: 100),
        .init(id: "core.recall.fields", moduleID: "core.recall", summary: "读取回想扩展字段定义", projection: "fields.recall", maxPageSize: 100),
        .init(id: "core.notes.fields", moduleID: "core.notes", summary: "读取收纳扩展字段定义", projection: "fields.notes", maxPageSize: 100),
        .init(id: "core.trace.recent", moduleID: "core.traceViewer", summary: "读取不含正文的使用记录", projection: "trace.events", maxPageSize: 200, maxDays: 30)
    ]
}

public extension V2NativeModuleDefinition {
    static var builtins: [Self] {
        V2ModuleDescriptor.builtins.map { descriptor in
            .init(
                descriptor: descriptor,
                commands: V2NativeCommandDescriptor.builtins.filter { $0.moduleID == descriptor.id },
                queries: V2NativeQueryDescriptor.builtins.filter { $0.moduleID == descriptor.id }
            )
        }
    }
}

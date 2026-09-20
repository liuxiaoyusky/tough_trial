import Foundation

/// The small set of values that a model may submit to a registered tool.
/// Domain commands remain responsible for their final validation; this layer
/// rejects fields and value shapes that must never cross the model boundary.
public enum V2ToolJSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case boolean(Bool)
    case object([String: V2ToolJSONValue])
    case array([V2ToolJSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? container.decode(Double.self) {
            guard value.isFinite else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "非有限数字")
            }
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: V2ToolJSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([V2ToolJSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "工具参数值无法解析")
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case let .string(value):
            try value.encode(to: encoder)
        case let .number(value):
            try value.encode(to: encoder)
        case let .boolean(value):
            try value.encode(to: encoder)
        case let .object(value):
            try value.encode(to: encoder)
        case let .array(value):
            try value.encode(to: encoder)
        case .null:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        }
    }

    public var stringValue: String? {
        if case let .string(value) = self { return value }
        return nil
    }

    public var decimalValue: Double? {
        switch self {
        case let .number(value): return value
        case let .string(value): return Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
        default: return nil
        }
    }
}

public enum V2ToolFieldType: String, Codable, Equatable, Sendable {
    case text
    case decimal
    case integer
    case boolean
    case date
    case enumID
    /// A human-readable reference such as a plan title or a task phrase.
    /// It is deliberately not a persistent object ID.
    case recordReference
}

public struct V2ToolFieldDefinition: Codable, Equatable, Hashable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let type: V2ToolFieldType
    public let required: Bool
    public let maxLength: Int?
    public let enumValues: [String]

    public init(
        id: String,
        label: String,
        type: V2ToolFieldType,
        required: Bool = false,
        maxLength: Int? = nil,
        enumValues: [String] = []
    ) {
        self.id = id
        self.label = label
        self.type = type
        self.required = required
        self.maxLength = maxLength
        self.enumValues = enumValues
    }
}

public struct V2ToolInputSchema: Codable, Equatable, Hashable, Sendable {
    public let fields: [V2ToolFieldDefinition]
    public let allowsAdditionalProperties: Bool

    public init(fields: [V2ToolFieldDefinition], allowsAdditionalProperties: Bool = false) {
        self.fields = fields
        self.allowsAdditionalProperties = allowsAdditionalProperties
    }

    public var requiredFieldIDs: Set<String> {
        Set(fields.filter(\.required).map(\.id))
    }

    public func field(_ id: String) -> V2ToolFieldDefinition? {
        fields.first { $0.id == id }
    }
}

public enum V2ToolSchemaError: Error, LocalizedError, Equatable, Sendable {
    case malformedArguments
    case unknownToolField(String)
    case missingRequiredField(String)
    case invalidField(String, String)
    case forbiddenField(String)
    case unknownTool(String)
    case unavailableTool(String)
    case staleCatalog
    case duplicateTool(String)

    public var errorDescription: String? {
        switch self {
        case .malformedArguments:
            return "工具参数不是有效对象。"
        case let .unknownToolField(field):
            return "工具参数包含未登记字段：" + field
        case let .missingRequiredField(field):
            return "工具参数缺少必填字段：" + field
        case let .invalidField(field, reason):
            return "工具参数字段 " + field + " 无效：" + reason
        case let .forbiddenField(field):
            return "工具参数不能包含宿主字段：" + field
        case let .unknownTool(tool):
            return "工具未登记：" + tool
        case let .unavailableTool(tool):
            return "工具当前不可用：" + tool
        case .staleCatalog:
            return "工具目录已变化，请重新整理这条请求。"
        case let .duplicateTool(tool):
            return "工具登记重复：" + tool
        }
    }
}

public struct V2ToolArguments: Equatable, Sendable {
    public let values: [String: V2ToolJSONValue]
    public let json: Data

    public init(values: [String: V2ToolJSONValue], json: Data) {
        self.values = values
        self.json = json
    }

    public subscript(_ field: String) -> V2ToolJSONValue? { values[field] }

    public func string(_ field: String) -> String? { values[field]?.stringValue }

    public func decimal(_ field: String) -> Double? { values[field]?.decimalValue }

    public func integer(_ field: String) -> Int? {
        guard let value = decimal(field), value.rounded() == value else { return nil }
        return Int(exactly: value)
    }

    public func bool(_ field: String) -> Bool? {
        guard case let .boolean(value) = values[field] else { return nil }
        return value
    }

    public static func parse(_ data: Data, using schema: V2ToolInputSchema) throws -> Self {
        let decoded: V2ToolJSONValue
        do {
            decoded = try JSONDecoder().decode(V2ToolJSONValue.self, from: data)
        } catch {
            throw V2ToolSchemaError.malformedArguments
        }
        guard case let .object(values) = decoded else {
            throw V2ToolSchemaError.malformedArguments
        }

        let fields = Dictionary(uniqueKeysWithValues: schema.fields.map { ($0.id, $0) })
        for key in values.keys.sorted() {
            guard let field = fields[key] else {
                if Self.isForbiddenHostField(key) {
                    throw V2ToolSchemaError.forbiddenField(key)
                }
                if !schema.allowsAdditionalProperties {
                    throw V2ToolSchemaError.unknownToolField(key)
                }
                // An extension schema may accept user-defined values, but it
                // can never opt out of the host-authority boundary. Inspect
                // unknown values recursively before retaining them.
                if let value = values[key] {
                    try Self.validateNoForbiddenKeys(in: value)
                }
                continue
            }
            guard !Self.isForbiddenHostField(key) else {
                throw V2ToolSchemaError.forbiddenField(key)
            }
            guard let value = values[key] else { continue }
            try Self.validateNoForbiddenKeys(in: value)
            try Self.validate(value, for: field)
        }
        for field in schema.fields where field.required {
            guard let value = values[field.id], !Self.isEmpty(value) else {
                throw V2ToolSchemaError.missingRequiredField(field.id)
            }
        }

        let normalized = try JSONEncoder.sorted.encode(values)
        return Self(values: values, json: normalized)
    }

    private static func validate(_ value: V2ToolJSONValue, for field: V2ToolFieldDefinition) throws {
        switch field.type {
        case .text, .date, .enumID, .recordReference:
            guard case let .string(text) = value else {
                throw V2ToolSchemaError.invalidField(field.id, "需要文字")
            }
            let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else {
                throw V2ToolSchemaError.invalidField(field.id, "不能为空")
            }
            if let maxLength = field.maxLength, normalized.count > maxLength {
                throw V2ToolSchemaError.invalidField(field.id, "长度超过限制")
            }
            if field.type == .enumID && !field.enumValues.isEmpty && !field.enumValues.contains(normalized) {
                throw V2ToolSchemaError.invalidField(field.id, "不在已登记选项中")
            }
            if field.type == .date {
                guard Self.isISODate(normalized) else {
                    throw V2ToolSchemaError.invalidField(field.id, "需要 YYYY-MM-DD 日期")
                }
            }
        case .decimal:
            guard let decimal = value.decimalValue, decimal.isFinite, abs(decimal) <= 1_000_000_000_000 else {
                throw V2ToolSchemaError.invalidField(field.id, "需要有限数字")
            }
        case .integer:
            guard let decimal = value.decimalValue, decimal.isFinite, decimal.rounded() == decimal,
                  abs(decimal) <= 2_147_483_647 else {
                throw V2ToolSchemaError.invalidField(field.id, "需要整数")
            }
        case .boolean:
            guard case .boolean = value else {
                throw V2ToolSchemaError.invalidField(field.id, "需要布尔值")
            }
        }
    }

    private static func isEmpty(_ value: V2ToolJSONValue) -> Bool {
        if case let .string(text) = value {
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return false
    }

    private static func isISODate(_ value: String) -> Bool {
        let components = value.split(separator: "-", omittingEmptySubsequences: false)
        guard components.count == 3,
              components[0].count == 4,
              components[1].count == 2,
              components[2].count == 2,
              let year = Int(components[0]),
              let month = Int(components[1]),
              let day = Int(components[2]),
              (1...9_999).contains(year),
              (1...12).contains(month) else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: date) else { return false }
        return range.contains(day)
    }

    /// These names represent authority or storage details. They are never
    /// accepted from a model even when a future descriptor accidentally opts
    /// into additional properties.
    public static func isForbiddenHostField(_ raw: String) -> Bool {
        let key = raw.lowercased().replacingOccurrences(of: "_", with: "")
        let exact = [
            "id", "userid", "moduleid", "caller", "actorkind", "operationid",
            "idempotencykey", "traceid", "generation", "grantrevision", "confirmed",
            "confirmation", "confirmationreceipt", "token", "apikey", "secret",
            "password", "path", "filepath", "fileurl", "attachmentpath", "sandbox"
        ]
        return exact.contains(key)
            || key.hasSuffix("operationid")
            || key.hasSuffix("idempotencykey")
            || key.hasSuffix("confirmationreceipt")
            || key.hasSuffix("filepath")
    }

    private static func validateNoForbiddenKeys(in value: V2ToolJSONValue) throws {
        switch value {
        case let .object(object):
            for key in object.keys where isForbiddenHostField(key) {
                throw V2ToolSchemaError.forbiddenField(key)
            }
            for nested in object.values {
                try validateNoForbiddenKeys(in: nested)
            }
        case let .array(values):
            for nested in values {
                try validateNoForbiddenKeys(in: nested)
            }
        default:
            break
        }
    }
}

public struct V2ToolDescriptor: Codable, Equatable, Hashable, Sendable, Identifiable {
    public enum ConfirmationPolicy: String, Codable, Equatable, Hashable, Sendable {
        case automatic
        case humanAlways
    }

    public let id: String
    public let moduleID: String
    public let title: String
    public let purpose: String
    public let inputSchema: V2ToolInputSchema
    public let requiredModules: [String]
    public let confirmationPolicy: ConfirmationPolicy
    public let canUndo: Bool
    public let readOnly: Bool
    public let contractVersion: Int

    public init(
        id: String,
        moduleID: String,
        title: String,
        purpose: String,
        inputSchema: V2ToolInputSchema,
        requiredModules: [String] = [],
        confirmationPolicy: ConfirmationPolicy = .automatic,
        canUndo: Bool = false,
        readOnly: Bool = false,
        contractVersion: Int = 1
    ) {
        self.id = id
        self.moduleID = moduleID
        self.title = title
        self.purpose = purpose
        self.inputSchema = inputSchema
        self.requiredModules = requiredModules.isEmpty ? [moduleID] : requiredModules
        self.confirmationPolicy = confirmationPolicy
        self.canUndo = canUndo
        self.readOnly = readOnly
        self.contractVersion = contractVersion
    }
}

public struct V2ToolCatalog: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public static let empty = Self(revision: "empty", modules: [:], tools: [])

    public let schemaVersion: Int
    public let revision: String
    public let modules: [String: UInt64]
    public let tools: [V2ToolDescriptor]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        revision: String,
        modules: [String: UInt64],
        tools: [V2ToolDescriptor]
    ) {
        self.schemaVersion = schemaVersion
        self.revision = revision
        self.modules = modules
        self.tools = tools.sorted { $0.id < $1.id }
    }

    public func tool(_ id: String) -> V2ToolDescriptor? {
        tools.first { $0.id == id }
    }

    public func validate(_ call: V2AgentToolCall) throws -> (V2ToolDescriptor, V2ToolArguments) {
        guard let descriptor = tool(call.toolID) else {
            throw V2ToolSchemaError.unknownTool(call.toolID)
        }
        let arguments = try V2ToolArguments.parse(call.argumentsJSON, using: descriptor.inputSchema)
        return (descriptor, arguments)
    }
}

public enum V2ToolCatalogBuilder {
    public static func validateAdditionalDescriptors(_ descriptors: [V2ToolDescriptor]) throws {
        var ids = Set(builtinTools.map(\.id))
        for descriptor in descriptors {
            guard ids.insert(descriptor.id).inserted else {
                throw V2ToolSchemaError.duplicateTool(descriptor.id)
            }
            guard !descriptor.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  descriptor.id.count <= 160,
                  descriptor.id.split(separator: ".").count >= 3 else {
                throw V2ToolSchemaError.unknownTool(descriptor.id)
            }
            var fieldIDs = Set<String>()
            for field in descriptor.inputSchema.fields {
                guard fieldIDs.insert(field.id).inserted else {
                    throw V2ToolSchemaError.duplicateTool(descriptor.id + "." + field.id)
                }
                guard !V2ToolArguments.isForbiddenHostField(field.id) else {
                    throw V2ToolSchemaError.forbiddenField(field.id)
                }
            }
        }
    }

    public static func make(
        runtime: V2ModuleRuntime,
        caller: V2CommandActor = .assistant,
        additional: [V2ToolDescriptor] = [],
        registeredToolIDs: Set<String>? = nil
    ) -> V2ToolCatalog {
        let candidates = builtinTools + additional
        var selected: [String: V2ToolDescriptor] = [:]
        for descriptor in candidates where descriptor.requiredModules.allSatisfy({ runtime.availability($0).isActive }) {
            guard runtime.registry.descriptor(descriptor.moduleID) != nil,
                  descriptor.requiredModules.allSatisfy({ runtime.registry.descriptor($0) != nil }),
                  registeredToolIDs.map({ $0.contains(descriptor.id) }) ?? true else { continue }
            if caller == .plugin,
               descriptor.id != "core.capture.create" {
                continue
            }
            if caller == .background, !descriptor.readOnly {
                continue
            }
            guard selected[descriptor.id] == nil else { continue }
            selected[descriptor.id] = descriptor
        }
        var modules: [String: UInt64] = [:]
        for descriptor in selected.values {
            if let ticket = try? runtime.ticket(for: descriptor.requiredModules) {
                for (id, generation) in ticket.generations {
                    modules[id] = generation
                }
            }
        }
        let signature = selected.values.sorted { $0.id < $1.id }.map { descriptor in
            let fields = descriptor.inputSchema.fields.map {
                "\($0.id):\($0.label):\($0.type.rawValue):\($0.required):\($0.maxLength ?? -1):\($0.enumValues.joined(separator: ","))"
            }.joined(separator: ",")
            let requiredModules = descriptor.requiredModules.sorted().joined(separator: ",")
            return "\(descriptor.id):\(descriptor.contractVersion):\(descriptor.moduleID):\(descriptor.title):\(descriptor.purpose):\(descriptor.confirmationPolicy.rawValue):\(descriptor.canUndo):\(descriptor.readOnly):\(descriptor.inputSchema.allowsAdditionalProperties):\(requiredModules):\(fields)"
        }.joined(separator: "|") + "|modules=" + modules.keys.sorted().map { "\($0):\(modules[$0] ?? 0)" }.joined(separator: ",")
        let revision = stableRevision(signature)
        return V2ToolCatalog(revision: revision, modules: modules, tools: Array(selected.values))
    }

    /// A deterministic revision is enough here because the host also keeps
    /// module generations. It avoids using Swift's process-randomized
    /// `hashValue` in a persisted or network-visible request.
    private static func stableRevision(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return value.isEmpty ? "empty" : String(hash, radix: 16)
    }

    public static let builtinTools: [V2ToolDescriptor] = [
        .init(
            id: "core.tasks.create",
            moduleID: "core.tasks",
            title: "创建任务",
            purpose: "根据用户明确提出的内容创建一个可执行任务。",
            inputSchema: .init(fields: [
                .init(id: "title", label: "任务标题", type: .text, required: true, maxLength: 240),
                .init(id: "note", label: "任务说明", type: .text, maxLength: 2_000),
                .init(id: "contextReference", label: "所属目标或领域", type: .recordReference, maxLength: 180),
                .init(id: "kind", label: "任务类型", type: .enumID, enumValues: ["goal", "commitment", "maintenance"])
            ]),
            canUndo: true
        ),
        .init(
            id: "core.tasks.schedule",
            moduleID: "core.tasks",
            title: "安排任务",
            purpose: "在已有任务或新任务上执行用户明确请求的日程调整。",
            inputSchema: .init(fields: [
                .init(id: "request", label: "日程请求", type: .text, required: true, maxLength: 2_000)
            ]),
            canUndo: true
        ),
        .init(
            id: "core.tasks.query",
            moduleID: "core.tasks",
            title: "查询任务",
            purpose: "读取限定数量的任务摘要。",
            inputSchema: .init(fields: [
                .init(id: "query", label: "查询词", type: .text, maxLength: 160),
                .init(id: "limit", label: "数量", type: .integer)
            ]),
            readOnly: true
        ),
        .init(
            id: "core.ledger.createPending",
            moduleID: "core.ledger",
            title: "记录待确认账单",
            purpose: "保存一笔账单事实并暂归 Others，正式分类仍需人工确认。",
            inputSchema: .init(fields: [
                .init(id: "description", label: "说明", type: .text, required: true, maxLength: 500),
                .init(id: "amount", label: "金额", type: .decimal, required: true),
                .init(id: "currency", label: "币种", type: .text, required: true, maxLength: 12),
                .init(id: "date", label: "日期", type: .date, required: true, maxLength: 80)
            ]),
            confirmationPolicy: .automatic,
            canUndo: true
        ),
        .init(
            id: "core.ledger.proposeCategory",
            moduleID: "core.ledger",
            title: "提出账单分类",
            purpose: "为已有账单提出分类建议，必须由人工确认后才改变正式分类。",
            inputSchema: .init(fields: [
                .init(id: "ledgerReference", label: "账单说明", type: .recordReference, required: true, maxLength: 240),
                .init(id: "category", label: "建议分类", type: .text, required: true, maxLength: 80)
            ]),
            confirmationPolicy: .humanAlways,
            canUndo: true
        ),
        .init(
            id: "core.finance.createPlan",
            moduleID: "core.finance",
            title: "创建订阅或还款计划",
            purpose: "创建订阅、房租、信用卡或借款还款计划；缺少必要信息时先询问。",
            inputSchema: .init(fields: [
                .init(id: "title", label: "计划名称", type: .text, required: true, maxLength: 180),
                .init(id: "amount", label: "金额", type: .decimal, required: true),
                .init(id: "currency", label: "币种", type: .text, required: true, maxLength: 12),
                .init(id: "dueDate", label: "到期日期", type: .date, required: true, maxLength: 80),
                .init(id: "kind", label: "计划类型", type: .enumID, required: true, enumValues: ["subscription", "rent", "creditCard", "loan", "bill"]),
                .init(id: "recurrence", label: "周期", type: .enumID, enumValues: ["once", "monthly", "yearly"]),
                .init(id: "link", label: "已配置的外部链接别名", type: .recordReference, maxLength: 120)
            ]),
            canUndo: true
        ),
        .init(
            id: "core.finance.markPaid",
            moduleID: "core.finance",
            title: "确认已付款",
            purpose: "在用户明确确认已经付款后记录付款事实。",
            inputSchema: .init(fields: [
                .init(id: "planReference", label: "计划名称", type: .recordReference, required: true, maxLength: 180),
                .init(id: "dueDate", label: "本期到期日期", type: .date, required: true, maxLength: 80)
            ]),
            confirmationPolicy: .humanAlways,
            canUndo: true
        ),
        .init(
            id: "core.finance.queryPlans",
            moduleID: "core.finance",
            title: "查询财务计划",
            purpose: "读取限定数量的订阅、账单和还款计划摘要。",
            inputSchema: .init(fields: [
                .init(id: "query", label: "查询词", type: .text, maxLength: 160),
                .init(id: "limit", label: "数量", type: .integer)
            ]),
            readOnly: true
        ),
        .init(
            id: "core.budget.set",
            moduleID: "core.budget",
            title: "设置预算",
            purpose: "为指定周期设置预算；预算进度从已确认账单读取。",
            inputSchema: .init(fields: [
                .init(id: "amount", label: "预算金额", type: .decimal, required: true),
                .init(id: "currency", label: "币种", type: .text, required: true, maxLength: 12),
                .init(id: "period", label: "周期", type: .enumID, required: true, enumValues: ["monthly"]),
                .init(id: "month", label: "月份", type: .text, maxLength: 7),
                .init(id: "category", label: "分类", type: .text, maxLength: 80)
            ]),
            canUndo: true
        ),
        .init(
            id: "core.budget.queryProgress",
            moduleID: "core.budget",
            title: "查询预算进度",
            purpose: "读取预算与已确认支出的同币种进度。",
            inputSchema: .init(fields: [
                .init(id: "currency", label: "币种", type: .text, maxLength: 12),
                .init(id: "category", label: "分类", type: .text, maxLength: 80)
            ]),
            readOnly: true
        ),
        .init(
            id: "core.recall.append",
            moduleID: "core.recall",
            title: "记录当天回响",
            purpose: "保存用户明确要记录的复盘或当天回响。",
            inputSchema: .init(fields: [
                .init(id: "text", label: "回响内容", type: .text, required: true, maxLength: 4_000),
                .init(id: "date", label: "日期", type: .date, required: true, maxLength: 80)
            ]),
            canUndo: true
        ),
        .init(
            id: "core.capture.create",
            moduleID: "core.capture",
            title: "保存随手记",
            purpose: "保留原文并创建一条待整理的统一输入记录。",
            inputSchema: .init(fields: [
                .init(id: "text", label: "原文", type: .text, required: true, maxLength: 8_000)
            ]),
            canUndo: true
        ),
        .init(
            id: "core.notes.create",
            moduleID: "core.notes",
            title: "记录灵感或收纳内容",
            purpose: "保存用户明确要记录的灵感、未来想法或 Others 内容。",
            inputSchema: .init(fields: [
                .init(id: "text", label: "内容", type: .text, required: true, maxLength: 4_000),
                .init(id: "kind", label: "类型", type: .enumID, enumValues: ["inspiration", "futureIdea", "other"])
            ]),
            canUndo: true
        ),
        .init(
            id: "core.recall.query",
            moduleID: "core.recall",
            title: "查询当天回响",
            purpose: "读取限定数量的回想记录。",
            inputSchema: .init(fields: [
                .init(id: "query", label: "查询词", type: .text, maxLength: 160),
                .init(id: "limit", label: "数量", type: .integer)
            ]),
            readOnly: true
        )
    ]
}

public struct V2AgentToolCall: Equatable, Sendable {
    /// Provider supplied call IDs are retained only for display/trace. The
    /// host never uses this value as an operation identity.
    public let modelCallID: String?
    public let toolID: String
    public let argumentsJSON: Data

    public init(toolID: String, argumentsJSON: Data, modelCallID: String? = nil) {
        self.toolID = toolID
        self.argumentsJSON = argumentsJSON
        self.modelCallID = modelCallID
    }
}

/// Evidence selected by the host for a tool invocation.  A model may suggest
/// a value, but it cannot manufacture this evidence or choose a persistent
/// record identity.  Keep the projection intentionally small: source text is
/// used for policy checks and the full source remains in its owning domain.
public struct V2ToolSourceEvidence: Equatable, Sendable {
    public let sourceKind: String
    public let excerpt: String

    public init(sourceKind: String = "submittedText", excerpt: String) {
        self.sourceKind = String(sourceKind.prefix(40))
        self.excerpt = String(excerpt.prefix(2_000))
    }
}

/// Host supplied authority for a confirmation-required command.  This is
/// deliberately a value that cannot be decoded from model JSON.
public enum V2ToolConfirmationAuthority: Equatable, Sendable {
    case none
    case human
}

/// The host classifies the submitted request before it lets a model-selected
/// write reach a domain reducer.  Discussion is deliberately not an implicit
/// authorization to persist a financial proposal.
public enum V2ToolIntent: Equatable, Sendable {
    case explicitWrite
    case discussion
    case unknown
}

public enum V2ToolExecutionState: String, Codable, Equatable, Sendable {
    case applied
    case pendingConfirmation
    case needsInformation
    case blocked
    case conflict
    case failed
    case cancelled
    case undone
}

public struct V2ToolExecutionResult: Codable, Equatable, Sendable, Identifiable {
    public var id: String { operationID }
    public let toolID: String
    public let state: V2ToolExecutionState
    public let operationID: String
    public let idempotencyKey: String
    public let summary: String
    public let entityReferences: [String]
    public let undoReference: String?
    public let traceID: String?
    /// Safe, schema-validated arguments retained only so the host can offer a
    /// retry after a transient failure. These are never trusted as identity.
    public let assistantRequestID: String?
    public let callOrdinal: Int?
    public let argumentsJSON: Data?
    public let modelCallID: String?
    /// A bounded copy of the submitted source used for confirmation/retry
    /// policy. The owning assistant message remains the source of truth; this
    /// copy only lets a host rebuild the same context after reopening a card.
    public let submittedText: String?
    /// Bounded read-tool evidence; kept separate from the short receipt card.
    public let observation: String?

    public init(
        toolID: String,
        state: V2ToolExecutionState,
        operationID: String,
        idempotencyKey: String,
        summary: String,
        entityReferences: [String] = [],
        undoReference: String? = nil,
        traceID: String? = nil,
        assistantRequestID: String? = nil,
        callOrdinal: Int? = nil,
        argumentsJSON: Data? = nil,
        modelCallID: String? = nil,
        submittedText: String? = nil,
        observation: String? = nil
    ) {
        self.toolID = toolID
        self.state = state
        self.operationID = operationID
        self.idempotencyKey = idempotencyKey
        self.summary = String(summary.prefix(1_000))
        self.entityReferences = Array(entityReferences.prefix(24))
        self.undoReference = undoReference
        self.traceID = traceID
        self.assistantRequestID = assistantRequestID
        self.callOrdinal = callOrdinal
        self.argumentsJSON = argumentsJSON
        self.modelCallID = modelCallID
        self.submittedText = submittedText.map { String($0.prefix(8_000)) }
        self.observation = observation.map { String($0.prefix(8_000)) }
    }

    public func bound(to call: V2AgentToolCall, context: V2ToolExecutionContext) -> Self {
        Self(
            toolID: toolID,
            state: state,
            operationID: context.operationID,
            idempotencyKey: context.idempotencyKey,
            summary: summary,
            entityReferences: entityReferences,
            undoReference: undoReference,
            traceID: context.traceID,
            assistantRequestID: context.assistantRequestID,
            callOrdinal: context.callOrdinal,
            argumentsJSON: call.argumentsJSON,
            modelCallID: call.modelCallID,
            submittedText: context.submittedText,
            observation: observation
        )
    }

    public var isTerminalSuccess: Bool { state == .applied || state == .undone }
    public var canUndo: Bool { undoReference != nil && state == .applied }
}

public struct V2ToolExecutionContext: Equatable, Sendable {
    public let traceID: String
    public let assistantRequestID: String
    public let attemptID: String
    public let callOrdinal: Int
    public let toolID: String
    public let operationID: String
    public let idempotencyKey: String
    public let actor: V2CommandActor
    /// The exact user submission associated with this call.  Domain handlers
    /// use it to verify that money/date values were evidenced by the user;
    /// tool arguments alone are never sufficient evidence.
    public let submittedText: String
    public let sourceEvidence: [V2ToolSourceEvidence]
    public let confirmation: V2ToolConfirmationAuthority
    public let intent: V2ToolIntent
    public let requiresReview: Bool
    public let assistantContext: V2AssistantContext?
    public let conversation: [V2AgentConversationMessage]

    public init(
        traceID: String,
        assistantRequestID: String,
        attemptID: String = UUID().uuidString,
        callOrdinal: Int,
        toolID: String = "unknown",
        actor: V2CommandActor = .assistant,
        submittedText: String = "",
        sourceEvidence: [V2ToolSourceEvidence] = [],
        confirmation: V2ToolConfirmationAuthority = .none,
        intent: V2ToolIntent = .explicitWrite,
        requiresReview: Bool = false,
        assistantContext: V2AssistantContext? = nil,
        conversation: [V2AgentConversationMessage] = []
    ) {
        self.traceID = traceID
        self.assistantRequestID = assistantRequestID
        self.attemptID = attemptID
        self.callOrdinal = max(0, callOrdinal)
        let normalizedToolID = toolID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.toolID = normalizedToolID.isEmpty ? "unknown" : String(normalizedToolID.prefix(160))
        self.operationID = "assistant.\(assistantRequestID).tool.\(self.toolID).\(max(0, callOrdinal))"
        self.idempotencyKey = "\(assistantRequestID):\(self.toolID):\(max(0, callOrdinal))"
        self.actor = actor
        self.submittedText = String(submittedText.prefix(8_000))
        self.sourceEvidence = Array(sourceEvidence.prefix(8))
        self.confirmation = confirmation
        self.intent = intent
        self.requiresReview = requiresReview
        self.assistantContext = assistantContext
        self.conversation = conversation
    }

    /// Rebuilds the same semantic operation identity for a host confirmation
    /// or retry.  The attempt/trace may change, while the durable idempotency
    /// key remains bound to the original assistant request and tool ordinal.
    public func confirmedContext(traceID: String = UUID().uuidString) -> Self {
        Self(
            traceID: traceID,
            assistantRequestID: assistantRequestID,
            attemptID: UUID().uuidString,
            callOrdinal: callOrdinal,
            toolID: toolID,
            actor: actor,
            submittedText: submittedText,
            sourceEvidence: sourceEvidence,
            confirmation: .human,
            intent: intent,
            assistantContext: assistantContext,
            conversation: conversation
        )
    }
}

public enum V2ToolExecutionError: Error, LocalizedError, Equatable, Sendable {
    case unsupported(String)
    case staleCatalog
    case operationAlreadyRunning

    public var errorDescription: String? {
        switch self {
        case let .unsupported(tool): return "工具暂未接入宿主：\(tool)"
        case .staleCatalog: return "工具目录已变化，请重新整理这条请求。"
        case .operationAlreadyRunning: return "这项操作正在执行，请稍候。"
        }
    }
}

private extension JSONEncoder {
    static let sorted: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}

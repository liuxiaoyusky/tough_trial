import Foundation

/// A typed host handler. Implementations live in the native module or host
/// adapter, where they can call the domain reducer and persist its receipt in
/// the same transaction. A handler must return the operation identity it was
/// given; it cannot accept identity supplied by model JSON.
public typealias V2ToolHandler = @MainActor @Sendable (
    V2ToolArguments,
    V2ToolExecutionContext
) async throws -> V2ToolExecutionResult

public typealias V2TypedToolHandler = @MainActor @Sendable (
    V2TypedToolCommand,
    V2ToolExecutionContext
) async throws -> V2ToolExecutionResult

public typealias V2ToolUndoHandler = @MainActor @Sendable (
    V2ToolExecutionResult,
    V2ToolExecutionContext
) async throws -> V2ToolExecutionResult

public enum V2ToolRegistryError: Error, LocalizedError, Equatable, Sendable {
    case duplicateRegistration(String)
    case missingHandler(String)
    case staleCatalog
    case invalidResult(String)
    case confirmationRequired(String)
    case undoUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case let .duplicateRegistration(tool): return "工具登记重复：" + tool
        case let .missingHandler(tool): return "工具未接入宿主：" + tool
        case .staleCatalog: return "工具目录已变化，请重新整理这条请求。"
        case let .invalidResult(reason): return "工具回执无效：" + reason
        case let .confirmationRequired(tool): return "工具需要人工确认：" + tool
        case let .undoUnavailable(tool): return "工具没有可用的撤销操作：" + tool
        }
    }
}

/// Checks facts that cannot be established from model arguments alone. This
/// is deliberately conservative for financial writes: amount, currency and
/// date must be present in the submitted source (or selected host evidence).
public enum V2ToolSourcePolicy {
    public static func missingInformation(
        for descriptor: V2ToolDescriptor,
        arguments: V2ToolArguments,
        context: V2ToolExecutionContext, at date: Date = Date(), timeZone: TimeZone = .current
    ) -> String? {
        guard !descriptor.readOnly else { return nil }
        if context.intent == .discussion {
            return "这段内容看起来是在讨论方案；请明确说出要执行哪项修改。"
        }

        let source = ([context.submittedText] + context.sourceEvidence.map(\.excerpt))
            .joined(separator: "\n")
        switch descriptor.id {
        case "core.ledger.createPending":
            guard hasAmount(arguments, "amount", in: source) else { return "账单金额没有在本轮原文中明确出现，请补充后再记录。" }
            guard hasCurrency(arguments, "currency", in: source) else { return "账单币种没有在本轮原文中明确出现，请补充后再记录。" }
            guard hasDate(arguments, "date", in: source, relativeTo: date, timeZone: timeZone) else { return "账单日期没有在本轮原文中明确出现，请补充具体日期。" }
        case "core.finance.createPlan":
            guard hasAmount(arguments, "amount", in: source) else { return "计划金额没有在本轮原文中明确出现，请补充后再创建。" }
            guard hasCurrency(arguments, "currency", in: source) else { return "计划币种没有在本轮原文中明确出现，请补充后再创建。" }
            guard hasDate(arguments, "dueDate", in: source) else { return "计划到期日必须在本轮原文中明确出现，请补充具体日期。" }
        case "core.budget.set":
            guard hasAmount(arguments, "amount", in: source), hasCurrency(arguments, "currency", in: source) else { return "请明确预算金额和币种。" }
            if let month = arguments.string("month"), !source.contains(month) {
                let current = String(V2CaptureContract.localDate(date, timeZone: timeZone).prefix(7))
                guard month == current, ["本月", "这个月", "当前月"].contains(where: source.contains) else { return "请明确预算所属月份。" }
            }
        case "core.recall.append":
            guard hasDate(arguments, "date", in: source, relativeTo: date, timeZone: timeZone) else { return "请明确这条回响的日期。" }
        case "core.finance.markPaid":
            let paidMarkers = ["已支付", "已付款", "付过", "扣款成功", "已扣费", "已经还款", "还款了", "付清"]
            guard paidMarkers.contains(where: source.localizedCaseInsensitiveContains) else {
                return "请先明确说明这笔计划已经支付，再确认记账。"
            }
        default:
            break
        }
        return nil
    }

    private static func hasAmount(_ arguments: V2ToolArguments, _ field: String, in source: String) -> Bool {
        guard let expected = decimalString(arguments[field]) else { return false }
        // A date is evidence for timing, never evidence for the price. Remove
        // complete calendar tokens before comparing numeric amounts.
        let amountSource = source.replacingOccurrences(
            of: #"\d{4}[-/年]\d{1,2}(?:[-/月]\d{1,2}[日号]?)?"#,
            with: " ", options: .regularExpression)
        let pattern = #"\d[\d,]*(?:\.\d+)?"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(amountSource.startIndex..<amountSource.endIndex, in: amountSource)
        for match in expression.matches(in: amountSource, range: range) {
            guard let tokenRange = Range(match.range, in: amountSource) else { continue }
            let token = amountSource[tokenRange].replacingOccurrences(of: ",", with: "")
            if decimalString(.string(token)) == expected { return true }
        }
        return false
    }

    private static func decimalString(_ value: V2ToolJSONValue?) -> Decimal? {
        guard let value else { return nil }
        switch value {
        case let .string(raw): return Decimal(string: raw.trimmingCharacters(in: .whitespacesAndNewlines), locale: Locale(identifier: "en_US_POSIX"))
        case let .number(number): return Decimal(number)
        default: return nil
        }
    }

    private static func hasCurrency(_ arguments: V2ToolArguments, _ field: String, in source: String) -> Bool {
        guard let raw = arguments.string(field)?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
              !raw.isEmpty else { return false }

        // Currency codes are matched as tokens so a value such as `USDOLLAR`
        // cannot satisfy a USD claim.  Chinese aliases are kept explicit;
        // generic “元/块” is only accepted for CNY after excluding a named
        // foreign currency in the same source.
        let namedAliases: [String: [String]] = [
            "CNY": ["CNY", "RMB", "人民币"],
            "HKD": ["HKD", "港币", "港元"],
            "USD": ["USD", "美元", "美金", "US$"],
            "EUR": ["EUR", "欧元", "€"],
            "GBP": ["GBP", "英镑", "£"],
            "JPY": ["JPY", "日元", "円", "¥"],
            "TWD": ["TWD", "台币", "新台币"],
            "SGD": ["SGD", "新加坡元"],
            "AUD": ["AUD", "澳元"],
            "CAD": ["CAD", "加元"],
            "KRW": ["KRW", "韩元", "₩"],
            "MYR": ["MYR", "马币"],
            "THB": ["THB", "泰铢", "฿"]
        ]
        let aliases = namedAliases[raw] ?? [raw]
        if aliases.contains(where: { containsCurrencyAlias($0, in: source) }) { return true }
        guard raw == "CNY" else { return false }

        let nonCNYAliases = namedAliases
            .filter { $0.key != "CNY" }
            .flatMap(\.value)
        guard !nonCNYAliases.contains(where: { containsCurrencyAlias($0, in: source) }) else { return false }
        return containsBareCNYUnit(in: source)
    }

    private static func hasDate(_ arguments: V2ToolArguments, _ field: String, in source: String, relativeTo date: Date? = nil, timeZone: TimeZone = .current) -> Bool {
        guard let value = arguments.string(field)?.trimmingCharacters(in: .whitespacesAndNewlines), isStrictISODate(value) else { return false }
        if containsDateToken(value, in: source) { return true }
        guard let date else { return false }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        for (markers, offset) in [(["今天", "今日"], 0), (["昨天", "昨日"], -1), (["前天"], -2)] {
            if markers.contains(where: source.contains), let target = calendar.date(byAdding: .day, value: offset, to: date),
               V2CaptureContract.localDate(target, timeZone: timeZone) == value { return true }
        }
        return false
    }

    private static func containsCurrencyAlias(_ alias: String, in source: String) -> Bool {
        guard !alias.isEmpty else { return false }
        if alias.unicodeScalars.allSatisfy({ $0.isASCII }) && alias.rangeOfCharacter(from: .letters) != nil {
            return containsToken(alias, in: source)
        }
        return source.localizedCaseInsensitiveContains(alias)
    }

    private static func containsBareCNYUnit(in source: String) -> Bool {
        for unit in ["元", "块"] {
            var searchStart = source.startIndex
            while let range = source.range(of: unit, range: searchStart..<source.endIndex) {
                let prefix = source[..<range.lowerBound]
                let qualifiers = ["港", "美", "新加坡", "日", "韩", "台", "欧", "英", "澳", "加"]
                if !qualifiers.contains(where: { prefix.hasSuffix($0) }) { return true }
                searchStart = range.upperBound
            }
        }
        return false
    }

    private static func containsToken(_ token: String, in source: String) -> Bool {
        var searchStart = source.startIndex
        while let range = source.range(of: token, options: [.caseInsensitive], range: searchStart..<source.endIndex) {
            let before = range.lowerBound == source.startIndex ? nil : source[source.index(before: range.lowerBound)]
            let after = range.upperBound == source.endIndex ? nil : source[range.upperBound]
            let isWord: (Character?) -> Bool = { character in
                guard let character else { return false }
                return character.unicodeScalars.allSatisfy { $0.isASCII && CharacterSet.letters.contains($0) }
            }
            if !isWord(before) && !isWord(after) { return true }
            searchStart = range.upperBound
        }
        return false
    }

    private static func containsDateToken(_ value: String, in source: String) -> Bool {
        var searchStart = source.startIndex
        while let range = source.range(of: value, range: searchStart..<source.endIndex) {
            let before = range.lowerBound == source.startIndex ? nil : source[source.index(before: range.lowerBound)]
            let after = range.upperBound == source.endIndex ? nil : source[range.upperBound]
            let isDigit: (Character?) -> Bool = { character in
                guard let character else { return false }
                return character.isNumber
            }
            if !isDigit(before) && !isDigit(after) { return true }
            searchStart = range.upperBound
        }
        return false
    }

    private static func isStrictISODate(_ value: String) -> Bool {
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
}

/// The host-side registry joins the dynamic catalog and typed execution. It
/// does not expose V2Engine; callers register small closures scoped to one
/// command and one module. Every execute call performs the catalog check again
/// so a delayed provider response cannot write after a module is disabled.
@MainActor
public final class V2ToolExecutionRegistry {
    public let runtime: V2ModuleRuntime
    private var handlers: [String: V2ToolHandler] = [:]
    private var undoHandlers: [String: V2ToolUndoHandler] = [:]
    private var additionalDescriptors: [V2ToolDescriptor]

    public init(runtime: V2ModuleRuntime, additionalDescriptors: [V2ToolDescriptor] = []) throws {
        self.runtime = runtime
        self.additionalDescriptors = additionalDescriptors
        try Self.validateDescriptors(additionalDescriptors)
    }

    public func register(
        _ descriptor: V2ToolDescriptor,
        handler: @escaping V2ToolHandler
    ) throws {
        try Self.validateDescriptors([descriptor], existing: Set(
            V2ToolCatalogBuilder.builtinTools.map(\.id) + additionalDescriptors.map(\.id)
        ).subtracting([descriptor.id]))
        guard handlers[descriptor.id] == nil else {
            throw V2ToolRegistryError.duplicateRegistration(descriptor.id)
        }
        if !additionalDescriptors.contains(where: { $0.id == descriptor.id }) {
            additionalDescriptors.append(descriptor)
        }
        handlers[descriptor.id] = handler
    }

    /// Registers a typed adapter. JSON decoding and schema checks complete
    /// before this closure is called, so native code receives a closed enum of
    /// commands and human-readable record references only.
    public func registerTyped(
        _ descriptor: V2ToolDescriptor,
        handler: @escaping V2TypedToolHandler
    ) throws {
        try register(descriptor) { arguments, context in
            try await handler(V2TypedToolCommandDecoder.decode(toolID: descriptor.id, arguments: arguments), context)
        }
    }

    public func registerUndo(
        for descriptor: V2ToolDescriptor,
        handler: @escaping V2ToolUndoHandler
    ) throws {
        guard handlers[descriptor.id] != nil else {
            throw V2ToolRegistryError.missingHandler(descriptor.id)
        }
        undoHandlers[descriptor.id] = handler
    }

    public func catalog(caller: V2CommandActor = .assistant) -> V2ToolCatalog {
        V2ToolCatalogBuilder.make(
            runtime: runtime,
            caller: caller,
            additional: additionalDescriptors,
            registeredToolIDs: Set(handlers.keys)
        )
    }

    public func execute(
        _ call: V2AgentToolCall,
        context: V2ToolExecutionContext,
        expectedCatalog: V2ToolCatalog? = nil
    ) async throws -> V2ToolExecutionResult {
        let current = catalog(caller: context.actor)
        if let expectedCatalog,
           current.revision != expectedCatalog.revision || current.modules != expectedCatalog.modules {
            throw V2ToolRegistryError.staleCatalog
        }
        let (descriptor, arguments) = try current.validate(call)
        guard context.toolID == descriptor.id else {
            throw V2ToolRegistryError.invalidResult("上下文工具与目录工具不一致")
        }
        guard let handler = handlers[descriptor.id] else {
            throw V2ToolRegistryError.missingHandler(descriptor.id)
        }
        try runtime.require(descriptor.requiredModules)

        let result = try await handler(arguments, context)
        guard result.toolID == descriptor.id,
              result.operationID == context.operationID,
              result.idempotencyKey == context.idempotencyKey else {
            throw V2ToolRegistryError.invalidResult("宿主操作身份与请求不一致")
        }
        return result.bound(to: call, context: context)
    }

    /// Replays a pending human action with host-created confirmation authority
    /// and the same durable operation identity.
    public func confirm(
        _ result: V2ToolExecutionResult,
        expectedCatalog: V2ToolCatalog? = nil
    ) async throws -> V2ToolExecutionResult {
        guard result.state == .pendingConfirmation,
              let argumentsJSON = result.argumentsJSON,
              let requestID = result.assistantRequestID,
              let ordinal = result.callOrdinal else {
            throw V2ToolRegistryError.confirmationRequired(result.toolID)
        }
        let call = V2AgentToolCall(toolID: result.toolID, argumentsJSON: argumentsJSON, modelCallID: result.modelCallID)
        let context = V2ToolExecutionContext(
            traceID: UUID().uuidString,
            assistantRequestID: requestID,
            attemptID: UUID().uuidString,
            callOrdinal: ordinal,
            toolID: result.toolID,
            submittedText: result.submittedText ?? "",
            sourceEvidence: result.submittedText.map { [V2ToolSourceEvidence(excerpt: $0)] } ?? [],
            confirmation: .human
        )
        return try await execute(call, context: context, expectedCatalog: expectedCatalog)
    }

    public func undo(_ result: V2ToolExecutionResult) async throws -> V2ToolExecutionResult {
        guard result.canUndo, let handler = undoHandlers[result.toolID] else {
            throw V2ToolRegistryError.undoUnavailable(result.toolID)
        }
        guard let descriptor = catalog().tool(result.toolID), descriptor.canUndo else {
            throw V2ToolRegistryError.undoUnavailable(result.toolID)
        }
        try runtime.require(descriptor.requiredModules)
        guard let requestID = result.assistantRequestID, let ordinal = result.callOrdinal else {
            throw V2ToolRegistryError.undoUnavailable(result.toolID)
        }
        let context = V2ToolExecutionContext(
            traceID: UUID().uuidString,
            assistantRequestID: requestID,
            attemptID: UUID().uuidString,
            callOrdinal: ordinal,
            toolID: result.toolID,
            submittedText: result.submittedText ?? "",
            sourceEvidence: result.submittedText.map { [V2ToolSourceEvidence(excerpt: $0)] } ?? [],
            confirmation: .human
        )
        let updated = try await handler(result, context)
        guard updated.toolID == result.toolID,
              updated.operationID == context.operationID,
              updated.idempotencyKey == context.idempotencyKey,
              updated.state == .undone else {
            throw V2ToolRegistryError.invalidResult("撤销回执无效")
        }
        return updated
    }

    private static func validateDescriptors(
        _ descriptors: [V2ToolDescriptor],
        existing: Set<String> = Set(V2ToolCatalogBuilder.builtinTools.map(\.id))
    ) throws {
        var seen = existing
        for descriptor in descriptors {
            guard seen.insert(descriptor.id).inserted else {
                throw V2ToolRegistryError.duplicateRegistration(descriptor.id)
            }
            guard !descriptor.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  descriptor.id.count <= 160,
                  descriptor.id.split(separator: ".").count >= 3 else {
                throw V2ToolRegistryError.duplicateRegistration(descriptor.id)
            }
            var fieldIDs = Set<String>()
            for field in descriptor.inputSchema.fields {
                guard fieldIDs.insert(field.id).inserted,
                      !V2ToolArguments.isForbiddenHostField(field.id) else {
                    throw V2ToolRegistryError.duplicateRegistration(descriptor.id + "." + field.id)
                }
            }
        }
    }
}

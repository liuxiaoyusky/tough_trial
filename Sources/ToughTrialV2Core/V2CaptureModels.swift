import Foundation

public enum V2CaptureError: String, Error, LocalizedError, Codable, Sendable {
    case invalidSchema, missingEvidence, invalidAmount, unknownCurrency, missingRequiredField
    case invalidReference, staleSource, staleTarget, duplicateCandidate, confirmationRequired
    case assetUnavailable, providerFailure, persistenceFailure
    public var errorDescription: String? {
        switch self {
        case .invalidSchema: "整理结果的格式不兼容，原文已保留。"
        case .missingEvidence: "整理结果缺少可核对的原文依据。"
        case .invalidAmount: "金额不完整或格式无效，请补充后再整理。"
        case .unknownCurrency: "还不能确定币种，请在原文中补充。"
        case .missingRequiredField: "信息还不完整，已留在收纳中心。"
        case .invalidReference: "关联内容不存在，请重新整理。"
        case .staleSource: "原文已经修改，请使用当前版本重新整理。"
        case .staleTarget: "内容已有后续修改，无法直接覆盖或撤销。"
        case .duplicateCandidate: "这条原文已有整理结果，请先查看或撤销，避免重复保存。"
        case .confirmationRequired: "账单分类需要你确认。"
        case .assetUnavailable: "附件未能读取，原文仍保留。"
        case .providerFailure: "AI 暂时无法整理，原文已保存，可以重试。"
        case .persistenceFailure: "保存失败，请保留当前输入后重试。"
        }
    }
}

public struct V2CaptureBlock: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable { case text, image, handwriting, audio, document }
    public var id: String
    public var kind: Kind
    public var text: String?
    public var assetID: String?
    public init(id: String = UUID().uuidString, kind: Kind = .text, text: String? = nil, assetID: String? = nil) {
        self.id = id; self.kind = kind; self.text = text; self.assetID = assetID
    }
}

public struct V2CaptureEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var revision: Int
    public var recordedAt: Date
    public var timeZoneIdentifier: String
    public var blocks: [V2CaptureBlock]
    public var text: String { blocks.compactMap(\.text).joined(separator: "\n") }
}

public enum V2CaptureKind: String, Codable, CaseIterable, Sendable {
    case ledger, recall, inspiration, futureIdea, task, other
    public var label: String {
        switch self { case .ledger: "账单"; case .recall: "回想"; case .inspiration: "灵感"
        case .futureIdea: "以后想做"; case .task: "任务"; case .other: "Others" }
    }
}
public enum V2LedgerDirection: String, Codable, CaseIterable, Sendable { case expense, income, transfer }
public struct V2CaptureEvidence: Codable, Equatable, Sendable {
    public var blockID: String
    public var quote: String
    public init(blockID: String, quote: String) { self.blockID = blockID; self.quote = quote }
}

/// The bounded writable subset. The contract below rejects fields belonging to a different kind.
public struct V2CapturePayload: Codable, Equatable, Sendable {
    public var text: String
    public var title: String?
    public var amount: String?
    public var currency: String?
    public var direction: V2LedgerDirection?
    public var categoryName: String?
    public var localDate: String?
    public var operations: [V2ScheduleOperation]?
    public init(text: String, title: String? = nil, amount: String? = nil, currency: String? = nil,
                direction: V2LedgerDirection? = nil, categoryName: String? = nil, localDate: String? = nil,
                operations: [V2ScheduleOperation]? = nil) {
        self.text = text; self.title = title; self.amount = amount; self.currency = currency
        self.direction = direction; self.categoryName = categoryName; self.localDate = localDate; self.operations = operations
    }
}
public struct V2CaptureCandidate: Codable, Equatable, Identifiable, Sendable {
    public var candidateID: String
    public var kind: V2CaptureKind
    public var evidence: [V2CaptureEvidence]
    public var payload: V2CapturePayload
    public var id: String { candidateID }
    public init(candidateID: String, kind: V2CaptureKind, evidence: [V2CaptureEvidence], payload: V2CapturePayload) {
        self.candidateID = candidateID; self.kind = kind; self.evidence = evidence; self.payload = payload
    }
}
public struct V2CaptureProposal: Codable, Equatable, Sendable {
    public var schemaVersion: Int = 1
    public var captureID: String
    public var sourceRevision: Int
    public var items: [V2CaptureCandidate]
    public init(captureID: String, sourceRevision: Int, items: [V2CaptureCandidate]) {
        self.captureID = captureID; self.sourceRevision = sourceRevision; self.items = items
    }
}
public enum V2CaptureStatus: String, Codable, Sendable {
    case proposed, needsConfirmation, needsInformation, applied, rejected, failed, undone
    public var label: String {
        switch self { case .proposed: "待整理"; case .needsConfirmation: "待确认分类"
        case .needsInformation: "待补充"; case .applied: "已保存"; case .rejected: "已拒绝"
        case .failed: "未保存"; case .undone: "已撤销" }
    }
}
/// A user-visible edit made while a capture candidate is still being checked.
/// The source revision and candidate identity stay stable; this log records
/// only the fields that the user changed.
public enum V2CaptureCorrectionField: String, Codable, CaseIterable, Sendable {
    case kind, text, amount, currency, direction, localDate, categoryName
}

public struct V2CaptureCorrection: Codable, Equatable, Sendable {
    public var candidateID: String
    public var field: V2CaptureCorrectionField
    public var before: String?
    public var after: String?
    public var at: Date

    public init(
        candidateID: String,
        field: V2CaptureCorrectionField,
        before: String?,
        after: String?,
        at: Date = Date()
    ) {
        self.candidateID = candidateID
        self.field = field
        self.before = before
        self.after = after
        self.at = at
    }
}

/// The latest typed values for a candidate. Keeping this separate from the
/// original proposal lets the app show both the model response and the exact
/// user correction history without rewriting the source proposal.
public struct V2LedgerCandidateOverride: Codable, Equatable, Sendable {
    public var candidateID: String
    public var draft: V2LedgerCandidateDraft
    public var at: Date

    public init(candidateID: String, draft: V2LedgerCandidateDraft, at: Date = Date()) {
        self.candidateID = candidateID
        self.draft = draft
        self.at = at
    }
}

/// Typed values for correcting a ledger proposal before it is applied. Nil
/// amount/currency/direction deliberately means "still needs information";
/// the candidate is not allowed to become a LedgerEntry until the normal
/// capture validation passes.
public struct V2LedgerCandidateDraft: Codable, Equatable, Sendable {
    public var kind: V2CaptureKind
    public var text: String
    public var amount: String?
    public var currency: String?
    public var direction: V2LedgerDirection?
    public var localDate: String?
    public var categoryName: String?

    public init(
        kind: V2CaptureKind = .ledger,
        text: String,
        amount: String? = nil,
        currency: String? = nil,
        direction: V2LedgerDirection? = nil,
        localDate: String? = nil,
        categoryName: String? = nil
    ) {
        self.kind = kind
        self.text = text
        self.amount = amount
        self.currency = currency
        self.direction = direction
        self.localDate = localDate
        self.categoryName = categoryName
    }
}

public struct V2CaptureBatch: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var traceID: String
    public var proposal: V2CaptureProposal
    public var model: String
    public var promptVersion: Int = 1
    public var taxonomyRevision: Int
    public var createdAt: Date
    public var corrections: [V2CaptureCorrection]
    public var ledgerCandidateOverrides: [V2LedgerCandidateOverride]

    public init(
        id: String,
        traceID: String,
        proposal: V2CaptureProposal,
        model: String,
        promptVersion: Int = 1,
        taxonomyRevision: Int,
        createdAt: Date,
        corrections: [V2CaptureCorrection] = [],
        ledgerCandidateOverrides: [V2LedgerCandidateOverride] = []
    ) {
        self.id = id
        self.traceID = traceID
        self.proposal = proposal
        self.model = model
        self.promptVersion = promptVersion
        self.taxonomyRevision = taxonomyRevision
        self.createdAt = createdAt
        self.corrections = corrections
        self.ledgerCandidateOverrides = ledgerCandidateOverrides
    }

    private enum CodingKeys: String, CodingKey {
        case id, traceID, proposal, model, promptVersion, taxonomyRevision, createdAt, corrections, ledgerCandidateOverrides
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        traceID = try container.decode(String.self, forKey: .traceID)
        proposal = try container.decode(V2CaptureProposal.self, forKey: .proposal)
        model = try container.decode(String.self, forKey: .model)
        promptVersion = try container.decodeIfPresent(Int.self, forKey: .promptVersion) ?? 1
        taxonomyRevision = try container.decode(Int.self, forKey: .taxonomyRevision)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        corrections = try container.decodeIfPresent([V2CaptureCorrection].self, forKey: .corrections) ?? []
        ledgerCandidateOverrides = try container.decodeIfPresent([V2LedgerCandidateOverride].self, forKey: .ledgerCandidateOverrides) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(traceID, forKey: .traceID)
        try container.encode(proposal, forKey: .proposal)
        try container.encode(model, forKey: .model)
        try container.encode(promptVersion, forKey: .promptVersion)
        try container.encode(taxonomyRevision, forKey: .taxonomyRevision)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(corrections, forKey: .corrections)
        try container.encode(ledgerCandidateOverrides, forKey: .ledgerCandidateOverrides)
    }

    public func effectiveCandidate(for candidateID: String) -> V2CaptureCandidate? {
        guard let original = proposal.items.first(where: { $0.candidateID == candidateID }) else { return nil }
        guard let override = ledgerCandidateOverrides.last(where: { $0.candidateID == candidateID }) else {
            return original
        }
        guard (original.kind == .ledger || original.kind == .other), override.draft.kind == .ledger else {
            return original
        }
        return V2CaptureCandidate(
            candidateID: original.candidateID,
            kind: override.draft.kind,
            evidence: original.evidence,
            payload: .init(
                text: override.draft.text,
                amount: override.draft.amount,
                currency: override.draft.currency,
                direction: override.draft.direction,
                categoryName: override.draft.categoryName,
                localDate: override.draft.localDate
            )
        )
    }
}
public struct V2LedgerEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var revision: Int = 1
    public var amount: String
    public var currency: String
    public var direction: V2LedgerDirection
    public var text: String
    public var localDate: String?
    public var categoryID: String = "others"
    public var recordedAt: Date
    public var receiptID: String
}
public struct V2CaptureNote: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var kind: V2CaptureKind
    public var title: String?
    public var text: String
    public var receiptID: String
    public var recordedAt: Date
}
public struct V2LedgerCategory: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var parentID: String?
    public var mergedIntoID: String?
}
public struct V2CaptureResolvedEvidence: Codable, Equatable, Sendable {
    public var blockID: String
    public var sourceRevision: Int
    public var startScalar: Int
    public var endScalar: Int
    public var assetID: String?
}
public struct V2CaptureReceipt: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var batchID: String
    public var candidateID: String
    public var status: V2CaptureStatus
    public var error: V2CaptureError?
    public var targetID: String?
    public var createdAt: Date
    public var ledgerAfter: V2LedgerEntry?
    public var recallBefore: V2RecallEntry?
    public var recallAfter: V2RecallEntry?
    public var noteAfter: V2CaptureNote?
    public var scheduleReceiptID: String?
    public var resolvedEvidence: [V2CaptureResolvedEvidence]?
}
public struct V2CategoryReceipt: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var beforeCategories: [V2LedgerCategory]
    public var afterCategories: [V2LedgerCategory]
    public var beforeLedger: [V2LedgerEntry]
    public var afterLedger: [V2LedgerEntry]
    public var taxonomyRevision: Int
    public var undone: Bool = false
}
public struct V2CaptureState: Codable, Equatable, Sendable {
    public var schemaVersion: Int = 1
    public var assets: [V2CaptureAsset] = []
    public var entries: [V2CaptureEntry] = [] // Immutable source revisions, not just the latest text.
    public var batches: [V2CaptureBatch] = []
    public var receipts: [V2CaptureReceipt] = []
    public var ledger: [V2LedgerEntry] = []
    public var notes: [V2CaptureNote] = []
    public var categories: [V2LedgerCategory] = [.init(id: "others", name: "Others")]
    public var taxonomyRevision: Int = 1
    public var categoryReceipts: [V2CategoryReceipt] = []
    public var imports: [V2ExternalImportReceipt]?
    public var finance: V2FinanceState?
    public init() {}
    public var latestEntries: [V2CaptureEntry] {
        Dictionary(grouping: entries, by: \.id).values.compactMap { $0.max { $0.revision < $1.revision } }
            .sorted { $0.recordedAt > $1.recordedAt }
    }
    public func totals(direction: V2LedgerDirection) -> [String: Decimal] {
        ledger.filter { $0.direction == direction }.reduce(into: [:]) {
            $0[$1.currency, default: 0] += Decimal(string: $1.amount, locale: Locale(identifier: "en_US_POSIX")) ?? 0
        }
    }
}

/// One authority for AI writable keys, strict parsing and local business validation.
public enum V2CaptureContract {
    public static let payloadFields: [V2CaptureKind: Set<String>] = [
        .ledger: ["text", "amount", "currency", "direction", "categoryName", "localDate"],
        .recall: ["text", "localDate"], .inspiration: ["text", "title"],
        .futureIdea: ["text", "title", "localDate"], .task: ["text", "operations"], .other: ["text"]
    ]
    public static let currencies: Set<String> = ["CNY", "HKD", "USD", "EUR", "GBP", "JPY", "TWD", "SGD", "AUD", "CAD", "KRW", "MYR", "THB"]
    public static func validAmount(_ value: String) -> Bool {
        value.range(of: #"^(0|[1-9][0-9]{0,14})(\.[0-9]{1,6})?$"#, options: .regularExpression) != nil
            && (Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) ?? 0) > 0
    }
    public static func localDate(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone; formatter.dateFormat = "yyyy-MM-dd"; return formatter.string(from: date)
    }
    public static func date(_ value: String, timeZone: TimeZone) -> Date? {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone; formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        guard let date = formatter.date(from: value), localDate(date, timeZone: timeZone) == value else { return nil }
        return date
    }
    public static func decode(_ data: Data) throws -> V2CaptureProposal {
        guard data.count <= 1_048_576,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw V2CaptureError.invalidSchema }
        try keys(root, allowed: ["schemaVersion", "captureID", "sourceRevision", "items"])
        guard let items = root["items"] as? [[String: Any]], items.count <= 50 else { throw V2CaptureError.invalidSchema }
        for item in items {
            try keys(item, allowed: ["candidateID", "kind", "evidence", "payload"])
            guard let kindString = item["kind"] as? String, let kind = V2CaptureKind(rawValue: kindString),
                  let payload = item["payload"] as? [String: Any], let evidence = item["evidence"] as? [[String: Any]]
            else { throw V2CaptureError.invalidSchema }
            try keys(payload, allowed: payloadFields[kind]!)
            for source in evidence { try keys(source, allowed: ["blockID", "quote"]) }
            if let operations = payload["operations"] as? [[String: Any]] {
                for operation in operations {
                    try keys(operation, allowed: ["kind", "localID", "targetID", "title", "note", "day", "startMinute", "durationMinutes"])
                }
            }
        }
        let result: V2CaptureProposal
        do { result = try JSONDecoder().decode(V2CaptureProposal.self, from: data) }
        catch { throw V2CaptureError.invalidSchema }
        guard result.schemaVersion == 1 else { throw V2CaptureError.invalidSchema }
        return result
    }
    private static func keys(_ object: [String: Any], allowed: Set<String>) throws {
        guard Set(object.keys).isSubset(of: allowed) else { throw V2CaptureError.invalidSchema }
    }
    public static func resolveEvidence(_ item: V2CaptureCandidate, source: V2CaptureEntry) throws -> [V2CaptureResolvedEvidence] {
        try item.evidence.map { evidence in
            guard let block = source.blocks.first(where: { $0.id == evidence.blockID }), let text = block.text,
                  !evidence.quote.isEmpty, let range = text.range(of: evidence.quote),
                  let lower = range.lowerBound.samePosition(in: text.unicodeScalars),
                  let upper = range.upperBound.samePosition(in: text.unicodeScalars) else { throw V2CaptureError.missingEvidence }
            return .init(blockID: block.id, sourceRevision: source.revision,
                startScalar: text.unicodeScalars.distance(from: text.unicodeScalars.startIndex, to: lower),
                endScalar: text.unicodeScalars.distance(from: text.unicodeScalars.startIndex, to: upper), assetID: block.assetID)
        }
    }
    public static func validate(_ item: V2CaptureCandidate, source: V2CaptureEntry) throws {
        guard !item.payload.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw V2CaptureError.missingRequiredField }
        guard !item.evidence.isEmpty, item.evidence.allSatisfy({ evidence in
            !evidence.quote.isEmpty && source.blocks.contains { $0.id == evidence.blockID && ($0.text?.contains(evidence.quote) ?? false) }
        }) else { throw V2CaptureError.missingEvidence }
        if let day = item.payload.localDate, date(day, timeZone: TimeZone(identifier: source.timeZoneIdentifier) ?? .current) == nil {
            throw V2CaptureError.invalidSchema
        }
        switch item.kind {
        case .ledger:
            guard let amount = item.payload.amount, validAmount(amount) else { throw V2CaptureError.invalidAmount }
            guard let currency = item.payload.currency, currencies.contains(currency) else { throw V2CaptureError.unknownCurrency }
            guard item.payload.direction != nil else { throw V2CaptureError.missingRequiredField }
        case .recall: guard item.payload.localDate != nil else { throw V2CaptureError.missingRequiredField }
        case .task:
            guard let operations = item.payload.operations, !operations.isEmpty, operations.count <= 10,
                  operations.allSatisfy({ $0.kind == .createTask || $0.kind == .scheduleTask }) else { throw V2CaptureError.invalidSchema }
            let aliases = Set(operations.filter { $0.kind == .createTask }.compactMap(\.localID))
            guard operations.filter({ $0.kind == .scheduleTask }).allSatisfy({ aliases.contains($0.targetID ?? "") }) else { throw V2CaptureError.invalidReference }
        default: break
        }
    }
}

import Foundation

/// The host-bound actor for a command invocation.  This type intentionally
/// does not conform to `Codable`: model output and plugin JSON cannot claim a
/// trusted identity or a human confirmation.
public enum V2CommandActor: String, Equatable, Sendable {
    case manual
    case assistant
    case plugin
    case background
}

public struct V2CommandContext: Equatable, Sendable {
    public var traceID: String
    public var actor: V2CommandActor
    public var confirmedPayment: Bool

    public init(
        traceID: String = UUID().uuidString,
        actor: V2CommandActor = .manual,
        confirmedPayment: Bool = false
    ) {
        self.traceID = traceID
        self.actor = actor
        self.confirmedPayment = confirmedPayment
    }
}

public enum V2FinanceCommandError: Error, Equatable, LocalizedError, Sendable {
    case paymentConfirmationRequired
    case paymentActorNotAllowed
    case unknownDraftFields([String])
    case invalidDraft(String)

    public var errorDescription: String? {
        switch self {
        case .paymentConfirmationRequired:
            "记账前需要宿主确认已经完成支付。"
        case .paymentActorNotAllowed:
            "后台或声明式插件不能确认支付。"
        case .unknownDraftFields(let fields):
            "财务计划草稿包含不支持的字段：\(fields.joined(separator: ","))"
        case .invalidDraft(let reason):
            "财务计划草稿无效：\(reason)"
        }
    }
}

/// A fixed descriptor for a built-in finance or budget command.
///
/// Descriptors are source code, rather than data supplied by a plugin.  This
/// keeps command IDs and confirmation policy stable while still allowing the
/// runtime to authorize the owning module.
public struct V2FinanceCommandDescriptor: Equatable, Sendable {
    public enum ConfirmationPolicy: String, Codable, Equatable, Sendable {
        case none
        case humanPayment
    }

    public let commandID: String
    public let domainID: String
    public let requiredModules: [String]
    public let confirmationPolicy: ConfirmationPolicy
    public let canUndo: Bool
    /// The model-facing, editable keys for a plan draft.  Core identity and
    /// lifecycle fields are deliberately absent.
    public let writableKeys: Set<String>

    public init(
        commandID: String,
        domainID: String,
        requiredModules: [String],
        confirmationPolicy: ConfirmationPolicy,
        canUndo: Bool,
        writableKeys: Set<String> = []
    ) {
        self.commandID = commandID
        self.domainID = domainID
        self.requiredModules = requiredModules
        self.confirmationPolicy = confirmationPolicy
        self.canUndo = canUndo
        self.writableKeys = writableKeys
    }

    public static let savePlan = Self(
        commandID: "core.finance.createPlan",
        domainID: "core.finance",
        requiredModules: ["core.finance"],
        confirmationPolicy: .none,
        canUndo: false,
        writableKeys: V2FinancePlanDraft.writableKeys
    )

    public static let setPlanActive = Self(
        commandID: "core.finance.setPlanActive",
        domainID: "core.finance",
        requiredModules: ["core.finance"],
        confirmationPolicy: .none,
        canUndo: false
    )

    public static let markPaid = Self(
        commandID: "core.finance.markPaid",
        domainID: "core.finance",
        requiredModules: ["core.finance"],
        confirmationPolicy: .humanPayment,
        canUndo: true
    )

    public static let undoPayment = Self(
        commandID: "core.finance.undoPayment",
        domainID: "core.finance",
        requiredModules: ["core.finance"],
        confirmationPolicy: .none,
        canUndo: false
    )

    public static let saveBudget = Self(
        commandID: "core.budget.set",
        domainID: "core.budget",
        requiredModules: ["core.budget"],
        confirmationPolicy: .none,
        canUndo: false
    )

    public static let removeBudget = Self(
        commandID: "core.budget.remove",
        domainID: "core.budget",
        requiredModules: ["core.budget"],
        confirmationPolicy: .none,
        canUndo: false
    )

    public static let all: [Self] = [
        .savePlan, .setPlanActive, .markPaid, .undoPayment, .saveBudget, .removeBudget
    ]
}

public enum V2FinanceCommand: Equatable, Sendable {
    case savePlan(V2FinancePlan, expectedRevision: Int?)
    case setPlanActive(id: String, isActive: Bool, expectedRevision: Int?)
    case markPaid(id: String, expectedRevision: Int, expectedDueDate: String)
    case undoPayment(id: String)
    case saveBudget(V2Budget, expectedRevision: Int?)
    case removeBudget(id: String)

    public var descriptor: V2FinanceCommandDescriptor {
        switch self {
        case .savePlan: .savePlan
        case .setPlanActive: .setPlanActive
        case .markPaid: .markPaid
        case .undoPayment: .undoPayment
        case .saveBudget: .saveBudget
        case .removeBudget: .removeBudget
        }
    }

    public var commandID: String { descriptor.commandID }

    public static let descriptors: [V2FinanceCommandDescriptor] = V2FinanceCommandDescriptor.all
}

/// A common, read-only projection over persisted domain receipts.  Finance
/// payment records remain the source of truth; this type is never persisted as
/// a second receipt log.
public struct V2OperationReceipt: Codable, Equatable, Identifiable, Sendable {
    public enum Status: String, Codable, Equatable, Sendable {
        case applied
        case undone
    }

    public enum UndoRef: Codable, Equatable, Sendable {
        case financePayment(String)

        private enum CodingKeys: String, CodingKey { case kind, id }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            guard try container.decode(String.self, forKey: .kind) == "financePayment" else {
                throw DecodingError.dataCorruptedError(
                    forKey: .kind,
                    in: container,
                    debugDescription: "unsupported undo reference"
                )
            }
            self = .financePayment(try container.decode(String.self, forKey: .id))
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .financePayment(let id):
                try container.encode("financePayment", forKey: .kind)
                try container.encode(id, forKey: .id)
            }
        }
    }

    public var id: String
    public var domainID: String
    public var commandID: String
    /// Old persisted payment rows have no trace field.  Their projection is
    /// therefore explicitly nil instead of inventing a trace ID.
    public var traceID: String?
    public var status: Status
    public var changedIDs: [String]
    public var undoRef: UndoRef?

    public init(
        id: String,
        domainID: String,
        commandID: String,
        traceID: String?,
        status: Status,
        changedIDs: [String],
        undoRef: UndoRef? = nil
    ) {
        self.id = id
        self.domainID = domainID
        self.commandID = commandID
        self.traceID = traceID
        self.status = status
        self.changedIDs = changedIDs
        self.undoRef = undoRef
    }

    public static func paymentReceipts(from snapshot: V2AppSnapshot) -> [Self] {
        (snapshot.capture.finance?.payments ?? []).map { paymentReceipt(for: $0) }
    }

    fileprivate static func paymentReceipt(
        for payment: V2FinancePayment,
        traceID: String? = nil,
        commandID: String = V2FinanceCommandDescriptor.markPaid.commandID
    ) -> Self {
        Self(
            id: payment.id,
            domainID: V2FinanceCommandDescriptor.markPaid.domainID,
            commandID: commandID,
            traceID: traceID,
            status: payment.status == .applied ? .applied : .undone,
            changedIDs: [payment.id, payment.planID, payment.ledgerID],
            undoRef: payment.status == .applied ? .financePayment(payment.id) : nil
        )
    }
}

public extension V2FinanceCommandDispatcher {
    /// Rebuild payment cards directly from the finance rows after a reopen.
    static func paymentReceipts(from snapshot: V2AppSnapshot) -> [V2OperationReceipt] {
        V2OperationReceipt.paymentReceipts(from: snapshot)
    }
}

/// The model-facing finance plan payload.  It deliberately omits `id`,
/// `revision`, `isActive`, and the timezone chosen by the host.  The host must
/// provide identity and timezone explicitly when converting it to a domain
/// plan; `V2Engine` remains the final validator.
public struct V2FinancePlanDraft: Codable, Equatable, Sendable {
    public var title: String
    public var kind: V2FinancePlanKind
    public var amount: String
    public var currency: String
    public var direction: V2LedgerDirection
    public var dueDate: String
    public var recurrence: V2FinanceRecurrence
    public var anchorDay: Int?
    public var anchorMonth: Int?
    public var reminderDays: Int
    public var reminderEnabled: Bool
    public var prompt: String
    public var link: String
    public var attachmentIDs: [String]

    public static let writableKeys: Set<String> = [
        "title", "kind", "amount", "currency", "direction", "dueDate", "recurrence",
        "anchorDay", "anchorMonth", "reminderDays", "reminderEnabled", "prompt", "link", "attachmentIDs"
    ]

    public init(
        title: String,
        kind: V2FinancePlanKind,
        amount: String,
        currency: String,
        direction: V2LedgerDirection? = nil,
        dueDate: String,
        recurrence: V2FinanceRecurrence = .once,
        anchorDay: Int? = nil,
        anchorMonth: Int? = nil,
        reminderDays: Int = 3,
        reminderEnabled: Bool = true,
        prompt: String = "",
        link: String = "",
        attachmentIDs: [String] = []
    ) {
        self.title = title
        self.kind = kind
        self.amount = amount
        self.currency = currency
        self.direction = direction ?? kind.defaultDirection
        self.dueDate = dueDate
        self.recurrence = recurrence
        self.anchorDay = anchorDay
        self.anchorMonth = anchorMonth
        self.reminderDays = reminderDays
        self.reminderEnabled = reminderEnabled
        self.prompt = prompt
        self.link = link
        self.attachmentIDs = attachmentIDs
    }

    public func toPlan(
        id: String,
        timeZoneIdentifier: String,
        revision: Int = 1,
        isActive: Bool = true
    ) -> V2FinancePlan {
        V2FinancePlan(
            id: id,
            revision: revision,
            title: title,
            kind: kind,
            amount: amount,
            currency: currency,
            direction: direction,
            dueDate: dueDate,
            timeZoneIdentifier: timeZoneIdentifier,
            recurrence: recurrence,
            anchorDay: anchorDay,
            anchorMonth: anchorMonth,
            reminderDays: reminderDays,
            reminderEnabled: reminderEnabled,
            prompt: prompt,
            link: link,
            attachmentIDs: attachmentIDs,
            isActive: isActive
        )
    }

    public static func decodeJSON(_ data: Data) throws -> Self {
        do {
            return try JSONDecoder().decode(Self.self, from: data)
        } catch let error as V2FinanceCommandError {
            throw error
        } catch {
            throw V2FinanceCommandError.invalidDraft("JSON 无法解析")
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case title
        case kind
        case amount
        case currency
        case direction
        case dueDate
        case recurrence
        case anchorDay
        case anchorMonth
        case reminderDays
        case reminderEnabled
        case prompt
        case link
        case attachmentIDs
    }

    public init(from decoder: Decoder) throws {
        let all = try decoder.container(keyedBy: V2AnyCodingKey.self)
        let allowed = V2FinanceCommandDescriptor.savePlan.writableKeys
        let unknown = all.allKeys.map(\.stringValue).filter { !allowed.contains($0) }.sorted()
        guard unknown.isEmpty else {
            throw V2FinanceCommandError.unknownDraftFields(unknown)
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        kind = try container.decode(V2FinancePlanKind.self, forKey: .kind)
        amount = try container.decode(String.self, forKey: .amount)
        currency = try container.decode(String.self, forKey: .currency)
        direction = try container.decodeIfPresent(V2LedgerDirection.self, forKey: .direction) ?? kind.defaultDirection
        dueDate = try container.decode(String.self, forKey: .dueDate)
        recurrence = try container.decodeIfPresent(V2FinanceRecurrence.self, forKey: .recurrence) ?? .once
        anchorDay = try container.decodeIfPresent(Int.self, forKey: .anchorDay)
        anchorMonth = try container.decodeIfPresent(Int.self, forKey: .anchorMonth)
        reminderDays = try container.decodeIfPresent(Int.self, forKey: .reminderDays) ?? 3
        reminderEnabled = try container.decodeIfPresent(Bool.self, forKey: .reminderEnabled) ?? true
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt) ?? ""
        link = try container.decodeIfPresent(String.self, forKey: .link) ?? ""
        attachmentIDs = try container.decodeIfPresent([String].self, forKey: .attachmentIDs) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(kind, forKey: .kind)
        try container.encode(amount, forKey: .amount)
        try container.encode(currency, forKey: .currency)
        try container.encode(direction, forKey: .direction)
        try container.encode(dueDate, forKey: .dueDate)
        try container.encode(recurrence, forKey: .recurrence)
        try container.encode(anchorDay, forKey: .anchorDay)
        try container.encode(anchorMonth, forKey: .anchorMonth)
        try container.encode(reminderDays, forKey: .reminderDays)
        try container.encode(reminderEnabled, forKey: .reminderEnabled)
        try container.encode(prompt, forKey: .prompt)
        try container.encode(link, forKey: .link)
        try container.encode(attachmentIDs, forKey: .attachmentIDs)
    }
}

private struct V2AnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

public final class V2FinanceCommandDispatcher {
    public let engine: V2Engine
    private let authorize: ([String]) throws -> Void

    public init(
        engine: V2Engine,
        authorize: @escaping ([String]) throws -> Void = { _ in }
    ) {
        self.engine = engine
        self.authorize = authorize
    }

    @discardableResult
    public func execute(
        _ command: V2FinanceCommand,
        context: V2CommandContext,
        at date: Date = Date()
    ) throws -> V2OperationReceipt {
        let descriptor = command.descriptor
        // The runtime resolves a finance/budget module's ledger dependency;
        // the dispatcher authorizes only the owning module here.
        try authorize(descriptor.requiredModules)

        switch command {
        case .savePlan(let plan, let expectedRevision):
            let saved = try engine.saveFinancePlan(plan, expectedRevision: expectedRevision)
            return receipt(
                id: UUID().uuidString,
                descriptor: descriptor,
                context: context,
                status: .applied,
                changedIDs: [saved.id]
            )

        case .setPlanActive(let id, let isActive, let expectedRevision):
            let saved = try engine.setFinancePlanActive(id: id, isActive: isActive, expectedRevision: expectedRevision)
            return receipt(
                id: UUID().uuidString,
                descriptor: descriptor,
                context: context,
                status: .applied,
                changedIDs: [saved.id]
            )

        case .markPaid(let id, let expectedRevision, let expectedDueDate):
            guard context.actor != .background, context.actor != .plugin else {
                throw V2FinanceCommandError.paymentActorNotAllowed
            }
            guard context.confirmedPayment else {
                throw V2FinanceCommandError.paymentConfirmationRequired
            }
            let payment = try engine.payFinancePlan(
                id: id,
                expectedRevision: expectedRevision,
                expectedDueDate: expectedDueDate,
                at: date
            )
            return V2OperationReceipt.paymentReceipt(
                for: payment,
                traceID: context.traceID,
                commandID: descriptor.commandID
            )

        case .undoPayment(let id):
            try engine.undoFinancePayment(id: id)
            // The reducer persisted the status.  Project the post-commit row;
            // there is intentionally no second receipt store to update.
            if let payment = engine.snapshot.capture.finance?.payments.first(where: { $0.id == id }) {
                return V2OperationReceipt.paymentReceipt(
                    for: payment,
                    traceID: context.traceID,
                    commandID: descriptor.commandID
                )
            }
            // A successful engine undo always retains the payment row.  Keep
            // this fallback non-throwing so no new error can escape after the
            // reducer has committed.
            return V2OperationReceipt(
                id: id,
                domainID: descriptor.domainID,
                commandID: descriptor.commandID,
                traceID: context.traceID,
                status: .undone,
                changedIDs: [id]
            )

        case .saveBudget(let budget, let expectedRevision):
            let saved = try engine.saveBudget(budget, expectedRevision: expectedRevision)
            return receipt(
                id: UUID().uuidString,
                descriptor: descriptor,
                context: context,
                status: .applied,
                changedIDs: [saved.id]
            )

        case .removeBudget(let id):
            let removed = try engine.removeBudget(id: id)
            return receipt(
                id: UUID().uuidString,
                descriptor: descriptor,
                context: context,
                status: .applied,
                changedIDs: [removed.id]
            )
        }
    }

    private func receipt(
        id: String,
        descriptor: V2FinanceCommandDescriptor,
        context: V2CommandContext,
        status: V2OperationReceipt.Status,
        changedIDs: [String]
    ) -> V2OperationReceipt {
        V2OperationReceipt(
            id: id,
            domainID: descriptor.domainID,
            commandID: descriptor.commandID,
            traceID: context.traceID,
            status: status,
            changedIDs: changedIDs,
            undoRef: nil
        )
    }
}

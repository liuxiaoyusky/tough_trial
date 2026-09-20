import Foundation

/// A small, typed vocabulary for recurring obligations. The model deliberately
/// stores a date-only due date so that a payment is not shifted by a device's
/// clock or daylight-saving transition.
public enum V2FinancePlanKind: String, Codable, CaseIterable, Sendable {
    case subscription
    case bill
    case creditCard
    case rent
    case loan

    public var label: String {
        switch self {
        case .subscription: "订阅"
        case .bill: "账单"
        case .creditCard: "信用卡"
        case .rent: "房租"
        case .loan: "借款还款"
        }
    }

    public var defaultDirection: V2LedgerDirection {
        switch self {
        case .creditCard, .loan: .transfer
        case .subscription, .bill, .rent: .expense
        }
    }
}

public enum V2FinanceRecurrence: String, Codable, CaseIterable, Sendable {
    case once
    case monthly
    case yearly
}

public struct V2FinancePlan: Codable, Equatable, Identifiable, Sendable {
    public typealias Kind = V2FinancePlanKind
    public typealias Recurrence = V2FinanceRecurrence

    public var id: String
    public var revision: Int
    public var title: String
    public var kind: V2FinancePlanKind
    public var amount: String
    public var currency: String
    public var direction: V2LedgerDirection
    /// A strict `yyyy-MM-dd` date in `timeZoneIdentifier`.
    public var dueDate: String
    public var timeZoneIdentifier: String
    public var recurrence: V2FinanceRecurrence
    /// The original day is retained when a month has fewer days. This keeps
    /// a 31st-of-the-month plan on the 31st when the next month allows it.
    public var anchorDay: Int?
    public var anchorMonth: Int?
    public var reminderDays: Int
    public var reminderEnabled: Bool
    public var prompt: String
    public var link: String
    public var attachmentIDs: [String]
    public var isActive: Bool

    public init(
        id: String = UUID().uuidString,
        revision: Int = 1,
        title: String,
        kind: V2FinancePlanKind,
        amount: String,
        currency: String,
        direction: V2LedgerDirection? = nil,
        dueDate: String,
        timeZoneIdentifier: String = TimeZone.current.identifier,
        recurrence: V2FinanceRecurrence = .once,
        anchorDay: Int? = nil,
        anchorMonth: Int? = nil,
        reminderDays: Int = 3,
        reminderEnabled: Bool = true,
        prompt: String = "",
        link: String = "",
        attachmentIDs: [String] = [],
        isActive: Bool = true
    ) {
        self.id = id
        self.revision = revision
        self.title = title
        self.kind = kind
        self.amount = amount
        self.currency = currency
        self.direction = direction ?? kind.defaultDirection
        self.dueDate = dueDate
        self.timeZoneIdentifier = timeZoneIdentifier
        self.recurrence = recurrence
        self.anchorDay = anchorDay
        self.anchorMonth = anchorMonth
        self.reminderDays = reminderDays
        self.reminderEnabled = reminderEnabled
        self.prompt = prompt
        self.link = link
        self.attachmentIDs = attachmentIDs
        self.isActive = isActive
    }
}

public struct V2FinancePayment: Codable, Equatable, Identifiable, Sendable {
    public enum Status: String, Codable, CaseIterable, Sendable {
        case applied
        case undone
    }

    public var id: String
    public var planID: String
    public var periodKey: String
    public var dueDate: String
    public var paidAt: Date
    public var timeZoneIdentifier: String
    public var amount: String
    public var currency: String
    public var direction: V2LedgerDirection
    public var ledgerID: String
    /// Snapshot used by undo to detect a later manual category or amount edit.
    public var ledgerAfter: V2LedgerEntry
    public var planRevisionBefore: Int
    public var planRevisionAfter: Int
    public var previousDueDate: String
    public var nextDueDate: String?
    public var previousIsActive: Bool
    public var status: Status

    public init(
        id: String = UUID().uuidString,
        planID: String,
        periodKey: String,
        dueDate: String,
        paidAt: Date,
        timeZoneIdentifier: String,
        amount: String,
        currency: String,
        direction: V2LedgerDirection,
        ledgerID: String,
        ledgerAfter: V2LedgerEntry,
        planRevisionBefore: Int,
        planRevisionAfter: Int,
        previousDueDate: String,
        nextDueDate: String?,
        previousIsActive: Bool,
        status: Status = .applied
    ) {
        self.id = id
        self.planID = planID
        self.periodKey = periodKey
        self.dueDate = dueDate
        self.paidAt = paidAt
        self.timeZoneIdentifier = timeZoneIdentifier
        self.amount = amount
        self.currency = currency
        self.direction = direction
        self.ledgerID = ledgerID
        self.ledgerAfter = ledgerAfter
        self.planRevisionBefore = planRevisionBefore
        self.planRevisionAfter = planRevisionAfter
        self.previousDueDate = previousDueDate
        self.nextDueDate = nextDueDate
        self.previousIsActive = previousIsActive
        self.status = status
    }
}

public struct V2Budget: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var revision: Int
    public var currency: String
    public var amount: String
    /// A strict `yyyy-MM` month in the user's budgeting calendar.
    public var month: String
    /// `nil` means all expense categories. Merged category IDs are resolved
    /// when calculating progress, so old budgets remain useful after a merge.
    public var categoryID: String?

    public init(
        id: String = UUID().uuidString,
        revision: Int = 1,
        currency: String,
        amount: String,
        month: String,
        categoryID: String? = nil
    ) {
        self.id = id
        self.revision = revision
        self.currency = currency
        self.amount = amount
        self.month = month
        self.categoryID = categoryID
    }
}

public struct V2BudgetProgress: Codable, Equatable, Sendable {
    public var budgetID: String
    public var month: String
    public var currency: String
    public var budgetAmount: Decimal
    public var spent: Decimal
    public var remaining: Decimal
    public var categoryID: String?

    public init(
        budgetID: String,
        month: String,
        currency: String,
        budgetAmount: Decimal,
        spent: Decimal,
        remaining: Decimal,
        categoryID: String?
    ) {
        self.budgetID = budgetID
        self.month = month
        self.currency = currency
        self.budgetAmount = budgetAmount
        self.spent = spent
        self.remaining = remaining
        self.categoryID = categoryID
    }
}

public struct V2FinanceState: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var plans: [V2FinancePlan]
    public var payments: [V2FinancePayment]
    public var budgets: [V2Budget]

    public init(
        schemaVersion: Int = 1,
        plans: [V2FinancePlan] = [],
        payments: [V2FinancePayment] = [],
        budgets: [V2Budget] = []
    ) {
        self.schemaVersion = schemaVersion
        self.plans = plans
        self.payments = payments
        self.budgets = budgets
    }
}

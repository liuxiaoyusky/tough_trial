import Foundation

public enum V2FinanceError: Error, Equatable, LocalizedError, Sendable {
    case invalidPlan(String)
    case invalidBudget(String)
    case financePlanNotFound(String)
    case budgetNotFound(String)
    case financeConflict(String)
    case paymentNotFound(String)
    case paymentNotUndoable(String)
    case invalidAttachment(String)
    case invalidLink
    case invalidDate(String)

    public var errorDescription: String? {
        switch self {
        case .invalidPlan(let reason): "订阅或还款计划无效：\(reason)"
        case .invalidBudget(let reason): "预算无效：\(reason)"
        case .financePlanNotFound(let id): "找不到财务计划：\(id)"
        case .budgetNotFound(let id): "找不到预算：\(id)"
        case .financeConflict(let reason): "财务数据已经改变，请刷新后重试：\(reason)"
        case .paymentNotFound(let id): "找不到支付记录：\(id)"
        case .paymentNotUndoable(let reason): "这笔支付不能撤销：\(reason)"
        case .invalidAttachment(let id): "附件不存在或已失效：\(id)"
        case .invalidLink: "应用链接必须是 HTTPS 或受支持的应用 scheme。"
        case .invalidDate(let value): "日期格式无效：\(value)"
        }
    }
}

public extension V2Engine {
    @discardableResult
    func saveFinancePlan(
        plan: V2FinancePlan,
        expectedRevision: Int? = nil
    ) throws -> V2FinancePlan {
        try saveFinancePlan(plan, expectedRevision: expectedRevision)
    }

    /// Saves a complete plan. Existing plans are optimistic-concurrency checked
    /// when `expectedRevision` is supplied; every accepted edit advances the
    /// revision so a later undo cannot overwrite that edit.
    @discardableResult
    func saveFinancePlan(
        _ plan: V2FinancePlan,
        expectedRevision: Int? = nil
    ) throws -> V2FinancePlan {
        try commit(modules: ["core.finance"], commandID: "core.finance.createPlan") { snapshot in
            var finance = snapshot.capture.finance ?? V2FinanceState()
            let existingIndex = finance.plans.firstIndex { $0.id == plan.id }
            if let existingIndex {
                let existing = finance.plans[existingIndex]
                if let expectedRevision, expectedRevision != existing.revision {
                    throw V2FinanceError.financeConflict("计划版本不一致")
                }
            } else if expectedRevision != nil {
                throw V2FinanceError.financeConflict("计划已经被删除")
            }

            var candidate = plan
            if let existingIndex {
                let existing = finance.plans[existingIndex]
                candidate.anchorDay = candidate.anchorDay ?? existing.anchorDay
                candidate.anchorMonth = candidate.anchorMonth ?? existing.anchorMonth
                candidate.revision = existing.revision + 1
            } else {
                candidate.revision = max(candidate.revision, 1)
            }
            candidate = try Self.validatedPlan(candidate, snapshot: snapshot)

            if let existingIndex {
                finance.plans[existingIndex] = candidate
            } else {
                finance.plans.append(candidate)
            }
            snapshot.capture.finance = finance
            return candidate
        }
    }

    /// Explicitly toggles a plan without changing its payment history.
    @discardableResult
    func setFinancePlanActive(
        id: String,
        isActive: Bool,
        expectedRevision: Int? = nil
    ) throws -> V2FinancePlan {
        try commit(modules: ["core.finance"], commandID: "core.finance.setPlanActive") { snapshot in
            var finance = snapshot.capture.finance ?? V2FinanceState()
            guard let index = finance.plans.firstIndex(where: { $0.id == id }) else {
                throw V2FinanceError.financePlanNotFound(id)
            }
            guard expectedRevision == nil || expectedRevision == finance.plans[index].revision else {
                throw V2FinanceError.financeConflict("计划版本不一致")
            }
            let plan = finance.plans[index]
            if isActive, plan.recurrence == .once, finance.payments.contains(where: { $0.planID == id && $0.periodKey == plan.dueDate && $0.status == .applied }) {
                throw V2FinanceError.financeConflict("这期已经支付，请撤销记账或修改到期日期后再恢复")
            }
            if finance.plans[index].isActive != isActive {
                finance.plans[index].isActive = isActive
                finance.plans[index].revision += 1
            }
            snapshot.capture.finance = finance
            return finance.plans[index]
        }
    }

    @discardableResult
    func setFinancePlanActive(
        planID: String,
        isActive: Bool,
        expectedRevision: Int? = nil
    ) throws -> V2FinancePlan {
        try setFinancePlanActive(id: planID, isActive: isActive, expectedRevision: expectedRevision)
    }

    /// Pays the current period and writes the resulting ledger record in the
    /// same snapshot transaction. Calling this again for the same period is
    /// idempotent and returns the existing payment.
    @discardableResult
    func payFinancePlan(
        id: String,
        expectedRevision: Int? = nil,
        expectedDueDate: String? = nil,
        at date: Date = Date()
    ) throws -> V2FinancePayment {
        try commit(modules: ["core.finance"], commandID: "core.finance.markPaid") { snapshot in
            var finance = snapshot.capture.finance ?? V2FinanceState()
            guard let planIndex = finance.plans.firstIndex(where: { $0.id == id }) else {
                throw V2FinanceError.financePlanNotFound(id)
            }
            let plan = finance.plans[planIndex]
            let requestedPeriod = expectedDueDate ?? plan.dueDate

            // Idempotency is checked before revision/activity checks. A retry
            // after a successful once-payment must still return its receipt.
            if let existing = finance.payments.last(where: {
                $0.planID == id && $0.periodKey == requestedPeriod && $0.status == .applied
            }) {
                return existing
            }

            guard plan.isActive else {
                throw V2FinanceError.financeConflict("计划当前未启用")
            }
            if let expectedRevision, expectedRevision != plan.revision {
                throw V2FinanceError.financeConflict("计划版本不一致")
            }
            if let expectedDueDate, expectedDueDate != plan.dueDate {
                throw V2FinanceError.financeConflict("到期日不一致")
            }
            guard requestedPeriod == plan.dueDate else {
                throw V2FinanceError.financeConflict("只能支付当前周期")
            }

            let timeZone = try Self.financeTimeZone(plan.timeZoneIdentifier)
            guard let due = Self.financeDate(plan.dueDate, timeZone: timeZone) else {
                throw V2FinanceError.invalidDate(plan.dueDate)
            }
            let nextDueDate = try Self.nextDueDate(for: plan, due: due, timeZone: timeZone)
            let paymentID = UUID().uuidString
            let ledgerID = UUID().uuidString
            let localDate = V2CaptureContract.localDate(date, timeZone: timeZone)
            let ledger = V2LedgerEntry(
                id: ledgerID,
                revision: 1,
                amount: plan.amount,
                currency: plan.currency,
                direction: plan.direction,
                text: plan.title,
                localDate: localDate,
                categoryID: "others",
                recordedAt: date,
                receiptID: paymentID
            )

            let revisionBefore = plan.revision
            var updatedPlan = plan
            updatedPlan.revision += 1
            updatedPlan.dueDate = nextDueDate ?? plan.dueDate
            updatedPlan.isActive = nextDueDate != nil
            let payment = V2FinancePayment(
                id: paymentID,
                planID: plan.id,
                periodKey: plan.dueDate,
                dueDate: plan.dueDate,
                paidAt: date,
                timeZoneIdentifier: plan.timeZoneIdentifier,
                amount: plan.amount,
                currency: plan.currency,
                direction: plan.direction,
                ledgerID: ledgerID,
                ledgerAfter: ledger,
                planRevisionBefore: revisionBefore,
                planRevisionAfter: updatedPlan.revision,
                previousDueDate: plan.dueDate,
                nextDueDate: nextDueDate,
                previousIsActive: plan.isActive
            )

            snapshot.capture.ledger.append(ledger)
            finance.plans[planIndex] = updatedPlan
            finance.payments.append(payment)
            snapshot.capture.finance = finance
            return payment
        }
    }

    /// Only the latest applied payment for a plan can be undone. The ledger
    /// row and the plan revision are compared before mutation to avoid
    /// clobbering a later manual edit.
    func undoFinancePayment(id: String) throws {
        try commit(modules: ["core.finance"], commandID: "core.finance.undoPayment") { snapshot in
            var finance = snapshot.capture.finance ?? V2FinanceState()
            guard let paymentIndex = finance.payments.firstIndex(where: { $0.id == id }) else {
                throw V2FinanceError.paymentNotFound(id)
            }
            let payment = finance.payments[paymentIndex]
            guard payment.status == .applied else {
                throw V2FinanceError.paymentNotUndoable("记录已经撤销")
            }
            guard let latest = finance.payments
                .filter({ $0.planID == payment.planID && $0.status == .applied })
                .max(by: { $0.paidAt == $1.paidAt ? $0.id < $1.id : $0.paidAt < $1.paidAt }),
                latest.id == payment.id else {
                throw V2FinanceError.paymentNotUndoable("存在更晚的支付周期")
            }
            guard let planIndex = finance.plans.firstIndex(where: { $0.id == payment.planID }) else {
                throw V2FinanceError.financePlanNotFound(payment.planID)
            }
            let plan = finance.plans[planIndex]
            let expectedDueDate = payment.nextDueDate ?? payment.previousDueDate
            let expectedActive = payment.nextDueDate != nil
            guard plan.revision == payment.planRevisionAfter,
                  plan.dueDate == expectedDueDate,
                  plan.isActive == expectedActive else {
                throw V2FinanceError.paymentNotUndoable("计划已有后续修改")
            }
            guard let ledgerIndex = snapshot.capture.ledger.firstIndex(where: { $0.id == payment.ledgerID }),
                  snapshot.capture.ledger[ledgerIndex] == payment.ledgerAfter else {
                throw V2FinanceError.paymentNotUndoable("对应账单已被修改或删除")
            }

            snapshot.capture.ledger.remove(at: ledgerIndex)
            var restored = plan
            restored.revision = payment.planRevisionBefore
            restored.dueDate = payment.previousDueDate
            restored.isActive = payment.previousIsActive
            finance.plans[planIndex] = restored
            finance.payments[paymentIndex].status = .undone
            snapshot.capture.finance = finance
        }
    }

    @discardableResult
    func saveBudget(
        _ budget: V2Budget,
        expectedRevision: Int? = nil
    ) throws -> V2Budget {
        try commit(modules: ["core.budget"], commandID: "core.budget.set") { snapshot in
            var finance = snapshot.capture.finance ?? V2FinanceState()
            let existingIndex = finance.budgets.firstIndex { $0.id == budget.id }
            if let existingIndex {
                guard expectedRevision == nil || expectedRevision == finance.budgets[existingIndex].revision else {
                    throw V2FinanceError.financeConflict("预算版本不一致")
                }
            } else if expectedRevision != nil {
                throw V2FinanceError.financeConflict("预算已经被删除")
            }

            var candidate = try Self.validatedBudget(budget, snapshot: snapshot)
            candidate.revision = existingIndex.map { finance.budgets[$0].revision + 1 } ?? max(budget.revision, 1)
            if let existingIndex {
                finance.budgets[existingIndex] = candidate
            } else {
                finance.budgets.append(candidate)
            }
            snapshot.capture.finance = finance
            return candidate
        }
    }

    @discardableResult
    func saveBudget(
        budget: V2Budget,
        expectedRevision: Int? = nil
    ) throws -> V2Budget {
        try saveBudget(budget, expectedRevision: expectedRevision)
    }

    @discardableResult
    func removeBudget(id: String) throws -> V2Budget {
        try commit(modules: ["core.budget"], commandID: "core.budget.remove") { snapshot in
            var finance = snapshot.capture.finance ?? V2FinanceState()
            guard let index = finance.budgets.firstIndex(where: { $0.id == id }) else {
                throw V2FinanceError.budgetNotFound(id)
            }
            let removed = finance.budgets.remove(at: index)
            snapshot.capture.finance = finance
            return removed
        }
    }

    public func budgetProgress(
        for budgetID: String,
        timeZone: TimeZone = .current
    ) throws -> V2BudgetProgress {
        guard let finance = snapshot.capture.finance,
              let budget = finance.budgets.first(where: { $0.id == budgetID }) else {
            throw V2FinanceError.budgetNotFound(budgetID)
        }
        return Self.budgetProgress(for: budget, snapshot: snapshot, timeZone: timeZone)
    }

    public func budgetProgress(
        for budget: V2Budget,
        timeZone: TimeZone = .current
    ) -> V2BudgetProgress {
        Self.budgetProgress(for: budget, snapshot: snapshot, timeZone: timeZone)
    }
}

private extension V2Engine {
    static let financeCurrencies: Set<String> = V2CaptureContract.currencies

    static func validatedPlan(_ plan: V2FinancePlan, snapshot: V2AppSnapshot) throws -> V2FinancePlan {
        var result = plan
        result.id = result.id.trimmingCharacters(in: .whitespacesAndNewlines)
        result.title = result.title.trimmingCharacters(in: .whitespacesAndNewlines)
        result.currency = result.currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        result.prompt = result.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        result.link = result.link.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !result.id.isEmpty, result.id.count <= 120 else { throw V2FinanceError.invalidPlan("缺少计划 ID") }
        guard !result.title.isEmpty, result.title.count <= 120 else { throw V2FinanceError.invalidPlan("缺少标题") }
        guard V2CaptureContract.validAmount(result.amount) else { throw V2FinanceError.invalidPlan("金额必须为正数") }
        guard financeCurrencies.contains(result.currency) else { throw V2FinanceError.invalidPlan("币种不受支持") }
        guard result.revision > 0 else { throw V2FinanceError.invalidPlan("版本无效") }
        guard result.reminderDays >= 0 && result.reminderDays <= 365 else { throw V2FinanceError.invalidPlan("提醒天数无效") }
        guard result.prompt.count <= 500 else { throw V2FinanceError.invalidPlan("提醒话术过长") }
        guard result.attachmentIDs.count <= 20,
              Set(result.attachmentIDs).count == result.attachmentIDs.count else {
            throw V2FinanceError.invalidPlan("附件引用重复或过多")
        }
        for attachmentID in result.attachmentIDs {
            guard snapshot.capture.assets.contains(where: { $0.id == attachmentID }) else {
                throw V2FinanceError.invalidAttachment(attachmentID)
            }
        }
        try validateLink(result.link)
        let timeZone = try financeTimeZone(result.timeZoneIdentifier)
        guard let dueDate = financeDate(result.dueDate, timeZone: timeZone) else {
            throw V2FinanceError.invalidDate(result.dueDate)
        }
        let components = financeCalendar(timeZone).dateComponents([.year, .month, .day], from: dueDate)
        let dueDay = components.day ?? 0
        let dueMonth = components.month ?? 0
        switch result.recurrence {
        case .once:
            break
        case .monthly:
            let anchorDay = result.anchorDay ?? dueDay
            guard (1...31).contains(anchorDay) else { throw V2FinanceError.invalidPlan("每月锚定日无效") }
            result.anchorDay = anchorDay
            result.anchorMonth = nil
        case .yearly:
            let anchorDay = result.anchorDay ?? dueDay
            let anchorMonth = result.anchorMonth ?? dueMonth
            guard (1...31).contains(anchorDay), (1...12).contains(anchorMonth) else {
                throw V2FinanceError.invalidPlan("每年锚定日期无效")
            }
            result.anchorDay = anchorDay
            result.anchorMonth = anchorMonth
        }
        return result
    }

    static func validatedBudget(_ budget: V2Budget, snapshot: V2AppSnapshot) throws -> V2Budget {
        var result = budget
        result.id = result.id.trimmingCharacters(in: .whitespacesAndNewlines)
        result.currency = result.currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !result.id.isEmpty, result.id.count <= 120 else { throw V2FinanceError.invalidBudget("缺少预算 ID") }
        guard V2CaptureContract.validAmount(result.amount) else { throw V2FinanceError.invalidBudget("金额必须为正数") }
        guard financeCurrencies.contains(result.currency) else { throw V2FinanceError.invalidBudget("币种不受支持") }
        guard isValidMonth(result.month) else { throw V2FinanceError.invalidBudget("月份必须为 yyyy-MM") }
        if let categoryID = result.categoryID {
            guard snapshot.capture.categories.contains(where: { $0.id == categoryID }) else {
                throw V2FinanceError.invalidBudget("分类不存在")
            }
        }
        return result
    }

    static func budgetProgress(
        for budget: V2Budget,
        snapshot: V2AppSnapshot,
        timeZone: TimeZone
    ) -> V2BudgetProgress {
        let budgetAmount = decimal(budget.amount) ?? .zero
        let expectedCategory = canonicalCategoryID(budget.categoryID, categories: snapshot.capture.categories)
        let spent = snapshot.capture.ledger.reduce(into: Decimal.zero) { total, ledger in
            guard ledger.direction == .expense,
                  ledger.currency.uppercased() == budget.currency.uppercased(),
                  let amount = decimal(ledger.amount) else { return }
            let dateString = ledger.localDate.flatMap { isValidDate($0, timeZone: timeZone) ? $0 : nil }
                ?? V2CaptureContract.localDate(ledger.recordedAt, timeZone: timeZone)
            guard dateString.hasPrefix(budget.month) else { return }
            let category = canonicalCategoryID(ledger.categoryID, categories: snapshot.capture.categories)
            guard expectedCategory == nil || expectedCategory == category else { return }
            total += amount
        }
        return V2BudgetProgress(
            budgetID: budget.id,
            month: budget.month,
            currency: budget.currency,
            budgetAmount: budgetAmount,
            spent: spent,
            remaining: budgetAmount - spent,
            categoryID: budget.categoryID
        )
    }

    static func decimal(_ string: String) -> Decimal? {
        Decimal(string: string, locale: Locale(identifier: "en_US_POSIX"))
    }

    static func validateLink(_ link: String) throws {
        guard !link.isEmpty else { return }
        guard !link.unicodeScalars.contains(where: { $0.properties.isWhitespace || $0.value < 0x20 }),
              let url = URL(string: link),
              let scheme = url.scheme?.lowercased(),
              scheme.range(of: #"^[a-z][a-z0-9+.-]{1,31}$"#, options: .regularExpression) != nil else {
            throw V2FinanceError.invalidLink
        }
        switch scheme {
        case "http", "file", "javascript", "data", "blob", "about":
            throw V2FinanceError.invalidLink
        case "https":
            guard url.host != nil, url.user == nil, url.password == nil else { throw V2FinanceError.invalidLink }
        default:
            // Custom application schemes such as shortcuts:// and
            // comgooglemaps:// are allowed; they cannot contain a local path.
            guard !url.path.hasPrefix("/") || url.host != nil else { throw V2FinanceError.invalidLink }
        }
    }

    static func financeTimeZone(_ identifier: String) throws -> TimeZone {
        guard !identifier.isEmpty, let timeZone = TimeZone(identifier: identifier) else {
            throw V2FinanceError.invalidPlan("时区无效")
        }
        return timeZone
    }

    static func financeCalendar(_ timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
        return calendar
    }

    static func financeDate(_ value: String, timeZone: TimeZone) -> Date? {
        guard value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = financeCalendar(timeZone)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: value) else { return nil }
        return V2CaptureContract.localDate(date, timeZone: timeZone) == value ? date : nil
    }

    static func isValidDate(_ value: String, timeZone: TimeZone) -> Bool {
        financeDate(value, timeZone: timeZone) != nil
    }

    static func isValidMonth(_ value: String) -> Bool {
        guard value.range(of: #"^\d{4}-\d{2}$"#, options: .regularExpression) != nil,
              let month = Int(value.suffix(2)) else { return false }
        return (1...12).contains(month)
    }

    static func nextDueDate(
        for plan: V2FinancePlan,
        due: Date,
        timeZone: TimeZone
    ) throws -> String? {
        guard plan.recurrence != .once else { return nil }
        var calendar = financeCalendar(timeZone)
        let current = calendar.dateComponents([.year, .month, .day], from: due)
        let year = current.year ?? 0
        let month = current.month ?? 0
        let anchorDay = plan.anchorDay ?? current.day ?? 1
        let targetYear: Int
        let targetMonth: Int
        switch plan.recurrence {
        case .once:
            return nil
        case .monthly:
            if month == 12 {
                targetYear = year + 1
                targetMonth = 1
            } else {
                targetYear = year
                targetMonth = month + 1
            }
        case .yearly:
            targetYear = year + 1
            targetMonth = plan.anchorMonth ?? month
        }
        guard let date = clampedDate(year: targetYear, month: targetMonth, day: anchorDay, calendar: &calendar) else {
            throw V2FinanceError.invalidDate(plan.dueDate)
        }
        return V2CaptureContract.localDate(date, timeZone: timeZone)
    }

    static func clampedDate(year: Int, month: Int, day: Int, calendar: inout Calendar) -> Date? {
        guard let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: first) else { return nil }
        var components = DateComponents(year: year, month: month, day: min(day, range.count))
        components.hour = 0
        components.minute = 0
        components.second = 0
        return calendar.date(from: components)
    }

    static func canonicalCategoryID(_ categoryID: String?, categories: [V2LedgerCategory]) -> String? {
        guard var id = categoryID else { return nil }
        var visited = Set<String>()
        while let category = categories.first(where: { $0.id == id }),
              let mergedIntoID = category.mergedIntoID,
              visited.insert(id).inserted {
            id = mergedIntoID
        }
        return id
    }
}

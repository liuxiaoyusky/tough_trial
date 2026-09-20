import Foundation
import XCTest
@testable import ToughTrialV2Core

final class V2FinanceTests: XCTestCase {
    private let utc = TimeZone(secondsFromGMT: 0)!

    func testPaidOncePlanCannotBeRestoredIntoAnAlreadyPaidPeriod() throws {
        let engine = V2Engine()
        let plan = try engine.saveFinancePlan(.init(title: "Bill", kind: .bill, amount: "10", currency: "CNY", dueDate: "2026-09-10"))
        _ = try engine.payFinancePlan(id: plan.id, expectedDueDate: plan.dueDate)
        XCTAssertThrowsError(try engine.setFinancePlanActive(id: plan.id, isActive: true))
        var next = try XCTUnwrap(engine.snapshot.capture.finance?.plans.first)
        next.dueDate = "2026-09-11"
        _ = try engine.saveFinancePlan(next, expectedRevision: next.revision)
        XCTAssertTrue(try engine.setFinancePlanActive(id: next.id, isActive: true).isActive)
    }
    func testPlanDefaultsCreditCardAndLoanToTransferAndValidatesAttachmentAndLink() throws {
        let assetID = UUID().uuidString
        var capture = V2CaptureState()
        capture.assets = [
            .init(
                id: assetID,
                kind: .document,
                fileName: "statement.pdf",
                sha256: String(repeating: "a", count: 64),
                byteCount: 3
            )
        ]
        let engine = V2Engine(snapshot: .init(capture: capture))
        let plan = V2FinancePlan(
            title: "信用卡还款",
            kind: .creditCard,
            amount: "1000",
            currency: "cny",
            dueDate: "2026-09-30",
            timeZoneIdentifier: "UTC",
            link: "bankapp://pay",
            attachmentIDs: [assetID]
        )

        let saved = try engine.saveFinancePlan(plan)
        XCTAssertEqual(saved.direction, .transfer)
        XCTAssertEqual(saved.currency, "CNY")

        var bad = plan
        bad.id = UUID().uuidString
        bad.link = "file:///private/statement.pdf"
        XCTAssertThrowsError(try engine.saveFinancePlan(bad)) { error in
            XCTAssertEqual(error as? V2FinanceError, .invalidLink)
        }

        bad.link = "https://bank.example/pay"
        bad.attachmentIDs = [UUID().uuidString]
        XCTAssertThrowsError(try engine.saveFinancePlan(bad)) { error in
            XCTAssertEqual(error as? V2FinanceError, .invalidAttachment(bad.attachmentIDs[0]))
        }
    }

    func testMonthlyAnchorReturnsToThirtyFirstAfterShortMonthAndHandlesLeapYear() throws {
        let engine = V2Engine()
        let plan = V2FinancePlan(
            title: "月租",
            kind: .rent,
            amount: "10",
            currency: "CNY",
            dueDate: "2024-01-31",
            timeZoneIdentifier: "UTC",
            recurrence: .monthly
        )
        let saved = try engine.saveFinancePlan(plan)
        _ = try engine.payFinancePlan(id: saved.id, expectedRevision: saved.revision, expectedDueDate: "2024-01-31", at: date("2024-01-31"))
        XCTAssertEqual(engine.snapshot.capture.finance?.plans.first?.dueDate, "2024-02-29")

        let secondPlan = try XCTUnwrap(engine.snapshot.capture.finance?.plans.first)
        _ = try engine.payFinancePlan(id: secondPlan.id, expectedRevision: secondPlan.revision, expectedDueDate: "2024-02-29", at: date("2024-02-29"))
        XCTAssertEqual(engine.snapshot.capture.finance?.plans.first?.dueDate, "2024-03-31")

        let nonLeapEngine = V2Engine()
        let nonLeap = try nonLeapEngine.saveFinancePlan(.init(
            title: "月租",
            kind: .rent,
            amount: "10",
            currency: "CNY",
            dueDate: "2023-01-31",
            timeZoneIdentifier: "UTC",
            recurrence: .monthly
        ))
        _ = try nonLeapEngine.payFinancePlan(id: nonLeap.id, expectedDueDate: "2023-01-31", at: date("2023-01-31"))
        XCTAssertEqual(nonLeapEngine.snapshot.capture.finance?.plans.first?.dueDate, "2023-02-28")
        let nonLeapNext = try XCTUnwrap(nonLeapEngine.snapshot.capture.finance?.plans.first)
        _ = try nonLeapEngine.payFinancePlan(id: nonLeapNext.id, expectedDueDate: "2023-02-28", at: date("2023-02-28"))
        XCTAssertEqual(nonLeapEngine.snapshot.capture.finance?.plans.first?.dueDate, "2023-03-31")

        let yearBoundaryEngine = V2Engine()
        let yearBoundary = try yearBoundaryEngine.saveFinancePlan(.init(
            title: "年末服务",
            kind: .bill,
            amount: "10",
            currency: "CNY",
            dueDate: "2023-11-30",
            timeZoneIdentifier: "UTC",
            recurrence: .monthly
        ))
        _ = try yearBoundaryEngine.payFinancePlan(id: yearBoundary.id, expectedDueDate: "2023-11-30", at: date("2023-11-30"))
        XCTAssertEqual(yearBoundaryEngine.snapshot.capture.finance?.plans.first?.dueDate, "2023-12-30")
        let december = try XCTUnwrap(yearBoundaryEngine.snapshot.capture.finance?.plans.first)
        _ = try yearBoundaryEngine.payFinancePlan(id: december.id, expectedDueDate: "2023-12-30", at: date("2023-12-30"))
        XCTAssertEqual(yearBoundaryEngine.snapshot.capture.finance?.plans.first?.dueDate, "2024-01-30")
    }

    func testYearlyLeapDayKeepsAnchorWithoutDrifting() throws {
        let engine = V2Engine()
        let plan = try engine.saveFinancePlan(.init(
            title: "年度服务",
            kind: .subscription,
            amount: "10",
            currency: "CNY",
            dueDate: "2024-02-29",
            timeZoneIdentifier: "UTC",
            recurrence: .yearly
        ))
        _ = try engine.payFinancePlan(id: plan.id, expectedDueDate: "2024-02-29", at: date("2024-02-29"))
        XCTAssertEqual(engine.snapshot.capture.finance?.plans.first?.dueDate, "2025-02-28")
        let next = try XCTUnwrap(engine.snapshot.capture.finance?.plans.first)
        _ = try engine.payFinancePlan(id: next.id, expectedDueDate: "2025-02-28", at: date("2025-02-28"))
        XCTAssertEqual(engine.snapshot.capture.finance?.plans.first?.dueDate, "2026-02-28")
    }

    func testPaymentIsAtomicAndIdempotentForSamePeriod() throws {
        let engine = V2Engine()
        let plan = try engine.saveFinancePlan(.init(
            title: "ChatGPT",
            kind: .subscription,
            amount: "20",
            currency: "USD",
            dueDate: "2026-09-10",
            timeZoneIdentifier: "UTC"
        ))
        let first = try engine.payFinancePlan(id: plan.id, expectedRevision: plan.revision, expectedDueDate: plan.dueDate, at: date("2026-09-10"))
        let retry = try engine.payFinancePlan(id: plan.id, expectedRevision: plan.revision, expectedDueDate: plan.dueDate, at: date("2026-09-10").addingTimeInterval(60))
        XCTAssertEqual(retry, first)
        XCTAssertEqual(engine.snapshot.capture.ledger.count, 1)
        XCTAssertEqual(engine.snapshot.capture.finance?.payments.count, 1)
        XCTAssertEqual(engine.snapshot.capture.ledger.first?.direction, .expense)
        XCTAssertEqual(engine.snapshot.capture.ledger.first?.categoryID, "others")
    }

    func testUndoLatestPaymentRestoresPlanAndLedgerAndRejectsLaterEdit() throws {
        let engine = V2Engine()
        let plan = try engine.saveFinancePlan(.init(
            title: "房租",
            kind: .rent,
            amount: "100",
            currency: "CNY",
            dueDate: "2026-09-10",
            timeZoneIdentifier: "UTC"
        ))
        let payment = try engine.payFinancePlan(id: plan.id, expectedDueDate: plan.dueDate, at: date("2026-09-10"))
        try engine.undoFinancePayment(id: payment.id)
        XCTAssertTrue(engine.snapshot.capture.ledger.isEmpty)
        XCTAssertEqual(engine.snapshot.capture.finance?.payments.first?.status, .undone)
        XCTAssertEqual(engine.snapshot.capture.finance?.plans.first?.dueDate, plan.dueDate)
        XCTAssertEqual(engine.snapshot.capture.finance?.plans.first?.revision, plan.revision)

        let secondPayment = try engine.payFinancePlan(id: plan.id, expectedDueDate: plan.dueDate, at: date("2026-09-10"))
        var edited = try XCTUnwrap(engine.snapshot.capture.finance?.plans.first)
        edited.title = "房租（已改）"
        _ = try engine.saveFinancePlan(edited, expectedRevision: edited.revision)
        XCTAssertThrowsError(try engine.undoFinancePayment(id: secondPayment.id)) { error in
            guard case .paymentNotUndoable = error as? V2FinanceError else {
                return XCTFail("expected an undo conflict, got \(error)")
            }
        }
        XCTAssertEqual(engine.snapshot.capture.ledger.count, 1)
    }

    func testUndoDoesNotOverwriteManualLedgerCategoryEdit() throws {
        let engine = V2Engine()
        let plan = try engine.saveFinancePlan(.init(
            title: "订阅",
            kind: .subscription,
            amount: "20",
            currency: "CNY",
            dueDate: "2026-09-10",
            timeZoneIdentifier: "UTC"
        ))
        let payment = try engine.payFinancePlan(id: plan.id, expectedDueDate: plan.dueDate, at: date("2026-09-10"))
        let category = try engine.createLedgerCategory(name: "软件", confirmed: true)
        let ledger = try XCTUnwrap(engine.snapshot.capture.ledger.first)
        try engine.confirmLedgerCategory(
            ledgerID: ledger.id,
            categoryName: category.name,
            expectedRevision: ledger.revision,
            confirmed: true
        )
        XCTAssertThrowsError(try engine.undoFinancePayment(id: payment.id)) { error in
            guard case .paymentNotUndoable = error as? V2FinanceError else {
                return XCTFail("expected a ledger conflict, got \(error)")
            }
        }
        XCTAssertEqual(engine.snapshot.capture.ledger.first?.categoryID, category.id)
    }

    func testBudgetExcludesTransfersAndMixedCurrenciesAndFollowsMergedCategory() throws {
        let source = V2LedgerCategory(id: "travel", name: "旅行", mergedIntoID: "leisure")
        let target = V2LedgerCategory(id: "leisure", name: "休闲")
        let date = date("2026-09-10")
        let entries = [
            V2LedgerEntry(id: "expense", amount: "30", currency: "CNY", direction: .expense, text: "晚餐", localDate: nil, categoryID: source.id, recordedAt: date, receiptID: "receipt-expense"),
            V2LedgerEntry(id: "transfer", amount: "100", currency: "CNY", direction: .transfer, text: "还款转账", localDate: "2026-09-10", categoryID: "others", recordedAt: date, receiptID: "receipt-transfer"),
            V2LedgerEntry(id: "usd", amount: "99", currency: "USD", direction: .expense, text: "美元", localDate: "2026-09-10", categoryID: target.id, recordedAt: date, receiptID: "receipt-usd")
        ]
        var capture = V2CaptureState()
        capture.categories = [V2LedgerCategory(id: "others", name: "Others"), source, target]
        capture.ledger = entries
        let engine = V2Engine(snapshot: .init(capture: capture))
        let budget = try engine.saveBudget(.init(currency: "CNY", amount: "100", month: "2026-09", categoryID: source.id))
        let progress = try engine.budgetProgress(for: budget.id, timeZone: utc)
        XCTAssertEqual(progress.spent, Decimal(30))
        XCTAssertEqual(progress.remaining, Decimal(70))
    }

    func testOncePaymentDeactivatesPlanAndConflictsDoNotWritePartialLedger() throws {
        let engine = V2Engine()
        let plan = try engine.saveFinancePlan(.init(
            title: "一次性账单",
            kind: .bill,
            amount: "50",
            currency: "CNY",
            dueDate: "2026-09-10",
            timeZoneIdentifier: "UTC",
            recurrence: .once
        ))
        let payment = try engine.payFinancePlan(id: plan.id, expectedDueDate: plan.dueDate, at: date("2026-09-10"))
        XCTAssertFalse(try XCTUnwrap(engine.snapshot.capture.finance?.plans.first).isActive)
        XCTAssertThrowsError(try engine.payFinancePlan(id: plan.id, expectedRevision: plan.revision, expectedDueDate: "2026-09-11", at: date("2026-09-10")))
        XCTAssertEqual(engine.snapshot.capture.ledger.count, 1)
        XCTAssertEqual(engine.snapshot.capture.finance?.payments.first?.id, payment.id)
    }

    private func date(_ value: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = utc
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)!
    }
}

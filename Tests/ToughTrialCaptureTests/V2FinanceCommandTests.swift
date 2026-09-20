import Foundation
import XCTest
@testable import ToughTrialV2Core

final class V2FinanceCommandTests: XCTestCase {
    private enum AuthorizationError: Error { case denied }

    func testAuthorizationRejectsEveryCommandWithoutWriting() throws {
        let engine = V2Engine()
        let before = engine.snapshot
        var calls: [[String]] = []
        let dispatcher = V2FinanceCommandDispatcher(engine: engine) { modules in
            calls.append(modules)
            throw AuthorizationError.denied
        }
        let plan = V2FinancePlan(
            title: "Plan",
            kind: .subscription,
            amount: "10",
            currency: "USD",
            dueDate: "2026-09-10"
        )
        let budget = V2Budget(currency: "USD", amount: "100", month: "2026-09")
        let commands: [V2FinanceCommand] = [
            .savePlan(plan, expectedRevision: nil),
            .setPlanActive(id: plan.id, isActive: false, expectedRevision: nil),
            .markPaid(id: plan.id, expectedRevision: 1, expectedDueDate: plan.dueDate),
            .undoPayment(id: "payment"),
            .saveBudget(budget, expectedRevision: nil),
            .removeBudget(id: budget.id)
        ]

        for command in commands {
            XCTAssertThrowsError(try dispatcher.execute(command, context: .init()))
            XCTAssertEqual(engine.snapshot, before)
        }
        XCTAssertEqual(calls.count, commands.count)
    }

    func testMarkPaidRequiresHostConfirmationAndAllowedActor() throws {
        let engine = V2Engine()
        let dispatcher = V2FinanceCommandDispatcher(engine: engine)
        let plan = try dispatcher.execute(
            .savePlan(.init(
                title: "Plan",
                kind: .subscription,
                amount: "10",
                currency: "USD",
                dueDate: "2026-09-10"
            ), expectedRevision: nil),
            context: .init()
        )
        let savedPlan = try XCTUnwrap(engine.snapshot.capture.finance?.plans.first)

        XCTAssertThrowsError(try dispatcher.execute(
            .markPaid(id: savedPlan.id, expectedRevision: savedPlan.revision, expectedDueDate: savedPlan.dueDate),
            context: .init(actor: .manual)
        )) { error in
            XCTAssertEqual(error as? V2FinanceCommandError, .paymentConfirmationRequired)
        }
        XCTAssertTrue(engine.snapshot.capture.ledger.isEmpty)

        for actor in [V2CommandActor.background, .plugin] {
            XCTAssertThrowsError(try dispatcher.execute(
                .markPaid(id: savedPlan.id, expectedRevision: savedPlan.revision, expectedDueDate: savedPlan.dueDate),
                context: .init(actor: actor, confirmedPayment: true)
            )) { error in
                XCTAssertEqual(error as? V2FinanceCommandError, .paymentActorNotAllowed)
            }
        }
        XCTAssertEqual(plan.status, .applied)
        XCTAssertTrue(engine.snapshot.capture.ledger.isEmpty)
    }

    func testDuplicatePaymentHasOneLedgerRowAndStablePaymentReceiptID() throws {
        let engine = V2Engine()
        let dispatcher = V2FinanceCommandDispatcher(engine: engine)
        let saved = try dispatcher.execute(
            .savePlan(.init(
                title: "Plan",
                kind: .subscription,
                amount: "10",
                currency: "USD",
                dueDate: "2026-09-10",
                timeZoneIdentifier: "UTC"
            ), expectedRevision: nil),
            context: .init()
        )
        let plan = try XCTUnwrap(engine.snapshot.capture.finance?.plans.first)
        let command = V2FinanceCommand.markPaid(
            id: plan.id,
            expectedRevision: plan.revision,
            expectedDueDate: plan.dueDate
        )
        let context = V2CommandContext(traceID: "trace-1", actor: .manual, confirmedPayment: true)
        let first = try dispatcher.execute(command, context: context)
        let retry = try dispatcher.execute(
            command,
            context: .init(traceID: "trace-2", actor: .assistant, confirmedPayment: true),
            at: Date(timeIntervalSince1970: 10)
        )
        let payment = try XCTUnwrap(engine.snapshot.capture.finance?.payments.first)

        XCTAssertEqual(saved.status, .applied)
        XCTAssertEqual(first.id, payment.id)
        XCTAssertEqual(retry.id, payment.id)
        XCTAssertEqual(first.undoRef, .financePayment(payment.id))
        XCTAssertEqual(engine.snapshot.capture.ledger.count, 1)
        XCTAssertEqual(engine.snapshot.capture.finance?.payments.count, 1)
    }

    func testUndoProjectsUndoneReceiptAndRespectsConcurrentPlanEdit() throws {
        let engine = V2Engine()
        let dispatcher = V2FinanceCommandDispatcher(engine: engine)
        _ = try dispatcher.execute(
            .savePlan(.init(
                title: "Plan",
                kind: .subscription,
                amount: "10",
                currency: "USD",
                dueDate: "2026-09-10",
                timeZoneIdentifier: "UTC"
            ), expectedRevision: nil),
            context: .init()
        )
        var plan = try XCTUnwrap(engine.snapshot.capture.finance?.plans.first)
        let paid = try dispatcher.execute(
            .markPaid(id: plan.id, expectedRevision: plan.revision, expectedDueDate: plan.dueDate),
            context: .init(confirmedPayment: true)
        )
        let undone = try dispatcher.execute(
            .undoPayment(id: paid.id),
            context: .init(traceID: "undo-trace")
        )
        XCTAssertEqual(undone.id, paid.id)
        XCTAssertEqual(undone.status, .undone)
        XCTAssertNil(undone.undoRef)
        XCTAssertTrue(engine.snapshot.capture.ledger.isEmpty)

        plan = try XCTUnwrap(engine.snapshot.capture.finance?.plans.first)
        let secondPayment = try dispatcher.execute(
            .markPaid(id: plan.id, expectedRevision: plan.revision, expectedDueDate: plan.dueDate),
            context: .init(confirmedPayment: true)
        )
        plan = try XCTUnwrap(engine.snapshot.capture.finance?.plans.first)
        plan.title = "Edited after payment"
        _ = try engine.saveFinancePlan(plan, expectedRevision: plan.revision)

        XCTAssertThrowsError(try dispatcher.execute(
            .undoPayment(id: secondPayment.id),
            context: .init()
        )) { error in
            guard case .paymentNotUndoable = error as? V2FinanceError else {
                return XCTFail("expected payment undo conflict, got \(error)")
            }
        }
        XCTAssertEqual(engine.snapshot.capture.ledger.count, 1)
    }

    func testRestoredPaymentReceiptKeepsPaymentIDAndStatusWithoutTrace() throws {
        let engine = V2Engine()
        let dispatcher = V2FinanceCommandDispatcher(engine: engine)
        _ = try dispatcher.execute(
            .savePlan(.init(
                title: "Plan",
                kind: .subscription,
                amount: "10",
                currency: "USD",
                dueDate: "2026-09-10",
                timeZoneIdentifier: "UTC"
            ), expectedRevision: nil),
            context: .init()
        )
        let plan = try XCTUnwrap(engine.snapshot.capture.finance?.plans.first)
        let receipt = try dispatcher.execute(
            .markPaid(id: plan.id, expectedRevision: plan.revision, expectedDueDate: plan.dueDate),
            context: .init(traceID: "runtime-trace", confirmedPayment: true)
        )

        let restored = V2Engine(snapshot: try JSONDecoder().decode(
            V2AppSnapshot.self,
            from: JSONEncoder().encode(engine.snapshot)
        ))
        let restoredReceipt = try XCTUnwrap(V2OperationReceipt.paymentReceipts(from: restored.snapshot).first)
        XCTAssertEqual(restoredReceipt.id, receipt.id)
        XCTAssertEqual(restoredReceipt.status, .applied)
        XCTAssertNil(restoredReceipt.traceID)
        XCTAssertEqual(restoredReceipt.undoRef, .financePayment(receipt.id))

        try dispatcher.execute(.undoPayment(id: receipt.id), context: .init())
        let restoredUndone = V2OperationReceipt.paymentReceipts(from: engine.snapshot)
        XCTAssertEqual(restoredUndone.first?.status, .undone)
        XCTAssertNil(restoredUndone.first?.undoRef)
    }

    func testForgedPlanDraftFieldsAreRejected() throws {
        let draft = V2FinancePlanDraft(
            title: "Plan",
            kind: .subscription,
            amount: "10",
            currency: "USD",
            dueDate: "2026-09-10"
        )
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(draft)) as? [String: Any])
        object["id"] = "forged-id"
        object["revision"] = 999
        object["status"] = "applied"
        object["confirmation"] = true
        object["traceID"] = "forged-trace"
        let data = try JSONSerialization.data(withJSONObject: object)

        XCTAssertThrowsError(try V2FinancePlanDraft.decodeJSON(data)) { error in
            guard case .unknownDraftFields(let fields) = error as? V2FinanceCommandError else {
                return XCTFail("expected unknown draft fields, got \(error)")
            }
            XCTAssertEqual(fields, ["confirmation", "id", "revision", "status", "traceID"])
        }
    }

    func testDescriptorWritableKeysMatchEncodedDraftKeysAndHostMapping() throws {
        let draft = V2FinancePlanDraft(
            title: "Plan",
            kind: .bill,
            amount: "10",
            currency: "USD",
            dueDate: "2026-09-10"
        )
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(draft)) as? [String: Any])
        XCTAssertEqual(Set(object.keys), V2FinanceCommandDescriptor.savePlan.writableKeys)
        XCTAssertEqual(
            V2FinanceCommandDescriptor.savePlan.writableKeys,
            V2FinancePlanDraft.writableKeys
        )

        let plan = draft.toPlan(id: "host-id", timeZoneIdentifier: "UTC")
        XCTAssertEqual(plan.id, "host-id")
        XCTAssertEqual(plan.timeZoneIdentifier, "UTC")
        XCTAssertEqual(plan.title, draft.title)
        XCTAssertFalse(object.keys.contains("id"))
        XCTAssertFalse(object.keys.contains("revision"))
        XCTAssertFalse(object.keys.contains("isActive"))
        XCTAssertFalse(object.keys.contains("timeZoneIdentifier"))
    }
}

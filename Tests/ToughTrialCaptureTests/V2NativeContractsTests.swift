import XCTest
@testable import ToughTrialV2Core

final class V2NativeContractsTests: XCTestCase {
    func testNativeCatalogCoversEveryBuiltinModuleAndRequiredAICommands() {
        let modules = Set(V2ModuleDescriptor.builtins.map(\.id))
        let definitions = V2NativeModuleDefinition.builtins
        XCTAssertEqual(Set(definitions.map { $0.descriptor.id }), modules)
        XCTAssertTrue(V2NativeCommandDescriptor.builtins.allSatisfy { modules.contains($0.moduleID) })
        XCTAssertTrue(V2NativeQueryDescriptor.builtins.allSatisfy { modules.contains($0.moduleID) })
        for id in [
            "core.tasks.create", "core.tasks.schedule", "core.capture.create",
            "core.ledger.createPending", "core.ledger.proposeCategory",
            "core.finance.createPlan", "core.finance.markPaid", "core.budget.set",
            "core.budget.queryProgress", "core.recall.append", "core.notes.create"
        ] {
            if id == "core.budget.queryProgress" {
                XCTAssertNotNil(V2NativeQueryDescriptor.builtins.first { $0.id == "core.budget.queryProgress" })
            } else {
                XCTAssertNotNil(V2NativeCommandDescriptor.builtins.first { $0.id == id }, id)
            }
        }
    }

    func testUnknownCommandIsRejectedAtReceiver() {
        let runtime = V2ModuleRuntime()
        XCTAssertThrowsError(try runtime.requireCommand("core.tasks.guessed")) { error in
            XCTAssertEqual(error as? V2ModuleRuntimeError, .commandNotRegistered("core.tasks.guessed"))
        }
    }

    func testContextCannotCrossModuleAndBecomesStaleAfterDisable() throws {
        let runtime = V2ModuleRuntime()
        let sends = TestCounter()
        let context = try runtime.makeContext(
            for: "core.tasks",
            send: { envelope in
                sends.value += 1
                return V2NativeOperationReceipt(
                    operationID: envelope.operationID,
                    idempotencyKey: envelope.idempotencyKey,
                    commandID: envelope.commandID,
                    status: .applied
                )
            },
            read: { _, _ in Data() }
        )

        let valid = V2NativeCommandEnvelope(
            idempotencyKey: "test-1",
            callerModuleID: "core.tasks",
            commandID: "core.tasks.create",
            commandVersion: 1,
            contractDigest: runtime.commandDescriptor("core.tasks.create")!.contractDigest
        )
        XCTAssertEqual(try context.commands.invoke(valid).status, .applied)
        XCTAssertEqual(sends.value, 1)

        let crossModule = V2NativeCommandEnvelope(
            idempotencyKey: "test-2",
            callerModuleID: "core.tasks",
            commandID: "core.finance.createPlan",
            commandVersion: 1,
            contractDigest: runtime.commandDescriptor("core.tasks.create")!.contractDigest
        )
        XCTAssertThrowsError(try context.commands.invoke(crossModule))

        var disabled = runtime.preferences
        disabled.disabled.insert("core.tasks")
        runtime.update(preferences: disabled)
        XCTAssertThrowsError(try context.commands.invoke(valid))
        XCTAssertEqual(sends.value, 1)
    }

    func testDisablingModuleCancelsOwnedContributionsAndJobs() throws {
        let runtime = V2ModuleRuntime()
        let contributionCleanup = TestCounter()
        let jobCancellation = TestCounter()
        let contribution = try runtime.registerContribution(moduleID: "core.tasks", contributionID: "today") {
            contributionCleanup.value += 1
        }
        let job = try runtime.registerJob(moduleID: "core.tasks", jobID: "reminders") {
            jobCancellation.value += 1
        }
        var disabled = runtime.preferences
        disabled.disabled.insert("core.tasks")
        runtime.update(preferences: disabled)
        XCTAssertFalse(contribution.isActive)
        XCTAssertFalse(job.isActive)
        XCTAssertEqual(contributionCleanup.value, 1)
        XCTAssertEqual(jobCancellation.value, 1)
    }

    func testQueriesAreBoundedAndFieldsAreReadOnlyDescriptors() throws {
        let runtime = V2ModuleRuntime()
        XCTAssertThrowsError(try runtime.requireQuery("core.ledger.recent", limit: 101))
        let query = try runtime.requireQuery("core.ledger.recent", limit: 100)
        XCTAssertEqual(query.projection, "ledger.entries")
        XCTAssertEqual(query.maxPageSize, 100)
        XCTAssertThrowsError(try runtime.requireQuery("core.ledger.recent", limit: 0))
        XCTAssertNil(runtime.queryRegistry.descriptor("core.ledger.recent")?.allowedFields.first { $0 == "amount" })
    }

    func testManualLedgerDoesNotRequireCaptureModule() throws {
        let runtime = V2ModuleRuntime(preferences: .init(disabled: ["core.capture"]))
        let engine = V2Engine(moduleRuntime: runtime)
        let entry = try engine.createManualLedgerEntry(
            amount: "38.00",
            currency: "cny",
            text: "午饭",
            at: Date(timeIntervalSince1970: 1_000)
        )
        XCTAssertEqual(entry.amount, "38.00")
        XCTAssertEqual(entry.currency, "CNY")
        XCTAssertEqual(engine.snapshot.capture.ledger.count, 1)
        XCTAssertTrue(engine.snapshot.capture.entries.isEmpty)
    }

    func testManualLedgerCannotSilentlyAssignAFormalCategory() throws {
        let runtime = V2ModuleRuntime(preferences: .init(disabled: ["core.capture"]))
        let engine = V2Engine(moduleRuntime: runtime)
        let category = try engine.createLedgerCategory(name: "餐饮", confirmed: true)
        XCTAssertThrowsError(try engine.createManualLedgerEntry(
            amount: "38",
            currency: "CNY",
            text: "午饭",
            categoryID: category.id
        )) { error in
            XCTAssertEqual(error as? V2CaptureError, .confirmationRequired)
        }
        let entry = try engine.createManualLedgerEntry(
            amount: "38",
            currency: "CNY",
            text: "午饭",
            categoryID: category.id,
            categoryConfirmed: true
        )
        XCTAssertEqual(entry.categoryID, category.id)
    }

    func testStandaloneMemoryEngineUsesNotesModuleWhenRuntimeIsAttached() throws {
        let runtime = V2ModuleRuntime(preferences: .init(disabled: ["core.notes"]))
        let engine = V2MemoryEngine(moduleRuntime: runtime)
        XCTAssertThrowsError(try engine.add(
            statement: "偏好",
            kind: .preference,
            origin: .explicitUser,
            at: Date()
        ))
    }
}

private final class TestCounter: @unchecked Sendable {
    var value = 0
}

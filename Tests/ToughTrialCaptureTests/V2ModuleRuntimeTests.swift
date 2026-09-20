import XCTest
@testable import ToughTrialV2Core

final class V2ModuleRuntimeTests: XCTestCase {
    func testBuiltinsUseCanonicalIDsAndDecoupledDependencies() {
        let descriptors = Dictionary(uniqueKeysWithValues: V2ModuleDescriptor.builtins.map { ($0.id, $0) })
        XCTAssertEqual(descriptors.count, 14)
        XCTAssertEqual(descriptors["core.ledger"]?.dependencies, [])
        XCTAssertEqual(descriptors["core.finance"]?.dependencies, ["core.ledger"])
        XCTAssertEqual(descriptors["core.budget"]?.dependencies, ["core.ledger"])
        XCTAssertEqual(descriptors["core.imports"]?.dependencies, ["core.capture"])
        XCTAssertEqual(descriptors["core.attachments"]?.dependencies, [])
        XCTAssertEqual(descriptors["core.web"]?.dependencies, ["core.assistant"])
        XCTAssertEqual(descriptors["core.sync"]?.dependencies, ["core.tasks"])
    }

    func testUnknownMissingAndCycleAreBlocked() {
        let registry = V2ModuleRegistry(descriptors: [
            .init(id: "community.missing", name: "Missing", dependencies: ["community.nope"]),
            .init(id: "community.a", name: "A", dependencies: ["community.b"]),
            .init(id: "community.b", name: "B", dependencies: ["community.a"])
        ])
        let unknown = registry.availability("community.nope", preferences: .init())
        XCTAssertFalse(unknown.isActive)
        XCTAssertEqual(unknown.reason, "未知模块")
        let missing = registry.availability("community.missing", preferences: .init())
        XCTAssertFalse(missing.isActive)
        XCTAssertTrue(missing.blockedBy.contains("community.nope"))
        XCTAssertFalse(registry.availability("community.a", preferences: .init()).isActive)
        XCTAssertFalse(registry.availability("community.b", preferences: .init()).isActive)
    }

    func testLedgerIsIndependentOfCapture() {
        let preferences = V2ModulePreferences(disabled: ["core.capture"])
        let runtime = V2ModuleRuntime(preferences: preferences)
        XCTAssertFalse(runtime.availability("core.capture").isActive)
        XCTAssertTrue(runtime.availability("core.ledger").isActive)
        XCTAssertTrue(runtime.availability("core.finance").isActive)
    }

    func testBlockedDependentReportsDependency() {
        let runtime = V2ModuleRuntime(preferences: .init(disabled: ["core.ledger"]))
        let budget = runtime.availability("core.budget")
        XCTAssertFalse(budget.isActive)
        XCTAssertTrue(budget.blockedBy.contains("core.ledger"))
        XCTAssertThrowsError(try runtime.require(["core.budget"]))
    }

    func testHiddenSurfaceChangeDoesNotInvalidateTicket() throws {
        let runtime = V2ModuleRuntime()
        let ticket = try runtime.ticket(for: ["core.tasks"])
        var next = runtime.preferences
        next.hiddenSurfaces.insert("today")
        runtime.update(preferences: next)
        XCTAssertNoThrow(try runtime.validate(ticket))
    }

    func testDisableReenableMakesOldTicketStale() throws {
        let runtime = V2ModuleRuntime()
        let ticket = try runtime.ticket(for: ["core.tasks"])
        var disabled = runtime.preferences
        disabled.disabled.insert("core.tasks")
        runtime.update(preferences: disabled)
        XCTAssertThrowsError(try runtime.validate(ticket))
        runtime.update(preferences: .init())
        XCTAssertThrowsError(try runtime.validate(ticket))
        XCTAssertNoThrow(try runtime.require(["core.tasks"]))
    }

    func testDependencyChangeInvalidatesDescendantTicket() throws {
        let runtime = V2ModuleRuntime()
        let ticket = try runtime.ticket(for: ["core.sync"])
        var next = runtime.preferences
        next.disabled.insert("core.tasks")
        runtime.update(preferences: next)
        XCTAssertFalse(runtime.availability("core.sync").isActive)
        XCTAssertThrowsError(try runtime.validate(ticket))
    }

    func testLeaseIsThreadSafeAndInvalidatesLikeTicket() throws {
        let runtime = V2ModuleRuntime()
        let lease = try runtime.lease(for: ["core.tasks"])
        XCTAssertNoThrow(try lease.validate())
        var disabled = runtime.preferences
        disabled.disabled.insert("core.tasks")
        runtime.update(preferences: disabled)
        XCTAssertThrowsError(try lease.validate())
    }

    func testHiddenSurfaceChangeKeepsLeaseValid() throws {
        let runtime = V2ModuleRuntime()
        let lease = try runtime.lease(for: ["core.tasks"])
        var next = runtime.preferences
        next.hiddenSurfaces.insert("tasks")
        runtime.update(preferences: next)
        XCTAssertNoThrow(try lease.validate())
    }

    func testRuntimeDoesNotRetainReleasedLeases() throws {
        let runtime = V2ModuleRuntime()
        weak var released: V2ModuleLease?
        do {
            let lease = try runtime.lease(for: ["core.tasks"])
            released = lease
            XCTAssertNotNil(released)
        }
        XCTAssertNil(released)
        runtime.update(preferences: runtime.preferences)
    }

    func testDescriptorChangeInvalidatesTicketEvenWhenAvailabilityMatches() throws {
        let runtime = V2ModuleRuntime()
        let ticket = try runtime.ticket(for: ["core.tasks"])
        let changed = V2ModuleDescriptor(id: "core.tasks", name: "任务（更新）")
        runtime.update(preferences: runtime.preferences, descriptors: [changed])
        XCTAssertTrue(runtime.availability("core.tasks").isActive)
        XCTAssertThrowsError(try runtime.validate(ticket))
    }

    func testMigrationMixedTodayTasksAndCommunity() {
        let result = V2ModulePreferences.migrate(
            legacyDisabled: ["today", "capture", "ledger", "community.notes"],
            traceEnabled: true,
            communityIDs: ["community.notes"]
        )
        XCTAssertTrue(result.hiddenSurfaces.contains("today"))
        XCTAssertFalse(result.disabled.contains("core.tasks"))
        XCTAssertTrue(result.disabled.contains("core.capture"))
        XCTAssertTrue(result.disabled.contains("core.ledger"))
        XCTAssertTrue(result.disabled.contains("community.notes"))
        XCTAssertTrue(result.migrationHolds.contains("core.finance"))
        XCTAssertTrue(result.migrationHolds.contains("core.attachments"))
    }

    func testMigrationTurnsTasksOffOnlyWhenBothLegacyEntrancesDisabled() {
        let one = V2ModulePreferences.migrate(legacyDisabled: ["today"], traceEnabled: nil, communityIDs: [])
        XCTAssertFalse(one.disabled.contains("core.tasks"))
        XCTAssertTrue(one.hiddenSurfaces.contains("today"))

        let both = V2ModulePreferences.migrate(legacyDisabled: ["today", "tasks"], traceEnabled: nil, communityIDs: [])
        XCTAssertTrue(both.disabled.contains("core.tasks"))
        XCTAssertTrue(both.hiddenSurfaces.contains("tasks"))
    }

    func testMigrationHoldsLegacyCaptureDependentsWithoutChangingRequestedDisabledSet() {
        let result = V2ModulePreferences.migrate(
            legacyDisabled: ["capture"],
            traceEnabled: nil,
            communityIDs: []
        )
        XCTAssertFalse(result.disabled.contains("core.ledger"))
        XCTAssertTrue(result.migrationHolds.contains("core.ledger"))
        XCTAssertTrue(result.migrationHolds.contains("core.finance"))
        XCTAssertTrue(result.migrationHolds.contains("core.budget"))
        XCTAssertTrue(result.migrationHolds.contains("core.imports"))
        XCTAssertTrue(result.migrationHolds.contains("core.attachments"))
    }

    func testMigrationTraceUsesEitherLegacySwitch() {
        XCTAssertTrue(V2ModulePreferences.migrate(legacyDisabled: [], traceEnabled: false, communityIDs: []).disabled.contains("core.traceViewer"))
        XCTAssertTrue(V2ModulePreferences.migrate(legacyDisabled: ["trace"], traceEnabled: true, communityIDs: []).disabled.contains("core.traceViewer"))
        XCTAssertFalse(V2ModulePreferences.migrate(legacyDisabled: [], traceEnabled: true, communityIDs: []).disabled.contains("core.traceViewer"))
    }

    func testMigrationRetainsUnknownPreferenceIDs() {
        let result = V2ModulePreferences.migrate(
            legacyDisabled: ["community.removed", "legacy.future"],
            traceEnabled: nil,
            communityIDs: []
        )
        XCTAssertTrue(result.disabled.contains("community.removed"))
        XCTAssertTrue(result.disabled.contains("legacy.future"))
    }

    func testPreferencesRoundTrip() throws {
        let original = V2ModulePreferences(disabled: ["core.capture"], hiddenSurfaces: ["today"], migrationHolds: ["core.ledger"])
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(V2ModulePreferences.self, from: data), original)
        XCTAssertThrowsError(try JSONDecoder().decode(V2ModulePreferences.self, from: Data("{}".utf8)))
    }
}

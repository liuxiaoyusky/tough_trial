import XCTest
import ToughTrialV2Core
@testable import ToughTrial

private final class MemoryPackageStorage: V2PluginPackageStorage {
    var data: Data?
    var saveError: Error?

    init(data: Data? = nil) { self.data = data }

    func load() throws -> Data? { data }
    func save(_ data: Data) throws {
        if let saveError { throw saveError }
        self.data = data
    }
}

@MainActor
final class V2PluginPackageStoreTests: XCTestCase {
    func testV2InstallPersistsPackageAndGrantAtomically() throws {
        let suite = "package-v2-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let package = makePackage()
        let store = V2PluginStore(defaults: defaults)
        let preview = try store.preview(package)
        XCTAssertFalse(preview.isUpdate)
        XCTAssertTrue(preview.delta.requiresConfirmation)
        XCTAssertThrowsError(try store.install(package)) { error in
            guard case V2PluginStoreError.permissionConfirmationRequired = error else { return XCTFail("unexpected error: \(error)") }
        }
        XCTAssertTrue(store.packages.isEmpty)
        try store.install(package, confirmed: true)
        XCTAssertEqual(store.packages, [package])
        XCTAssertTrue(store.enabled(package.id))

        let reopened = V2PluginStore(defaults: defaults)
        XCTAssertEqual(reopened.packages, [package])
        XCTAssertTrue(reopened.enabled(package.id))
    }

    func testUpdateShowsOnlyNewPermissionAndRejectsDowngrade() throws {
        let suite = "package-update-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = V2PluginStore(defaults: defaults)
        try store.install(makePackage(), confirmed: true)
        let same = makePackage(version: "1.1.0")
        XCTAssertFalse(try store.preview(same).delta.requiresConfirmation)
        try store.install(same)

        let withLink = makePackage(version: "1.2.0", includeLink: true)
        let delta = try store.preview(withLink).delta
        XCTAssertEqual(delta.addedLinkDomains, ["example.com"])
        XCTAssertThrowsError(try store.install(withLink))
        try store.install(withLink, confirmed: true)
        XCTAssertEqual(store.packages.first?.version, "1.2.0")

        XCTAssertThrowsError(try store.install(makePackage(version: "1.0.1"), confirmed: true)) { error in
            guard case V2PluginStoreError.downgrade = error else { return XCTFail("unexpected error: \(error)") }
        }
    }

    func testUninstallRetainsDataMarkerAndRemovesDefinitionAndGrant() throws {
        let suite = "package-uninstall-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = V2PluginStore(defaults: defaults)
        let package = makePackage()
        try store.install(package, confirmed: true)
        let retained = try store.uninstall(package.id)
        XCTAssertEqual(retained.id, package.id)
        XCTAssertTrue(store.packages.isEmpty)
        XCTAssertEqual(store.retained.first?.id, package.id)
        let reopened = V2PluginStore(defaults: defaults)
        XCTAssertTrue(reopened.packages.isEmpty)
        XCTAssertEqual(reopened.retained.first?.id, package.id)
    }

    func testDisablingModuleRunsStopGuardBeforeStateChanges() throws {
        let suite = "package-guard-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = V2PluginStore(defaults: defaults)
        var calls = 0
        let token = store.registerStopGuard(moduleID: "capture") { calls += 1 }
        defer { store.removeStopGuard(token) }
        store.setEnabled("capture", false)
        XCTAssertEqual(calls, 1)
        XCTAssertFalse(store.enabled("capture"))
        store.setEnabled("capture", true)
    }

    func testStopGuardFailureLeavesPreferenceAndRuntimeUnchanged() throws {
        let suite = "package-guard-failure-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = V2PluginStore(defaults: defaults)
        let token = store.registerStopGuard(moduleID: "capture") { throw V2PluginStoreError.stopped }
        defer { store.removeStopGuard(token) }

        store.setEnabled("capture", false)
        XCTAssertTrue(store.requested("capture"), "failed stop must not change the requested preference")
        XCTAssertTrue(store.enabled("capture"), "failed stop must not change runtime availability")
    }

    func testMissingGrantFailsClosedWithoutInferringPermission() throws {
        let suite = "package-grant-missing-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let package = makePackage()
        let record = V2PluginPackageRecord(package: package)
        let storage = MemoryPackageStorage(data: try JSONEncoder().encode(V2PluginPackageEnvelope(packages: [record])))
        let store = V2PluginStore(defaults: defaults, packageStorage: storage)

        XCTAssertEqual(store.packages, [package])
        XCTAssertTrue(store.requested(package.id))
        XCTAssertFalse(store.enabled(package.id), "missing grants must never be reconstructed from the package")
        XCTAssertThrowsError(try store.formContext(packageID: package.id, formID: "note", appStore: makeApp(runtime: store.runtime)))
        XCTAssertNil(defaults.data(forKey: "plugins.packages.v2"), "initialization must not rewrite the missing grant")
    }

    func testCorruptPackageEnvelopeBlocksMutationAndPreservesOriginalBytes() throws {
        let suite = "package-corrupt-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let raw = Data(#"{"schemaVersion":999,"packages":["future"],"grants":[],"retained":[]}"#.utf8)
        let storage = MemoryPackageStorage(data: raw)
        let store = V2PluginStore(defaults: defaults, packageStorage: storage)

        XCTAssertNotNil(store.issue)
        XCTAssertThrowsError(try store.install(makePackage(), confirmed: true)) { error in
            guard case V2PluginStoreError.storageRecoveryRequired = error else { return XCTFail("unexpected error: \(error)") }
        }
        XCTAssertEqual(storage.data, raw)
    }

    func testUpdatingDisabledPackagePreservesPreference() throws {
        let suite = "package-disabled-update-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = V2PluginStore(defaults: defaults)
        try store.install(makePackage(), confirmed: true)
        store.setEnabled("community.package-test", false)
        XCTAssertFalse(store.requested("community.package-test"))

        try store.install(makePackage(version: "1.1.0"))
        XCTAssertFalse(store.requested("community.package-test"), "an update must not opt a deliberately disabled package back in")
        XCTAssertFalse(store.enabled("community.package-test"))
    }

    func testStaleInstallPreviewCannotBeConsumedAfterUninstall() throws {
        let suite = "package-preview-stale-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = V2PluginStore(defaults: defaults)
        let package = makePackage()
        try store.install(package, confirmed: true)
        let preview = try store.preview(makePackage(version: "1.1.0"))
        _ = try store.uninstall(package.id)

        XCTAssertThrowsError(try store.install(preview, confirmed: true)) { error in
            guard case V2PluginStoreError.stalePreview = error else { return XCTFail("unexpected error: \(error)") }
        }
    }

    func testV1UninstallRetainsMarker() throws {
        let suite = "package-v1-retention-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = V2PluginStore(defaults: defaults)
        let manifest = V2PluginManifest(id: "community.legacy-v1", name: "旧插件", summary: "旧输入", fields: [.init(id: "note", title: "Note")], template: "{{note}}")
        try store.install(manifest)
        XCTAssertEqual(store.manifests, [manifest])

        let record = try store.uninstall(manifest.id)
        XCTAssertEqual(record.id, manifest.id)
        XCTAssertTrue(store.manifests.isEmpty)
        XCTAssertEqual(store.retained.first?.id, manifest.id)
        let reopened = V2PluginStore(defaults: defaults)
        XCTAssertTrue(reopened.manifests.isEmpty)
        XCTAssertEqual(reopened.retained.first?.id, manifest.id)
    }

    func testRepeatedFormSubmissionIsIdempotentAndOldContextStalesOnGrantUpdate() throws {
        let suite = "package-form-idempotent-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = V2PluginStore(defaults: defaults)
        let package = makePackage()
        try store.install(package, confirmed: true)
        let app = makeApp(runtime: store.runtime)
        let context = try store.formContext(packageID: package.id, formID: "note", appStore: app)
        let first = try context.submit(values: ["text": "same request"])
        let second = try context.submit(values: ["text": "same request"])
        XCTAssertEqual(first.id, second.id)
        let freshContext = try store.formContext(packageID: package.id, formID: "note", appStore: app, submissionID: context.operationID)
        let retried = try freshContext.submit(values: ["text": "same request"])
        XCTAssertEqual(first.id, retried.id, "a fresh host context must refind the durable Capture by operation identity")
        XCTAssertEqual(app.engine.snapshot.capture.entries.count, 1)
        let intentionalNewEntry = try store.formContext(packageID: package.id, formID: "note", appStore: app)
        let newEntry = try intentionalNewEntry.submit(values: ["text": "same request"])
        XCTAssertNotEqual(first.id, newEntry.id, "a new form presentation is a new user action even when text matches")
        XCTAssertEqual(app.engine.snapshot.capture.entries.count, 2)

        try store.install(makePackage(version: "1.1.0"))
        XCTAssertThrowsError(try context.submit(values: ["text": "new request"])) { error in
            switch error {
            case V2PluginStoreError.grantUnavailable, V2ModuleRuntimeError.stale:
                break
            default:
                XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testMismatchedGrantCannotAuthorizeAnUpdateWithoutConfirmation() throws {
        let suite = "package-tampered-grant-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let old = makePackage()
        let update = makePackage(version: "1.1.0", includeLink: true)
        let grant = V2PluginGrantRecord(pluginID: old.id, permissionKeys: update.permissionKeys, linkDomains: update.linkDomains)
        let raw = try JSONEncoder().encode(V2PluginPackageEnvelope(packages: [.init(package: old)], grants: [grant]))
        let storage = MemoryPackageStorage(data: raw)
        let store = V2PluginStore(defaults: defaults, packageStorage: storage)

        XCTAssertFalse(store.enabled(old.id))
        let preview = try store.preview(update)
        XCTAssertTrue(preview.delta.requiresConfirmation)
        XCTAssertEqual(preview.delta.addedLinkDomains, ["example.com"])
        XCTAssertThrowsError(try store.install(preview)) { error in
            guard case V2PluginStoreError.permissionConfirmationRequired = error else { return XCTFail("unexpected error: \(error)") }
        }
        XCTAssertEqual(storage.data, raw)
        try store.install(preview, confirmed: true)
        XCTAssertTrue(store.enabled(old.id))
    }

    func testLegacyPackageIDCollisionBlocksMutationAndPreservesEnvelope() throws {
        let suite = "package-collision-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let package = makePackage()
        let manifest = V2PluginManifest(id: package.id, name: "Legacy", summary: "Input", fields: [.init(id: "note", title: "Note")], template: "{{note}}")
        try defaults.set(JSONEncoder().encode([manifest]), forKey: "plugins.manifests")
        let raw = try JSONEncoder().encode(V2PluginPackageEnvelope(packages: [.init(package: package)], grants: [
            .init(pluginID: package.id, permissionKeys: package.permissionKeys, linkDomains: package.linkDomains)
        ]))
        let storage = MemoryPackageStorage(data: raw)
        let store = V2PluginStore(defaults: defaults, packageStorage: storage)
        let other = V2PluginPackage(id: "community.other", version: "1.0.0", name: "Other", permissions: package.permissions, contributions: package.contributions)
        XCTAssertNotNil(store.issue)
        XCTAssertThrowsError(try store.install(other, confirmed: true)) { error in
            XCTAssertEqual(error as? V2PluginStoreError, .storageRecoveryRequired)
        }
        XCTAssertThrowsError(try store.uninstall(manifest.id))
        XCTAssertEqual(storage.data, raw)
        XCTAssertEqual(store.manifests, [manifest])
    }

    func testInvalidOrExhaustedGrantRevisionCannotCrashOrOverwriteStorage() throws {
        for revision in [Int.max, V2PluginGrantRecord.maximumRevision] {
            let suite = "package-revision-\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let package = makePackage()
            let raw = try JSONEncoder().encode(V2PluginPackageEnvelope(packages: [.init(package: package)], grants: [
                .init(pluginID: package.id, permissionKeys: package.permissionKeys, linkDomains: package.linkDomains, revision: revision)
            ]))
            let storage = MemoryPackageStorage(data: raw)
            let store = V2PluginStore(defaults: defaults, packageStorage: storage)
            XCTAssertThrowsError(try store.install(makePackage(version: "1.1.0"), confirmed: true)) { error in
                XCTAssertEqual(error as? V2PluginStoreError, .storageRecoveryRequired)
            }
            XCTAssertEqual(storage.data, raw)
        }
    }

    func testLinksRequireCurrentPackageAndLegacyFormLease() throws {
        let suite = "package-link-lease-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = V2PluginStore(defaults: defaults)
        let package = makePackage(includeLink: true)
        let link = "https://example.com/help"
        try store.install(package, confirmed: true)
        XCTAssertEqual(try store.authorizedLink(package: package, rawURL: link).absoluteString, link)
        XCTAssertThrowsError(try store.authorizedLink(package: package, rawURL: "https://example.com/undeclared"))
        store.setEnabled(package.id, false)
        XCTAssertThrowsError(try store.authorizedLink(package: package, rawURL: link))
        store.setEnabled(package.id, true)
        try store.install(makePackage(version: "1.1.0"))
        XCTAssertThrowsError(try store.authorizedLink(package: package, rawURL: link))

        let manifest = V2PluginManifest(id: "community.legacy-link", name: "Legacy", summary: "Input", fields: [.init(id: "note", title: "Note")], template: "{{note}}", link: link)
        try store.install(manifest)
        let app = makeApp(runtime: store.runtime)
        let context = try store.legacyFormContext(manifestID: manifest.id, appStore: app)
        XCTAssertEqual(try context.linkURL().absoluteString, link)
        store.setEnabled(manifest.id, false)
        XCTAssertThrowsError(try context.linkURL())
        store.setEnabled(manifest.id, true)
        XCTAssertThrowsError(try context.linkURL(), "re-enabling must not revive the old view's lease")
        let fresh = try store.legacyFormContext(manifestID: manifest.id, appStore: app)
        try store.install(manifest)
        XCTAssertThrowsError(try fresh.linkURL(), "updating also invalidates an already open form")
    }

    private func makeApp(runtime: V2ModuleRuntime) -> V2AppStore {
        let app = V2AppStore(engine: V2Engine(moduleRuntime: runtime))
        app.engine.moduleRuntime = runtime
        return app
    }

    private func makePackage(version: String = "1.0.0", includeLink: Bool = false) -> V2PluginPackage {
        var permissions = [V2PluginPermission(capability: "capture.create", scope: "submitted-form")]
        var links: [String] = []
        if includeLink {
            permissions.append(.init(capability: "link.open", scope: "https://example.com"))
            links = ["https://example.com/help"]
        }
        return V2PluginPackage(
            id: "community.package-test",
            version: version,
            name: "Package Test",
            permissions: permissions,
            contributions: .init(forms: [.init(id: "note", fields: [.init(id: "text", type: .text, title: "Text", required: true)], submit: .init(template: "{{text}}"))], links: links)
        )
    }
}

import XCTest
import ToughTrialV2Core
@testable import ToughTrial

@MainActor
final class V2FinanceIntegrationTests: XCTestCase {
    func testCaptureFilesSaveOneRevisionAndReopenWithOriginalBytes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let engine = V2Engine(); let app = V2AppStore(engine: engine)
        let store = V2CaptureStore(appStore: app, assetDirectory: directory)
        store.draft = "保留这些原件"
        store.attachFiles([.init(data: Data("pdf bytes".utf8), fileName: "invoice.pdf", kind: .document),
            .init(data: Data("audio bytes".utf8), fileName: "memo.wav", kind: .audio)])
        XCTAssertNil(store.issue)
        let entry = try XCTUnwrap(store.state.latestEntries.first)
        XCTAssertEqual(entry.revision, 1)
        XCTAssertEqual(entry.blocks.filter { $0.assetID != nil }.map(\.kind), [.document, .audio])
        let reopened = V2CaptureStore(appStore: app, assetDirectory: directory)
        reopened.open(entry)
        XCTAssertEqual(reopened.draft, "保留这些原件")
        let asset = try XCTUnwrap(reopened.asset(for: reopened.mediaBlocks[0]))
        XCTAssertEqual(asset.originalFileName, "invoice.pdf")
        XCTAssertEqual(try reopened.assets.data(for: asset), Data("pdf bytes".utf8))
    }
    func testReminderDatesRespectPlanTimeZoneAndPause() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-10T00:00:00Z"))
        var plan = V2FinancePlan(title: "Rent", kind: .rent, amount: "1000", currency: "CNY", dueDate: "2026-09-15", timeZoneIdentifier: "Asia/Shanghai", reminderDays: 3)
        let reminders = V2FinanceNotifications.reminders(for: [plan], now: now)
        XCTAssertEqual(reminders.count, 2)
        XCTAssertEqual(reminders.first { $0.0 == "due" }?.1, ISO8601DateFormatter().date(from: "2026-09-15T01:00:00Z"))
        XCTAssertEqual(reminders.first { $0.0 == "early" }?.1, ISO8601DateFormatter().date(from: "2026-09-12T01:00:00Z"))
        plan.isActive = false
        XCTAssertTrue(V2FinanceNotifications.reminders(for: [plan], now: now).isEmpty)
        plan.isActive = true; plan.reminderEnabled = false
        XCTAssertTrue(V2FinanceNotifications.reminders(for: [plan], now: now).isEmpty)
    }
    func testPluginPersistsInstallationAndChoicesWithoutDeletingContent() throws {
        let name = "plugin-test-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = V2PluginStore(defaults: defaults)
        let manifest = V2PluginManifest(id: "community.notes", name: "Notes", summary: "Note form", fields: [.init(id: "note", title: "Note", required: true)], template: "{{note}}")
        try store.install(manifest)
        store.setEnabled("capture", false)
        let reopened = V2PluginStore(defaults: defaults)
        XCTAssertEqual(reopened.manifests, [manifest])
        XCTAssertTrue(reopened.enabled("finance"))
        XCTAssertFalse(reopened.enabled(manifest.id))
        reopened.setEnabled("capture", true)
        XCTAssertTrue(reopened.enabled("finance"))
        XCTAssertEqual(reopened.manifests, [manifest])
    }
}

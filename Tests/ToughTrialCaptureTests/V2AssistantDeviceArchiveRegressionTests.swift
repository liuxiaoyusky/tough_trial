import Foundation
import XCTest
@testable import ToughTrialV2Core

final class V2AssistantDeviceArchiveRegressionTests: XCTestCase {
    /// Opt-in: operate on an already exported copy; never modify phone data or
    /// print personal messages. No real conversation fixture enters the repo.
    func testRecentExportedSessionsRetainReferencesAndRejectGreetingWrites() throws {
        guard let path = ProcessInfo.processInfo.environment["TOUGH_TRIAL_ARCHIVE_REVIEW_PATH"] else {
            throw XCTSkip("Requires a read-only device workspace export")
        }
        let source = URL(fileURLWithPath: path)
        let before = try Data(contentsOf: source)
        let workspace = try V2AgentWorkspaceJSONStore(fileURL: source).load()
        let sessions = workspace.sessions.sorted { $0.updatedAt > $1.updatedAt }.prefix(2)
        XCTAssertEqual(sessions.count, 2)
        XCTAssertNotNil(sessions.first?.sourceTask)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = V2AssistantArchive(rootURL: directory)
        try archive.sync(workspace)
        try archive.sync(workspace)
        var checkedGreetings = 0
        for session in sessions {
            _ = try archive.compact(session, recentMessageLimit: 2)
            XCTAssertEqual(try archive.readSession(id: session.id, limit: 100).count, session.messages.count)
            for (index, message) in session.messages.enumerated() where message.role == .user && message.plainText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == "hello" {
                checkedGreetings += 1
                XCTAssertFalse(V2AssistantWriteIntent.authorize(message.plainText, priorMessages: Array(session.messages[..<index]), hasTaskReference: session.sourceTask != nil))
            }
        }
        XCTAssertGreaterThan(checkedGreetings, 0)
        XCTAssertEqual(try Data(contentsOf: source), before)
    }
}

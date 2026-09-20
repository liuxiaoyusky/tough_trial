import Foundation
import ToughTrialV2Core

@MainActor
func checkUsageTracePersistenceAndBounds() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("trace.json")
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let trace = V2UsageTraceStore(fileURL: url, limit: 2)
    try trace.record(.init(kind: .inputSubmitted, source: .keyboard, characterCount: 20, at: now), now: now)
    trace.isEnabled = false
    try trace.record(.init(kind: .inputSubmitted, at: now), now: now)
    require(trace.events.count == 1, "Disabled trace must not record")
    trace.isEnabled = true
    try trace.record(.init(kind: .speechStarted, at: now), now: now)
    try trace.record(.init(kind: .speechFinished, duration: 10, at: now), now: now)
    require(trace.events.count == 2 && trace.events.first?.kind == .speechStarted, "Trace must retain bounded latest events")
    let reopened = V2UsageTraceStore(fileURL: url, limit: 2, now: now)
    require(reopened.events == trace.events, "Trace must survive reopening")
    try reopened.record(.init(kind: .inputSubmitted, at: now.addingTimeInterval(31 * 86400)), now: now.addingTimeInterval(31 * 86400))
    require(reopened.events.count == 1, "Expired trace events must be purged")
    let exported = try reopened.exportJSON(now: now.addingTimeInterval(31 * 86400))
    require(!exported.contains("apiKey") && !exported.contains("transcript"), "Trace schema must omit credentials and text payloads")
    try reopened.clear()
    require(reopened.events.isEmpty, "Clear must remove retained events")
    let corrupt = Data("broken original".utf8)
    try corrupt.write(to: url)
    let damaged = V2UsageTraceStore(fileURL: url)
    require(damaged.hasStorageError, "Corrupt trace must report storage error")
    do {
        try damaged.record(.init(kind: .inputSubmitted))
        fatalError("Corrupt file must block writes")
    } catch {}
    let preserved = try Data(contentsOf: url)
    require(preserved == corrupt, "Trace must preserve corrupt file until explicit clear")
    try damaged.clear()
    try damaged.record(.init(kind: .inputSubmitted))
    require(damaged.events.count == 1, "Explicit clear recovers trace")
}

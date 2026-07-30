import Foundation
import ToughTrialV2Core

func checkMemoryPersistenceCorrectionAndForget() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("tough-trial-memory-\(UUID().uuidString)", isDirectory: true)
    let fileURL = directory.appendingPathComponent("v2-memory.json")
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = V2MemoryJSONStore(fileURL: fileURL)
    let engine = V2MemoryEngine(store: store)
    let baseDate = Date(timeIntervalSince1970: 1_800_000_000)
    let original = try engine.add(
        statement: "工作日晚上适合轻量运动",
        kind: .routine,
        origin: .explicitUser,
        at: baseDate
    )
    let corrected = try engine.correct(
        id: original.id,
        statement: "工作日晚上最多安排 30 分钟轻量运动",
        at: baseDate.addingTimeInterval(60)
    )

    require(engine.snapshot.records.count == 2, "Memory correction should preserve its audit trail")
    require(
        engine.activeRecords(at: baseDate.addingTimeInterval(120)).map(\.id) == [corrected.id],
        "Only the newest memory version should be active"
    )

    let reloaded = try V2MemoryEngine.load(from: store)
    require(
        reloaded.activeStatements(at: baseDate.addingTimeInterval(120))
            == ["工作日晚上最多安排 30 分钟轻量运动"],
        "Active memory should survive a restart"
    )

    try reloaded.forget(id: corrected.id)
    require(reloaded.snapshot.records.isEmpty, "Forgetting a memory should physically remove its full version chain")
    let afterForget = try V2MemoryEngine.load(from: store)
    require(afterForget.snapshot.records.isEmpty, "Forgotten memory must stay absent after restart")
}

func checkTemporaryMemoryExpiryAndCorruptionBoundary() throws {
    let now = Date(timeIntervalSince1970: 1_800_100_000)
    let engine = V2MemoryEngine()
    _ = try engine.add(
        statement: "本周暂时不安排晨跑",
        kind: .constraint,
        origin: .temporaryContext,
        expiresAt: now.addingTimeInterval(3_600),
        at: now
    )
    require(engine.activeRecords(at: now).count == 1, "Temporary context should be active before expiry")
    require(
        engine.activeRecords(at: now.addingTimeInterval(3_601)).isEmpty,
        "Expired temporary context should not reach planning requests"
    )

    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("tough-trial-memory-corrupt-\(UUID().uuidString)", isDirectory: true)
    let fileURL = directory.appendingPathComponent("v2-memory.json")
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data("{not-json".utf8).write(to: fileURL)

    do {
        _ = try V2MemoryEngine.load(from: V2MemoryJSONStore(fileURL: fileURL))
        fatalError("Corrupt memory JSON must not be silently replaced")
    } catch {
        require(
            FileManager.default.fileExists(atPath: fileURL.path),
            "Corrupt memory source must remain available for recovery"
        )
    }
}

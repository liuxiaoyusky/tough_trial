import XCTest
import ToughTrialV2Core
@testable import ToughTrial

final class V2ScheduleFileTests: XCTestCase {
    func testBoundFileRoundTripAndConcurrentEditProtection() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("日程.md")
        let snapshotStore = V2JSONSnapshotStore(fileURL: directory.appendingPathComponent("snapshot.json"))
        let engine = V2Engine(store: snapshotStore)
        let note = "协议原文\n<!-- tough-trial:end owned -->\n保留 &lt; 和 &#10;\r\n"
        let task = try engine.createTask(title: "原来的任务", note: note)
        let initial = try engine.prepareScheduleDocument(timeZoneIdentifier: "Asia/Shanghai")
        try Data(V2ScheduleMarkdown.encode(initial).utf8).write(to: file)
        let bound = try V2ScheduleFileIO.read(url: file)
        try engine.recordScheduleFileWrite(initial, bookmark: bound.bookmark, fileName: file.lastPathComponent)
        let resolved = try V2ScheduleFileIO.resolve(try XCTUnwrap(engine.snapshot.scheduleDocumentState?.bookmark))
        XCTAssertEqual(resolved.standardizedFileURL, file.standardizedFileURL)

        var humanEdit = initial
        humanEdit.tasks[0].title = "电脑上改好的任务"
        try Data(V2ScheduleMarkdown.encode(humanEdit).utf8).write(to: file, options: .atomic)
        let read = try V2ScheduleFileIO.read(url: resolved)
        _ = try engine.importScheduleDocument(V2ScheduleMarkdown.decode(String(decoding: read.data, as: UTF8.self)),
            expectedSnapshot: engine.snapshot, requestID: "from-file", bookmark: read.bookmark)
        XCTAssertEqual(engine.snapshot.tasks.first { $0.id == task.id }?.title, "电脑上改好的任务")
        _ = try engine.createTask(title: "手机上新增的任务")
        let output = try engine.prepareScheduleDocument(timeZoneIdentifier: "Asia/Shanghai")
        try V2ScheduleFileIO.write(Data(V2ScheduleMarkdown.encode(output).utf8), replacing: read)
        try engine.recordScheduleFileWrite(output)
        let disk = try V2ScheduleMarkdown.decode(String(contentsOf: file, encoding: .utf8))
        XCTAssertEqual(disk.tasks.map(\.title), ["电脑上改好的任务", "手机上新增的任务"])
        XCTAssertEqual(disk.tasks[0].note, note)
        XCTAssertEqual(try V2Engine.load(from: snapshotStore).snapshot.scheduleDocumentState?.fileBaseline?.tasks.count, 2)

        let staleRead = try V2ScheduleFileIO.read(url: file)
        let newer = Data("# 另一端还在编辑\n".utf8)
        try newer.write(to: file, options: .atomic)
        XCTAssertThrowsError(try V2ScheduleFileIO.write(staleRead.data, replacing: staleRead))
        XCTAssertEqual(try Data(contentsOf: file), newer)
    }

    func testInvalidFileAndFailedWritePreserveState() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".md")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("损坏的日程文件".utf8).write(to: file)
        let read = try V2ScheduleFileIO.read(url: file)
        XCTAssertThrowsError(try V2ScheduleMarkdown.decode(String(decoding: read.data, as: UTF8.self)))
        XCTAssertEqual(try Data(contentsOf: file), read.data)
    }
}

import XCTest
import ToughTrialV2Core

final class V2TaskInputPlacementTests: XCTestCase {
    func testTodayAndSelectedDateKeepNotesInTheCreationTransaction() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let today = calendar.date(from: DateComponents(year: 2026, month: 9, day: 11, hour: 10))!
        let selected = calendar.date(from: DateComponents(year: 2026, month: 9, day: 15))!
        let engine = V2Engine()
        let first = try engine.quickInsertTodayTask(title: "今天处理", note: "保留今日备注", at: today, calendar: calendar)
        let second = try engine.quickInsertScheduledTask(title: "未来处理", note: "保留未来备注", on: selected, calendar: calendar)
        XCTAssertEqual(first.task.note, "保留今日备注")
        XCTAssertEqual(second.task.note, "保留未来备注")
        XCTAssertEqual(first.planItem.date, calendar.startOfDay(for: today))
        XCTAssertEqual(second.planItem.date, selected)
        XCTAssertEqual(first.planItem.taskID, first.task.id)
        XCTAssertEqual(second.planItem.taskID, second.task.id)
        XCTAssertEqual(engine.snapshot.tasks.count, 2)
        XCTAssertEqual(engine.snapshot.planItems.count, 2)
        let before = engine.snapshot
        XCTAssertThrowsError(try engine.quickInsertTodayTask(title: " \n ", note: "不创建空任务", at: today))
        XCTAssertEqual(engine.snapshot, before)
    }

    func testFailedCreationLeavesNeitherTaskNorSchedule() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let engine = V2Engine(store: V2JSONSnapshotStore(fileURL: directory))
        let before = engine.snapshot
        XCTAssertThrowsError(try engine.quickInsertTodayTask(title: "写入失败", note: "不能部分保存"))
        XCTAssertEqual(engine.snapshot, before)
    }
}

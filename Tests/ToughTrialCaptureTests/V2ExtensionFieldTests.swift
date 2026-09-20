import Foundation
import XCTest
@testable import ToughTrialV2Core

final class V2ExtensionFieldTests: XCTestCase {
    private let fieldID = "core.tasks.custom.priority"
    private func field(enabled: Bool = true, revision: Int = 1, type: V2PluginFieldType = .enumID) -> V2FieldDefinition {
        .init(id: fieldID, domain: "core.tasks", type: type, displayName: "优先程度",
              enums: type == .enumID ? ["低", "高"] : [], enabled: enabled, revision: revision)
    }

    func testFieldsRequireHumanDefinitionAndCannotChangeType() throws {
        let engine = V2Engine()
        XCTAssertThrowsError(try engine.saveExtensionField(field(), expectedRevision: nil, confirmed: false))
        try engine.saveExtensionField(field(), expectedRevision: nil, confirmed: true)
        XCTAssertThrowsError(try engine.saveExtensionField(field(revision: 2, type: .text), expectedRevision: 1, confirmed: true))
        XCTAssertEqual(engine.snapshot.extensionFields.definitions.first?.type, .enumID)
    }

    func testUnknownFieldEnumAndStaleDefinitionCannotPolluteTask() throws {
        let engine = V2Engine()
        let task = try engine.createTask(title: "准备材料")
        try engine.saveExtensionField(field(), expectedRevision: nil, confirmed: true)
        XCTAssertThrowsError(try engine.setRecordAttributes(domainID: "core.tasks", recordID: task.id,
            values: [.init(fieldID: "amount", value: .decimal("100"))], expectedDefinitionsRevision: 1, expectedRecordRevision: 0))
        XCTAssertThrowsError(try engine.setRecordAttributes(domainID: "core.tasks", recordID: task.id,
            values: [.init(fieldID: fieldID, value: .enumID("任意新分类"))], expectedDefinitionsRevision: 1, expectedRecordRevision: 0))
        XCTAssertThrowsError(try engine.setRecordAttributes(domainID: "core.tasks", recordID: task.id,
            values: [.init(fieldID: fieldID, value: .enumID("高"))], expectedDefinitionsRevision: 0, expectedRecordRevision: 0))
        XCTAssertEqual(engine.snapshot.tasks.first, task)
        XCTAssertTrue(engine.snapshot.extensionFields.records.isEmpty)
    }

    func testDisabledFieldsAndDisabledModulesRetainHistoryAcrossPersistence() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = V2JSONSnapshotStore(fileURL: directory.appendingPathComponent("snapshot.json"))
        let runtime = V2ModuleRuntime()
        let engine = V2Engine(store: disk, moduleRuntime: runtime)
        let task = try engine.createTask(title: "准备材料")
        try engine.saveExtensionField(field(), expectedRevision: nil, confirmed: true)
        try engine.setRecordAttributes(domainID: "core.tasks", recordID: task.id,
            values: [.init(fieldID: fieldID, value: .enumID("高"))], expectedDefinitionsRevision: 1, expectedRecordRevision: 0)
        try engine.saveExtensionField(field(enabled: false, revision: 2), expectedRevision: 1, confirmed: true)
        try engine.setRecordAttributes(domainID: "core.tasks", recordID: task.id, values: [], expectedDefinitionsRevision: 2, expectedRecordRevision: 1)
        XCTAssertEqual(engine.snapshot.extensionFields.records.first?.values.first?.value, .enumID("高"))
        runtime.update(preferences: .init(disabled: ["core.tasks"]))
        XCTAssertThrowsError(try engine.setRecordAttributes(domainID: "core.tasks", recordID: task.id,
            values: [], expectedDefinitionsRevision: 2, expectedRecordRevision: 1))
        XCTAssertEqual(try disk.load().extensionFields, engine.snapshot.extensionFields)
    }

    func testRecordReferenceMustPointToExistingStableRecord() throws {
        let engine = V2Engine()
        let task = try engine.createTask(title: "准备材料")
        try engine.saveExtensionField(field(type: .recordRef), expectedRevision: nil, confirmed: true)
        XCTAssertThrowsError(try engine.setRecordAttributes(domainID: "core.tasks", recordID: task.id,
            values: [.init(fieldID: fieldID, value: .recordRef(domain: "core.tasks", id: "missing"))],
            expectedDefinitionsRevision: 1, expectedRecordRevision: 0))
        let value = try engine.setRecordAttributes(domainID: "core.tasks", recordID: task.id,
            values: [.init(fieldID: fieldID, value: .recordRef(domain: "core.tasks", id: task.id))],
            expectedDefinitionsRevision: 1, expectedRecordRevision: 0)
        XCTAssertEqual(value.values.count, 1)
    }
}

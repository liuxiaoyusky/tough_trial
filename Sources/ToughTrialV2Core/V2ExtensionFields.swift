import Foundation

public typealias V2RecordAttribute = V2TypedAttribute

public struct V2RecordAttributes: Codable, Equatable, Sendable, Identifiable {
    public var id: String { domainID + ":" + recordID }
    public let domainID: String
    public let recordID: String
    public var revision: Int
    public var values: [V2RecordAttribute]
}

public struct V2ExtensionFieldState: Codable, Equatable, Sendable {
    public var revision: Int = 0
    public var definitions: [V2FieldDefinition] = []
    public var records: [V2RecordAttributes] = []
    public init() {}
}

public enum V2ExtensionFieldError: Error, Equatable, LocalizedError {
    case confirmationRequired, invalidDefinition, stale, missingRecord, invalidValue
    public var errorDescription: String? {
        switch self {
        case .confirmationRequired: "扩展字段的定义需要你确认。"
        case .invalidDefinition: "字段名称、类型或所属功能不兼容；已有字段不能更换类型，请新建字段。"
        case .stale: "字段或记录已经修改，请刷新后重试。"
        case .missingRecord: "关联的记录已不存在，原来的引用仍保留。"
        case .invalidValue: "字段值不符合已确认的类型或范围。"
        }
    }
}

public struct V2FieldRecordProjection: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
}

extension V2AppSnapshot {
    /// A bounded read projection. The host can retain historical references
    /// without reopening a disabled module's mutation capability.
    public func fieldRecords(domainID: String, limit: Int = 100) -> [V2FieldRecordProjection] {
        let records: [V2FieldRecordProjection]
        switch domainID {
        case "core.tasks": records = tasks.map { .init(id: $0.id, title: $0.title) }
        case "core.capture": records = capture.latestEntries.map { .init(id: $0.id, title: String($0.text.prefix(100))) }
        case "core.ledger": records = capture.ledger.map { .init(id: $0.id, title: $0.text) }
        case "core.finance": records = (capture.finance?.plans ?? []).map { .init(id: $0.id, title: $0.title) }
        case "core.budget": records = (capture.finance?.budgets ?? []).map { .init(id: $0.id, title: "\($0.month) · \($0.currency) \($0.amount)") }
        case "core.recall": records = recallEntries.map { .init(id: $0.id, title: String($0.text.prefix(100))) }
        case "core.notes": records = capture.notes.map { .init(id: $0.id, title: $0.title ?? String($0.text.prefix(100))) }
        default: records = []
        }
        return Array(records.suffix(max(0, min(100, limit))))
    }

    public func containsFieldRecord(domainID: String, recordID: String) -> Bool {
        switch domainID {
        case "core.tasks": tasks.contains { $0.id == recordID }
        case "core.capture": capture.entries.contains { $0.id == recordID }
        case "core.ledger": capture.ledger.contains { $0.id == recordID }
        case "core.finance": capture.finance?.plans.contains { $0.id == recordID } == true
        case "core.budget": capture.finance?.budgets.contains { $0.id == recordID } == true
        case "core.recall": recallEntries.contains { $0.id == recordID }
        case "core.notes": capture.notes.contains { $0.id == recordID }
        default: false
        }
    }
}

extension V2Engine {
    public static var extensionFieldDomains: [String] {
        ["core.tasks", "core.capture", "core.ledger", "core.finance", "core.budget", "core.recall", "core.notes"]
    }

    @discardableResult
    public func saveExtensionField(_ definition: V2FieldDefinition, expectedRevision: Int?, confirmed: Bool) throws -> V2FieldDefinition {
        guard confirmed else { throw V2ExtensionFieldError.confirmationRequired }
        try definition.validate()
        guard Self.extensionFieldDomains.contains(definition.domain), definition.id.hasPrefix(definition.domain + ".custom."),
              definition.constraints.count <= 10, definition.enums.count <= 100 else { throw V2ExtensionFieldError.invalidDefinition }
        return try commit(modules: [definition.domain], commandID: definition.domain + ".fields.define") { snapshot in
            if let index = snapshot.extensionFields.definitions.firstIndex(where: { $0.id == definition.id }) {
                let old = snapshot.extensionFields.definitions[index]
                guard old.revision == expectedRevision, definition.revision == old.revision + 1 else { throw V2ExtensionFieldError.stale }
                guard old.domain == definition.domain, old.type == definition.type, old.multiple == definition.multiple else { throw V2ExtensionFieldError.invalidDefinition }
                snapshot.extensionFields.definitions[index] = definition
            } else {
                guard expectedRevision == nil, definition.revision == 1, snapshot.extensionFields.definitions.count < 100 else { throw V2ExtensionFieldError.stale }
                snapshot.extensionFields.definitions.append(definition)
            }
            snapshot.extensionFields.revision += 1
            return definition
        }
    }

    @discardableResult
    public func setRecordAttributes(domainID: String, recordID: String, values: [V2RecordAttribute], expectedDefinitionsRevision: Int, expectedRecordRevision: Int) throws -> V2RecordAttributes {
        try commit(modules: [domainID], commandID: domainID + ".attributes.set") { snapshot in
            guard snapshot.extensionFields.revision == expectedDefinitionsRevision else { throw V2ExtensionFieldError.stale }
            guard snapshot.containsFieldRecord(domainID: domainID, recordID: recordID) else { throw V2ExtensionFieldError.missingRecord }
            let definitions = Dictionary(uniqueKeysWithValues: snapshot.extensionFields.definitions.filter { $0.domain == domainID }.map { ($0.id, $0) })
            guard values.count <= 100 else { throw V2ExtensionFieldError.invalidValue }
            try V2TypedAttribute.validate(values, using: definitions)
            for attribute in values {
                if case .recordRef(let targetDomain, let targetID) = attribute.value,
                   !snapshot.containsFieldRecord(domainID: targetDomain, recordID: targetID) { throw V2ExtensionFieldError.missingRecord }
            }
            let index = snapshot.extensionFields.records.firstIndex { $0.domainID == domainID && $0.recordID == recordID }
            let old = index.map { snapshot.extensionFields.records[$0] }
            guard (old?.revision ?? 0) == expectedRecordRevision else { throw V2ExtensionFieldError.stale }
            // Disabled fields remain historical evidence; a new edit cannot
            // drop their values just because they disappeared from the form.
            let retained = (old?.values ?? []).filter { definitions[$0.fieldID]?.enabled != true }
            let nextValues = retained + values
            if let old, old.values == nextValues { return old }
            let record = V2RecordAttributes(domainID: domainID, recordID: recordID, revision: expectedRecordRevision + 1, values: nextValues)
            if let index { snapshot.extensionFields.records[index] = record }
            else { snapshot.extensionFields.records.append(record) }
            return record
        }
    }
}

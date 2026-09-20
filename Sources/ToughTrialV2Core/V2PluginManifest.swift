import Foundation

public struct V2PluginField: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var required: Bool
    public init(id: String, title: String, required: Bool = false) { self.id = id; self.title = title; self.required = required }
}

/// Plugins describe capabilities; their form output goes through the same Capture commands.
public struct V2PluginManifest: Codable, Equatable, Identifiable, Sendable {
    public var schemaVersion: Int
    public var id: String
    public var name: String
    public var summary: String
    public var fields: [V2PluginField]
    public var template: String
    public var link: String?
    public init(id: String, name: String, summary: String, fields: [V2PluginField], template: String, link: String? = nil) {
        schemaVersion = 1; self.id = id; self.name = name; self.summary = summary
        self.fields = fields; self.template = template; self.link = link
    }
    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= 64 * 1024 else { throw V2PluginError.invalidManifest }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys).isSubset(of: ["schemaVersion", "id", "name", "summary", "fields", "template", "link"]) else { throw V2PluginError.invalidManifest }
        let result = try JSONDecoder().decode(Self.self, from: data)
        guard result.schemaVersion == 1, result.id.hasPrefix("community."), result.id.count <= 100,
              result.id.range(of: #"^[a-z0-9.-]+$"#, options: .regularExpression) != nil,
              !result.name.isEmpty, result.name.count <= 60, result.summary.count <= 1000,
              !result.template.isEmpty, result.template.count <= 10_000,
              result.fields.count <= 20, Set(result.fields.map(\.id)).count == result.fields.count,
              result.fields.allSatisfy({ !$0.title.isEmpty && $0.title.count <= 100 && $0.id.count <= 60 && $0.id.range(of: #"^[a-zA-Z][a-zA-Z0-9_]*$"#, options: .regularExpression) != nil }),
              result.link == nil || URL(string: result.link!)?.scheme?.lowercased() == "https" else { throw V2PluginError.invalidManifest }
        if let link = result.link {
            guard let url = URL(string: link), url.host?.isEmpty == false, url.user == nil, url.password == nil else { throw V2PluginError.invalidManifest }
        }
        let placeholders = result.template.matches(of: /\{\{([a-zA-Z][a-zA-Z0-9_]*)\}\}/).map { String($0.1) }
        guard Set(placeholders).isSubset(of: Set(result.fields.map(\.id))) else { throw V2PluginError.invalidManifest }
        return result
    }
    public func render(_ values: [String: String]) throws -> String {
        for field in fields {
            let value = values[field.id] ?? ""
            guard value.count <= 10_000 else { throw V2PluginError.invalidInput }
            if field.required && value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw V2PluginError.requiredField }
        }
        // One pass prevents field values containing placeholders from being reinterpreted.
        let result = template.replacing(/\{\{([a-zA-Z][a-zA-Z0-9_]*)\}\}/) { values[String($0.1)] ?? "" }
        guard !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, result.count <= 50_000 else { throw V2PluginError.invalidInput }
        return result
    }
}
public enum V2PluginError: Error, LocalizedError {
    case invalidManifest, invalidInput, requiredField
    public var errorDescription: String? {
        switch self {
        case .invalidManifest: "插件文件不兼容。请使用版本 1 的声明式 JSON 插件。"
        case .invalidInput: "内容过长或为空，暂未保存。"
        case .requiredField: "请先填写必填内容。"
        }
    }
}
public struct V2FeatureModule: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let dependencies: [String]
    public init(_ id: String, _ name: String, dependencies: [String] = []) {
        self.id = id; self.name = name; self.dependencies = dependencies
    }
    public static let builtins: [Self] = [
        .init("today", "今天"), .init("tasks", "任务"), .init("assistant", "助手"),
        .init("recall", "回想"), .init("capture", "随手记"),
        .init("ledger", "理账"),
        .init("finance", "订阅与还款", dependencies: ["ledger"]),
        .init("budget", "预算", dependencies: ["ledger"]),
        .init("imports", "外部文件导入", dependencies: ["capture"]),
        .init("attachments", "附件输入"),
        .init("speech", "语音输入"), .init("sync", "日程同步"), .init("trace", "使用 Trace")
    ]
    public static func isEnabled(_ id: String, disabled: Set<String>) -> Bool {
        guard !disabled.contains(id) else { return false }
        return builtins.first { $0.id == id }?.dependencies.allSatisfy { isEnabled($0, disabled: disabled) } ?? false
    }
}

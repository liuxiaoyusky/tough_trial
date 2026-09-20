import Foundation

/// The host API is intentionally small and versioned independently from the
/// persisted data schema. Declarative packages never carry executable code.
public enum V2PluginPackageKind: String, Codable, Equatable, Sendable {
    case declarative
}

public enum V2PluginFieldType: String, Codable, Equatable, Sendable {
    case text
    case decimal
    case boolean
    case date
    case enumID
    case recordRef
}

public struct V2PluginPermission: Codable, Equatable, Hashable, Sendable {
    public let capability: String
    public let scope: String

    public init(capability: String, scope: String) {
        self.capability = capability
        self.scope = scope
    }

    public var key: String { capability + ":" + scope }
}

/// A namespaced field definition for host-owned typed extensions. Form fields
/// are local to a contribution; persisted extension fields use this stable ID.
public struct V2FieldDefinition: Codable, Equatable, Hashable, Sendable, Identifiable {
    public let id: String
    public let domain: String
    public let type: V2PluginFieldType
    public let displayName: String
    public let constraints: [String: String]
    public let enums: [String]
    public let multiple: Bool
    public let enabled: Bool
    public let revision: Int

    public init(
        id: String,
        domain: String,
        type: V2PluginFieldType,
        displayName: String,
        constraints: [String: String] = [:],
        enums: [String] = [],
        multiple: Bool = false,
        enabled: Bool = true,
        revision: Int = 1
    ) {
        self.id = id
        self.domain = domain
        self.type = type
        self.displayName = displayName
        self.constraints = constraints
        self.enums = enums
        self.multiple = multiple
        self.enabled = enabled
        self.revision = revision
    }

    public func validate() throws {
        let supportedConstraints: Set<String>
        switch type {
        case .text: supportedConstraints = ["minLength", "maxLength"]
        case .decimal: supportedConstraints = ["minimum", "maximum"]
        case .boolean: supportedConstraints = []
        case .date: supportedConstraints = ["minimum", "maximum"]
        case .enumID: supportedConstraints = []
        case .recordRef: supportedConstraints = ["allowedDomains"]
        }
        guard id.range(of: #"^[a-z][a-z0-9.-]{1,119}\.[a-z][a-z0-9_.-]{0,119}$"#, options: .regularExpression) != nil,
              domain.range(of: #"^(core|community)\.[a-z0-9.-]+$"#, options: .regularExpression) != nil,
              id.hasPrefix(domain + "."),
              !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              displayName.count <= 100,
              revision > 0,
              constraints.count <= 20,
              constraints.allSatisfy({ !$0.key.isEmpty && $0.key.count <= 60 && $0.value.count <= 500 }),
              Set(constraints.keys).isSubset(of: supportedConstraints),
              Set(enums).count == enums.count,
              enums.allSatisfy({ !$0.isEmpty && $0.count <= 100 }) else {
            throw V2PluginError.invalidManifest
        }
        if type == .enumID {
            guard !enums.isEmpty else { throw V2PluginError.invalidManifest }
        } else {
            guard enums.isEmpty else { throw V2PluginError.invalidManifest }
        }

        switch type {
        case .text:
            guard validateBound(constraints["minLength"], lower: 0, upper: 10_000),
                  validateBound(constraints["maxLength"], lower: 0, upper: 10_000),
                  validOrderedBounds(constraints["minLength"], constraints["maxLength"]) else {
                throw V2PluginError.invalidManifest
            }
        case .decimal:
            guard validDecimalBound(constraints["minimum"]), validDecimalBound(constraints["maximum"]),
                  validDecimalOrder(constraints["minimum"], constraints["maximum"]) else {
                throw V2PluginError.invalidManifest
            }
        case .date:
            guard validDateBound(constraints["minimum"]), validDateBound(constraints["maximum"]),
                  validDateRange(constraints["minimum"], constraints["maximum"]) else {
                throw V2PluginError.invalidManifest
            }
        case .recordRef:
            if let rawDomains = constraints["allowedDomains"] {
                let domains = rawDomains.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
                guard !domains.isEmpty, domains.count <= 20,
                      domains.allSatisfy({ $0.range(of: #"^(core|community)\.[a-z0-9.-]+$"#, options: .regularExpression) != nil }) else {
                    throw V2PluginError.invalidManifest
                }
            }
        case .boolean, .enumID:
            break
        }
    }

    public func validate(_ value: V2TypedFieldValue) throws {
        try validate()
        guard enabled else { throw V2FieldValidationError.disabledField(id) }
        guard value.fieldType == type else { throw V2FieldValidationError.typeMismatch(id) }
        switch value {
        case .text(let text):
            let minimum = constraints["minLength"].flatMap(Int.init) ?? 0
            let maximum = constraints["maxLength"].flatMap(Int.init) ?? 10_000
            guard text.count >= minimum, text.count <= maximum else { throw V2FieldValidationError.invalidValue(id) }
        case .decimal(let decimal):
            guard decimal.range(of: #"^-?(0|[1-9][0-9]*)(\.[0-9]+)?$"#, options: .regularExpression) != nil else {
                throw V2FieldValidationError.invalidValue(id)
            }
            guard validDecimalOrder(constraints["minimum"], decimal), validDecimalOrder(decimal, constraints["maximum"]) else {
                throw V2FieldValidationError.invalidValue(id)
            }
        case .boolean:
            break
        case .date(let date):
            let iso = ISO8601DateFormatter()
            let dateOnly = DateFormatter()
            dateOnly.calendar = Calendar(identifier: .gregorian)
            dateOnly.locale = Locale(identifier: "en_US_POSIX")
            dateOnly.timeZone = TimeZone(secondsFromGMT: 0)
            dateOnly.dateFormat = "yyyy-MM-dd"
            guard iso.date(from: date) != nil || dateOnly.date(from: date) != nil else {
                throw V2FieldValidationError.invalidValue(id)
            }
            guard validDateOrder(constraints["minimum"], date), validDateOrder(date, constraints["maximum"]) else {
                throw V2FieldValidationError.invalidValue(id)
            }
        case .enumID(let value):
            guard enums.contains(value) else { throw V2FieldValidationError.invalidValue(id) }
        case .recordRef(let valueDomain, let recordID):
            guard valueDomain.range(of: #"^(core|community)\.[a-z0-9.-]+$"#, options: .regularExpression) != nil,
                  !recordID.isEmpty, recordID.count <= 200 else { throw V2FieldValidationError.invalidValue(id) }
            if let rawDomains = constraints["allowedDomains"] {
                let domains = rawDomains.split(separator: ",").map(String.init)
                guard domains.contains(valueDomain) else { throw V2FieldValidationError.invalidValue(id) }
            }
        }
    }

    private func validateBound(_ value: String?, lower: Int, upper: Int) -> Bool {
        guard let value else { return true }
        guard let parsed = Int(value), parsed >= lower, parsed <= upper else { return false }
        return true
    }

    private func validOrderedBounds(_ lower: String?, _ upper: String?) -> Bool {
        guard let lower, let upper, let lhs = Int(lower), let rhs = Int(upper) else { return true }
        return lhs <= rhs
    }

    private func validDecimalBound(_ value: String?) -> Bool {
        guard let value else { return true }
        return value.range(of: #"^-?(0|[1-9][0-9]*)(\.[0-9]+)?$"#, options: .regularExpression) != nil
    }

    private func validDecimalOrder(_ lower: String?, _ upper: String?) -> Bool {
        guard let lower, let upper, let lhs = Decimal(string: lower), let rhs = Decimal(string: upper) else { return true }
        return lhs <= rhs
    }

    private func validDateBound(_ value: String?) -> Bool {
        guard let value else { return true }
        let dateOnly = DateFormatter()
        dateOnly.calendar = Calendar(identifier: .gregorian)
        dateOnly.locale = Locale(identifier: "en_US_POSIX")
        dateOnly.timeZone = TimeZone(secondsFromGMT: 0)
        dateOnly.dateFormat = "yyyy-MM-dd"
        return ISO8601DateFormatter().date(from: value) != nil || dateOnly.date(from: value) != nil
    }

    private func validDateRange(_ lower: String?, _ upper: String?) -> Bool {
        guard let lower, let upper else { return true }
        guard let lhs = dateValue(lower), let rhs = dateValue(upper) else { return false }
        return lhs <= rhs
    }

    private func validDateOrder(_ lower: String?, _ value: String) -> Bool {
        guard let lower else { return true }
        guard let lhs = dateValue(lower), let rhs = dateValue(value) else { return false }
        return lhs <= rhs
    }

    private func dateValue(_ value: String) -> Date? {
        if let date = ISO8601DateFormatter().date(from: value) { return date }
        let dateOnly = DateFormatter()
        dateOnly.calendar = Calendar(identifier: .gregorian)
        dateOnly.locale = Locale(identifier: "en_US_POSIX")
        dateOnly.timeZone = TimeZone(secondsFromGMT: 0)
        dateOnly.dateFormat = "yyyy-MM-dd"
        return dateOnly.date(from: value)
    }

    private func validDateOrder(_ value: String, _ upper: String?) -> Bool {
        guard let upper else { return true }
        guard let lhs = dateValue(value), let rhs = dateValue(upper) else { return false }
        return lhs <= rhs
    }
}

public enum V2FieldValidationError: Error, LocalizedError, Equatable, Sendable {
    case unknownField(String)
    case disabledField(String)
    case typeMismatch(String)
    case invalidValue(String)

    public var errorDescription: String? {
        switch self {
        case .unknownField(let id): "字段 " + id + " 未登记。"
        case .disabledField(let id): "字段 " + id + " 已停用，只能读取历史值。"
        case .typeMismatch(let id): "字段 " + id + " 的值类型不匹配。"
        case .invalidValue(let id): "字段 " + id + " 的值不符合约束。"
        }
    }
}

/// The discriminated value used by host-owned typed attributes. It is
/// deliberately not an untyped JSON value, so an AI response cannot smuggle a
/// core amount/category field through `attributes`.
public enum V2TypedFieldValue: Codable, Equatable, Hashable, Sendable {
    case text(String)
    case decimal(String)
    case boolean(Bool)
    case date(String)
    case enumID(String)
    case recordRef(domain: String, id: String)

    private enum CodingKeys: String, CodingKey { case type, value, domain, id }
    private struct AnyCodingKey: CodingKey {
        let stringValue: String
        init?(stringValue: String) { self.stringValue = stringValue }
        let intValue: Int? = nil
        init?(intValue: Int) { return nil }
    }
    private enum Kind: String, Codable { case text, decimal, boolean, date, enumID, recordRef }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        guard let typeKey = AnyCodingKey(stringValue: "type"),
              let valueKey = AnyCodingKey(stringValue: "value"),
              let domainKey = AnyCodingKey(stringValue: "domain"),
              let idKey = AnyCodingKey(stringValue: "id") else {
            throw V2PluginError.invalidInput
        }
        let kind = try container.decode(Kind.self, forKey: typeKey)
        switch kind {
        case .text:
            guard Set(container.allKeys.map(\.stringValue) ) == ["type", "value"] else { throw V2PluginError.invalidInput }
            self = .text(try container.decode(String.self, forKey: valueKey))
        case .decimal:
            guard Set(container.allKeys.map(\.stringValue) ) == ["type", "value"] else { throw V2PluginError.invalidInput }
            self = .decimal(try container.decode(String.self, forKey: valueKey))
        case .boolean:
            guard Set(container.allKeys.map(\.stringValue) ) == ["type", "value"] else { throw V2PluginError.invalidInput }
            self = .boolean(try container.decode(Bool.self, forKey: valueKey))
        case .date:
            guard Set(container.allKeys.map(\.stringValue) ) == ["type", "value"] else { throw V2PluginError.invalidInput }
            self = .date(try container.decode(String.self, forKey: valueKey))
        case .enumID:
            guard Set(container.allKeys.map(\.stringValue) ) == ["type", "value"] else { throw V2PluginError.invalidInput }
            self = .enumID(try container.decode(String.self, forKey: valueKey))
        case .recordRef:
            guard Set(container.allKeys.map(\.stringValue) ) == ["type", "domain", "id"] else { throw V2PluginError.invalidInput }
            self = .recordRef(domain: try container.decode(String.self, forKey: domainKey),
                              id: try container.decode(String.self, forKey: idKey))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let value):
            try container.encode(Kind.text, forKey: .type); try container.encode(value, forKey: .value)
        case .decimal(let value):
            try container.encode(Kind.decimal, forKey: .type); try container.encode(value, forKey: .value)
        case .boolean(let value):
            try container.encode(Kind.boolean, forKey: .type); try container.encode(value, forKey: .value)
        case .date(let value):
            try container.encode(Kind.date, forKey: .type); try container.encode(value, forKey: .value)
        case .enumID(let value):
            try container.encode(Kind.enumID, forKey: .type); try container.encode(value, forKey: .value)
        case .recordRef(let domain, let id):
            try container.encode(Kind.recordRef, forKey: .type)
            try container.encode(domain, forKey: .domain); try container.encode(id, forKey: .id)
        }
    }

    public var fieldType: V2PluginFieldType {
        switch self {
        case .text: .text
        case .decimal: .decimal
        case .boolean: .boolean
        case .date: .date
        case .enumID: .enumID
        case .recordRef: .recordRef
        }
    }
}

public struct V2TypedAttribute: Codable, Equatable, Hashable, Sendable {
    public let fieldID: String
    public let value: V2TypedFieldValue

    public init(fieldID: String, value: V2TypedFieldValue) {
        self.fieldID = fieldID
        self.value = value
    }

    public func validate(using definitions: [String: V2FieldDefinition]) throws {
        guard let definition = definitions[fieldID] else { throw V2FieldValidationError.unknownField(fieldID) }
        try definition.validate(value)
    }

    public static func validate(_ attributes: [V2TypedAttribute], using definitions: [String: V2FieldDefinition]) throws {
        guard attributes.count <= 20 else { throw V2FieldValidationError.invalidValue("attributes") }
        var counts: [String: Int] = [:]
        for attribute in attributes {
            counts[attribute.fieldID, default: 0] += 1
            if counts[attribute.fieldID]! > 1 {
                guard let definition = definitions[attribute.fieldID], definition.multiple else {
                    throw V2FieldValidationError.invalidValue(attribute.fieldID)
                }
            }
        }
        for attribute in attributes { try attribute.validate(using: definitions) }
    }
}

public struct V2PluginFormField: Codable, Equatable, Hashable, Sendable, Identifiable {
    public let id: String
    public let type: V2PluginFieldType
    public let title: String?
    public let required: Bool

    public init(id: String, type: V2PluginFieldType = .text, title: String? = nil, required: Bool = false) {
        self.id = id
        self.type = type
        self.title = title
        self.required = required
    }

    public var displayTitle: String { title ?? id }
}

public struct V2PluginFormSubmit: Codable, Equatable, Hashable, Sendable {
    public let template: String
    public let command: String

    public init(template: String, command: String = "core.capture.create") {
        self.template = template
        self.command = command
    }
}

public struct V2PluginForm: Codable, Equatable, Hashable, Sendable, Identifiable {
    public let id: String
    public let title: String?
    public let fields: [V2PluginFormField]
    public let submit: V2PluginFormSubmit

    public init(id: String, title: String? = nil, fields: [V2PluginFormField], submit: V2PluginFormSubmit) {
        self.id = id
        self.title = title
        self.fields = fields
        self.submit = submit
    }

    /// Render is a single substitution pass over declared fields. A value is
    /// never interpreted as a second template, preventing template injection.
    public func render(_ values: [String: String]) throws -> String {
        guard Set(values.keys).isSubset(of: Set(fields.map(\.id))) else { throw V2PluginError.invalidInput }
        for field in fields {
            let value = values[field.id] ?? ""
            guard value.count <= 10_000 else { throw V2PluginError.invalidInput }
            if field.required && value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw V2PluginError.requiredField
            }
        }
        let result = submit.template.replacing(/\{\{([a-zA-Z][a-zA-Z0-9_]*)\}\}/) {
            values[String($0.1)] ?? ""
        }
        guard !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, result.count <= 50_000 else {
            throw V2PluginError.invalidInput
        }
        return result
    }
}

public struct V2PluginContributions: Codable, Equatable, Hashable, Sendable {
    public let forms: [V2PluginForm]
    public let links: [String]

    public init(forms: [V2PluginForm] = [], links: [String] = []) {
        self.forms = forms
        self.links = links
    }

    private enum CodingKeys: String, CodingKey { case forms, links }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        forms = try container.decode([V2PluginForm].self, forKey: .forms)
        links = try container.decodeIfPresent([String].self, forKey: .links) ?? []
    }
}

/// Version 2 package declaration. It is intentionally separate from the v1
/// `V2PluginManifest`: a v1 file cannot gain executable-looking fields merely
/// because a newer host decodes it.
public struct V2PluginPackage: Codable, Equatable, Hashable, Sendable, Identifiable {
    public static let currentManifestVersion = 2
    public static let currentHostAPIMajor = 1

    public let manifestVersion: Int
    public let id: String
    public let version: String
    public let hostAPIMajor: Int
    public let name: String
    public let kind: V2PluginPackageKind
    public let permissions: [V2PluginPermission]
    public let contributions: V2PluginContributions

    public init(
        id: String,
        version: String,
        name: String,
        permissions: [V2PluginPermission] = [],
        contributions: V2PluginContributions,
        hostAPIMajor: Int = V2PluginPackage.currentHostAPIMajor,
        kind: V2PluginPackageKind = .declarative
    ) {
        self.manifestVersion = Self.currentManifestVersion
        self.id = id
        self.version = version
        self.hostAPIMajor = hostAPIMajor
        self.name = name
        self.kind = kind
        self.permissions = permissions
        self.contributions = contributions
    }

    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= 64 * 1024 else { throw V2PluginError.invalidManifest }
        let object = try strictObject(data)
        guard object.keys.allSatisfy({ ["manifestVersion", "id", "version", "hostAPIMajor", "name", "kind", "permissions", "contributions"].contains($0) }) else {
            throw V2PluginError.invalidManifest
        }
        try validateShape(object)
        let package = try JSONDecoder().decode(Self.self, from: data)
        try package.validate()
        return package
    }

    public func validate() throws {
        guard manifestVersion == Self.currentManifestVersion,
              hostAPIMajor == Self.currentHostAPIMajor,
              kind == .declarative,
              id.hasPrefix("community."), id.count <= 100,
              id.range(of: #"^community\.[a-z0-9.-]+$"#, options: .regularExpression) != nil,
              name.count > 0, name.count <= 60,
              Self.isSemVer(version),
              Set(permissions.map(\.key)).count == permissions.count,
              permissions.allSatisfy(Self.validPermission) else {
            throw V2PluginError.invalidManifest
        }
        guard contributions.forms.count <= 20,
              Set(contributions.forms.map(\.id)).count == contributions.forms.count,
              contributions.links.count <= 20,
              Set(contributions.links).count == contributions.links.count else {
            throw V2PluginError.invalidManifest
        }
        for form in contributions.forms { try Self.validate(form) }
        for rawLink in contributions.links { try Self.validateHTTPSLink(rawLink) }
        if contributions.forms.contains(where: { $0.submit.command == "core.capture.create" }) {
            guard permissions.contains(where: { $0.capability == "capture.create" && $0.scope == "submitted-form" }) else {
                throw V2PluginError.invalidManifest
            }
        }
        if !contributions.links.isEmpty {
        let linkPermissions = permissions.filter { $0.capability == "link.open" }
            guard contributions.links.allSatisfy({ link in
                guard let host = URL(string: link)?.host?.lowercased() else { return false }
                return linkPermissions.contains { permission in
                    Self.permissionHost(permission.scope) == host
                }
            }) else { throw V2PluginError.invalidManifest }
        }
    }

    public var permissionKeys: Set<String> { Set(permissions.map(\.key)) }
    public var linkDomains: Set<String> {
        Set(contributions.links.compactMap { URL(string: $0)?.host?.lowercased() })
    }

    public func form(id: String) -> V2PluginForm? { contributions.forms.first { $0.id == id } }

    private static func validate(_ form: V2PluginForm) throws {
        guard form.id.range(of: #"^[a-z][a-z0-9._-]{0,59}$"#, options: .regularExpression) != nil,
              form.fields.count <= 20,
              Set(form.fields.map(\.id)).count == form.fields.count,
              form.fields.allSatisfy({ field in
                  field.id.range(of: #"^[a-zA-Z][a-zA-Z0-9_]*$"#, options: .regularExpression) != nil
                      && field.id.count <= 60
                      && (field.title == nil || (field.title!.count > 0 && field.title!.count <= 100))
              }),
              form.submit.command == "core.capture.create",
              permissionKeysForCapture(form: form) else {
            throw V2PluginError.invalidManifest
        }
        let template = form.submit.template
        guard !template.isEmpty, template.count <= 10_000 else { throw V2PluginError.invalidManifest }
        let placeholders = template.matches(of: /\{\{([a-zA-Z][a-zA-Z0-9_]*)\}\}/).map { String($0.1) }
        guard Set(placeholders).isSubset(of: Set(form.fields.map(\.id))) else { throw V2PluginError.invalidManifest }
        let stripped = template.replacing(/\{\{[a-zA-Z][a-zA-Z0-9_]*\}\}/, with: "")
        guard !stripped.contains("{{"), !stripped.contains("}}") else { throw V2PluginError.invalidManifest }
    }

    private static func permissionKeysForCapture(form: V2PluginForm) -> Bool {
        // The command itself is checked here; the package-level permission is
        // checked in validate() after the form is decoded.
        form.submit.command == "core.capture.create"
    }

    private static func validPermission(_ permission: V2PluginPermission) -> Bool {
        guard !permission.capability.isEmpty, permission.capability.count <= 100,
              !permission.scope.isEmpty, permission.scope.count <= 200,
              permission.capability.range(of: #"^[a-z][a-z0-9._-]*$"#, options: .regularExpression) != nil else {
            return false
        }
        let supported = ["capture.create", "link.open"]
        if !supported.contains(permission.capability) { return false }
        if permission.capability == "capture.create" { return permission.scope == "submitted-form" }
        return permissionHost(permission.scope) != nil
    }

    private static func permissionHost(_ scope: String) -> String? {
        if let url = URL(string: scope), url.scheme?.lowercased() == "https", let host = url.host,
           url.user == nil, url.password == nil, !host.isEmpty {
            return host.lowercased()
        }
        guard scope.range(of: #"^[a-z0-9](?:[a-z0-9.-]{0,251}[a-z0-9])?$"#, options: .regularExpression) != nil else { return nil }
        return scope.lowercased()
    }

    private static func validateHTTPSLink(_ raw: String) throws {
        guard raw.count <= 2_000,
              let url = URL(string: raw),
              url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil,
              !raw.contains("\\"), !raw.contains("\n"), !raw.contains("\r") else {
            throw V2PluginError.invalidManifest
        }
    }

    private static func isSemVer(_ value: String) -> Bool {
        value.range(of: #"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$"#, options: .regularExpression) != nil
    }

    public static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        func parse(_ value: String) -> (core: [Int], pre: [Substring]?) {
            let withoutBuild = value.split(separator: "+", maxSplits: 1).first ?? Substring(value)
            let parts = withoutBuild.split(separator: "-", maxSplits: 1)
            let core = parts[0].split(separator: ".").compactMap { Int($0) }
            return (core, parts.count == 2 ? parts[1].split(separator: ".") : nil)
        }
        let left = parse(lhs), right = parse(rhs)
        for index in 0..<max(left.core.count, right.core.count) {
            let a = index < left.core.count ? left.core[index] : 0
            let b = index < right.core.count ? right.core[index] : 0
            if a < b { return .orderedAscending }
            if a > b { return .orderedDescending }
        }
        switch (left.pre, right.pre) {
        case (nil, nil): return .orderedSame
        case (nil, .some): return .orderedDescending
        case (.some, nil): return .orderedAscending
        case let (.some(a), .some(b)):
            for index in 0..<max(a.count, b.count) {
                guard index < a.count else { return .orderedAscending }
                guard index < b.count else { return .orderedDescending }
                let leftPart = a[index], rightPart = b[index]
                if let leftNumber = Int(leftPart), let rightNumber = Int(rightPart) {
                    if leftNumber < rightNumber { return .orderedAscending }
                    if leftNumber > rightNumber { return .orderedDescending }
                } else if let _ = Int(leftPart) {
                    return .orderedAscending
                } else if let _ = Int(rightPart) {
                    return .orderedDescending
                } else if leftPart < rightPart {
                    return .orderedAscending
                } else if leftPart > rightPart {
                    return .orderedDescending
                }
            }
        }
        return .orderedSame
    }

    private static func strictObject(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw V2PluginError.invalidManifest
        }
        return object
    }

    /// Codable ignores unknown keys by default. Walk the small declarative
    /// grammar before decoding so adding an executor, SQL fragment or network
    /// request to a package can never be silently accepted.
    private static func validateShape(_ root: [String: Any]) throws {
        func object(_ value: Any) -> [String: Any]? { value as? [String: Any] }
        func requireObject(_ value: Any) throws -> [String: Any] {
            guard let value = object(value) else { throw V2PluginError.invalidManifest }
            return value
        }
        func check(_ value: [String: Any], keys: Set<String>) throws {
            guard Set(value.keys).isSubset(of: keys) else { throw V2PluginError.invalidManifest }
        }

        try check(root, keys: ["manifestVersion", "id", "version", "hostAPIMajor", "name", "kind", "permissions", "contributions"])
        guard let permissions = root["permissions"] as? [Any], let contributionsValue = root["contributions"] else {
            throw V2PluginError.invalidManifest
        }
        for permissionValue in permissions {
            let permission = try requireObject(permissionValue)
            try check(permission, keys: ["capability", "scope"])
        }
        let contributions = try requireObject(contributionsValue)
        try check(contributions, keys: ["forms", "links"])
        if let links = contributions["links"] as? [Any] {
            guard links.allSatisfy({ $0 is String }) else { throw V2PluginError.invalidManifest }
        } else if contributions["links"] != nil {
            throw V2PluginError.invalidManifest
        }
        guard let forms = contributions["forms"] as? [Any] else { throw V2PluginError.invalidManifest }
        for formValue in forms {
            let form = try requireObject(formValue)
            try check(form, keys: ["id", "title", "fields", "submit"])
            guard let fields = form["fields"] as? [Any], let submitValue = form["submit"] else {
                throw V2PluginError.invalidManifest
            }
            for fieldValue in fields {
                let field = try requireObject(fieldValue)
                try check(field, keys: ["id", "type", "title", "required"])
            }
            let submit = try requireObject(submitValue)
            try check(submit, keys: ["template", "command"])
        }
    }
}

/// A format-neutral decoder used by the file importer. It keeps v1 behavior
/// intact while making callers explicit about which package version they saw.
public enum V2PluginDocument: Equatable, Sendable {
    case v1(V2PluginManifest)
    case v2(V2PluginPackage)

    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= 64 * 1024 else { throw V2PluginError.invalidManifest }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw V2PluginError.invalidManifest
        }
        if object["manifestVersion"] != nil { return .v2(try V2PluginPackage.decode(data)) }
        return .v1(try V2PluginManifest.decode(data))
    }
}

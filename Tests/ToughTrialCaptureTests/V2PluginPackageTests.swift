import XCTest
@testable import ToughTrialV2Core

final class V2PluginPackageTests: XCTestCase {
    func testVersionTwoExampleDecodesAndRendersInOnePass() throws {
        let package = try V2PluginPackage.decode(Data("""
        {
          "manifestVersion": 2,
          "id": "community.reading-note",
          "version": "1.0.0",
          "hostAPIMajor": 1,
          "name": "阅读随记",
          "kind": "declarative",
          "permissions": [{"capability":"capture.create", "scope":"submitted-form"}],
          "contributions": {"forms": [{
            "id":"quick-note",
            "fields":[{"id":"book","type":"text","required":true},{"id":"note","type":"text","required":true}],
            "submit":{"template":"阅读《{{book}}》：{{note}}", "command":"core.capture.create"}
          }]}
        }
        """.utf8))

        XCTAssertEqual(package.manifestVersion, 2)
        let form = try XCTUnwrap(package.form(id: "quick-note"))
        XCTAssertEqual(try form.render(["book": "Swift", "note": "{{book}}" ]), "阅读《Swift》：{{book}}")
    }

    func testUnknownExecutorAndMalformedTemplateAreRejected() {
        let executor = Data("""
        {
          "manifestVersion":2,"id":"community.bad","version":"1.0.0","hostAPIMajor":1,"name":"bad","kind":"declarative",
          "permissions":[],"contributions":{"forms":[],"executor":"javascript"}
        }
        """.utf8)
        XCTAssertThrowsError(try V2PluginPackage.decode(executor))

        let malformed = Data("""
        {
          "manifestVersion":2,"id":"community.bad","version":"1.0.0","hostAPIMajor":1,"name":"bad","kind":"declarative",
          "permissions":[{"capability":"capture.create","scope":"submitted-form"}],
          "contributions":{"forms":[{"id":"f","fields":[{"id":"x","type":"text"}],"submit":{"template":"{{x | shell}}","command":"core.capture.create"}}]}
        }
        """.utf8)
        XCTAssertThrowsError(try V2PluginPackage.decode(malformed))
    }

    func testUnsupportedPermissionLinkAndFutureVersionAreRejected() {
        let unsupported = Data("""
        {
          "manifestVersion":2,"id":"community.bad","version":"1.0.0","hostAPIMajor":1,"name":"bad","kind":"declarative",
          "permissions":[{"capability":"network.request","scope":"*"}],"contributions":{"forms":[]}
        }
        """.utf8)
        XCTAssertThrowsError(try V2PluginPackage.decode(unsupported))

        let future = Data("""
        {
          "manifestVersion":3,"id":"community.future","version":"1.0.0","hostAPIMajor":1,"name":"future","kind":"declarative",
          "permissions":[],"contributions":{"forms":[]}
        }
        """.utf8)
        XCTAssertThrowsError(try V2PluginPackage.decode(future))
    }

    func testTypedFieldValuesAreDiscriminatedAndFieldDefinitionsAreImmutable() throws {
        let values: [V2TypedFieldValue] = [.text("x"), .decimal("12.30"), .boolean(true), .date("2026-09-10"), .enumID("food"), .recordRef(domain: "core.tasks", id: "task-1")]
        let data = try JSONEncoder().encode(values)
        XCTAssertEqual(try JSONDecoder().decode([V2TypedFieldValue].self, from: data), values)

        let definition = V2FieldDefinition(id: "community.reading-note.rating", domain: "community.reading-note", type: .enumID, displayName: "评分", enums: ["good", "bad"])
        XCTAssertNoThrow(try definition.validate())
        XCTAssertNoThrow(try definition.validate(.enumID("good")))
        XCTAssertThrowsError(try V2FieldDefinition(id: "rating", domain: "core.tasks", type: .text, displayName: "不带命名空间").validate())
        XCTAssertThrowsError(try V2FieldDefinition(id: "community.reading-note.rating", domain: "community.reading-note", type: .text, displayName: "错误枚举", enums: ["good"]).validate())

        let date = V2FieldDefinition(id: "community.reading-note.date", domain: "community.reading-note", type: .date, displayName: "日期")
        XCTAssertNoThrow(try date.validate(.date("2026-09-10")))
        let multi = V2FieldDefinition(id: "community.reading-note.tag", domain: "community.reading-note", type: .text, displayName: "标签", multiple: true)
        XCTAssertNoThrow(try V2TypedAttribute.validate([
            .init(fieldID: multi.id, value: .text("a")), .init(fieldID: multi.id, value: .text("b"))
        ], using: [multi.id: multi]))
    }

    func testTypedValueRejectsUnknownJSONKeysAndUnsupportedBounds() {
        let injected = Data(#"{"type":"text","value":"ok","command":"core.capture.create"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(V2TypedFieldValue.self, from: injected))

        let unknownConstraint = V2FieldDefinition(
            id: "community.reading-note.title",
            domain: "community.reading-note",
            type: .text,
            displayName: "标题",
            constraints: ["pattern": ".*"]
        )
        XCTAssertThrowsError(try unknownConstraint.validate())

        let bounded = V2FieldDefinition(
            id: "community.reading-note.title",
            domain: "community.reading-note",
            type: .text,
            displayName: "标题",
            constraints: ["minLength": "2", "maxLength": "4"]
        )
        XCTAssertNoThrow(try bounded.validate(.text("okay")))
        XCTAssertThrowsError(try bounded.validate(.text("x")))
        XCTAssertThrowsError(try bounded.validate(.text("too long")))
    }

    func testSemanticVersionComparison() {
        XCTAssertEqual(V2PluginPackage.compareVersions("1.2.0", "1.1.9"), .orderedDescending)
        XCTAssertEqual(V2PluginPackage.compareVersions("1.2.0", "1.2.0"), .orderedSame)
        XCTAssertEqual(V2PluginPackage.compareVersions("1.1.9", "1.2.0"), .orderedAscending)
    }

    func testDocumentDecoderKeepsV1AndV2Separate() throws {
        let legacy = V2PluginManifest(id: "community.legacy", name: "Legacy", summary: "v1", fields: [.init(id: "note", title: "Note")], template: "{{note}}")
        switch try V2PluginDocument.decode(JSONEncoder().encode(legacy)) {
        case .v1(let decoded): XCTAssertEqual(decoded, legacy)
        case .v2: XCTFail("v1 must not be promoted to v2")
        }
        let package = V2PluginPackage(id: "community.next", version: "1.0.0", name: "Next", contributions: .init())
        switch try V2PluginDocument.decode(JSONEncoder().encode(package)) {
        case .v1: XCTFail("v2 must not be decoded as v1")
        case .v2(let decoded): XCTAssertEqual(decoded, package)
        }
    }
}

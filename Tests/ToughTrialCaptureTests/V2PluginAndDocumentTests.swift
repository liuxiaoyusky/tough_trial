import Foundation
import XCTest
@testable import ToughTrialV2Core

final class V2PluginAndDocumentTests: XCTestCase {
    func testPluginRendersOnceAndRejectsMissingRequiredInput() throws {
        let manifest = V2PluginManifest(id: "community.notes", name: "Notes", summary: "Capture notes",
            fields: [.init(id: "title", title: "Title", required: true), .init(id: "note", title: "Note")], template: "{{title}}: {{note}}")
        let decoded = try V2PluginManifest.decode(JSONEncoder().encode(manifest))
        XCTAssertEqual(try decoded.render(["title": "{{note}}", "note": "原文"]), "{{note}}: 原文")
        XCTAssertThrowsError(try decoded.render(["title": "  "]))
        var invalid = manifest; invalid.template = "{{undefined}}"
        XCTAssertThrowsError(try V2PluginManifest.decode(JSONEncoder().encode(invalid)))
        invalid = manifest; invalid.link = "javascript:alert(1)"
        XCTAssertThrowsError(try V2PluginManifest.decode(JSONEncoder().encode(invalid)))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(manifest)) as? [String: Any])
        json["script"] = "fetch('example')"
        XCTAssertThrowsError(try V2PluginManifest.decode(JSONSerialization.data(withJSONObject: json)))
    }
    func testModuleDependenciesPauseWithoutChangingDisabledChoices() {
        let disabled: Set<String> = ["capture"]
        XCTAssertTrue(V2FeatureModule.isEnabled("finance", disabled: disabled))
        XCTAssertTrue(V2FeatureModule.isEnabled("budget", disabled: disabled))
        XCTAssertFalse(V2FeatureModule.isEnabled("finance", disabled: ["ledger"]))
        XCTAssertFalse(V2FeatureModule.isEnabled("unknown", disabled: []))
        XCTAssertTrue(V2FeatureModule.isEnabled("today", disabled: disabled))
        XCTAssertTrue(V2FeatureModule.isEnabled("finance", disabled: []))
    }
    func testDocumentOriginalAndMetadataSurviveSnapshotReload() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let assets = V2CaptureAssetStore(directory: folder)
        let engine = V2Engine()
        let bytes = Data("unknown-format-content".utf8)
        let asset = try engine.saveCaptureAsset(bytes, kind: .document, fileExtension: "xyz", store: assets, originalFileName: "我的记录.xyz")
        let entry = try engine.saveCapture(text: "", mediaBlocks: [.init(kind: .document, assetID: asset.id)])
        let reloaded = try JSONDecoder().decode(V2AppSnapshot.self, from: JSONEncoder().encode(engine.snapshot))
        XCTAssertEqual(reloaded.capture.latestEntries.first { $0.id == entry.id }?.blocks.last?.assetID, asset.id)
        XCTAssertEqual(reloaded.capture.assets.first?.originalFileName, "我的记录.xyz")
        XCTAssertEqual(try V2CaptureAssetStore(directory: folder).data(for: asset), bytes)
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.snapshot.capture)) as? [String: Any])
        old.removeValue(forKey: "finance")
        XCTAssertNil(try JSONDecoder().decode(V2CaptureState.self, from: JSONSerialization.data(withJSONObject: old)).finance)
        var oldAsset = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(asset)) as? [String: Any])
        oldAsset.removeValue(forKey: "originalFileName")
        XCTAssertNil(try JSONDecoder().decode(V2CaptureAsset.self, from: JSONSerialization.data(withJSONObject: oldAsset)).originalFileName)
    }
}

import Foundation
import XCTest
@testable import ToughTrialV2Core

final class V2CaptureAssetTests: XCTestCase {
    func testAssetCanBeReadAfterStoreIsRecreated() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let payload = Data("capture audio bytes".utf8)
        let firstStore = V2CaptureAssetStore(directory: directory)
        let asset = try firstStore.save(payload, kind: .audio, fileExtension: "m4a")

        let encoded = try JSONEncoder().encode(asset)
        let decoded = try JSONDecoder().decode(V2CaptureAsset.self, from: encoded)
        XCTAssertEqual(decoded, asset)

        let restartedStore = V2CaptureAssetStore(directory: directory)
        XCTAssertEqual(try restartedStore.data(for: asset), payload)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try restartedStore.url(for: asset).path))
    }

    func testCorruptedBytesAreRejected() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = V2CaptureAssetStore(directory: directory)
        let asset = try store.save(Data([1, 2, 3, 4]), kind: .image, fileExtension: "png")
        let corrupted = Data([1, 2, 9, 4])
        try corrupted.write(to: try store.url(for: asset), options: [.atomic])

        XCTAssertThrowsError(try store.data(for: asset)) { error in
            guard let storeError = error as? V2CaptureAssetStoreError,
                  case .hashMismatch = storeError else {
                return XCTFail("Expected hash verification to reject corrupted bytes")
            }
        }
    }

    func testPathTraversalAndMaliciousExtensionsAreRejected() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = V2CaptureAssetStore(directory: directory)
        XCTAssertThrowsError(
            try store.save(Data([1]), kind: .image, fileExtension: "png/../../outside")
        ) { error in
            XCTAssertEqual(error as? V2CaptureAssetStoreError, .invalidFileExtension)
        }

        let id = UUID().uuidString.lowercased()
        let forgedAsset = V2CaptureAsset(
            id: id,
            kind: .image,
            fileName: "(id).png/../../outside",
            sha256: String(repeating: "0", count: 64),
            byteCount: 1
        )
        XCTAssertThrowsError(try store.url(for: forgedAsset)) { error in
            XCTAssertEqual(error as? V2CaptureAssetStoreError, .invalidAsset)
        }
    }

    func testEmptyDataIsRejected() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = V2CaptureAssetStore(directory: directory)
        XCTAssertThrowsError(try store.save(Data(), kind: .handwriting, fileExtension: "drawing")) { error in
            XCTAssertEqual(error as? V2CaptureAssetStoreError, .emptyData)
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ToughTrialCaptureAssetTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        return directory
    }
}

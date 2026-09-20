import CryptoKit
import Foundation
import ToughTrialV2Core
import UIKit
import XCTest
@testable import ToughTrial

@MainActor
final class V2FileAttachmentTests: XCTestCase {
    func testReaderPreservesAnyFileAndDetectsAudioKind() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let textURL = directory.appendingPathComponent("凭证.custom")
        try Data("原格式内容".utf8).write(to: textURL)
        let audioURL = directory.appendingPathComponent("录音.wav")
        try Data(repeating: 7, count: 4).write(to: audioURL)

        let files = try await V2FileAttachmentReader.read(
            urls: [textURL, audioURL],
            maximumFileCount: 10,
            maximumFileSize: 25 * 1024 * 1024
        )

        XCTAssertEqual(files.count, 2)
        XCTAssertEqual(files[0].fileName, "凭证.custom")
        XCTAssertEqual(files[0].data, Data("原格式内容".utf8))
        XCTAssertEqual(files[0].kind, .document)
        XCTAssertEqual(files[1].kind, .audio)
        XCTAssertEqual(V2PickedFile(data: Data([1]), fileName: "记录.数据", kind: .document).storageExtension, "bin")
        XCTAssertEqual(V2PickedFile(data: Data([1]), fileName: "invoice.PDF", kind: .document).storageExtension, "PDF")
    }

    func testReaderRejectsMoreThanTenFiles() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let urls = try (0..<11).map { index -> URL in
            let url = directory.appendingPathComponent("file-\(index).txt")
            try Data("x".utf8).write(to: url)
            return url
        }

        do {
            _ = try await V2FileAttachmentReader.read(
                urls: urls,
                maximumFileCount: 10,
                maximumFileSize: 25 * 1024 * 1024
            )
            XCTFail("Expected the picker to reject more than ten files")
        } catch let error as V2FileAttachmentError {
            XCTAssertEqual(error, .tooManyFiles(maximum: 10))
        }
    }

    func testReaderRejectsOversizedAndEmptyFiles() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let oversizedURL = directory.appendingPathComponent("large.bin")
        try Data(repeating: 0, count: 33).write(to: oversizedURL)
        let emptyURL = directory.appendingPathComponent("empty.bin")
        try Data().write(to: emptyURL)

        do {
            _ = try await V2FileAttachmentReader.read(
                urls: [oversizedURL],
                maximumFileCount: 10,
                maximumFileSize: 32
            )
            XCTFail("Expected the reader to reject an oversized file")
        } catch let error as V2FileAttachmentError {
            XCTAssertEqual(error, .fileTooLarge(fileName: "large.bin", maximumBytes: 32))
        }

        do {
            _ = try await V2FileAttachmentReader.read(
                urls: [emptyURL],
                maximumFileCount: 10,
                maximumFileSize: 32
            )
            XCTFail("Expected the reader to reject an empty file")
        } catch let error as V2FileAttachmentError {
            XCTAssertEqual(error, .emptyFile(fileName: "empty.bin"))
        }
    }

    func testReaderRejectsDirectories() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let nested = directory.appendingPathComponent("资料")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: false)

        do {
            _ = try await V2FileAttachmentReader.read(
                urls: [nested],
                maximumFileCount: 10,
                maximumFileSize: 25 * 1024 * 1024
            )
            XCTFail("Expected the reader to reject a directory")
        } catch let error as V2FileAttachmentError {
            XCTAssertEqual(error, .directoryNotAllowed(fileName: "资料"))
        }
    }

    func testImageAndPDFGetQuickLookThumbnails() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = V2CaptureAssetStore(directory: directory)
        let imageAsset = try store.save(
            makePNG(),
            kind: .image,
            fileExtension: "png"
        )
        let pdfAsset = try store.save(
            makePDF(),
            kind: .document,
            fileExtension: "pdf"
        )

        let imageURL = try store.url(for: imageAsset)
        let pdfURL = try store.url(for: pdfAsset)
        XCTAssertTrue(V2AttachmentThumbnailer.canRenderThumbnail(for: imageAsset, url: imageURL))
        XCTAssertTrue(V2AttachmentThumbnailer.canRenderThumbnail(for: pdfAsset, url: pdfURL))
        let imageThumbnail = await V2AttachmentThumbnailer.thumbnail(
            for: imageAsset,
            store: store,
            size: CGSize(width: 96, height: 96)
        )
        let pdfThumbnail = await V2AttachmentThumbnailer.thumbnail(
            for: pdfAsset,
            store: store,
            size: CGSize(width: 96, height: 96)
        )
        XCTAssertNotNil(imageThumbnail)
        XCTAssertNotNil(pdfThumbnail)
    }

    func testUnknownFormatUsesExplicitDocumentIconFallback() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = V2CaptureAssetStore(directory: directory)
        let asset = try store.save(
            Data("unrenderable".utf8),
            kind: .document,
            fileExtension: "opaque"
        )
        let url = try store.url(for: asset)

        XCTAssertFalse(V2AttachmentThumbnailer.canRenderThumbnail(for: asset, url: url))
        let thumbnail = await V2AttachmentThumbnailer.thumbnail(
            for: asset,
            store: store,
            size: CGSize(width: 96, height: 96)
        )
        XCTAssertNil(thumbnail)
        XCTAssertEqual(V2AttachmentThumbnailer.fallbackIconName(for: asset), "doc.fill")
        XCTAssertNotNil(try store.url(for: asset), "Unknown files remain shareable by their original URL")
    }

    func testShareRepresentationKeepsOriginalNameWithoutChangingContent() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceURL = directory.appendingPathComponent("asset-uuid.bin")
        let originalData = Data(repeating: 13, count: 4_096)
        try originalData.write(to: sourceURL)
        let item = V2AttachmentShareItem(
            fileURL: sourceURL,
            suggestedFileName: "MoneyThings-2026.csv"
        )

        let sent = try item.makeSentTransferredFile()
        let sharedData = try Data(contentsOf: sent.file)
        XCTAssertEqual(sent.file.lastPathComponent, "MoneyThings-2026.csv")
        XCTAssertFalse(sent.allowAccessingOriginalFile)
        XCTAssertEqual(SHA256.hash(data: sharedData), SHA256.hash(data: originalData))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tough-trial-attachments-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }

    private func makePNG() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24)).pngData { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 24, height: 24))
        }
    }

    private func makePDF() -> Data {
        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, .zero, nil)
        UIGraphicsBeginPDFPageWithInfo(CGRect(x: 0, y: 0, width: 72, height: 72), nil)
        UIColor.systemBlue.setFill()
        UIRectFill(CGRect(x: 0, y: 0, width: 72, height: 72))
        UIGraphicsEndPDFContext()
        return data as Data
    }
}

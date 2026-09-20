import Foundation
import CoreTransferable
import QuickLook
import QuickLookThumbnailing
#if os(macOS)
import QuickLookUI
#endif
import SwiftUI
import ToughTrialV2Core
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif
import UniformTypeIdentifiers

#if os(iOS)
fileprivate typealias V2AttachmentThumbnailImage = UIImage
#elseif os(macOS)
fileprivate typealias V2AttachmentThumbnailImage = NSImage
#endif

/// A file selected by the user. The original filename is kept so the Store can
/// preserve the source format when it creates a V2CaptureAsset.
public struct V2PickedFile: Equatable, Sendable {
    public let data: Data
    public let fileName: String
    public let kind: V2CaptureAsset.Kind

    var storageExtension: String {
        let value = (fileName as NSString).pathExtension
        return value.range(of: #"^[a-zA-Z0-9_-]{1,32}$"#, options: .regularExpression) == nil ? "bin" : value
    }

    public init(data: Data, fileName: String, kind: V2CaptureAsset.Kind) {
        self.data = data
        self.fileName = fileName
        self.kind = kind
    }
}

public enum V2FileAttachmentError: Error, Equatable, LocalizedError, Sendable {
    case tooManyFiles(maximum: Int)
    case directoryNotAllowed(fileName: String)
    case fileTooLarge(fileName: String, maximumBytes: Int)
    case emptyFile(fileName: String)
    case cannotRead(fileName: String)
    case cannotPrepareShare(fileName: String)

    public var errorDescription: String? {
        switch self {
        case let .tooManyFiles(maximum):
            return "最多可以同时选择 \(maximum) 个文件。"
        case let .directoryNotAllowed(fileName):
            return "“\(fileName)”是文件夹，请选择文件。"
        case let .fileTooLarge(fileName, maximumBytes):
            return "“\(fileName)”超过单文件 \(Self.byteCount(maximumBytes)) 限制。"
        case let .emptyFile(fileName):
            return "“\(fileName)”没有可读取的内容。"
        case let .cannotRead(fileName):
            return "暂时无法读取“\(fileName)”。请确认文件仍可访问后重试。"
        case let .cannotPrepareShare(fileName):
            return "暂时无法准备“\(fileName)”的分享文件。请稍后重试。"
        }
    }

    private static func byteCount(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

/// A reusable file picker for capture screens. It accepts any file type so a
/// non-renderable attachment can still be retained with its original format.
public struct V2FileAttachmentPicker: View {
    public typealias PickHandler = ([V2PickedFile]) -> Void

    private let onPick: PickHandler
    private let maximumFileCount: Int
    private let maximumFileSize: Int
    private let ownerModuleID: String
    @State private var inputTicket: V2ModuleTicket?
    @State private var isImporting = false
    @State private var errorMessage: String?

    public init(
        maximumFileCount: Int = 10,
        maximumFileSize: Int = 25 * 1024 * 1024,
        ownerModuleID: String = "core.capture",
        onPick: @escaping PickHandler
    ) {
        self.maximumFileCount = max(1, maximumFileCount)
        self.maximumFileSize = max(1, maximumFileSize)
        self.ownerModuleID = ownerModuleID
        self.onPick = onPick
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                do {
                    inputTicket = try V2PluginStore.shared.ticket([ownerModuleID, "core.attachments"])
                    errorMessage = nil
                    isImporting = true
                } catch { errorMessage = error.localizedDescription }
            } label: {
                Label("添加附件", systemImage: "paperclip")
                    .font(V2Theme.TypeRole.labelLarge)
            }
            .buttonStyle(.bordered)
            .tint(V2Theme.blue)
            .accessibilityIdentifier("capture.attachment.add")

            Text("图片和 PDF 会显示缩略图，其他格式保留原文件。单个文件最多 \(Self.byteCount(maximumFileSize))，一次最多 \(maximumFileCount) 个。")
                .font(V2Theme.TypeRole.bodySmall)
                .foregroundStyle(V2Theme.secondary)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(V2Theme.TypeRole.bodySmall)
                    .foregroundStyle(V2Theme.orange)
                    .accessibilityIdentifier("capture.attachment.error")
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case let .success(urls):
                read(urls)
            case let .failure(error):
                errorMessage = error.localizedDescription
            }
        }
    }

    private func read(_ urls: [URL]) {
        let fileCountLimit = maximumFileCount
        let fileSizeLimit = maximumFileSize
        let pickHandler = onPick

        Task { @MainActor in
            do {
                guard let inputTicket else { throw V2CaptureError.assetUnavailable }
                try V2PluginStore.shared.validate(inputTicket)
                // File coordination and bounded stream reads happen on the
                // generic executor, then only the UI callback returns here.
                let files = try await Task.detached(priority: .userInitiated) {
                    try await V2FileAttachmentReader.read(
                        urls: urls,
                        maximumFileCount: fileCountLimit,
                        maximumFileSize: fileSizeLimit
                    )
                }.value
                try V2PluginStore.shared.validate(inputTicket)
                errorMessage = nil
                pickHandler(files)
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private static func byteCount(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

enum V2FileAttachmentReader {
    nonisolated static func read(
        urls: [URL],
        maximumFileCount: Int,
        maximumFileSize: Int
    ) async throws -> [V2PickedFile] {
        guard urls.count <= maximumFileCount else {
            throw V2FileAttachmentError.tooManyFiles(maximum: maximumFileCount)
        }

        var files: [V2PickedFile] = []
        files.reserveCapacity(urls.count)
        for url in urls {
            files.append(try read(url: url, maximumFileSize: maximumFileSize))
        }
        return files
    }

    private static func read(url: URL, maximumFileSize: Int) throws -> V2PickedFile {
        let fileName = url.lastPathComponent.isEmpty ? "附件" : url.lastPathComponent
        let hasSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            if values.isDirectory == true {
                throw V2FileAttachmentError.directoryNotAllowed(fileName: fileName)
            }
            if let fileSize = values.fileSize, fileSize > maximumFileSize {
                throw V2FileAttachmentError.fileTooLarge(
                    fileName: fileName,
                    maximumBytes: maximumFileSize
                )
            }
        } catch let error as V2FileAttachmentError {
            throw error
        } catch {
            throw V2FileAttachmentError.cannotRead(fileName: fileName)
        }

        let data: Data
        do {
            data = try readBoundedData(from: url, maximumBytes: maximumFileSize)
        } catch let error as V2FileAttachmentError {
            throw error
        } catch {
            throw V2FileAttachmentError.cannotRead(fileName: fileName)
        }
        guard !data.isEmpty else {
            throw V2FileAttachmentError.emptyFile(fileName: fileName)
        }

        return V2PickedFile(data: data, fileName: fileName, kind: kind(for: url))
    }

    private static func readBoundedData(from url: URL, maximumBytes: Int) throws -> Data {
        guard let stream = InputStream(url: url) else {
            throw V2FileAttachmentError.cannotRead(fileName: url.lastPathComponent)
        }
        stream.open()
        defer { stream.close() }

        var data = Data()
        data.reserveCapacity(min(maximumBytes, 64 * 1024))
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)

        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 {
                throw V2FileAttachmentError.cannotRead(fileName: url.lastPathComponent)
            }
            if count == 0 {
                break
            }
            guard data.count <= maximumBytes - count else {
                throw V2FileAttachmentError.fileTooLarge(
                    fileName: url.lastPathComponent,
                    maximumBytes: maximumBytes
                )
            }
            data.append(contentsOf: buffer[0..<count])
        }
        return data
    }

    private static func kind(for url: URL) -> V2CaptureAsset.Kind {
        guard let type = UTType(filenameExtension: url.pathExtension) else {
            return .document
        }
        if type.conforms(to: .image) {
            return .image
        }
        if type.conforms(to: .audio) {
            return .audio
        }
        return .document
    }
}

/// A compact attachment row with a Quick Look thumbnail where available.
public struct V2AttachmentTile: View {
    public let asset: V2CaptureAsset
    public let store: V2CaptureAssetStore

    @State private var isPreviewPresented = false

    public init(asset: V2CaptureAsset, store: V2CaptureAssetStore) {
        self.asset = asset
        self.store = store
    }

    public var body: some View {
        HStack(spacing: 12) {
            Button {
                guard canPreview else { return }
                isPreviewPresented = true
            } label: {
                HStack(spacing: 12) {
                    V2AttachmentThumbnail(asset: asset, store: store)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(asset.originalFileName ?? asset.fileName)
                            .font(V2Theme.TypeRole.labelLarge)
                            .foregroundStyle(V2Theme.ink)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(Self.metadata(for: asset))
                            .font(V2Theme.TypeRole.bodySmall)
                            .foregroundStyle(V2Theme.secondary)
                    }
                    Spacer(minLength: 0)
                    if canPreview {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(V2Theme.tertiary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("capture.attachment.\(asset.id).preview")

            if let url = fileURL {
                let shareItem = V2AttachmentShareItem(
                    fileURL: url,
                    suggestedFileName: asset.originalFileName ?? asset.fileName
                )
                ShareLink(
                    item: shareItem,
                    preview: SharePreview(
                        asset.originalFileName ?? asset.fileName,
                        icon: Image(systemName: V2AttachmentThumbnailer.fallbackIconName(for: asset))
                    )
                ) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(V2Theme.blue)
                }
                .accessibilityLabel("分享附件")
                .accessibilityIdentifier("capture.attachment.\(asset.id).share")
            }
        }
        .padding(12)
        .background(V2Theme.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(V2Theme.line.opacity(0.75), lineWidth: 1)
        }
        .sheet(isPresented: $isPreviewPresented) {
            if let fileURL {
                #if os(macOS)
                VStack(spacing: 0) {
                    HStack {
                        Text(asset.originalFileName ?? "附件预览").font(.headline).lineLimit(1)
                        Spacer()
                        Button("完成") { isPreviewPresented = false }.keyboardShortcut(.cancelAction)
                    }.padding(16)
                    Divider()
                    V2QuickLookPreview(url: fileURL).frame(maxWidth: .infinity, maxHeight: .infinity)
                }.frame(minWidth: 620, minHeight: 460)
                #else
                V2QuickLookPreview(url: fileURL)
                    .ignoresSafeArea(edges: .bottom)
                #endif
            }
        }
    }

    private var fileURL: URL? {
        try? store.url(for: asset)
    }

    private var canPreview: Bool {
        fileURL != nil
    }

    private static func metadata(for asset: V2CaptureAsset) -> String {
        let size = ByteCountFormatter.string(fromByteCount: Int64(asset.byteCount), countStyle: .file)
        let suffix = ((asset.originalFileName ?? asset.fileName) as NSString).pathExtension
        let ext = suffix.isEmpty ? "文件" : suffix.uppercased()
        return "\(ext) · \(size)"
    }
}

/// The item handed to ShareLink. The transfer representation exposes a
/// temporary hard link or symlink with the original basename, so sharing keeps
/// the user's filename without copying the attachment bytes into app storage.
struct V2AttachmentShareItem: Transferable, Sendable {
    let fileURL: URL
    let suggestedFileName: String

    init(fileURL: URL, suggestedFileName: String) {
        self.fileURL = fileURL
        self.suggestedFileName = suggestedFileName
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(
            exportedContentType: .data,
            shouldAllowToOpenInPlace: false
        ) { item in
            try item.makeSentTransferredFile()
        }
    }

    /// This method is also used by the App XCTest to inspect the exact file
    /// returned by the FileRepresentation exporter.
    func makeSentTransferredFile() throws -> SentTransferredFile {
        let exportURL = try V2AttachmentShareFile.prepare(
            sourceURL: fileURL,
            suggestedFileName: suggestedFileName
        )
        return SentTransferredFile(exportURL, allowAccessingOriginalFile: false)
    }
}

private enum V2AttachmentShareFile {
    private static let rootDirectoryName = "ToughTrialShare"
    private static let maximumRetainedExports = 24
    private static let staleExportInterval: TimeInterval = 60 * 60

    static func prepare(sourceURL: URL, suggestedFileName: String) throws -> URL {
        let fileName = safeFileName(suggestedFileName, fallback: sourceURL.lastPathComponent)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw V2FileAttachmentError.cannotPrepareShare(fileName: fileName)
        }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(rootDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true,
            attributes: nil
        )
        prune(root: root)

        let exportDirectory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: exportDirectory,
            withIntermediateDirectories: false,
            attributes: nil
        )
        let exportURL = exportDirectory.appendingPathComponent(fileName, isDirectory: false)

        do {
            // A hard link shares the existing bytes and gives the transfer
            // provider the requested basename.
            try FileManager.default.linkItem(at: sourceURL, to: exportURL)
        } catch {
            do {
                // A symlink is the fallback for stores that do not allow hard
                // links across their container boundary. It also avoids a
                // potentially large duplicate file.
                try FileManager.default.createSymbolicLink(
                    at: exportURL,
                    withDestinationURL: sourceURL
                )
            } catch {
                try? FileManager.default.removeItem(at: exportDirectory)
                throw V2FileAttachmentError.cannotPrepareShare(fileName: fileName)
            }
        }
        return exportURL
    }

    private static func safeFileName(_ suggestedFileName: String, fallback: String) -> String {
        let candidate = URL(fileURLWithPath: suggestedFileName).lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let base = candidate.isEmpty ? fallback : candidate
        let sanitized = base.unicodeScalars.map { scalar in
            scalar.value < 32 || scalar == "/" || scalar == ":" ? "-" : String(scalar)
        }.joined()
        return sanitized.isEmpty ? "附件" : sanitized
    }

    private static func prune(root: URL) {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let now = Date()
        var retained = urls.filter { url in
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                  let date = values.contentModificationDate
            else {
                return true
            }
            if now.timeIntervalSince(date) > staleExportInterval {
                try? FileManager.default.removeItem(at: url)
                return false
            }
            return true
        }
        guard retained.count > maximumRetainedExports else { return }
        retained.sort { modificationDate($0) < modificationDate($1) }
        for url in retained.prefix(retained.count - maximumRetainedExports) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func modificationDate(_ url: URL) -> Date {
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
              let date = values.contentModificationDate
        else {
            return .distantPast
        }
        return date
    }
}

private struct V2AttachmentThumbnail: View {
    let asset: V2CaptureAsset
    let store: V2CaptureAssetStore
#if os(iOS)
    @State private var thumbnail: UIImage?
#elseif os(macOS)
    @State private var thumbnail: NSImage?
#endif
    @State private var isLoading = true

    var body: some View {
        Group {
            if let thumbnail {
                Self.image(for: thumbnail)
                    .resizable()
                    .scaledToFill()
            } else if isLoading {
                ProgressView()
                    .tint(V2Theme.blue)
            } else {
                Image(systemName: V2AttachmentThumbnailer.fallbackIconName(for: asset))
                    .font(.title2)
                    .foregroundStyle(V2Theme.blue)
            }
        }
        .frame(width: 58, height: 58)
        .background(V2Theme.ColorRole.primaryContainer, in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .task(id: asset.id) {
            isLoading = true
            thumbnail = await V2AttachmentThumbnailer.thumbnail(
                for: asset,
                store: store,
                size: CGSize(width: 116, height: 116)
            )
            isLoading = false
        }
    }

    private static func image(for thumbnail: V2AttachmentThumbnailImage) -> Image {
#if os(iOS)
        Image(uiImage: thumbnail)
#elseif os(macOS)
        Image(nsImage: thumbnail)
#endif
    }
}

@MainActor
enum V2AttachmentThumbnailer {
    fileprivate static func thumbnail(
        for asset: V2CaptureAsset,
        store: V2CaptureAssetStore,
        size: CGSize
    ) async -> V2AttachmentThumbnailImage? {
        guard let url = try? store.url(for: asset), canRenderThumbnail(for: asset, url: url)
        else {
            return nil
        }

#if os(iOS)
        let scale = UIScreen.main.scale
#elseif os(macOS)
        let scale = NSScreen.main?.backingScaleFactor ?? 2
#endif
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: scale,
            representationTypes: .thumbnail
        )

        return await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
#if os(iOS)
                continuation.resume(returning: representation?.uiImage)
#elseif os(macOS)
                continuation.resume(returning: representation?.nsImage)
#endif
            }
        }
    }

    static func canRenderThumbnail(for asset: V2CaptureAsset, url: URL) -> Bool {
        if asset.kind == .image {
            return true
        }
        guard asset.kind == .document,
              let type = UTType(filenameExtension: url.pathExtension)
        else {
            return false
        }
        return type.conforms(to: .pdf)
    }

    static func fallbackIconName(for asset: V2CaptureAsset) -> String {
        switch asset.kind {
        case .image:
            return "photo"
        case .audio:
            return "waveform"
        case .handwriting:
            return "pencil.and.scribble"
        case .document:
            return "doc.fill"
        }
    }
}

#if os(iOS)
private struct V2QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        context.coordinator.url = url
        controller.reloadData()
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(
            _ controller: QLPreviewController,
            previewItemAt index: Int
        ) -> QLPreviewItem {
            url as NSURL
        }
    }
}
#elseif os(macOS)
private struct V2QuickLookPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let preview = QLPreviewView(frame: .zero, style: .normal)!
        preview.shouldCloseWithWindow = true
        preview.previewItem = url as NSURL
        return preview
    }

    func updateNSView(_ preview: QLPreviewView, context: Context) {
        preview.previewItem = url as NSURL
    }

    static func dismantleNSView(_ preview: QLPreviewView, coordinator: ()) {
        preview.close()
    }
}
#endif

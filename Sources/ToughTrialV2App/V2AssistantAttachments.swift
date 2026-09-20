import Foundation
import PDFKit
import SwiftUI
import ToughTrialV2Core

@MainActor
enum V2AssistantAttachments {
    static var assets: V2CaptureAssetStore {
        V2CaptureAssetStore(directory: V2PlatformStorage.assets)
    }

    static func save(_ file: V2PickedFile, appStore: V2AppStore) async throws -> V2AssistantAttachment {
        let ticket = try V2PluginStore.shared.ticket(["core.assistant", "core.attachments"])
        let extracted: String?
        if file.kind == .image { extracted = await V2CaptureView.recognize(file.data) }
        else {
            extracted = await Task.detached(priority: .userInitiated) {
                let suffix = (file.fileName as NSString).pathExtension.lowercased()
                if suffix == "pdf", let document = PDFDocument(data: file.data) {
                    return String((0..<min(document.pageCount, 20)).compactMap { document.page(at: $0)?.string }.joined(separator: "\n").prefix(8_000))
                }
                if ["txt", "md", "csv", "json", "log", "ics"].contains(suffix) {
                    return String(data: file.data.prefix(64_000), encoding: .utf8).map { String($0.prefix(8_000)) }
                }
                return nil
            }.value
        }
        try V2PluginStore.shared.validate(ticket)
        let asset = try appStore.engine.saveCaptureAsset(file.data, kind: file.kind, fileExtension: file.storageExtension,
                                                       store: assets, originalFileName: file.fileName)
        return .init(assetID: asset.id, fileName: file.fileName, extractedText: extracted)
    }
}

struct V2AssistantAttachmentPreview: View {
    let attachment: V2AssistantAttachment
    @ObservedObject var appStore: V2AppStore
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let asset = appStore.engine.snapshot.capture.assets.first(where: { $0.id == attachment.assetID }) {
                V2AttachmentTile(asset: asset, store: V2AssistantAttachments.assets)
            } else { Label(attachment.fileName, systemImage: "doc") }
            Text(attachment.extractedText?.isEmpty == false ? "已提取文字供助手参考（最多 8,000 字；PDF 前 20 页）" : "原文件已保留，暂未提取到可读文字")
                .font(.caption).foregroundStyle(V2Theme.secondary)
        }.padding()
    }
}

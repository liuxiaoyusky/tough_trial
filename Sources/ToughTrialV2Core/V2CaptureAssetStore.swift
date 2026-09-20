import CryptoKit
import Foundation

public enum V2CaptureAssetStoreError: Error, Equatable, Sendable {
    case emptyData
    case invalidFileExtension
    case invalidAsset
    case fileNotFound
    case readFailed
    case writeFailed
    case byteCountMismatch(expected: Int, actual: Int)
    case hashMismatch(expected: String, actual: String)
    case unableToAllocateFileName
}

public struct V2CaptureAsset: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Equatable, Sendable {
        case image
        case handwriting
        case audio
        case document
    }

    public let id: String
    public let kind: Kind
    public let fileName: String
    public let sha256: String
    public let byteCount: Int
    public var originalFileName: String?

    public init(
        id: String,
        kind: Kind,
        fileName: String,
        sha256: String,
        byteCount: Int,
        originalFileName: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.fileName = fileName
        self.sha256 = sha256
        self.byteCount = byteCount
        self.originalFileName = originalFileName
    }
}

public struct V2CaptureAssetStore: Sendable {
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory.standardizedFileURL
    }

    public func save(
        _ data: Data,
        kind: V2CaptureAsset.Kind,
        fileExtension: String
    ) throws -> V2CaptureAsset {
        guard !data.isEmpty else {
            throw V2CaptureAssetStoreError.emptyData
        }

        let normalizedExtension = try Self.normalizedExtension(fileExtension)
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            throw V2CaptureAssetStoreError.writeFailed
        }

        for _ in 0..<8 {
            let id = UUID().uuidString.lowercased()
            let fileName = "\(id).\(normalizedExtension)"
            let asset = V2CaptureAsset(
                id: id,
                kind: kind,
                fileName: fileName,
                sha256: Self.sha256(data),
                byteCount: data.count
            )
            let targetURL = try url(for: asset)
            guard !FileManager.default.fileExists(atPath: targetURL.path) else {
                continue
            }

            do {
                try data.write(to: targetURL, options: [.atomic])
                return asset
            } catch {
                throw V2CaptureAssetStoreError.writeFailed
            }
        }

        throw V2CaptureAssetStoreError.unableToAllocateFileName
    }

    public func data(for asset: V2CaptureAsset) throws -> Data {
        let targetURL = try url(for: asset)
        guard FileManager.default.fileExists(atPath: targetURL.path) else {
            throw V2CaptureAssetStoreError.fileNotFound
        }

        let data: Data
        do {
            data = try Data(contentsOf: targetURL, options: [.mappedIfSafe])
        } catch {
            throw V2CaptureAssetStoreError.readFailed
        }

        guard data.count == asset.byteCount else {
            throw V2CaptureAssetStoreError.byteCountMismatch(
                expected: asset.byteCount,
                actual: data.count
            )
        }

        let actualHash = Self.sha256(data)
        guard actualHash.caseInsensitiveCompare(asset.sha256) == .orderedSame else {
            throw V2CaptureAssetStoreError.hashMismatch(
                expected: asset.sha256,
                actual: actualHash
            )
        }

        return data
    }

    public func url(for asset: V2CaptureAsset) throws -> URL {
        guard Self.isValid(asset: asset) else {
            throw V2CaptureAssetStoreError.invalidAsset
        }

        let targetURL = directory.appendingPathComponent(asset.fileName, isDirectory: false)
            .standardizedFileURL
        let normalizedDirectory = directory.standardizedFileURL

        guard targetURL.deletingLastPathComponent() == normalizedDirectory else {
            throw V2CaptureAssetStoreError.invalidAsset
        }

        if FileManager.default.fileExists(atPath: targetURL.path) {
            let resolvedTarget = targetURL.resolvingSymlinksInPath().standardizedFileURL
            let resolvedDirectory = normalizedDirectory.resolvingSymlinksInPath()
                .standardizedFileURL
            guard resolvedTarget.deletingLastPathComponent() == resolvedDirectory else {
                throw V2CaptureAssetStoreError.invalidAsset
            }
        }

        return targetURL
    }

    private static func isValid(asset: V2CaptureAsset) -> Bool {
        guard let uuid = UUID(uuidString: asset.id),
              asset.byteCount > 0,
              asset.sha256.count == 64,
              asset.sha256.unicodeScalars.allSatisfy(Self.isHexScalar)
        else {
            return false
        }

        let parts = asset.fileName.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2,
              UUID(uuidString: String(parts[0])) != nil,
              uuid.uuidString.caseInsensitiveCompare(String(parts[0])) == .orderedSame,
              let normalizedExtension = try? normalizedExtension(String(parts[1])),
              normalizedExtension == String(parts[1])
        else {
            return false
        }

        return true
    }

    private static func normalizedExtension(_ fileExtension: String) throws -> String {
        let extensionWithoutLeadingDot: String
        if fileExtension.hasPrefix(".") {
            extensionWithoutLeadingDot = String(fileExtension.dropFirst())
        } else {
            extensionWithoutLeadingDot = fileExtension
        }

        guard !extensionWithoutLeadingDot.isEmpty,
              extensionWithoutLeadingDot.count <= 32,
              extensionWithoutLeadingDot.unicodeScalars.allSatisfy(isSafeExtensionScalar)
        else {
            throw V2CaptureAssetStoreError.invalidFileExtension
        }

        return extensionWithoutLeadingDot.lowercased()
    }

    private static func isSafeExtensionScalar(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 48...57, 65...90, 97...122, 45, 95:
            return true
        default:
            return false
        }
    }

    private static func isHexScalar(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 48...57, 65...70, 97...102:
            return true
        default:
            return false
        }
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

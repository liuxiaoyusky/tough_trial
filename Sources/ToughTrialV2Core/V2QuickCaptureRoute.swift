import Foundation

public enum V2QuickCaptureAction: String, CaseIterable, Sendable {
    case ledger, task, note
    public var url: URL { URL(string: "toughtrial://capture/\(rawValue)")! }
    public init?(url: URL) {
        guard url.scheme?.lowercased() == "toughtrial", url.host?.lowercased() == "capture",
              url.user == nil, url.password == nil, url.port == nil, url.query == nil, url.fragment == nil,
              let action = Self(rawValue: String(url.path.dropFirst())) else { return nil }
        self = action
    }
}

public struct V2QuickCaptureRequest: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let action: V2QuickCaptureAction
    public init(action: V2QuickCaptureAction) { self.id = UUID(); self.action = action }
}

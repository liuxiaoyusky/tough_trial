import Foundation

/// Native hosts retain their own local document directories.
enum V2PlatformStorage {
    static var root: URL {
        #if os(macOS)
        #if DEBUG
        let verification = Bundle.main.object(forInfoDictionaryKey: "ToughTrialVerificationDirectory") as? String
        #else
        let verification: String? = nil
        #endif
        return (ProcessInfo.processInfo.environment["TOUGH_TRIAL_MAC_DATA_DIR"] ?? verification).map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? URL.applicationSupportDirectory.appendingPathComponent("ToughTrialMac", isDirectory: true)
        #else
        return URL.applicationSupportDirectory.appendingPathComponent("ToughTrial", isDirectory: true)
        #endif
    }
    static var assets: URL { root.appendingPathComponent("capture-assets", isDirectory: true) }
}

import AVFoundation

/// Requests the microphone permission through the native API for the host
/// platform. The audio engines still perform their own setup after this gate
/// succeeds; a granted permission does not imply that recording will succeed.
enum V2MicrophonePermission {
    static func requestAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            #if os(iOS)
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
            #elseif os(macOS)
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
            #else
            continuation.resume(returning: false)
            #endif
        }
    }
}

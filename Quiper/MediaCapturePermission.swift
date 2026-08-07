import AVFoundation
import WebKit

/// Bridges website media-capture requests to macOS TCC (camera / microphone).
///
/// WebKit's `requestMediaCapturePermissionFor` only covers the page-level grant.
/// Without an explicit `AVCaptureDevice.requestAccess`, the system never prompts
/// and capture fails silently for first-time use.
enum MediaCapturePermission {
    @available(macOS 12.0, *)
    static func ensureAccess(for type: WKMediaCaptureType) async -> Bool {
        switch type {
        case .camera:
            return await ensureAccess(for: .video)
        case .microphone:
            return await ensureAccess(for: .audio)
        case .cameraAndMicrophone:
            // Request sequentially so macOS can present one TCC prompt at a time.
            guard await ensureAccess(for: .video) else { return false }
            return await ensureAccess(for: .audio)
        @unknown default:
            return false
        }
    }

    private static func ensureAccess(for mediaType: AVMediaType) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: mediaType) { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
}

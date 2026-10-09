import Foundation

/// Where a secure engine's encrypted volume mounts and what lives inside
/// it. Derived from the host app's bundle identifier so the main app and
/// the resident link helper resolve the same location — and see the same
/// truth: a locked engine's volume is not mounted, so nothing inside it,
/// including its external link routing records, is readable.
enum SecureEngineStorage {
    /// The engine metadata file inside a mounted secure bundle.
    static let metadataFileName = "quiper_engine_metadata.json"

    /// The directory an engine's encrypted volume mounts at:
    /// `~/Library/WebKit/<bundleIdentifier>/WebsiteDataStore/<serviceID>`.
    static func mountPointURL(bundleIdentifier: String, serviceID: UUID) -> URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WebKit")
            .appendingPathComponent(bundleIdentifier)
            .appendingPathComponent("WebsiteDataStore")
            .appendingPathComponent(serviceID.uuidString)
    }

    /// The engine metadata file's location for an engine's secure bundle.
    static func metadataFileURL(bundleIdentifier: String, serviceID: UUID) -> URL {
        mountPointURL(bundleIdentifier: bundleIdentifier, serviceID: serviceID)
            .appendingPathComponent(metadataFileName)
    }

    /// Whether a volume is actually mounted at the mount point — the
    /// filesystem's answer to "is this engine unlocked".
    static func isMounted(at mountPointURL: URL) -> Bool {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: mountPointURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return false
        }
        guard let values = try? mountPointURL.resourceValues(forKeys: [.isVolumeKey]) else {
            return false
        }
        return values.isVolume ?? false
    }
}

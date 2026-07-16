import Foundation
import WebKit

@MainActor
final class SecureDataMigrationManager {
    static let shared = SecureDataMigrationManager()
    
    var isMigrationPending = false
    
    private init() {}
    
    private func getTempURL(for serviceID: UUID) -> URL {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
        return tempDir.appendingPathComponent("QuiperMigration-\(serviceID.uuidString)")
    }
    
    /// Copies all files and subdirectories from one directory to another, replacing existing items if necessary.
    private func copyDirectoryContents(from source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        
        // Ensure destination directory exists
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        
        let contents = try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil, options: [])
        for item in contents {
            let destItemURL = destination.appendingPathComponent(item.lastPathComponent)
            if fileManager.fileExists(atPath: destItemURL.path) {
                try fileManager.removeItem(at: destItemURL)
            }
            try fileManager.copyItem(at: item, to: destItemURL)
        }
    }
    
    func hasBackup(for serviceID: UUID) -> Bool {
        FileManager.default.fileExists(atPath: getTempURL(for: serviceID).path)
    }
    
    /// Backs up the current data store folder to a safe temporary location.
    /// Returns true if backup succeeded or if there was no source data to backup.
    func backupData(for serviceID: UUID) -> Bool {
        (try? prepareMountedVolumeBackup(for: serviceID)) != nil
    }
    
    enum MountedVolumeBackupResult {
        case created
        case reusedExisting
    }
    
    /// Prepares migration backup data for a sparse bundle upgrade.
    /// When the engine volume is mounted, any existing temp backup is replaced with a fresh copy.
    /// When the volume is not mounted, an existing temp backup is preserved for a later retry.
    func prepareMountedVolumeBackup(for serviceID: UUID) throws -> MountedVolumeBackupResult {
        let fileManager = FileManager.default
        let sourceURL = EncryptedVolumeManager.shared.getMountPointURL(for: serviceID)
        let tempURL = getTempURL(for: serviceID)
        
        guard EncryptedVolumeManager.shared.isMounted(for: serviceID) else {
            if hasBackup(for: serviceID) {
                NSLog(
                    "[SecureDataMigration] Volume is not mounted for service %@; reusing existing migration backup at %@",
                    serviceID.uuidString,
                    tempURL.path
                )
                return .reusedExisting
            }
            throw NSError(
                domain: "SecureDataMigration",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Secure storage must be mounted before creating a migration backup."]
            )
        }
        
        try removeBackupIfPresent(at: tempURL)
        
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            NSLog("[SecureDataMigration] No data found at \(sourceURL.path), nothing to back up.")
            return .created
        }
        
        try fileManager.createDirectory(at: tempURL, withIntermediateDirectories: true)
        try copyDirectoryContents(from: sourceURL, to: tempURL)
        NSLog(
            "[SecureDataMigration] Successfully backed up database store contents from \(sourceURL.path) to \(tempURL.path)"
        )
        return .created
    }
    
    private func removeBackupIfPresent(at url: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return }
        do {
            try fileManager.removeItem(at: url)
        } catch {
            NSLog(
                "[SecureDataMigration] Failed to remove existing migration backup at %@: %@",
                url.path,
                error.localizedDescription
            )
            throw NSError(
                domain: "SecureDataMigration",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Failed to replace an existing migration backup. Please try again."]
            )
        }
    }
    
    /// Restores the backed up data store folder to the target location.
    func restoreData(for serviceID: UUID) {
        let fileManager = FileManager.default
        let tempURL = getTempURL(for: serviceID)
        let targetURL = EncryptedVolumeManager.shared.getMountPointURL(for: serviceID)
        
        guard fileManager.fileExists(atPath: tempURL.path) else {
            NSLog("[SecureDataMigration] No backup found at \(tempURL.path), restore skipped.")
            return
        }
        
        do {
            try copyDirectoryContents(from: tempURL, to: targetURL)
            NSLog("[SecureDataMigration] Successfully migrated database store contents to \(targetURL.path)")
        } catch {
            NSLog("[SecureDataMigration] Error restoring backup: \(error.localizedDescription)")
        }
        
        // Clean up backup directory
        try? fileManager.removeItem(at: tempURL)
    }
    
    /// Discards any backed up data store files to prevent lingering caches in temporary folders.
    func discardBackup(for serviceID: UUID) {
        let tempURL = getTempURL(for: serviceID)
        try? FileManager.default.removeItem(at: tempURL)
    }
}

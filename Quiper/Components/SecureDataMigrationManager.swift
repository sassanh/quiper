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
    
    /// Backs up the current data store folder to a safe temporary location.
    /// Returns true if backup succeeded or if there was no source data to backup.
    func backupData(for serviceID: UUID) -> Bool {
        let fileManager = FileManager.default
        let sourceURL = EncryptedVolumeManager.shared.getMountPointURL(for: serviceID)
        let tempURL = getTempURL(for: serviceID)
        
        // Wipe old temp directory if it exists
        if fileManager.fileExists(atPath: tempURL.path) {
            try? fileManager.removeItem(at: tempURL)
        }
        
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            NSLog("[SecureDataMigration] No data found at \(sourceURL.path), nothing to back up.")
            return true
        }
        
        do {
            try fileManager.createDirectory(at: tempURL, withIntermediateDirectories: true)
            try copyDirectoryContents(from: sourceURL, to: tempURL)
            NSLog("[SecureDataMigration] Successfully backed up database store contents from \(sourceURL.path) to \(tempURL.path)")
            return true
        } catch {
            NSLog("[SecureDataMigration] Error creating backup: \(error.localizedDescription)")
            return false
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

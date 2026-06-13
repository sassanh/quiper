import Foundation

internal struct SettingsDirectoryMigrator {
    
    /// Migrates the Application Support directory from the old legacy name (Quiper / QuiperDev)
    /// to the new Bundle Identifier based name, if it hasn't been migrated yet.
    /// Returns true if migration was attempted and succeeded, or if no migration was needed.
    /// Returns false if migration failed.
    @discardableResult
    internal static func migrateIfNeeded(fileManager: FileManager = .default, bundleID: String, supportDir: URL) -> Bool {
        let newDir = supportDir.appendingPathComponent(bundleID, isDirectory: true)
        
        // The old directory was named QuiperDev in Debug, or Quiper in Release.
        let oldDirName = bundleID.hasSuffix("Dev") ? "QuiperDev" : "Quiper"
        let oldDir = supportDir.appendingPathComponent(oldDirName, isDirectory: true)
        
        // Migrate only if the old directory exists and the new directory does not exist yet.
        if fileManager.fileExists(atPath: oldDir.path) && !fileManager.fileExists(atPath: newDir.path) {
            do {
                try fileManager.moveItem(at: oldDir, to: newDir)
                return true
            } catch {
                print("[Migration] Failed to migrate Application Support directory: \(error)")
                return false
            }
        }
        
        // No migration needed
        return true
    }
}

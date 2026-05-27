import Foundation
import WebKit

/// A sophisticated utility responsible for identifying and purging orphaned persistent WebKit data stores
/// without blocking the main application UI thread.
final class WebKitCacheCleaner {
    
    /// Returns the active WebKit bundle-specific WebsiteDataStore cache folder.
    private static func getWebsiteDataStoreDirectory() -> URL? {
        guard let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            return nil
        }
        let bundleID = Bundle.main.bundleIdentifier ?? "app.sassanh.quiper.Quiper"
        return libraryURL
            .appendingPathComponent("WebKit")
            .appendingPathComponent(bundleID)
            .appendingPathComponent("WebsiteDataStore")
    }
    
    /// Scans the WebKit stores, filters directories that match UUID layout but do not exist
    /// in the active user settings configuration, and purges them asynchronously.
    @MainActor
    static func cleanOrphanedStores() {
        guard Settings.shared.shouldPurgeDanglingWebData else {
            NSLog("[WebKitCacheCleaner] Background orphaned cache data store cleaner is disabled by user settings.")
            return
        }
        // Collect active engine IDs from Settings.shared
        let activeIDs = Set(Settings.shared.services.map { $0.id })
        
        // Retrieve the WebKit data store root folder URL
        guard let storeDir = getWebsiteDataStoreDirectory() else {
            return
        }
        
        guard FileManager.default.fileExists(atPath: storeDir.path) else {
            return
        }
        
        // Enumerate directory entries in the background (disk I/O)
        DispatchQueue.global(qos: .utility).async {
            let fileManager = FileManager.default
            guard let contents = try? fileManager.contentsOfDirectory(
                at: storeDir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
                return
            }
            
            // Loop through directory paths and detect UUID-based orphans
            for url in contents {
                let folderName = url.lastPathComponent
                
                // 1. Strict UUID checking - completely ignores system folders (.default, safe browsing, etc.)
                guard let storeUUID = UUID(uuidString: folderName) else {
                    continue
                }
                
                // 2. Active preservation - preserves active engine caches (both locked and unlocked)
                if activeIDs.contains(storeUUID) {
                    continue
                }
                
                // 3. Purge orphaned directory natively via WebKit
                DispatchQueue.main.async {
                    NSLog("[WebKitCacheCleaner] Purging orphaned cache data store: \(storeUUID)")
                    WKWebsiteDataStore.remove(forIdentifier: storeUUID) { error in
                        if let error = error {
                            NSLog("[WebKitCacheCleaner] Failed to natively remove data store \(storeUUID): \(error.localizedDescription)")
                            // Fallback file manager deletion just in case WebKit is locked or busy
                            let pathToDelete = url.path
                            DispatchQueue.global(qos: .utility).async {
                                try? FileManager.default.removeItem(atPath: pathToDelete)
                            }
                        } else {
                            NSLog("[WebKitCacheCleaner] Successfully removed data store \(storeUUID)")
                        }
                    }
                }
            }
        }
    }
}

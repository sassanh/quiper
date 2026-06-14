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
    
    /// Scans the WebKit stores, Application Support directories, and filters items that match UUID layout
    /// but do not exist in the active user settings configuration, purging them asynchronously.
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
        
        // Enumerate directory entries in the background (disk I/O)
        DispatchQueue.global(qos: .utility).async {
            let fileManager = FileManager.default
            
            // 1. Clean per-engine WebKit data stores
            if fileManager.fileExists(atPath: storeDir.path),
               let contents = try? fileManager.contentsOfDirectory(
                at: storeDir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
               ) {
                // Loop through directory paths and detect UUID-based orphans
                for url in contents {
                    let folderName = url.lastPathComponent
                    
                    // Check if this directory is an orphaned UUID data store
                    guard isOrphanedStore(folderName: folderName, activeIDs: activeIDs) else {
                        continue
                    }
                    
                    // Purge orphaned directory natively via WebKit
                    let storeUUID = UUID(uuidString: folderName)!
                    
                    DispatchQueue.main.async {
                        NSLog("[WebKitCacheCleaner] Purging orphaned cache data store: \(storeUUID)")
                        WKWebsiteDataStore.remove(forIdentifier: storeUUID) { error in
                            if let error = error {
                                NSLog("[WebKitCacheCleaner] Failed to natively remove data store \(storeUUID): \(error.localizedDescription)")
                                // Fallback file manager deletion just in case WebKit is locked or busy
                                let pathToDelete = url.path
                                DispatchQueue.global(qos: .utility).async {
                                    try? fileManager.removeItem(atPath: pathToDelete)
                                }
                            } else {
                                NSLog("[WebKitCacheCleaner] Successfully removed data store \(storeUUID)")
                            }
                        }
                    }
                }
            }
            
            // 2. Clean Application Support folders
            if let appSupportDir = baseAppSupportDirectory {
                let cssDir = appSupportDir.appendingPathComponent("CustomCSS", isDirectory: true)
                purgeOrphanedFiles(in: cssDir, fileExtension: "css", activeIDs: activeIDs, fileManager: fileManager)
                
                let selectorsDir = appSupportDir.appendingPathComponent("FocusSelectors", isDirectory: true)
                purgeOrphanedFiles(in: selectorsDir, fileExtension: "txt", activeIDs: activeIDs, fileManager: fileManager)
                
                let scriptsDir = appSupportDir.appendingPathComponent("ActionScripts", isDirectory: true)
                purgeOrphanedFiles(in: scriptsDir, fileExtension: nil, activeIDs: activeIDs, fileManager: fileManager)
                
                let encryptedDir = appSupportDir.appendingPathComponent("EncryptedStores", isDirectory: true)
                purgeOrphanedFiles(in: encryptedDir, fileExtension: "sparsebundle", activeIDs: activeIDs, fileManager: fileManager)
            }
        }
    }
    
    private static var baseAppSupportDirectory: URL? {
        let isRunningTests = NSClassFromString("XCTestCase") != nil
        let isUITesting = CommandLine.arguments.contains("--uitesting")
        
        let appDir: URL
        if isRunningTests || isUITesting {
            let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            appDir = tempDir.appendingPathComponent("QuiperTests-\(ProcessInfo.processInfo.processIdentifier)")
        } else {
            guard let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                return nil
            }
            appDir = supportDir.appendingPathComponent(Constants.APP_FOLDER_NAME, isDirectory: true)
        }
        return appDir
    }
    
    internal static func purgeOrphanedFiles(
        in directory: URL,
        fileExtension: String?,
        activeIDs: Set<UUID>,
        fileManager: FileManager
    ) {
        guard fileManager.fileExists(atPath: directory.path) else { return }
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }
        
        for url in contents {
            let nameWithoutExtension: String
            if let ext = fileExtension {
                guard url.pathExtension.lowercased() == ext.lowercased() else { continue }
                nameWithoutExtension = url.deletingPathExtension().lastPathComponent
            } else {
                nameWithoutExtension = url.lastPathComponent
            }
            
            guard isOrphanedStore(folderName: nameWithoutExtension, activeIDs: activeIDs) else {
                continue
            }
            
            let uuid = UUID(uuidString: nameWithoutExtension)!
            
            NSLog("[WebKitCacheCleaner] Purging orphaned leftovers at: \(url.path)")
            try? fileManager.removeItem(at: url)
            
            // Delete matching key from Keychain on the MainActor
            DispatchQueue.main.async {
                SecureStorageManager.shared.deleteKeyFromKeychain(for: uuid)
            }
        }
    }
    
    /// Pure function for testing whether a specific folder represents an orphaned data store.
    internal static func isOrphanedStore(folderName: String, activeIDs: Set<UUID>) -> Bool {
        // 1. Strict UUID checking - completely ignores system folders (.default, safe browsing, etc.)
        guard let storeUUID = UUID(uuidString: folderName) else {
            return false
        }
        
        // 2. Active preservation - preserves active engine caches
        if activeIDs.contains(storeUUID) {
            return false
        }
        
        return true
    }
}

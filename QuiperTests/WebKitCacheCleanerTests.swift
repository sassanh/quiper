import XCTest
@testable import Quiper

final class WebKitCacheCleanerTests: XCTestCase {

    func testIsOrphanedStore_WithSystemFolders_ReturnsFalse() {
        let activeIDs: Set<UUID> = []
        
        // These are standard WebKit/macOS system folders that should NOT be deleted
        XCTAssertFalse(WebKitCacheCleaner.isOrphanedStore(folderName: ".default", activeIDs: activeIDs))
        XCTAssertFalse(WebKitCacheCleaner.isOrphanedStore(folderName: "SafeBrowsing", activeIDs: activeIDs))
        XCTAssertFalse(WebKitCacheCleaner.isOrphanedStore(folderName: "IndexedDB", activeIDs: activeIDs))
        XCTAssertFalse(WebKitCacheCleaner.isOrphanedStore(folderName: ".DS_Store", activeIDs: activeIDs))
    }

    func testIsOrphanedStore_WithActiveEngineUUID_ReturnsFalse() {
        let activeUUID = UUID()
        let activeIDs: Set<UUID> = [activeUUID]
        
        // Ensure active engines are preserved
        XCTAssertFalse(WebKitCacheCleaner.isOrphanedStore(folderName: activeUUID.uuidString, activeIDs: activeIDs))
    }

    func testIsOrphanedStore_WithMultipleActiveEngines_ReturnsFalse() {
        let activeUUID1 = UUID()
        let activeUUID2 = UUID()
        let activeIDs: Set<UUID> = [activeUUID1, activeUUID2]
        
        XCTAssertFalse(WebKitCacheCleaner.isOrphanedStore(folderName: activeUUID1.uuidString, activeIDs: activeIDs))
        XCTAssertFalse(WebKitCacheCleaner.isOrphanedStore(folderName: activeUUID2.uuidString, activeIDs: activeIDs))
    }

    func testIsOrphanedStore_WithDanglingUUID_ReturnsTrue() {
        let activeUUID = UUID()
        let danglingUUID = UUID()
        let activeIDs: Set<UUID> = [activeUUID]
        
        // A UUID that isn't in activeIDs should be flagged as orphaned
        XCTAssertTrue(WebKitCacheCleaner.isOrphanedStore(folderName: danglingUUID.uuidString, activeIDs: activeIDs))
    }

    func testIsOrphanedStore_WithEmptyActiveIDs_ReturnsTrueForUUID() {
        let danglingUUID = UUID()
        let activeIDs: Set<UUID> = []
        
        XCTAssertTrue(WebKitCacheCleaner.isOrphanedStore(folderName: danglingUUID.uuidString, activeIDs: activeIDs))
    }

    func testIsOrphanedStore_WithMalformedUUID_ReturnsFalse() {
        let activeIDs: Set<UUID> = []
        
        // Only perfectly valid UUID strings should be processed
        XCTAssertFalse(WebKitCacheCleaner.isOrphanedStore(folderName: "123e4567-e89b-12d3-a456-42661417400", activeIDs: activeIDs)) // Missing character
        XCTAssertFalse(WebKitCacheCleaner.isOrphanedStore(folderName: "not-a-uuid", activeIDs: activeIDs))
    }

    func testPurgeOrphanedFiles_ClearsOrphanedFilesAndKeepsActiveOnes() throws {
        let fileManager = FileManager.default
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("WebKitCacheCleanerTests-\(UUID().uuidString)")
        
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? fileManager.removeItem(at: tempDir)
        }
        
        let activeUUID1 = UUID()
        let activeUUID2 = UUID()
        let orphanedUUID1 = UUID()
        let orphanedUUID2 = UUID()
        
        let activeIDs: Set<UUID> = [activeUUID1, activeUUID2]
        
        // 1. Create CSS test files
        let cssDir = tempDir.appendingPathComponent("CustomCSS")
        try fileManager.createDirectory(at: cssDir, withIntermediateDirectories: true)
        
        let activeCSS1 = cssDir.appendingPathComponent("\(activeUUID1.uuidString).css")
        let activeCSS2 = cssDir.appendingPathComponent("\(activeUUID2.uuidString).css")
        let orphanedCSS = cssDir.appendingPathComponent("\(orphanedUUID1.uuidString).css")
        let systemCSS = cssDir.appendingPathComponent("system.css")
        
        try "content".write(to: activeCSS1, atomically: true, encoding: .utf8)
        try "content".write(to: activeCSS2, atomically: true, encoding: .utf8)
        try "content".write(to: orphanedCSS, atomically: true, encoding: .utf8)
        try "content".write(to: systemCSS, atomically: true, encoding: .utf8)
        
        // Purge css
        WebKitCacheCleaner.purgeOrphanedFiles(in: cssDir, fileExtension: "css", activeIDs: activeIDs, fileManager: fileManager)
        
        XCTAssertTrue(fileManager.fileExists(atPath: activeCSS1.path))
        XCTAssertTrue(fileManager.fileExists(atPath: activeCSS2.path))
        XCTAssertTrue(fileManager.fileExists(atPath: systemCSS.path))
        XCTAssertFalse(fileManager.fileExists(atPath: orphanedCSS.path))
        
        // 2. Create Script folders (ActionScripts directory subfolders)
        let scriptsDir = tempDir.appendingPathComponent("ActionScripts")
        try fileManager.createDirectory(at: scriptsDir, withIntermediateDirectories: true)
        
        let activeScriptDir = scriptsDir.appendingPathComponent(activeUUID1.uuidString)
        let orphanedScriptDir = scriptsDir.appendingPathComponent(orphanedUUID2.uuidString)
        let systemScriptDir = scriptsDir.appendingPathComponent("system_folder")
        
        try fileManager.createDirectory(at: activeScriptDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: orphanedScriptDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: systemScriptDir, withIntermediateDirectories: true)
        
        // Purge script folders
        WebKitCacheCleaner.purgeOrphanedFiles(in: scriptsDir, fileExtension: nil, activeIDs: activeIDs, fileManager: fileManager)
        
        XCTAssertTrue(fileManager.fileExists(atPath: activeScriptDir.path))
        XCTAssertTrue(fileManager.fileExists(atPath: systemScriptDir.path))
        XCTAssertFalse(fileManager.fileExists(atPath: orphanedScriptDir.path))
    }
}

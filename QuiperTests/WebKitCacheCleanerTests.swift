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
}

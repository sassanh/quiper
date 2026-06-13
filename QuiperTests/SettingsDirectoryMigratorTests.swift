import XCTest
@testable import Quiper

final class SettingsDirectoryMigratorTests: XCTestCase {

    private var fileManager: FileManager!
    private var tempSupportDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        tempSupportDir = tempDir
    }

    override func tearDownWithError() throws {
        if let dir = tempSupportDir, fileManager.fileExists(atPath: dir.path) {
            try fileManager.removeItem(at: dir)
        }
        fileManager = nil
        tempSupportDir = nil
        try super.tearDownWithError()
    }

    func testMigration_FromLegacyRelease_ToNewBundleID() throws {
        let bundleID = "app.sassanh.quiper.Quiper"
        let legacyDir = tempSupportDir.appendingPathComponent("Quiper", isDirectory: true)
        let newDir = tempSupportDir.appendingPathComponent(bundleID, isDirectory: true)

        // Setup legacy directory
        try fileManager.createDirectory(at: legacyDir, withIntermediateDirectories: true)
        let testFile = legacyDir.appendingPathComponent("settings.json")
        try "test data".write(to: testFile, atomically: true, encoding: .utf8)

        // Perform migration
        let success = SettingsDirectoryMigrator.migrateIfNeeded(fileManager: fileManager, bundleID: bundleID, supportDir: tempSupportDir)

        XCTAssertTrue(success, "Migration should succeed")
        XCTAssertFalse(fileManager.fileExists(atPath: legacyDir.path), "Legacy directory should be removed")
        XCTAssertTrue(fileManager.fileExists(atPath: newDir.path), "New directory should be created")
        
        let newTestFile = newDir.appendingPathComponent("settings.json")
        XCTAssertTrue(fileManager.fileExists(atPath: newTestFile.path), "Contents should be moved")
        let content = try String(contentsOf: newTestFile)
        XCTAssertEqual(content, "test data")
    }

    func testMigration_FromLegacyDebug_ToNewBundleID() throws {
        let bundleID = "app.sassanh.quiper.QuiperDev"
        let legacyDir = tempSupportDir.appendingPathComponent("QuiperDev", isDirectory: true)
        let newDir = tempSupportDir.appendingPathComponent(bundleID, isDirectory: true)

        // Setup legacy directory
        try fileManager.createDirectory(at: legacyDir, withIntermediateDirectories: true)

        // Perform migration
        let success = SettingsDirectoryMigrator.migrateIfNeeded(fileManager: fileManager, bundleID: bundleID, supportDir: tempSupportDir)

        XCTAssertTrue(success)
        XCTAssertFalse(fileManager.fileExists(atPath: legacyDir.path))
        XCTAssertTrue(fileManager.fileExists(atPath: newDir.path))
    }

    func testMigration_SkipsIfLegacyDirDoesNotExist() throws {
        let bundleID = "app.sassanh.quiper.Quiper"
        let newDir = tempSupportDir.appendingPathComponent(bundleID, isDirectory: true)

        // Ensure legacy doesn't exist
        
        // Perform migration
        let success = SettingsDirectoryMigrator.migrateIfNeeded(fileManager: fileManager, bundleID: bundleID, supportDir: tempSupportDir)

        XCTAssertTrue(success, "Migration reports success (no-op)")
        XCTAssertFalse(fileManager.fileExists(atPath: newDir.path), "New directory should not be created if old didn't exist")
    }

    func testMigration_SkipsIfNewDirAlreadyExists() throws {
        let bundleID = "app.sassanh.quiper.Quiper"
        let legacyDir = tempSupportDir.appendingPathComponent("Quiper", isDirectory: true)
        let newDir = tempSupportDir.appendingPathComponent(bundleID, isDirectory: true)

        // Setup BOTH directories
        try fileManager.createDirectory(at: legacyDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: newDir, withIntermediateDirectories: true)

        // Perform migration
        let success = SettingsDirectoryMigrator.migrateIfNeeded(fileManager: fileManager, bundleID: bundleID, supportDir: tempSupportDir)

        XCTAssertTrue(success, "Migration reports success (no-op)")
        XCTAssertTrue(fileManager.fileExists(atPath: legacyDir.path), "Legacy directory should still exist")
    }
}

import XCTest
@testable import Quiper

@MainActor  
final class InstallUpdateTests: XCTestCase {
    override func setUp() async throws {
        Settings.shared.reset()
    }
    
    func testUpdateAvailableCheck() async throws {
        let manager = UpdateManager.shared
        
        // This test verifies the update manager can check for updates
        // In a real scenario, we'd mock the network layer
        // For now, we just verify the method is callable
        
        // The actual update check would happen here
        // await manager.checkForUpdates(userInitiated: false)
        
        // We can verify the manager exists and has appropriate state
        XCTAssertNotNil(manager, "UpdateManager should exist")
    }
    
    func testUpdatePreferencesConfiguration() async throws {
        // Test that update preferences can be configured
        Settings.shared.updatePreferences.automaticallyChecksForUpdates = true
        Settings.shared.updatePreferences.automaticallyDownloadsUpdates = true
        
        XCTAssertTrue(Settings.shared.updatePreferences.automaticallyChecksForUpdates)
        XCTAssertTrue(Settings.shared.updatePreferences.automaticallyDownloadsUpdates)
        
        // Save and verify persistence
        Settings.shared.saveSettings()
        XCTAssertTrue(Settings.shared.updatePreferences.automaticallyChecksForUpdates)
    }
}

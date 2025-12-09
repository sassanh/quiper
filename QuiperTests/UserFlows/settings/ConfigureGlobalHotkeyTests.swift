import XCTest
import Carbon
@testable import Quiper

@MainActor
final class ConfigureGlobalHotkeyTests: XCTestCase {
    override func setUp() async throws {
        Settings.shared.reset()
    }
    
    override func tearDown() async throws {
        Settings.shared.reset()
    }
    
    func testConfigureGlobalHotkey() async throws {
        // Get initial hotkey configuration
        let initialConfig = Settings.shared.hotkeyConfiguration
        XCTAssertNotNil(initialConfig, "Should have default hotkey config")
        
        // Create new hotkey configuration
        let newConfig = HotkeyManager.Configuration(
            keyCode: UInt32(kVK_ANSI_Q),
            modifierFlags: NSEvent.ModifierFlags.command.union(.option).rawValue
        )
        
        // Update configuration
        Settings.shared.hotkeyConfiguration = newConfig
        
        // Verify new configuration is set
        XCTAssertEqual(Settings.shared.hotkeyConfiguration.keyCode, UInt32(kVK_ANSI_Q))
        XCTAssertEqual(Settings.shared.hotkeyConfiguration.modifierFlags, NSEvent.ModifierFlags.command.union(.option).rawValue)
        
        // Save settings
        Settings.shared.saveSettings()
        
        // Verify persistence
        XCTAssertEqual(Settings.shared.hotkeyConfiguration.keyCode, newConfig.keyCode)
    }
    
    func testResetToDefaultHotkey() async throws {
        // Change hotkey
        let customConfig = HotkeyManager.Configuration(
            keyCode: UInt32(kVK_ANSI_Q),
            modifierFlags: NSEvent.ModifierFlags.command.union(.option).rawValue
        )
        Settings.shared.hotkeyConfiguration = customConfig
        
        // Reset to default
        Settings.shared.hotkeyConfiguration = HotkeyManager.defaultConfiguration
        
        // Verify reset
        XCTAssertEqual(
            Settings.shared.hotkeyConfiguration.keyCode,
            HotkeyManager.defaultConfiguration.keyCode
        )
        XCTAssertEqual(
            Settings.shared.hotkeyConfiguration.modifierFlags,
            HotkeyManager.defaultConfiguration.modifierFlags
        )
    }
}

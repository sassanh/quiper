import XCTest
import Carbon
@testable import Quiper

@MainActor
final class EditActionTests: XCTestCase {
    override func setUp() async throws {
        Settings.shared.reset()
    }
    
    override func tearDown() async throws {
        Settings.shared.reset()
    }
    
    func testEditActionName() async throws {
        // Create an action
        let action = CustomAction(id: UUID(), name: "Original Name", shortcut: nil)
        Settings.shared.customActions = [action]
        
        // Edit the name
        Settings.shared.customActions[0].name = "Updated Name"
        
        // Verify change
        XCTAssertEqual(Settings.shared.customActions[0].name, "Updated Name")
        
        // Save and verify persistence
        Settings.shared.saveSettings()
        XCTAssertEqual(Settings.shared.customActions[0].name, "Updated Name")
    }
    
    func testEditActionShortcut() async throws {
        let originalShortcut = HotkeyManager.Configuration(
            keyCode: UInt32(kVK_ANSI_N),
            modifierFlags: NSEvent.ModifierFlags.command.rawValue
        )
        let action = CustomAction(id: UUID(), name: "Test", shortcut: originalShortcut)
        Settings.shared.customActions = [action]
        
        // Change shortcut
        let newShortcut = HotkeyManager.Configuration(
            keyCode: UInt32(kVK_ANSI_M),
            modifierFlags: NSEvent.ModifierFlags.command.union(.shift).rawValue
        )
        Settings.shared.customActions[0].shortcut = newShortcut
        
        // Verify change
        XCTAssertEqual(Settings.shared.customActions[0].shortcut?.keyCode, UInt32(kVK_ANSI_M))
        XCTAssertEqual(Settings.shared.customActions[0].shortcut?.modifierFlags, NSEvent.ModifierFlags.command.union(.shift).rawValue)
    }
    
    func testEditActionScript() async throws {
        let testService = Service(name: "Test", url: "https://test.com", focus_selector: "")
        Settings.shared.services = [testService]
        
        let action = CustomAction(id: UUID(), name: "Test", shortcut: nil)
        Settings.shared.customActions = [action]
        
        // Save initial script
        let originalScript = "console.log('original');"
        ActionScriptStorage.saveScript(originalScript, serviceID: testService.id, actionID: action.id)
        
        // Update script
        let updatedScript = "console.log('updated');"
        ActionScriptStorage.saveScript(updatedScript, serviceID: testService.id, actionID: action.id)
        
        // Verify update
        let loadedScript = ActionScriptStorage.loadScript(
            serviceID: testService.id,
            actionID: action.id,
            fallback: ""
        )
        XCTAssertEqual(loadedScript, updatedScript)
    }
    
    func testRemoveActionShortcut() async throws {
        let shortcut = HotkeyManager.Configuration(
            keyCode: 0,
            modifierFlags: NSEvent.ModifierFlags.command.rawValue
        )
        let action = CustomAction(id: UUID(), name: "Test", shortcut: shortcut)
        Settings.shared.customActions = [action]
        
        // Remove shortcut
        Settings.shared.customActions[0].shortcut = nil
        
        // Verify removal
        XCTAssertNil(Settings.shared.customActions[0].shortcut)
    }
}

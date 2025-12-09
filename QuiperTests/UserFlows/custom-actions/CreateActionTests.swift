import XCTest
import Carbon
@testable import Quiper

@MainActor
final class CreateActionTests: XCTestCase {
    override func setUp() async throws {
        Settings.shared.reset()
    }
    
    override func tearDown() async throws {
        Settings.shared.reset()
    }
    
    func testCreateCustomAction() async throws {
        // Initially no custom actions
        XCTAssertEqual(Settings.shared.customActions.count, 0)
        
        // Create a new custom action
        let action = CustomAction(
            id: UUID(),
            name: "Test Action",
            shortcut: HotkeyManager.Configuration(
                keyCode: UInt32(kVK_ANSI_N),
                modifierFlags: NSEvent.ModifierFlags.command.rawValue
            )
        )
        
        // Add to settings
        Settings.shared.customActions.append(action)
        
        // Verify action was added
        XCTAssertEqual(Settings.shared.customActions.count, 1)
        XCTAssertEqual(Settings.shared.customActions[0].name, "Test Action")
        XCTAssertNotNil(Settings.shared.customActions[0].shortcut)
        
        // Save settings
        Settings.shared.saveSettings()
        
        // Verify persistence
        XCTAssertEqual(Settings.shared.customActions.count, 1)
    }
    
    func testCreateActionWithScript() async throws {
        let testService = Service(
            name: "TestService",
            url: "https://test.com",
            focus_selector: ""
        )
        Settings.shared.services = [testService]
        
        let action = CustomAction(
            id: UUID(),
            name: "New Chat",
            shortcut: nil
        )
        Settings.shared.customActions.append(action)
        
        // Save a script for this action and service
        let script = "document.querySelector('button').click();"
        ActionScriptStorage.saveScript(script, serviceID: testService.id, actionID: action.id)
        
        // Load the script back
        let loadedScript = ActionScriptStorage.loadScript(
            serviceID: testService.id,
            actionID: action.id,
            fallback: ""
        )
        
        XCTAssertEqual(loadedScript, script, "Script should be saved and loaded correctly")
    }
    
    func testCreateMultipleActions() async throws {
        let action1 = CustomAction(id: UUID(), name: "Action 1", shortcut: nil)
        let action2 = CustomAction(id: UUID(), name: "Action 2", shortcut: nil)
        let action3 = CustomAction(id: UUID(), name: "Action 3", shortcut: nil)
        
        Settings.shared.customActions = [action1, action2, action3]
        
        XCTAssertEqual(Settings.shared.customActions.count, 3)
        XCTAssertEqual(Settings.shared.customActions[0].name, "Action 1")
        XCTAssertEqual(Settings.shared.customActions[1].name, "Action 2")
        XCTAssertEqual(Settings.shared.customActions[2].name, "Action 3")
    }
}

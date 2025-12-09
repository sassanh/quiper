import XCTest
@testable import Quiper

@MainActor
final class DeleteActionTests: XCTestCase {
    override func setUp() async throws {
        Settings.shared.reset()
    }
    
    override func tearDown() async throws {
        Settings.shared.reset()
    }
    
    func testDeleteAction() async throws {
        // Create actions
        let action1 = CustomAction(id: UUID(), name: "Action 1", shortcut: nil)
        let action2 = CustomAction(id: UUID(), name: "Action 2", shortcut: nil)
        let action3 = CustomAction(id: UUID(), name: "Action 3", shortcut: nil)
        
        Settings.shared.customActions = [action1, action2, action3]
        XCTAssertEqual(Settings.shared.customActions.count, 3)
        
        // Delete middle action
        Settings.shared.customActions.remove(at: 1)
        
        // Verify deletion
        XCTAssertEqual(Settings.shared.customActions.count, 2)
        XCTAssertEqual(Settings.shared.customActions[0].name, "Action 1")
        XCTAssertEqual(Settings.shared.customActions[1].name, "Action 3")
        
        // Save and verify persistence
        Settings.shared.saveSettings()
        XCTAssertEqual(Settings.shared.customActions.count, 2)
    }
    
    func testDeleteActionWithScripts() async throws {
        let testService = Service(name: "Test", url: "https://test.com", focus_selector: "")
        Settings.shared.services = [testService]
        
        let action = CustomAction(id: UUID(), name: "Test", shortcut: nil)
        Settings.shared.customActions = [action]
        
        // Save script for this action
        let script = "console.log('test');"
        ActionScriptStorage.saveScript(script, serviceID: testService.id, actionID: action.id)
        
        // Verify script exists
        let loadedScript = ActionScriptStorage.loadScript(
            serviceID: testService.id,
            actionID: action.id,
            fallback: "NOT_FOUND"
        )
        XCTAssertNotEqual(loadedScript, "NOT_FOUND")
        
        // Delete the action
        Settings.shared.customActions.removeAll()
        
        // Delete associated scripts
        ActionScriptStorage.deleteScript(serviceID: testService.id, actionID: action.id)
        
        // Verify action deleted
        XCTAssertEqual(Settings.shared.customActions.count, 0)
        
        // Verify script deleted
        let deletedScript = ActionScriptStorage.loadScript(
            serviceID: testService.id,
            actionID: action.id,
            fallback: "NOT_FOUND"
        )
        XCTAssertEqual(deletedScript, "NOT_FOUND")
    }
    
    func testDeleteAllActions() async throws {
        // Create multiple actions
        let actions = (1...5).map { CustomAction(id: UUID(), name: "Action \($0)", shortcut: nil) }
        Settings.shared.customActions = actions
        
        XCTAssertEqual(Settings.shared.customActions.count, 5)
        
        // Delete all
        Settings.shared.customActions.removeAll()
        
        // Verify all deleted
        XCTAssertEqual(Settings.shared.customActions.count, 0)
        
        Settings.shared.saveSettings()
        XCTAssertEqual(Settings.shared.customActions.count, 0)
    }
}

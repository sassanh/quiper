import XCTest
import Carbon
@testable import Quiper

@MainActor
final class CustomActionTests: XCTestCase {
    func testCustomActionInitialization() {
        let action = CustomAction(name: "Test Action")
        
        XCTAssertFalse(action.name.isEmpty)
        XCTAssertNotNil(action.id)
        XCTAssertNil(action.shortcut)
    }
    
    func testCustomActionWithShortcut() {
        let shortcut = HotkeyManager.Configuration(
            keyCode: UInt32(kVK_ANSI_A),
            modifierFlags: NSEvent.ModifierFlags.command.rawValue
        )
        let action = CustomAction(name: "Test", shortcut: shortcut)
        
        XCTAssertNotNil(action.shortcut)
        XCTAssertEqual(action.shortcut?.keyCode, UInt32(kVK_ANSI_A))
    }
    
    func testDisplayShortcutWhenNotAssigned() {
        let action = CustomAction(name: "Test")
        XCTAssertEqual(action.displayShortcut, "Not assigned")
    }
    
    func testDisplayShortcutWhenAssigned() {
        let shortcut = HotkeyManager.Configuration(
            keyCode: UInt32(kVK_ANSI_B),
            modifierFlags: NSEvent.ModifierFlags.command.rawValue
        )
        let action = CustomAction(name: "Test", shortcut: shortcut)
        
        // Should format the shortcut
        XCTAssertNotEqual(action.displayShortcut, "Not assigned")
        XCTAssertTrue(action.displayShortcut.contains("⌘"))
    }
    
    func testCustomActionEquality() {
        let id = UUID()
        let action1 = CustomAction(id: id, name: "Test")
        let action2 = CustomAction(id: id, name: "Test")
        
        XCTAssertEqual(action1, action2)
    }
    
    func testCustomActionInequality() {
        let action1 = CustomAction(name: "Test1")
        let action2 = CustomAction(name: "Test2")
        
        XCTAssertNotEqual(action1, action2)
    }
    
    func testCustomActionCodable() throws {
        let shortcut = HotkeyManager.Configuration(
            keyCode: UInt32(kVK_ANSI_C),
            modifierFlags: NSEvent.ModifierFlags([.command, .shift]).rawValue
        )
        let original = CustomAction(name: "Codable Test", shortcut: shortcut)
        
        // Encode
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        // Decode
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(CustomAction.self, from: data)
        
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.shortcut?.keyCode, original.shortcut?.keyCode)
        XCTAssertEqual(decoded.shortcut?.modifierFlags, original.shortcut?.modifierFlags)
    }
}

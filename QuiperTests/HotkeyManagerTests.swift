import XCTest
import Carbon
@testable import Quiper

@MainActor
final class HotkeyManagerTests: XCTestCase {
    func testConfigurationEquality() {
        let config1 = HotkeyManager.Configuration(keyCode: 1, modifierFlags: 2)
        let config2 = HotkeyManager.Configuration(keyCode: 1, modifierFlags: 2)
        let config3 = HotkeyManager.Configuration(keyCode: 2, modifierFlags: 2)
        
        XCTAssertEqual(config1, config2)
        XCTAssertNotEqual(config1, config3)
    }
    
    func testConfigurationCodable() throws {
        let original = HotkeyManager.Configuration(
            keyCode: UInt32(kVK_Space),
            modifierFlags: NSEvent.ModifierFlags.command.rawValue
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(HotkeyManager.Configuration.self, from: data)
        
        XCTAssertEqual(decoded.keyCode, original.keyCode)
        XCTAssertEqual(decoded.modifierFlags, original.modifierFlags)
    }
    
    func testCocoaFlagsMapping() {
        let flags = NSEvent.ModifierFlags([.command, .shift])
        let config = HotkeyManager.Configuration(
            keyCode: 0,
            modifierFlags: flags.rawValue
        )
        
        XCTAssertTrue(config.cocoaFlags.contains(.command))
        XCTAssertTrue(config.cocoaFlags.contains(.shift))
        XCTAssertFalse(config.cocoaFlags.contains(.option))
    }
    
    func testDefaultConfiguration() {
        let config = HotkeyManager.defaultConfiguration
        XCTAssertEqual(config.keyCode, UInt32(kVK_Space))
        XCTAssertTrue(config.cocoaFlags.contains(.option))
    }
}

@MainActor
final class EngineHotkeyManagerTests: XCTestCase {
    func testEntryEquality() {
        let id = UUID()
        let config = HotkeyManager.Configuration(keyCode: 1, modifierFlags: 0)
        
        let entry1 = EngineHotkeyManager.Entry(serviceID: id, configuration: config)
        let entry2 = EngineHotkeyManager.Entry(serviceID: id, configuration: config)
        let entry3 = EngineHotkeyManager.Entry(serviceID: UUID(), configuration: config)
        
        XCTAssertEqual(entry1, entry2)
        XCTAssertNotEqual(entry1, entry3)
    }
}

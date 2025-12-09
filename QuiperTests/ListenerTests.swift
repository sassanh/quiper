import Testing
import AppKit
import Carbon
@testable import Quiper

@MainActor
struct ListenerTests {
    
    @Test func hotkeyManagerConfiguration_CocoaFlags() {
        let config = HotkeyManager.Configuration(keyCode: 0, modifierFlags: NSEvent.ModifierFlags.command.rawValue)
        #expect(config.cocoaFlags == .command)
    }
    
    @Test func hotkeyManagerConfiguration_DefaultConfiguration() {
        let config = HotkeyManager.defaultConfiguration
        #expect(config.keyCode == UInt32(kVK_Space))
        #expect(config.modifierFlags == NSEvent.ModifierFlags.option.rawValue)
    }
    
    @Test func hotkeyManagerConfiguration_Codable() throws {
        let config = HotkeyManager.Configuration(keyCode: 123, modifierFlags: 456)
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(HotkeyManager.Configuration.self, from: data)
        
        #expect(decoded == config)
    }
}

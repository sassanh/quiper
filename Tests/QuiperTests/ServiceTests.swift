import XCTest
import Carbon
@testable import Quiper

final class ServiceTests: XCTestCase {
    func testServiceInitialization() {
        let service = Service(
            name: "Test Service",
            url: "https://example.com",
            focus_selector: "input"
        )
        
        XCTAssertFalse(service.name.isEmpty)
        XCTAssertFalse(service.url.isEmpty)
        XCTAssertNotNil(service.id)
        XCTAssertTrue(service.actionScripts.isEmpty)
        XCTAssertNil(service.activationShortcut)
    }
    
    func testServiceWithActionScripts() {
        let actionID = UUID()
        let scripts = [actionID: "console.log('test')"]
        let service = Service(
            name: "Test",
            url: "https://example.com",
            focus_selector: "input",
            actionScripts: scripts
        )
        
        XCTAssertEqual(service.actionScripts.count, 1)
        XCTAssertEqual(service.actionScripts[actionID], "console.log('test')")
    }
    
    func testServiceWithActivationShortcut() {
        let shortcut = HotkeyManager.Configuration(
            keyCode: UInt32(kVK_ANSI_1),
            modifierFlags: NSEvent.ModifierFlags.command.rawValue
        )
        let service = Service(
            name: "Test",
            url: "https://example.com",
            focus_selector: "input",
            activationShortcut: shortcut
        )
        
        XCTAssertNotNil(service.activationShortcut)
        XCTAssertEqual(service.activationShortcut?.keyCode, UInt32(kVK_ANSI_1))
    }
    
    func testServiceEquality() {
        let id = UUID()
        let service1 = Service(id: id, name: "Test", url: "https://example.com", focus_selector: "input")
        let service2 = Service(id: id, name: "Test", url: "https://example.com", focus_selector: "input")
        
        XCTAssertEqual(service1, service2)
    }
    
    func testServiceCodable() throws {
        let actionID = UUID()
        let shortcut = HotkeyManager.Configuration(
            keyCode: UInt32(kVK_F1),
            modifierFlags: 0
        )
        let original = Service(
            name: "Codable Test",
            url: "https://test.com",
            focus_selector: "#input",
            actionScripts: [actionID: "alert('hi')"],
            activationShortcut: shortcut
        )
        
        // Encode
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        // Decode
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Service.self, from: data)
        
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.url, original.url)
        XCTAssertEqual(decoded.focus_selector, original.focus_selector)
        XCTAssertEqual(decoded.actionScripts.count, 1)
        XCTAssertEqual(decoded.activationShortcut?.keyCode, shortcut.keyCode)
    }
    
    func testServiceDecodesWithMissingOptionalFields() throws {
        // Test backward compatibility - old JSON without new fields
        let json = """
        {
            "name": "Old Service",
            "url": "https://old.com",
            "focus_selector": "input"
        }
        """
        
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let service = try decoder.decode(Service.self, from: data)
        
        XCTAssertEqual(service.name, "Old Service")
        XCTAssertNotNil(service.id) // Should generate new ID
        XCTAssertTrue(service.actionScripts.isEmpty)
        XCTAssertNil(service.activationShortcut)
    }
}

final class UpdatePreferencesTests: XCTestCase {
    func testDefaultValues() {
        let prefs = UpdatePreferences()
        
        XCTAssertTrue(prefs.automaticallyChecksForUpdates)
        XCTAssertFalse(prefs.automaticallyDownloadsUpdates)
        XCTAssertNil(prefs.lastAutomaticCheck)
        XCTAssertNil(prefs.lastNotifiedVersion)
    }
    
    func testUpdatePreferencesEquality() {
        let prefs1 = UpdatePreferences(
            automaticallyChecksForUpdates: true,
            automaticallyDownloadsUpdates: false
        )
        let prefs2 = UpdatePreferences(
            automaticallyChecksForUpdates: true,
            automaticallyDownloadsUpdates: false
        )
        
        XCTAssertEqual(prefs1, prefs2)
    }
    
    func testUpdatePreferencesCodable() throws {
        let original = UpdatePreferences(
            automaticallyChecksForUpdates: false,
            automaticallyDownloadsUpdates: true,
            lastAutomaticCheck: Date(),
            lastNotifiedVersion: "1.2.3"
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(UpdatePreferences.self, from: data)
        
        XCTAssertEqual(decoded.automaticallyChecksForUpdates, original.automaticallyChecksForUpdates)
        XCTAssertEqual(decoded.automaticallyDownloadsUpdates, original.automaticallyDownloadsUpdates)
        XCTAssertEqual(decoded.lastNotifiedVersion, original.lastNotifiedVersion)
    }
}

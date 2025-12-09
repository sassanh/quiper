import Testing
import Foundation
import AppKit
import Carbon
@testable import Quiper

struct SettingsServiceTests {
    
    @Test func service_Codable() throws {
        let service = Service(id: UUID(), name: "Test Service", url: "https://example.com", focus_selector: "#input")
        let data = try JSONEncoder().encode(service)
        let decoded = try JSONDecoder().decode(Service.self, from: data)
        
        #expect(decoded == service)
    }
    
    @Test func updatePreferences_Codable() throws {
        let prefs = UpdatePreferences(automaticallyChecksForUpdates: true, automaticallyDownloadsUpdates: false)
        let data = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(UpdatePreferences.self, from: data)
        
        #expect(decoded == prefs)
    }
}

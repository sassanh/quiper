import Testing
import Foundation
import AppKit
import Carbon
@testable import Quiper

@MainActor
struct SettingsServiceTests {
    
    @Test func service_Codable() throws {
        let service = Service(id: UUID(), name: "Test Service", url: "https://example.com", focus_selector: "#input")
        let data = try JSONEncoder().encode(service)
        let decoded = try JSONDecoder().decode(Service.self, from: data)
        
        #expect(decoded.id == service.id)
        #expect(decoded.name == service.name)
        #expect(decoded.url == service.url)
        #expect(decoded.focus_selector == service.focus_selector)
    }
    
    @Test func updatePreferences_Codable() throws {
        let prefs = UpdatePreferences(automaticallyChecksForUpdates: true, automaticallyDownloadsUpdates: false)
        let data = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(UpdatePreferences.self, from: data)
        
        #expect(decoded.automaticallyChecksForUpdates == prefs.automaticallyChecksForUpdates)
        #expect(decoded.automaticallyDownloadsUpdates == prefs.automaticallyDownloadsUpdates)
    }
}

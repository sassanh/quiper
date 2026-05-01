import Testing
import Foundation
@testable import Quiper

@MainActor
struct UpdateSettingsTests {
    
    @Test func updatePreferences_DefaultValue() {
        let prefs = UpdatePreferences()
        #expect(prefs.channel == .stable)
        #expect(prefs.automaticallyChecksForUpdates == true)
        #expect(prefs.automaticallyDownloadsUpdates == false)
    }
    
    @Test func settings_ResetIncludesUpdateNightly() {
        let settings = Settings.shared
        settings.updatePreferences.channel = .nightly
        settings.reset()
        #expect(settings.updatePreferences.channel == .stable)
    }
    
    @Test func updatePreferences_Codable() throws {
        var prefs = UpdatePreferences()
        prefs.channel = .nightly
        
        let encoded = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(UpdatePreferences.self, from: encoded)
        
        #expect(decoded.channel == .nightly)
    }
    
    @Test func gitHubRelease_Sorting() throws {
        let now = Date()
        let older = now.addingTimeInterval(-3600)
        let newest = now.addingTimeInterval(3600)
        
        let releases = [
            GitHubRelease(tagName: "v1.0", prerelease: false, publishedAt: older, body: nil, htmlUrl: URL(string: "https://a.com")!, assets: []),
            GitHubRelease(tagName: "v2.0-nightly", prerelease: true, publishedAt: newest, body: nil, htmlUrl: URL(string: "https://b.com")!, assets: []),
            GitHubRelease(tagName: "v1.5", prerelease: false, publishedAt: now, body: nil, htmlUrl: URL(string: "https://c.com")!, assets: [])
        ]
        
        let sorted = releases.sorted(by: { $0.publishedAt > $1.publishedAt })
        #expect(sorted.first?.tagName == "v2.0-nightly")
        #expect(sorted[1].tagName == "v1.5")
    }
}

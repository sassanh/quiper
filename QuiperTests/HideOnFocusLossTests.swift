import Testing
import Foundation
@testable import Quiper

@Suite(.serialized)
@MainActor
struct HideOnFocusLossTests {
    @Test func hideOnFocusLoss_DefaultsToOff() {
        Settings.shared.wipeAllData()
        _ = Settings.shared.loadSettings()
        defer { Settings.shared.wipeAllData() }

        #expect(Settings.shared.hideOnFocusLoss == false)
        #expect(Settings.shared.makePersistedSettings().hideOnFocusLoss == false)
    }

    @Test func hideOnFocusLoss_MissingKeyDecodesToOff() throws {
        Settings.shared.wipeAllData()
        _ = Settings.shared.loadSettings()
        defer { Settings.shared.wipeAllData() }

        let legacyData = Data(
            """
            {
              "services": [],
              "quiperVersion": "6.1.1",
              "version": 1
            }
            """.utf8
        )
        let decoded = try JSONDecoder().decode(PersistedSettings.self, from: legacyData)
        #expect(decoded.hideOnFocusLoss == nil)

        Settings.shared.applyPersistedSettings(decoded)
        #expect(Settings.shared.hideOnFocusLoss == false)

        // Re-reading legacy output stays stable and keeps the current behavior.
        let reread = try JSONDecoder().decode(PersistedSettings.self, from: legacyData)
        Settings.shared.applyPersistedSettings(reread)
        #expect(Settings.shared.hideOnFocusLoss == false)

        // Current schema always encodes the key once known.
        let encoded = try JSONEncoder().encode(Settings.shared.makePersistedSettings())
        let object = try JSONSerialization.jsonObject(with: encoded)
        #expect((object as? [String: Any])?["hideOnFocusLoss"] as? Bool == false)
    }

    @Test func hideOnFocusLoss_RoundTrips() throws {
        Settings.shared.wipeAllData()
        _ = Settings.shared.loadSettings()
        defer { Settings.shared.wipeAllData() }

        Settings.shared.hideOnFocusLoss = true
        var data = try JSONEncoder().encode(Settings.shared.makePersistedSettings())
        var decoded = try JSONDecoder().decode(PersistedSettings.self, from: data)
        #expect(decoded.hideOnFocusLoss == true)

        Settings.shared.hideOnFocusLoss = false
        data = try JSONEncoder().encode(Settings.shared.makePersistedSettings())
        decoded = try JSONDecoder().decode(PersistedSettings.self, from: data)
        #expect(decoded.hideOnFocusLoss == false)
    }

    @Test func hideOnFocusLoss_ResetRestoresDefault() {
        Settings.shared.wipeAllData()
        _ = Settings.shared.loadSettings()
        defer { Settings.shared.wipeAllData() }

        Settings.shared.hideOnFocusLoss = true
        Settings.shared.reset()
        #expect(Settings.shared.hideOnFocusLoss == false)
    }

    @Test func keepOverlayOnTop_FalseSurvivesDiskReload() throws {
        let settings = Settings.shared
        settings.wipeAllData()
        _ = settings.loadSettings()
        defer { settings.wipeAllData() }

        settings.keepOverlayOnTop = false
        settings.saveSettings()
        let saved = try Data(contentsOf: SettingsPersistence.settingsFile)
        settings.keepOverlayOnTop = true
        try saved.write(to: SettingsPersistence.settingsFile, options: .atomic)

        _ = settings.loadSettings()
        #expect(settings.keepOverlayOnTop == false)
    }

    @Test(arguments: [false, true])
    func keepOverlayOnTop_LegacyMissingOrNullRestoresTopmost(explicitNull: Bool) throws {
        let settings = Settings.shared
        settings.wipeAllData()
        _ = settings.loadSettings()
        defer { settings.wipeAllData() }

        let legacyData = Data("""
        {"services": [], "quiperVersion": "6.2.0", "version": 1\(explicitNull ? ", \"keepOverlayOnTop\": null" : "")}
        """.utf8)
        settings.keepOverlayOnTop = false
        try legacyData.write(to: SettingsPersistence.settingsFile, options: .atomic)
        _ = settings.loadSettings()
        #expect(settings.keepOverlayOnTop == true)

        settings.keepOverlayOnTop = false
        try ConfigPortManager.importConfig(from: legacyData)
        #expect(settings.keepOverlayOnTop == true)
    }

    @Test func keepOverlayOnTop_ResetRestoresTopmostAfterOptOut() {
        let settings = Settings.shared
        settings.wipeAllData()
        _ = settings.loadSettings()
        defer { settings.wipeAllData() }

        settings.keepOverlayOnTop = false
        settings.reset()
        #expect(settings.keepOverlayOnTop == true)
        settings.saveSettings()
        _ = settings.loadSettings()
        #expect(settings.keepOverlayOnTop == true)
    }
}

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
}

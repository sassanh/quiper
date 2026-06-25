import Testing
import Foundation
import AppKit
@testable import Quiper

@Suite(.serialized)
@MainActor
struct TabSurvivalTests {

    init() {
        Settings.shared.wipeAllData()
        _ = Settings.shared.loadSettings()
    }

    @Test func tabSurvivalPolicy_AllCases() {
        #expect(TabSurvivalPolicy.allCases.count == 3)
        #expect(TabSurvivalPolicy.always.rawValue == "Always Restore")
        #expect(TabSurvivalPolicy.askOnExit.rawValue == "Ask on Exit")
        #expect(TabSurvivalPolicy.never.rawValue == "Never Restore")
    }

    @Test func tabSurvivalPolicy_Codable() throws {
        for policy in TabSurvivalPolicy.allCases {
            let data = try JSONEncoder().encode(policy)
            let decoded = try JSONDecoder().decode(TabSurvivalPolicy.self, from: data)
            #expect(decoded == policy)
        }
    }

    @Test func persistedTabState_Codable() throws {
        var state = PersistedTabState()
        state.activeServiceURL = "https://gemini.google.com"
        state.activeIndicesByURL = ["https://gemini.google.com": 2]
        state.openTabs = ["https://gemini.google.com": [0: "https://gemini.google.com/app", 2: "https://gemini.google.com/chat"]]

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(PersistedTabState.self, from: data)

        #expect(decoded.activeServiceURL == "https://gemini.google.com")
        #expect(decoded.activeIndicesByURL["https://gemini.google.com"] == 2)
        #expect(decoded.openTabs["https://gemini.google.com"]?[0] == "https://gemini.google.com/app")
        #expect(decoded.openTabs["https://gemini.google.com"]?[2] == "https://gemini.google.com/chat")
    }

    @Test func persistedTabState_Codable_WithInputs() throws {
        let inputState = TabInputState(text: "Hello World", isContentEditable: true, start: 5, end: 11)
        var state = PersistedTabState()
        state.activeServiceURL = "https://gemini.google.com"
        state.activeIndicesByURL = ["https://gemini.google.com": 2]
        state.openTabs = ["https://gemini.google.com": [2: "https://gemini.google.com/chat"]]
        state.tabInputs = ["https://gemini.google.com": [2: inputState]]

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(PersistedTabState.self, from: data)

        #expect(decoded.activeServiceURL == "https://gemini.google.com")
        #expect(decoded.activeIndicesByURL["https://gemini.google.com"] == 2)
        #expect(decoded.openTabs["https://gemini.google.com"]?[2] == "https://gemini.google.com/chat")
        #expect(decoded.tabInputs["https://gemini.google.com"]?[2] == inputState)
    }

    @Test func persistedTabState_BackwardCompatibility() throws {
        // Raw JSON without tabInputs
        let jsonStr = """
        {
            "activeServiceURL": "https://gemini.google.com",
            "activeIndicesByURL": {"https://gemini.google.com": 2},
            "openTabs": {"https://gemini.google.com": {"2": "https://gemini.google.com/chat"}}
        }
        """
        guard let data = jsonStr.data(using: .utf8) else { return }
        let decoded = try JSONDecoder().decode(PersistedTabState.self, from: data)

        #expect(decoded.activeServiceURL == "https://gemini.google.com")
        #expect(decoded.activeIndicesByURL["https://gemini.google.com"] == 2)
        #expect(decoded.openTabs["https://gemini.google.com"]?[2] == "https://gemini.google.com/chat")
        #expect(decoded.tabInputs.isEmpty)
        #expect(decoded.tabPromptHistories.isEmpty)
        #expect(decoded.tabPromptHistoryEnabledOverrides.isEmpty)
    }

    @Test func persistedTabState_Codable_WithPromptHistories() throws {
        let entry1 = PromptHistoryEntry(text: "Prompt 1", timestamp: Date(timeIntervalSince1970: 1000))
        let entry2 = PromptHistoryEntry(text: "Prompt 2", timestamp: Date(timeIntervalSince1970: 2000))
        var state = PersistedTabState()
        state.activeServiceURL = "https://gemini.google.com"
        state.openTabs = ["https://gemini.google.com": [2: "https://gemini.google.com/chat"]]
        state.tabPromptHistories = ["https://gemini.google.com": [2: [entry1, entry2]]]
        state.tabPromptHistoryEnabledOverrides = ["https://gemini.google.com": [2: false]]

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(PersistedTabState.self, from: data)

        #expect(decoded.tabPromptHistories["https://gemini.google.com"]?[2]?.count == 2)
        #expect(decoded.tabPromptHistories["https://gemini.google.com"]?[2]?[0].text == "Prompt 1")
        #expect(decoded.tabPromptHistories["https://gemini.google.com"]?[2]?[1].text == "Prompt 2")
        #expect(decoded.tabPromptHistoryEnabledOverrides["https://gemini.google.com"]?[2] == false)
    }

    @Test func promptHistoryLimit_DefaultPersistenceAndClamping() throws {
        let settings = Settings.shared
        _ = settings.loadSettings()
        #expect(settings.promptHistoryLimit == Settings.defaultPromptHistoryLimit)

        settings.promptHistoryLimit = 24
        let persisted = settings.makePersistedSettings()
        let data = try JSONEncoder().encode(persisted)
        let decoded = try JSONDecoder().decode(PersistedSettings.self, from: data)
        #expect(decoded.promptHistoryLimit == 24)

        settings.promptHistoryLimit = 99
        #expect(settings.promptHistoryLimit == Settings.promptHistoryLimitRange.upperBound)

        settings.promptHistoryLimit = 0
        #expect(settings.promptHistoryLimit == Settings.promptHistoryLimitRange.lowerBound)
    }

    @Test func settings_TabSurvivalPolicyPersistence() throws {
        let settings = Settings.shared
        _ = settings.loadSettings() // Ensure settings are loaded/initialized first
        let originalPolicy = settings.tabSurvivalPolicy
        let originalState = settings.persistedTabState

        defer {
            settings.tabSurvivalPolicy = originalPolicy
            settings.persistedTabState = originalState
            settings.saveSettings()
        }

        // Change settings
        settings.tabSurvivalPolicy = .askOnExit
        var state = PersistedTabState()
        state.activeServiceURL = "https://custom.engine"
        state.activeIndicesByURL = ["https://custom.engine": 5]
        state.openTabs = ["https://custom.engine": [5: "https://custom.engine/sub"]]
        settings.persistedTabState = state

        settings.saveSettings()

        // Re-read from disk (simulate app restart)
        // Make a fresh settings instance by calling reset then re-applying from disk load
        settings.reset()
        #expect(settings.tabSurvivalPolicy == .always)
        #expect(settings.persistedTabState == nil)

        // Trigger load Settings
        let persisted = settings.loadSettings()
        #expect(!persisted.isEmpty) // Should have default engines

        // Verify values are reloaded
        #expect(settings.tabSurvivalPolicy == .askOnExit)
        #expect(settings.persistedTabState?.activeServiceURL == "https://custom.engine")
        #expect(settings.persistedTabState?.activeIndicesByURL["https://custom.engine"] == 5)
        #expect(settings.persistedTabState?.openTabs["https://custom.engine"]?[5] == "https://custom.engine/sub")
    }

    @Test func settings_DiscardSavedTabs() throws {
        let settings = Settings.shared
        let originalState = settings.persistedTabState

        defer {
            settings.persistedTabState = originalState
            settings.saveSettings()
        }

        var state = PersistedTabState()
        state.activeServiceURL = "https://custom.engine"
        settings.persistedTabState = state
        settings.saveSettings()

        #expect(settings.persistedTabState != nil)

        settings.discardSavedTabs()

        #expect(settings.persistedTabState == nil)

        // Check it was saved to disk as nil
        settings.reset()
        _ = settings.loadSettings()
        #expect(settings.persistedTabState == nil)
    }
}

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
        let serviceID = UUID()
        var state = PersistedTabState()
        state.activeServiceID = serviceID
        state.activeIndicesByID = [serviceID: 2]
        state.openTabs = [serviceID: [0: "https://gemini.google.com/app", 2: "https://gemini.google.com/chat"]]
        state.tabTitles = [serviceID: [0: "Gemini", 2: "Restored chat"]]

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(PersistedTabState.self, from: data)

        #expect(decoded.activeServiceID == serviceID)
        #expect(decoded.activeIndicesByID[serviceID] == 2)
        #expect(decoded.openTabs[serviceID]?[0] == "https://gemini.google.com/app")
        #expect(decoded.openTabs[serviceID]?[2] == "https://gemini.google.com/chat")
        #expect(decoded.tabTitles[serviceID]?[0] == "Gemini")
        #expect(decoded.tabTitles[serviceID]?[2] == "Restored chat")
    }

    @Test func persistedTabState_Codable_WithInputs() throws {
        let serviceID = UUID()
        let inputState = TabInputState(text: "Hello World", isContentEditable: true, start: 5, end: 11)
        var state = PersistedTabState()
        state.activeServiceID = serviceID
        state.activeIndicesByID = [serviceID: 2]
        state.openTabs = [serviceID: [2: "https://gemini.google.com/chat"]]
        state.tabInputs = [serviceID: [2: inputState]]

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(PersistedTabState.self, from: data)

        #expect(decoded.activeServiceID == serviceID)
        #expect(decoded.activeIndicesByID[serviceID] == 2)
        #expect(decoded.openTabs[serviceID]?[2] == "https://gemini.google.com/chat")
        #expect(decoded.tabInputs[serviceID]?[2] == inputState)
    }

    @Test func persistedSettings_LegacyServiceIdentifiersMigrateLosslessly() throws {
        let serviceID = try #require(UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        let jsonStr = """
        {
            "services": [{
                "id": "\(serviceID.uuidString)",
                "name": "Gemini",
                "url": "https://gemini.google.com",
                "focus_selector": "textarea"
            }],
            "serviceZoomLevels": {
                "https://gemini.google.com": 1.25
            },
            "persistedTabState": {
                "activeServiceURL": "https://gemini.google.com",
                "activeIndicesByURL": {"https://gemini.google.com": 2},
                "openTabs": {
                    "https://gemini.google.com": {
                        "2": "https://gemini.google.com/chat"
                    }
                },
                "tabTitles": {
                    "https://gemini.google.com": {
                        "2": "Restored chat"
                    }
                },
                "tabInputs": {
                    "https://gemini.google.com": {
                        "2": {
                            "text": "Draft",
                            "isContentEditable": false,
                            "start": 5,
                            "end": 5
                        }
                    }
                },
                "tabPromptHistoryEnabledOverrides": {
                    "https://gemini.google.com": {
                        "2": false
                    }
                },
                "tabHistory": [{
                    "serviceURL": "https://gemini.google.com",
                    "sessionIndex": 2
                }]
            }
        }
        """
        let legacyData = try #require(jsonStr.data(using: .utf8))
        let migrated = try JSONDecoder().decode(PersistedSettings.self, from: legacyData)
        let tabState = try #require(migrated.persistedTabState)

        #expect(migrated.didDecodeLegacyServiceIdentifiers)
        #expect(migrated.serviceZoomLevels?[serviceID] == 1.25)
        #expect(tabState.activeServiceID == serviceID)
        #expect(tabState.activeIndicesByID[serviceID] == 2)
        #expect(tabState.openTabs[serviceID]?[2] == "https://gemini.google.com/chat")
        #expect(tabState.tabTitles[serviceID]?[2] == "Restored chat")
        #expect(tabState.tabInputs[serviceID]?[2]?.text == "Draft")
        #expect(tabState.tabPromptHistoryEnabledOverrides[serviceID]?[2] == false)
        #expect(tabState.tabHistory == [TabIdentifier(serviceID: serviceID, sessionIndex: 2)])

        let migratedData = try JSONEncoder().encode(migrated)
        let migratedObject = try #require(
            JSONSerialization.jsonObject(with: migratedData) as? [String: Any]
        )
        let migratedTabState = try #require(
            migratedObject["persistedTabState"] as? [String: Any]
        )
        #expect(migratedTabState["activeServiceURL"] == nil)
        #expect(migratedTabState["activeIndicesByURL"] == nil)
        #expect(migratedTabState["activeServiceID"] as? String == serviceID.uuidString)
        #expect(migratedObject["serviceZoomLevels"] is [Any])

        let repeatedRead = try JSONDecoder().decode(PersistedSettings.self, from: migratedData)
        #expect(!repeatedRead.didDecodeLegacyServiceIdentifiers)
        #expect(repeatedRead.serviceZoomLevels?[serviceID] == 1.25)
        #expect(repeatedRead.persistedTabState?.activeServiceID == serviceID)
        #expect(repeatedRead.persistedTabState?.openTabs[serviceID]?[2] == "https://gemini.google.com/chat")
    }

    @Test func persistedSettings_MixedServiceIdentifiersPreferCurrentAndRequestRewrite() throws {
        let currentServiceID = try #require(UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        let legacyServiceID = try #require(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"))
        let jsonStr = """
        {
            "services": [
                {
                    "id": "\(currentServiceID.uuidString)",
                    "name": "Current",
                    "url": "https://current.example",
                    "focus_selector": "textarea"
                },
                {
                    "id": "\(legacyServiceID.uuidString)",
                    "name": "Legacy",
                    "url": "https://legacy.example",
                    "focus_selector": "textarea"
                }
            ],
            "persistedTabState": {
                "activeServiceID": "\(currentServiceID.uuidString)",
                "activeServiceURL": "https://legacy.example"
            }
        }
        """
        let mixedData = try #require(jsonStr.data(using: .utf8))
        let decoded = try JSONDecoder().decode(PersistedSettings.self, from: mixedData)

        #expect(decoded.persistedTabState?.activeServiceID == currentServiceID)
        #expect(decoded.didDecodeLegacyServiceIdentifiers)

        let migratedData = try JSONEncoder().encode(decoded)
        let migratedObject = try #require(
            JSONSerialization.jsonObject(with: migratedData) as? [String: Any]
        )
        let migratedTabState = try #require(
            migratedObject["persistedTabState"] as? [String: Any]
        )
        #expect(migratedTabState["activeServiceURL"] == nil)
    }

    @Test func secureTabState_TitlePersistenceAndBackwardCompatibility() throws {
        let state = MainWindowController.SecureTabState(
            activeIndex: 2,
            openTabs: [2: "https://secure.example/chat"],
            tabTitles: [2: "Secure chat"],
            tabInputs: nil,
            tabPromptHistories: nil,
            tabPromptHistoryEnabledOverrides: nil
        )
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(MainWindowController.SecureTabState.self, from: data)

        #expect(decoded.tabTitles?[2] == "Secure chat")

        let legacyData = try #require(
            """
            {
                "activeIndex": 2,
                "openTabs": {"2": "https://secure.example/chat"}
            }
            """.data(using: .utf8)
        )
        let legacyState = try JSONDecoder().decode(MainWindowController.SecureTabState.self, from: legacyData)

        #expect(legacyState.tabTitles == nil)
    }

    @Test func persistedTabState_Codable_WithPromptHistories() throws {
        let serviceID = UUID()
        let entry1 = PromptHistoryEntry(text: "Prompt 1", timestamp: Date(timeIntervalSince1970: 1000))
        let entry2 = PromptHistoryEntry(text: "Prompt 2", timestamp: Date(timeIntervalSince1970: 2000))
        var state = PersistedTabState()
        state.activeServiceID = serviceID
        state.openTabs = [serviceID: [2: "https://gemini.google.com/chat"]]
        state.tabPromptHistories = [serviceID: [2: [entry1, entry2]]]
        state.tabPromptHistoryEnabledOverrides = [serviceID: [2: false]]

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(PersistedTabState.self, from: data)

        #expect(decoded.tabPromptHistories[serviceID]?[2]?.count == 2)
        #expect(decoded.tabPromptHistories[serviceID]?[2]?[0].text == "Prompt 1")
        #expect(decoded.tabPromptHistories[serviceID]?[2]?[1].text == "Prompt 2")
        #expect(decoded.tabPromptHistoryEnabledOverrides[serviceID]?[2] == false)
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
        let serviceID = try #require(settings.services.first?.id)
        var state = PersistedTabState()
        state.activeServiceID = serviceID
        state.activeIndicesByID = [serviceID: 5]
        state.openTabs = [serviceID: [5: "https://custom.engine/sub"]]
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
        #expect(settings.persistedTabState?.activeServiceID == serviceID)
        #expect(settings.persistedTabState?.activeIndicesByID[serviceID] == 5)
        #expect(settings.persistedTabState?.openTabs[serviceID]?[5] == "https://custom.engine/sub")
    }

    @Test func settings_DiscardSavedTabs() throws {
        let settings = Settings.shared
        let originalState = settings.persistedTabState

        defer {
            settings.persistedTabState = originalState
            settings.saveSettings()
        }

        var state = PersistedTabState()
        state.activeServiceID = UUID()
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

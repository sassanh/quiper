import Testing
import Foundation
import AppKit
import Carbon
@testable import Quiper

@Suite(.serialized)
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

    @Test func persistedSettings_WritesQuiperVersion() throws {
        Settings.shared.wipeAllData()
        _ = Settings.shared.loadSettings()

        let persisted = Settings.shared.makePersistedSettings()
        let data = try JSONEncoder().encode(persisted)
        let decoded = try JSONDecoder().decode(PersistedSettings.self, from: data)

        #expect(decoded.quiperVersion == Bundle.main.versionDisplayString)
    }

    @Test func focusLossEffect_DefaultsToEnabledAndRoundTrips() throws {
        Settings.shared.wipeAllData()
        _ = Settings.shared.loadSettings()
        defer { Settings.shared.wipeAllData() }

        #expect(Settings.shared.focusLossEffectEnabled == true)

        Settings.shared.focusLossEffectEnabled = false
        let data = try JSONEncoder().encode(Settings.shared.makePersistedSettings())
        let decoded = try JSONDecoder().decode(PersistedSettings.self, from: data)
        #expect(decoded.focusLossEffectEnabled == false)

        Settings.shared.applyPersistedSettings(decoded)
        #expect(Settings.shared.focusLossEffectEnabled == false)

        let legacyData = Data(
            """
            {
              "services": [],
              "version": 1
            }
            """.utf8
        )
        let legacy = try JSONDecoder().decode(PersistedSettings.self, from: legacyData)
        #expect(legacy.focusLossEffectEnabled == nil)
        Settings.shared.applyPersistedSettings(legacy)
        #expect(Settings.shared.focusLossEffectEnabled == true)
    }

    @Test func focusLossBehavior_MapsBothBooleans() throws {
        Settings.shared.wipeAllData()
        _ = Settings.shared.loadSettings()
        defer { Settings.shared.wipeAllData() }

        #expect(Settings.shared.focusLossBehavior == .dim)

        Settings.shared.focusLossBehavior = .unchanged
        #expect(Settings.shared.hideOnFocusLoss == false)
        #expect(Settings.shared.focusLossEffectEnabled == false)

        Settings.shared.focusLossBehavior = .hide
        #expect(Settings.shared.hideOnFocusLoss == true)

        Settings.shared.focusLossBehavior = .dim
        #expect(Settings.shared.hideOnFocusLoss == false)
        #expect(Settings.shared.focusLossEffectEnabled == true)
    }

    @Test func selectorDisplayModes_LegacySharedModeMigratesToBothSelectors() throws {
        Settings.shared.wipeAllData()
        _ = Settings.shared.loadSettings()
        defer { Settings.shared.wipeAllData() }

        let legacyData = Data(
            """
            {
              "services": [],
              "selectorDisplayMode": "Compact",
              "quiperVersion": "4.5.0",
              "version": 1
            }
            """.utf8
        )
        let migrated = try JSONDecoder().decode(PersistedSettings.self, from: legacyData)

        #expect(migrated.didDecodeLegacySelectorDisplayMode)
        #expect(migrated.engineSelectorDisplayMode == .compact)
        #expect(migrated.sessionSelectorDisplayMode == .compact)

        Settings.shared.applyPersistedSettings(migrated)
        #expect(Settings.shared.engineSelectorDisplayMode == .compact)
        #expect(Settings.shared.sessionSelectorDisplayMode == .compact)

        let rewrittenData = try JSONEncoder().encode(migrated)
        let rewrittenObject = try JSONSerialization.jsonObject(with: rewrittenData)
        guard let rewrittenSettings = rewrittenObject as? [String: Any] else {
            Issue.record("Expected a settings JSON object")
            return
        }
        #expect(rewrittenSettings["selectorDisplayMode"] == nil)
    }

    @Test func selectorDisplayModes_PersistIndependently() throws {
        Settings.shared.wipeAllData()
        _ = Settings.shared.loadSettings()
        defer { Settings.shared.wipeAllData() }

        Settings.shared.engineSelectorDisplayMode = .expanded
        Settings.shared.sessionSelectorDisplayMode = .compact

        let data = try JSONEncoder().encode(Settings.shared.makePersistedSettings())
        let decoded = try JSONDecoder().decode(PersistedSettings.self, from: data)
        let object = try JSONSerialization.jsonObject(with: data)

        #expect(decoded.engineSelectorDisplayMode == .expanded)
        #expect(decoded.sessionSelectorDisplayMode == .compact)
        #expect((object as? [String: Any])?["selectorDisplayMode"] == nil)
    }

    @Test func modifierHoldBehaviors_DefaultToExpandAndRoundTrip() throws {
        Settings.shared.wipeAllData()
        _ = Settings.shared.loadSettings()
        defer { Settings.shared.wipeAllData() }

        #expect(Settings.shared.sessionModifierHoldBehavior == .expand)
        #expect(Settings.shared.engineModifierHoldBehavior == .expand)

        Settings.shared.sessionModifierHoldBehavior = .hud
        Settings.shared.engineModifierHoldBehavior = .off
        let data = try JSONEncoder().encode(Settings.shared.makePersistedSettings())
        let decoded = try JSONDecoder().decode(PersistedSettings.self, from: data)
        #expect(decoded.sessionModifierHoldBehavior == .hud)
        #expect(decoded.engineModifierHoldBehavior == .off)

        Settings.shared.applyPersistedSettings(decoded)
        #expect(Settings.shared.sessionModifierHoldBehavior == .hud)
        #expect(Settings.shared.engineModifierHoldBehavior == .off)

        let reread = try JSONDecoder().decode(PersistedSettings.self, from: data)
        Settings.shared.applyPersistedSettings(reread)
        #expect(Settings.shared.sessionModifierHoldBehavior == .hud)
        #expect(Settings.shared.engineModifierHoldBehavior == .off)

        let legacyData = Data(
            """
            {
              "services": [],
              "version": 1
            }
            """.utf8
        )
        let legacy = try JSONDecoder().decode(PersistedSettings.self, from: legacyData)
        #expect(legacy.sessionModifierHoldBehavior == nil)
        #expect(legacy.engineModifierHoldBehavior == nil)
        Settings.shared.applyPersistedSettings(legacy)
        #expect(Settings.shared.sessionModifierHoldBehavior == .expand)
        #expect(Settings.shared.engineModifierHoldBehavior == .expand)
    }

    @Test func templateActionScriptSync_UsesBundledDefaultAndCustomEditsOptOut() throws {
        Settings.shared.wipeAllData()
        _ = Settings.shared.loadSettings()

        guard let pair = defaultTemplatePair() else {
            Issue.record("Expected at least one default service/action script pair")
            return
        }

        let action = CustomAction(id: UUID(), name: pair.action.name)
        var service = pair.service
        service.id = UUID()
        service.actionScripts = [action.id: "console.log('stale custom');"]
        service.templateActionScriptSync = [:]

        Settings.shared.customActions = [action]
        Settings.shared.services = [service]

        Settings.shared.setTemplateActionScriptSync(true, serviceID: service.id, actionID: action.id)
        guard let syncedService = Settings.shared.services.first else {
            Issue.record("Expected synced service")
            return
        }

        #expect(syncedService.templateActionScriptSync[action.id] == true)
        #expect(syncedService.actionScripts[action.id] == nil)
        #expect(Settings.shared.actionScript(for: syncedService, action: action) == pair.defaultScript)

        Settings.shared.saveCustomActionScript("console.log('custom');", serviceID: service.id, actionID: action.id)
        guard let customService = Settings.shared.services.first else {
            Issue.record("Expected custom service")
            return
        }

        #expect(customService.templateActionScriptSync[action.id] == false)
        #expect(Settings.shared.actionScript(for: customService, action: action) == "console.log('custom');")
    }

    @Test func templateActionScriptMigration_UpdatesOrKeepsCustomScripts() throws {
        Settings.shared.wipeAllData()
        _ = Settings.shared.loadSettings()

        guard let pair = defaultTemplatePair() else {
            Issue.record("Expected at least one default service/action script pair")
            return
        }

        let updateAction = CustomAction(id: UUID(), name: pair.action.name)
        var updateService = pair.service
        updateService.id = UUID()
        updateService.actionScripts = [updateAction.id: "console.log('old');"]
        Settings.shared.customActions = [updateAction]
        Settings.shared.services = [updateService]

        Settings.shared.resolveTemplateActionSyncMigration(updateScripts: true)
        let syncedService = Settings.shared.services[0]
        #expect(syncedService.templateActionScriptSync[updateAction.id] == true)
        #expect(syncedService.actionScripts[updateAction.id] == nil)

        let keepAction = CustomAction(id: UUID(), name: pair.action.name)
        var keepService = pair.service
        keepService.id = UUID()
        keepService.actionScripts = [keepAction.id: "console.log('old');"]
        Settings.shared.customActions = [keepAction]
        Settings.shared.services = [keepService]

        Settings.shared.resolveTemplateActionSyncMigration(updateScripts: false)
        let customService = Settings.shared.services[0]
        #expect(customService.templateActionScriptSync[keepAction.id] == false)
        #expect(customService.actionScripts[keepAction.id] == "console.log('old');")
    }

    @Test func templateResources_UseBundledDefaultsAndCustomEditsOptOut() throws {
        Settings.shared.wipeAllData()
        _ = Settings.shared.loadSettings()
        defer { Settings.shared.wipeAllData() }

        guard var selectorService = Settings.shared.defaultServiceTemplates.first(where: {
            Settings.shared.defaultPromptInputSelector(for: $0) != nil
        }),
              let defaultSelector = Settings.shared.defaultPromptInputSelector(for: selectorService) else {
            Issue.record("Expected a default prompt input selector")
            return
        }

        selectorService.id = UUID()
        selectorService.focus_selector = "#custom-input"
        selectorService.templatePromptInputSelectorSync = false
        Settings.shared.services = [selectorService]

        Settings.shared.setTemplatePromptInputSelectorSync(true, serviceID: selectorService.id)
        let syncedSelectorService = Settings.shared.services[0]
        #expect(syncedSelectorService.templatePromptInputSelectorSync)
        #expect(syncedSelectorService.focus_selector.isEmpty)
        #expect(Settings.shared.promptInputSelector(for: syncedSelectorService) == defaultSelector)

        Settings.shared.savePromptInputSelector("#custom-input", serviceID: selectorService.id)
        let customSelectorService = Settings.shared.services[0]
        #expect(!customSelectorService.templatePromptInputSelectorSync)
        #expect(Settings.shared.promptInputSelector(for: customSelectorService) == "#custom-input")

        guard var cssService = Settings.shared.defaultServiceTemplates.first(where: {
            Settings.shared.defaultCustomCSS(for: $0) != nil
        }),
              let defaultCSS = Settings.shared.defaultCustomCSS(for: cssService) else {
            Issue.record("Expected default custom CSS")
            return
        }

        cssService.id = UUID()
        cssService.customCSS = "body { color: red; }"
        cssService.templateCustomCSSSync = false
        Settings.shared.services = [cssService]

        Settings.shared.setTemplateCustomCSSSync(true, serviceID: cssService.id)
        let syncedCSSService = Settings.shared.services[0]
        #expect(syncedCSSService.templateCustomCSSSync)
        #expect(syncedCSSService.customCSS == nil)
        #expect(Settings.shared.customCSS(for: syncedCSSService) == defaultCSS)

        Settings.shared.saveCustomCSS("body { color: red; }", serviceID: cssService.id)
        let customCSSService = Settings.shared.services[0]
        #expect(!customCSSService.templateCustomCSSSync)
        #expect(Settings.shared.customCSS(for: customCSSService) == "body { color: red; }")
    }

    @Test func actionScriptResolution_PrefersCustomOverEngineOverGlobal() {
        Settings.shared.wipeAllData()
        _ = Settings.shared.loadSettings()
        defer { Settings.shared.wipeAllData() }

        // An engine with no Share script anywhere falls back to the global default.
        let plainEngine = Service(name: "Plain Test Engine", url: "https://example.com", focus_selector: "input")
        let shareAction = CustomAction(name: "Share")
        #expect(ActionScripts.resolvedActionScript(for: plainEngine, action: shareAction).contains("navigator.clipboard"))

        // History has no global default, so it resolves empty.
        let historyAction = CustomAction(name: "History")
        #expect(ActionScripts.resolvedActionScript(for: plainEngine, action: historyAction).isEmpty)

        // An engine with no temporary automation falls back to the global
        // ephemeral default instead of beeping.
        let temporaryAction = CustomAction(name: "New Temporary Session")
        #expect(ActionScripts.resolvedActionScript(for: plainEngine, action: temporaryAction).contains("ephemeral"))

        // An engine template default wins over the global one.
        var geminiEngine = Service(name: "Gemini", url: "https://example.com", focus_selector: "input")
        geminiEngine.templateActionScriptSync[shareAction.id] = true
        let geminiShare = ActionScripts.resolvedActionScript(for: geminiEngine, action: shareAction)
        #expect(geminiShare.contains("Share conversation"))
        #expect(!geminiShare.contains("navigator.clipboard"))

        // A custom script wins over both.
        let customAction = CustomAction(id: UUID(), name: "Share")
        var customEngine = plainEngine
        customEngine.actionScripts[customAction.id] = "custom();"
        #expect(ActionScripts.resolvedActionScript(for: customEngine, action: customAction) == "custom();")
    }

    @Test func actionRunner_ForwardsEphemeralFlag() {
        let runner = WebScripts.makeActionRunnerScript(script: "return { ephemeral: true };")
        #expect(runner.contains("result.ephemeral === true"))
        #expect(runner.contains("return { ephemeral: true };"))
        #expect(runner.contains("return \"ok\";"))
    }

    @Test func quiperReferral_StrippedOnlyWhenOurs() {
        let referral = "referrer=https://github.io/sassanh/quiper"
        #expect(DefaultEngineDefinitions.urlStringWithoutQuiperReferral(
            "https://gemini.google.com?" + referral
        ) == "https://gemini.google.com")
        #expect(DefaultEngineDefinitions.urlStringWithoutQuiperReferral(
            "https://example.com?foo=1&" + referral + "&bar=2#frag"
        ) == "https://example.com?foo=1&bar=2#frag")
        #expect(DefaultEngineDefinitions.urlStringWithoutQuiperReferral(
            "https://example.com?referrer=https://other.example"
        ) == "https://example.com?referrer=https://other.example")
        #expect(DefaultEngineDefinitions.urlStringWithoutQuiperReferral(
            "https://example.com?noref=1"
        ) == "https://example.com?noref=1")
        #expect(DefaultEngineDefinitions.urlStringWithoutQuiperReferral("not a url") == "not a url")
    }

    @Test func engineShortcutToggle_NewUserDefaultsEnabledWithoutMigrationPrompt() {
        Settings.shared.wipeAllData()
        _ = Settings.shared.loadSettings()
        defer { Settings.shared.wipeAllData() }

        #expect(Settings.shared.hideQuiperWhenRetriggeringActiveEngineShortcut == true)
        #expect(Settings.shared.needsEngineShortcutToggleMigrationPrompt == false)
        #expect(Settings.shared.makePersistedSettings().hideQuiperWhenRetriggeringActiveEngineShortcut == true)
    }

    @Test func engineShortcutToggle_MissingKeyTriggersMigrationAndResolvePersists() {
        Settings.shared.wipeAllData()
        _ = Settings.shared.loadSettings()
        defer { Settings.shared.wipeAllData() }

        let imported = PersistedSettings(
            services: Settings.shared.services,
            hideQuiperWhenRetriggeringActiveEngineShortcut: nil,
            quiperVersion: "4.4.1"
        )
        Settings.shared.applyPersistedSettings(imported)

        #expect(Settings.shared.hideQuiperWhenRetriggeringActiveEngineShortcut == false)
        #expect(Settings.shared.needsEngineShortcutToggleMigrationPrompt == true)
        #expect(Settings.shared.makePersistedSettings().hideQuiperWhenRetriggeringActiveEngineShortcut == nil)

        Settings.shared.resolveEngineShortcutToggleMigration(enable: true)
        #expect(Settings.shared.hideQuiperWhenRetriggeringActiveEngineShortcut == true)
        #expect(Settings.shared.needsEngineShortcutToggleMigrationPrompt == false)
        #expect(Settings.shared.makePersistedSettings().hideQuiperWhenRetriggeringActiveEngineShortcut == true)

        Settings.shared.resolveEngineShortcutToggleMigration(enable: false)
        #expect(Settings.shared.hideQuiperWhenRetriggeringActiveEngineShortcut == false)
        #expect(Settings.shared.makePersistedSettings().hideQuiperWhenRetriggeringActiveEngineShortcut == false)
    }

    @Test func engineShortcutToggle_DoubleLoadDoesNotStampKeyOrClearMigrationPrompt() {
        Settings.shared.wipeAllData()
        defer { Settings.shared.wipeAllData() }

        // Simulate an existing install that predates the preference (key absent).
        let preFeature = PersistedSettings(
            services: [Service(name: "Gemini", url: "https://example.com", focus_selector: "")],
            hasCompletedGhostOnboarding: true,
            enableHUDDoubleTapCmd: true,
            enableHUDCmdEscape: true,
            hideQuiperWhenRetriggeringActiveEngineShortcut: nil,
            quiperVersion: "4.4.0 (2)"
        )
        Settings.shared.applyPersistedSettings(preFeature)
        #expect(Settings.shared.needsEngineShortcutToggleMigrationPrompt == true)
        #expect(Settings.shared.hideQuiperWhenRetriggeringActiveEngineShortcut == false)

        // didSet-driven saves during apply/load must not stamp the preference while migration is pending.
        Settings.shared.saveSettings()
        #expect(Settings.shared.makePersistedSettings().hideQuiperWhenRetriggeringActiveEngineShortcut == nil)

        // MainWindowController calls loadSettings() again after Settings.init — must not clear the prompt.
        _ = Settings.shared.loadSettings()
        #expect(Settings.shared.needsEngineShortcutToggleMigrationPrompt == true)
        #expect(Settings.shared.hideQuiperWhenRetriggeringActiveEngineShortcut == false)
        #expect(Settings.shared.makePersistedSettings().hideQuiperWhenRetriggeringActiveEngineShortcut == nil)

        _ = Settings.shared.loadSettings()
        #expect(Settings.shared.needsEngineShortcutToggleMigrationPrompt == true)
        #expect(Settings.shared.makePersistedSettings().hideQuiperWhenRetriggeringActiveEngineShortcut == nil)
    }

    @Test func engineShortcutToggle_SetFromUISettlesMigration() {
        Settings.shared.wipeAllData()
        _ = Settings.shared.loadSettings()
        defer { Settings.shared.wipeAllData() }

        let imported = PersistedSettings(
            services: Settings.shared.services,
            hideQuiperWhenRetriggeringActiveEngineShortcut: nil,
            quiperVersion: "4.4.1"
        )
        Settings.shared.applyPersistedSettings(imported)
        #expect(Settings.shared.needsEngineShortcutToggleMigrationPrompt == true)

        Settings.shared.setHideQuiperWhenRetriggeringActiveEngineShortcut(true)
        #expect(Settings.shared.hideQuiperWhenRetriggeringActiveEngineShortcut == true)
        #expect(Settings.shared.needsEngineShortcutToggleMigrationPrompt == false)
        #expect(Settings.shared.makePersistedSettings().hideQuiperWhenRetriggeringActiveEngineShortcut == true)
    }

    @Test func engineShortcutToggle_NewerSettingsDeferMigrationAndPreserveVersion() {
        Settings.shared.wipeAllData()
        _ = Settings.shared.loadSettings()
        defer { Settings.shared.wipeAllData() }

        let futureVersion = "9999.0.0-whatever (10)"
        let imported = PersistedSettings(
            services: Settings.shared.services,
            hideQuiperWhenRetriggeringActiveEngineShortcut: nil,
            quiperVersion: futureVersion
        )
        Settings.shared.applyPersistedSettings(imported)

        let persisted = Settings.shared.makePersistedSettings()
        #expect(Settings.shared.hideQuiperWhenRetriggeringActiveEngineShortcut == false)
        #expect(Settings.shared.needsEngineShortcutToggleMigrationPrompt == false)
        #expect(persisted.hideQuiperWhenRetriggeringActiveEngineShortcut == nil)
        #expect(persisted.quiperVersion == futureVersion)
    }

    @Test func engineShortcutToggle_UnknownSettingsVersionDefersConservatively() {
        Settings.shared.wipeAllData()
        _ = Settings.shared.loadSettings()
        defer { Settings.shared.wipeAllData() }

        let unknownVersion = "not-a-quiper-version"
        let imported = PersistedSettings(
            services: Settings.shared.services,
            hideQuiperWhenRetriggeringActiveEngineShortcut: nil,
            quiperVersion: unknownVersion
        )
        Settings.shared.applyPersistedSettings(imported)

        let persisted = Settings.shared.makePersistedSettings()
        #expect(Settings.shared.needsEngineShortcutToggleMigrationPrompt == false)
        #expect(persisted.hideQuiperWhenRetriggeringActiveEngineShortcut == nil)
        #expect(persisted.quiperVersion == unknownVersion)
    }

    @Test func templateActionMigration_ImportedLegacySettingsKeepVersionUnsetUntilResolved() {
        Settings.shared.wipeAllData()
        _ = Settings.shared.loadSettings()
        defer { Settings.shared.wipeAllData() }

        guard let pair = defaultTemplatePair() else {
            Issue.record("Expected at least one default service/action script pair")
            return
        }

        let action = CustomAction(id: UUID(), name: pair.action.name)
        var service = pair.service
        service.id = UUID()
        service.actionScripts = [action.id: "console.log('legacy');"]
        service.templateActionScriptSync = [:]

        let imported = PersistedSettings(
            services: [service],
            customActions: [action],
            hideQuiperWhenRetriggeringActiveEngineShortcut: false,
            quiperVersion: nil
        )
        Settings.shared.applyPersistedSettings(imported)

        #expect(Settings.shared.needsTemplateActionSyncMigrationPrompt)
        #expect(Settings.shared.makePersistedSettings().quiperVersion == nil)

        Settings.shared.resolveTemplateActionSyncMigration(updateScripts: false)

        #expect(!Settings.shared.needsTemplateActionSyncMigrationPrompt)
        #expect(Settings.shared.makePersistedSettings().quiperVersion != nil)
    }

    @Test func newInstallIncludesEngineSettingsAction() {
        Settings.shared.wipeAllData()
        _ = Settings.shared.loadSettings()
        defer { Settings.shared.wipeAllData() }

        #expect(Settings.shared.customActions.contains { $0.name == "Settings" })
    }

    private func defaultTemplatePair() -> (service: Service, action: CustomAction, defaultScript: String)? {
        for service in Settings.shared.defaultServiceTemplates {
            for action in Settings.shared.defaultActionTemplates {
                if let script = Settings.shared.defaultActionScript(for: service, action: action) {
                    return (service, action, script)
                }
            }
        }
        return nil
    }
}

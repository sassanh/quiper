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

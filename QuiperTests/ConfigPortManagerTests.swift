import Testing
import Foundation
@testable import Quiper
import Carbon

@MainActor
final class ConfigPortManagerTests {
    
    @Test func testExportAndImportConfig() throws {
        // Reset state before tests run
        Settings.shared.wipeAllData()

        let settings = Settings.shared
        
        let testAction = CustomAction(id: UUID(), name: "Test Action", shortcut: nil)
        let testService = Service(
            id: UUID(),
            name: "Export Test Service",
            url: "https://example.com/export",
            focus_selector: ".focus",
            actionScripts: [testAction.id: "console.log('test');"],
            friendDomains: ["example.com"],
            customCSS: "body { background: black; }"
        )
        
        // 1. Setup specific state
        settings.services = [testService]
        settings.customActions = [testAction]
        settings.updatePreferences.automaticallyChecksForUpdates = false
        settings.showHiddenBarOnModifiers = false
        settings.dockVisibility = .never
        
        // Write the script to disk so it gets collected
        let scriptContent = "console.log('test source');"
        ActionScriptStorage.saveScript(scriptContent, serviceID: testService.id, actionID: testAction.id)
        
        // Verify script is stored
        let loadedPre = ActionScriptStorage.loadScript(serviceID: testService.id, actionID: testAction.id, fallback: "")
        #expect(loadedPre == scriptContent)
        
        // 2. Export Config
        let exportedData = try ConfigPortManager.exportConfig()
        #expect(!exportedData.isEmpty)
        
        // Verify exported JSON looks correct structurally
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decodedPS = try decoder.decode(PersistedSettings.self, from: exportedData)
        #expect(decodedPS.version == 1)
        
        let targetService = decodedPS.services.first(where: { $0.id == testService.id })
        #expect(targetService?.actionScripts[testAction.id] == scriptContent)

        
        // 3. Wipe and change state to verify import actually overwrites
        settings.wipeAllData()
        
        let dummyService = Service(name: "Dummy", url: "dummy", focus_selector: "")
        settings.services = [dummyService]
        settings.customActions = []
        settings.updatePreferences.automaticallyChecksForUpdates = true
        settings.showHiddenBarOnModifiers = true
        settings.dockVisibility = .always
        
        ActionScriptStorage.deleteScript(serviceID: testService.id, actionID: testAction.id)
        
        // 4. Import Config
        try ConfigPortManager.importConfig(from: exportedData)
        
        // 5. Verify restored state matches initial
        #expect(settings.services.count == 1)
        #expect(settings.services.first?.name == "Export Test Service")
        #expect(settings.services.first?.url == "https://example.com/export")
        #expect(settings.services.first?.customCSS == "body { background: black; }")
        #expect(settings.services.first?.actionScripts[testAction.id] == scriptContent)
        
        #expect(settings.customActions.count == 1)
        #expect(settings.customActions.first?.name == "Test Action")
        
        #expect(settings.updatePreferences.automaticallyChecksForUpdates == false)
        #expect(settings.showHiddenBarOnModifiers == false)
        #expect(settings.dockVisibility == .never)
        
        // Verify script was written back to disk
        let loadedPost = ActionScriptStorage.loadScript(serviceID: testService.id, actionID: testAction.id, fallback: "")
        #expect(loadedPost == scriptContent)
        
        // Cleanup after tests
        Settings.shared.wipeAllData()
    }
}

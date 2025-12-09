import Testing
import Foundation
@testable import Quiper

final class ActionScriptStorageTests {
    let testServiceID = UUID()
    let testActionID = UUID()
    
    deinit {
        ActionScriptStorage.deleteScript(serviceID: testServiceID, actionID: testActionID)
    }
    
    @Test func saveAndLoadScript() {
        let scriptContent = "console.log('test');"
        
        ActionScriptStorage.saveScript(scriptContent, serviceID: testServiceID, actionID: testActionID)
        let loaded = ActionScriptStorage.loadScript(serviceID: testServiceID, actionID: testActionID, fallback: "fallback")
        
        #expect(loaded == scriptContent)
    }
    
    @Test func loadScript_ReturnsFallback_WhenFileDoesNotExist() {
        let fallback = "fallback script"
        let loaded = ActionScriptStorage.loadScript(serviceID: UUID(), actionID: UUID(), fallback: fallback)
        
        #expect(loaded == fallback)
    }
    
    @Test func saveScript_DeletesFile_WhenScriptIsEmpty() {
        // First save a script
        ActionScriptStorage.saveScript("test", serviceID: testServiceID, actionID: testActionID)
        
        // Then save empty string
        ActionScriptStorage.saveScript("", serviceID: testServiceID, actionID: testActionID)
        
        // Should return fallback since file was deleted
        let loaded = ActionScriptStorage.loadScript(serviceID: testServiceID, actionID: testActionID, fallback: "fallback")
        #expect(loaded == "fallback")
    }
    
    @Test func saveScript_TrimsWhitespace_BeforeCheckingIfEmpty() {
        ActionScriptStorage.saveScript("  \n  ", serviceID: testServiceID, actionID: testActionID)
        
        let loaded = ActionScriptStorage.loadScript(serviceID: testServiceID, actionID: testActionID, fallback: "fallback")
        #expect(loaded == "fallback")
    }
    
    @Test func deleteScript() {
        ActionScriptStorage.saveScript("test", serviceID: testServiceID, actionID: testActionID)
        ActionScriptStorage.deleteScript(serviceID: testServiceID, actionID: testActionID)
        
        let loaded = ActionScriptStorage.loadScript(serviceID: testServiceID, actionID: testActionID, fallback: "fallback")
        #expect(loaded == "fallback")
    }
}

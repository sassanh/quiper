import Testing
import Foundation
@testable import Quiper

@MainActor
final class FocusSelectorStorageTests {
    let testServiceID = UUID()
    

    @Test func saveAndLoadSelector() {
        let selectorContent = "input[type='search']"
        
        FocusSelectorStorage.saveSelector(selectorContent, serviceID: testServiceID)
        let loaded = FocusSelectorStorage.loadSelector(serviceID: testServiceID, fallback: "fallback")
        
        #expect(loaded == selectorContent)
    }
    
    @Test func loadSelector_ReturnsFallback_WhenFileDoesNotExist() {
        let fallback = "fallback selector"
        let loaded = FocusSelectorStorage.loadSelector(serviceID: UUID(), fallback: fallback)
        
        #expect(loaded == fallback)
    }
    
    @Test func saveSelector_DeletesFile_WhenSelectorEmpty() {
        // First save selector
        FocusSelectorStorage.saveSelector(".input-text", serviceID: testServiceID)
        
        // Then save empty string
        FocusSelectorStorage.saveSelector("", serviceID: testServiceID)
        
        // Should return fallback since file was deleted
        let loaded = FocusSelectorStorage.loadSelector(serviceID: testServiceID, fallback: "fallback")
        #expect(loaded == "fallback")
    }
    
    @Test func saveSelector_TrimsWhitespace_BeforeCheckingIfEmpty() {
        FocusSelectorStorage.saveSelector("  \n  ", serviceID: testServiceID)
        
        let loaded = FocusSelectorStorage.loadSelector(serviceID: testServiceID, fallback: "fallback")
        #expect(loaded == "fallback")
    }
    
    @Test func deleteSelector() {
        FocusSelectorStorage.saveSelector("#chat-input", serviceID: testServiceID)
        FocusSelectorStorage.deleteSelector(for: testServiceID)
        
        let loaded = FocusSelectorStorage.loadSelector(serviceID: testServiceID, fallback: "fallback")
        #expect(loaded == "fallback")
    }
}

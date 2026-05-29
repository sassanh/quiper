import Testing
import Foundation
@testable import Quiper

@MainActor
final class CustomCSSStorageTests {
    let testServiceID = UUID()
    

    @Test func saveAndLoadCSS() {
        let cssContent = "body { background: red; }"
        
        CustomCSSStorage.saveCSS(cssContent, serviceID: testServiceID)
        let loaded = CustomCSSStorage.loadCSS(serviceID: testServiceID, fallback: "fallback")
        
        #expect(loaded == cssContent)
    }
    
    @Test func loadCSS_ReturnsFallback_WhenFileDoesNotExist() {
        let fallback = "fallback css"
        let loaded = CustomCSSStorage.loadCSS(serviceID: UUID(), fallback: fallback)
        
        #expect(loaded == fallback)
    }
    
    @Test func saveCSS_DeletesFile_WhenCSSEmpty() {
        // First save CSS
        CustomCSSStorage.saveCSS("body { color: blue; }", serviceID: testServiceID)
        
        // Then save empty string
        CustomCSSStorage.saveCSS("", serviceID: testServiceID)
        
        // Should return fallback since file was deleted
        let loaded = CustomCSSStorage.loadCSS(serviceID: testServiceID, fallback: "fallback")
        #expect(loaded == "fallback")
    }
    
    @Test func saveCSS_TrimsWhitespace_BeforeCheckingIfEmpty() {
        CustomCSSStorage.saveCSS("  \n  ", serviceID: testServiceID)
        
        let loaded = CustomCSSStorage.loadCSS(serviceID: testServiceID, fallback: "fallback")
        #expect(loaded == "fallback")
    }
    
    @Test func deleteCSS() {
        CustomCSSStorage.saveCSS("body { font-size: 12px; }", serviceID: testServiceID)
        CustomCSSStorage.deleteCSS(for: testServiceID)
        
        let loaded = CustomCSSStorage.loadCSS(serviceID: testServiceID, fallback: "fallback")
        #expect(loaded == "fallback")
    }
}

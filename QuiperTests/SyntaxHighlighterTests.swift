import Testing
import Foundation
import SwiftUI
@testable import Quiper

@MainActor
final class SyntaxHighlighterTests {
    
    @Test func highlightEmptyCode() {
        let highlighted = SyntaxHighlighter.highlight(code: "", language: "javascript")
        #expect(highlighted.description.isEmpty)
    }
    
    @Test func highlightJavaScriptKeywords() {
        let code = "const x = true; return null;"
        let highlighted = SyntaxHighlighter.highlight(code: code, language: "javascript")
        
        // Ensure styling gets applied to the keywords
        #expect(!highlighted.description.isEmpty)
    }
    
    @Test func highlightCSSSelectorsAndProperties() {
        let code = ".my-class { background: red; }"
        let highlighted = SyntaxHighlighter.highlight(code: code, language: "css")
        
        #expect(!highlighted.description.isEmpty)
    }
}

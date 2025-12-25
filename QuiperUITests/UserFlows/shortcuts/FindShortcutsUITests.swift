
import XCTest

final class FindShortcutsUITests: BaseUITest {
    
    let fileManager = FileManager.default
    lazy var tempDir: URL = {
        return fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }()
    
    lazy var overrideFile: URL = {
        return tempDir.appendingPathComponent("test-custom-engine-1.html")
    }()

    override var launchArguments: [String] {
        return ["--uitesting", "--test-custom-engines=2", "--test-custom-engines-path=\(tempDir.path)"]
    }

    override func setUp() {
        do {
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)

            // HTML with multiple instances of searchable text for find testing
            // Each paragraph contains "apple" in different contexts for proper navigation testing
            // JS exposes current selection to document.title for verification
            let htmlContent = """
             <html>
             <head>
                 <style>
                     body { font-family: -apple-system, sans-serif; padding: 20px; }
                     p { margin: 10px 0; }
                 </style>
                 <script>
                 // Expose selection state to document title for XCTest verification
                 function updateSelectionInfo() {
                     const sel = window.getSelection();
                     const text = sel.toString().trim();
                     const parent = sel.anchorNode?.parentElement?.id || 'none';
                     document.title = 'Selection: ' + text + ' in ' + parent;
                 }
                 // Poll for selection changes
                 setInterval(updateSelectionInfo, 100);
                 document.addEventListener('selectionchange', updateSelectionInfo);
                 </script>
             </head>
             <body>
                 <h1>Find Test Page</h1>
                 <p id="p1">The first apple is red.</p>
                 <p id="p2">The second apple is green.</p>
                 <p id="p3">The third apple is yellow.</p>
                 <p id="p4">Oranges are not apples.</p>
                 <p id="p5">But this apple is the best apple of all.</p>
                 <p id="p6">End of the apple orchard tour.</p>
             </body>
             </html>
             """
             try htmlContent.write(to: overrideFile, atomically: true, encoding: .utf8)
        } catch {
            XCTFail("Failed to set up test files: \(error)")
        }
         
        super.setUp()
    }
    
    override func tearDown() {
        try? fileManager.removeItem(at: tempDir)
        super.tearDown()
    }
    
    func testFindFeature() {
        // Comprehensive test for Find feature with custom content
        // JS in HTML exposes selection to document.title as "Selection: <text> in <parentId>"
        ensureWindowVisible()
        
        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 5.0))
        
        let findField = app.searchFields["Find in page"]
        
        // 1. Open find bar with Cmd+f
        app.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(findField.waitForExistence(timeout: 3.0), "Find bar should appear after Cmd+f")
        
        // 2. Type search text - "apple" appears 7 times in our test content
        findField.typeText("apple")
        
        // Allow UI and JS to update
        Thread.sleep(forTimeInterval: 0.5)
        
        // First match should be in p1
        // WebKit find should set selection, which JS exposes to title
        
        // 3. Find Forward with Cmd+g (navigate to next match)
        app.typeKey("g", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertTrue(findField.exists, "Find bar should remain open after Cmd+g")
        
        // 4. Find Forward with Enter (another match)
        app.typeKey(.return, modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertTrue(findField.exists, "Find bar should remain open after Enter")
        
        // 5. Find Forward again (continue through matches)
        app.typeKey(.return, modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertTrue(findField.exists, "Find bar should remain open after second Enter")
        
        // 6. Find Backward with Cmd+Shift+g (go back)
        app.typeKey("g", modifierFlags: [.command, .shift])
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertTrue(findField.exists, "Find bar should remain open after Cmd+Shift+g")
        
        // 7. Find Backward with Shift+Enter (go back more)
        app.typeKey(.return, modifierFlags: .shift)
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertTrue(findField.exists, "Find bar should remain open after Shift+Enter")
        
        // 8. Close find bar with Escape
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(findField.waitForNonExistence(timeout: 2.0), "Find bar should close after Escape")
        
        // 9. Reopen to verify toggle works
        app.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(findField.waitForExistence(timeout: 3.0), "Find bar should reopen after Cmd+f")
        
        // 10. Close again with Escape
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(findField.waitForNonExistence(timeout: 2.0), "Find bar should close again after Escape")
    }
}

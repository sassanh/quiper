
import XCTest

final class ReloadShortcutsUITests: BaseUITest {
    
    let fileManager = FileManager.default
    // Use a unique temporary directory for this test
    lazy var tempDir: URL = {
        return fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }()
    
    lazy var overrideFile: URL = {
        return tempDir.appendingPathComponent("test-custom-engine-1.html")
    }()

    override var launchArguments: [String] {
        // Pass the path to our temp directory so the app knows where to look
        return ["--uitesting", "--test-custom-engines=2", "--test-custom-engines-path=\(tempDir.path)"]
    }

    override func setUp() {
        do {
            // Create the specific test directory
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)

            let htmlContent = """
             <html>
             <head>
                 <script>
                 // Generate a random ID on load
                 const pageId = Math.random().toString(36).substring(7);
                 window.onload = function() {
                     document.getElementById('content').textContent = 'ID: ' + pageId;
                     document.title = 'ID: ' + pageId;
                 }
                 </script>
             </head>
             <body>
                 <h1 id='content'>Loading...</h1>
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
    
    func testReloadShortcut() {
        ensureWindowVisible()
        
        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 5.0))
        
        // Wait for initial ID
        let idPredicate = NSPredicate(format: "label BEGINSWITH 'ID: '")
        let idExpectation = XCTNSPredicateExpectation(predicate: idPredicate, object: webView)
        // Wait up to 5s for load
        let result = XCTWaiter().wait(for: [idExpectation], timeout: 5.0)
        XCTAssertEqual(result, .completed, "Webview should have a 'ID: X' label")
        
        let initialLabel = webView.label
        
        // Reload (Cmd+r)
        app.typeKey("r", modifierFlags: .command)
        
        // Expect label to CHANGE to a new ID
        // The page reload might take a moment, and the ID will change
        let changedPredicate = NSPredicate(format: "label BEGINSWITH 'ID: ' AND label != %@", initialLabel)
        let changedExpectation = XCTNSPredicateExpectation(predicate: changedPredicate, object: webView)
        
        // Wait for reload (network/file IO)
        let changeResult = XCTWaiter().wait(for: [changedExpectation], timeout: 5.0)
        XCTAssertEqual(changeResult, .completed, "Page ID should change after Reload")
        
        let newLabel = webView.label
        XCTAssertNotEqual(newLabel, initialLabel)
    }
}

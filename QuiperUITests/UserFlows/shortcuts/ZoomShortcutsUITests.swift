
import XCTest

final class ZoomShortcutsUITests: BaseUITest {
    
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
                 const initialWidth = parseFloat(getComputedStyle(document.documentElement).width);
                 function updateTitle() {
                     // Calculate relative zoom based on initial state to normalize across displays (Retina vs Non-Retina)
                     // This ensures we always start at "Zoom: 1.00"
                     const relativeZoom = initialWidth / parseFloat(getComputedStyle(document.documentElement).width);
                     const zoomText = 'Zoom: ' + relativeZoom.toFixed(2);
                     document.getElementById('content').textContent = zoomText;
                     document.title = zoomText;
                 }
                 window.addEventListener('resize', updateTitle);
                 // Poll for changes as backup since resize might not fire immediately on zoom
                 setInterval(updateTitle, 100);
                 </script>
             </head>
             <body>
                 <h1 id='content'>Zoom: 1.00</h1>
             </body>
             </html>
             """
             try htmlContent.write(to: overrideFile, atomically: true, encoding: .utf8)
        } catch {
            XCTFail("Failed to set up test files: \(error)")
        }
         
         // Call super.setUp() AFTER creating the files and ensuring launchArguments are ready
         super.setUp()
    }
    
    override func tearDown() {
        try? fileManager.removeItem(at: tempDir)
        super.tearDown()
    }
    
    func testZoomShortcuts() {
        ensureWindowVisible()
        
        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 5.0))
        
        // Wait for initial zoom value to populate in title
        let zoomPredicate = NSPredicate(format: "label == 'Zoom: 1.00'")
        let zoomExpectation = XCTNSPredicateExpectation(predicate: zoomPredicate, object: webView)
        let result = XCTWaiter().wait(for: [zoomExpectation], timeout: 5.0)
        XCTAssertEqual(result, .completed, "Webview should have a 'Zoom: X.XX' label from our JS")
        
        let initialLabel = webView.label
        
        // Zoom In (Cmd+=)
        app.typeKey("=", modifierFlags: .command)
        
        // Expect label to CHANGE to something different (and presumably larger)
        // Since we can't easily parse float from string in NSPredicate, we just check for inequality first
        let changedPredicate = NSPredicate(format: "label != %@", initialLabel)
        let changedExpectation = XCTNSPredicateExpectation(predicate: changedPredicate, object: webView)
        // Increased timeout to 5.0s to allow for JS polling interval and UI updates
        let changeResult = XCTWaiter().wait(for: [changedExpectation], timeout: 50.0)
        XCTAssertEqual(changeResult, .completed, "Zoom label should change after Zoom In")
        
        let zoomedInLabel = webView.label
        XCTAssertNotEqual(zoomedInLabel, initialLabel)
        
        // Zoom Out (Cmd+-)
        app.typeKey("-", modifierFlags: .command)
        
        // Expect label to return to initial
        let returnPredicate = NSPredicate(format: "label == %@", initialLabel)
        let returnExpectation = XCTNSPredicateExpectation(predicate: returnPredicate, object: webView)
        let returnResult = XCTWaiter().wait(for: [returnExpectation], timeout: 2.0)
         XCTAssertEqual(returnResult, .completed, "Zoom label should return to initial value after Zoom Out")
    }
    
    // MARK: - Helpers
    
    private func ensureWindowVisible() {
        // The main window is an overlay and may not appear in app.windows.
        // We check for a UI element inside it to verify visibility.
        let sessionSelector = app.descendants(matching: .any).matching(identifier: "ServiceSelector")
        
        if !sessionSelector.firstMatch.exists {
             let statusItem = app.statusItems.firstMatch
             if statusItem.waitForExistence(timeout: 5.0) {
                 statusItem.click()
                 
                 let showItem = app.menuItems["Show Quiper"]
                 if showItem.waitForExistence(timeout: 2.0) {
                     showItem.click()
                 }
             }
        }

        if !waitForElement(sessionSelector.firstMatch, timeout: 5.0) {
            XCTFail("Main window content (SessionSelector) must be visible for tests")
        }
    }
}

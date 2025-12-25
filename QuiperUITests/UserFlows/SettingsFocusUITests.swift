import XCTest

class SettingsFocusUITests: BaseUITest {
    
    private var tempDir: URL!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        // Create temp directory with custom HTML for focus testing
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        // HTML that listens for keypress and shows "FOCUSED!" when a key is pressed
        let focusTestHTML = """
        <!DOCTYPE html>
        <html>
        <head>
            <title>Focus Test</title>
        </head>
        <body>
            <div id="status">Waiting for keypress...</div>
            <script>
                document.addEventListener('keydown', function(e) {
                    document.getElementById('status').textContent = 'FOCUSED!';
                    document.title = 'FOCUSED!';
                });
            </script>
        </body>
        </html>
        """
        
        let htmlFile = tempDir.appendingPathComponent("test-custom-engine-1.html")
        try focusTestHTML.write(to: htmlFile, atomically: true, encoding: .utf8)
    }
    
    override func tearDownWithError() throws {
        if let tempDir = tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try super.tearDownWithError()
    }
    
    override var launchArguments: [String] {
        guard let tempDir = tempDir else {
            return ["--uitesting", "--no-default-services"]
        }
        return [
            "--uitesting",
            "--test-custom-engines=1",
            "--test-custom-engines-path=\(tempDir.path)"
        ]
    }
    
    func testSettingsCloseButtonRestoresFocus() throws {
        ensureWindowVisible()

        let overlayWindow = app.windows["Quiper Overlay"]
        
        // Wait for webview to load
        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 5.0), "WebView should exist")
        
        // Verify initial state (title should be "Focus Test")
        let initialPredicate = NSPredicate(format: "label == 'Focus Test'")
        let initialExpectation = XCTNSPredicateExpectation(predicate: initialPredicate, object: webView)
        XCTAssertEqual(XCTWaiter.wait(for: [initialExpectation], timeout: 5.0), .completed, "WebView should have initial title 'Focus Test'")
        
        // Open Settings
        openSettings()
        
        let settingsWindow = app.windows.containing(.radioButton, identifier: "gear").firstMatch
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 3.0), "Settings window should open")
        
        // Close Settings via the close button
        let closeButton = settingsWindow.buttons[XCUIIdentifierCloseWindow]
        XCTAssertTrue(closeButton.exists, "Close button should exist on Settings window")
        closeButton.click()
        
        // Verify Settings is closed
        XCTAssertTrue(settingsWindow.waitForNonExistence(timeout: 2.0), "Settings window should close")
        
        // Verify app is in foreground
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 2.0), "App should remain in foreground")
        XCTAssertTrue(overlayWindow.exists, "Main overlay should be visible after settings close")
        
        // FUNCTIONAL FOCUS VERIFICATION:
        // Press a key and verify the webview receives it (title changes to "FOCUSED!")
        app.typeKey("a", modifierFlags: [])
        
        let focusedPredicate = NSPredicate(format: "label == 'FOCUSED!'")
        let focusedExpectation = XCTNSPredicateExpectation(predicate: focusedPredicate, object: webView)
        let result = XCTWaiter.wait(for: [focusedExpectation], timeout: 5.0)
        XCTAssertEqual(result, .completed, "WebView title should change to 'FOCUSED!' after keypress, proving focus was restored")
    }
    
    func testSettingsCloseShortcutRestoresFocus() throws {
        ensureWindowVisible()

        let overlayWindow = app.windows["Quiper Overlay"]
        
        // Wait for webview to load
        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 5.0), "WebView should exist")
        
        // Verify initial state (title should be "Focus Test")
        let initialPredicate = NSPredicate(format: "label == 'Focus Test'")
        let initialExpectation = XCTNSPredicateExpectation(predicate: initialPredicate, object: webView)
        XCTAssertEqual(XCTWaiter.wait(for: [initialExpectation], timeout: 5.0), .completed, "WebView should have initial title 'Focus Test'")
        
        // Open Settings
        openSettings()
        
        let settingsWindow = app.windows.containing(.radioButton, identifier: "gear").firstMatch
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 3.0), "Settings window should open")
        
        // Close Settings via the keyboard shortcut Cmd+W
        settingsWindow.typeKey("w", modifierFlags: .command)
        
        // Verify Settings is closed
        XCTAssertTrue(settingsWindow.waitForNonExistence(timeout: 2.0), "Settings window should close")
        
        // Verify app is in foreground
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 2.0), "App should remain in foreground")
        XCTAssertTrue(overlayWindow.exists, "Main overlay should be visible after settings close")
        
        // FUNCTIONAL FOCUS VERIFICATION:
        // Press a key and verify the webview receives it (title changes to "FOCUSED!")
        app.typeKey("b", modifierFlags: [])
        
        let focusedPredicate = NSPredicate(format: "label == 'FOCUSED!'")
        let focusedExpectation = XCTNSPredicateExpectation(predicate: focusedPredicate, object: webView)
        let result = XCTWaiter.wait(for: [focusedExpectation], timeout: 5.0)
        XCTAssertEqual(result, .completed, "WebView title should change to 'FOCUSED!' after keypress, proving focus was restored")
    }
}

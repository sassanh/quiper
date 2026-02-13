import XCTest

class ModalPopupTests: BaseUITest {
    private var tempDir: URL!
    
    override func setUpWithError() throws {
        // Setup temp directory
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("QuiperModalTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        // Popup page
        let popupHTML = """
        <!DOCTYPE html>
        <html>
        <head><title>Popup Page</title></head>
        <body><h1>This is a popup</h1></body>
        </html>
        """
        try popupHTML.write(to: tempDir.appendingPathComponent("popup.html"), atomically: true, encoding: .utf8)
        
        // Main test page
        let htmlContent = """
        <!DOCTYPE html>
        <html>
        <head><title>Modal Test</title></head>
        <body>
            <button id="open-btn" style="width: 200px; height: 50px;" onclick="window.open('popup.html', 'popup', 'width=300,height=300')">Open Popup</button>
            <script>
                document.addEventListener('keydown', function(e) {
                    document.title = 'FOCUSED!';
                });
            </script>
        </body>
        </html>
        """
        try htmlContent.write(to: tempDir.appendingPathComponent("test-custom-engine-1.html"), atomically: true, encoding: .utf8)
        
        try super.setUpWithError()
    }
    
    override func tearDownWithError() throws {
        if let tempDir = tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try super.tearDownWithError()
    }
    
    override var launchArguments: [String] {
        guard let tempDir = tempDir else {
            return ["--uitesting"]
        }
        return [
            "--uitesting",
            "--test-custom-engines=1",
            "--test-custom-engines-path=\(tempDir.path)",
            "--no-default-actions"
        ]
    }
    
    func testModalPopupLifecycle() throws {
        ensureWindowVisible()
        
        let overlayWindow = app.windows["Quiper Overlay"]
        XCTAssertTrue(overlayWindow.waitForExistence(timeout: 5.0))
        
        // 2. Click "Open Popup"
        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 10.0), "WebView should load test content")
        
        let openButton = webView.buttons["Open Popup"]
        XCTAssertTrue(openButton.waitForExistence(timeout: 5.0), "Open Popup button should exist")
        openButton.click()
        
        // 3. Verify Popup Window exists
        var popupWindow: XCUIElement?
        let deadline = Date(timeIntervalSinceNow: 10.0)
        while Date() < deadline {
            let windows = app.windows.allElementsBoundByIndex
            for win in windows {
                let title = win.title
                if title != "Quiper Overlay" && title != "Quiper Settings" {
                    popupWindow = win
                    break
                }
            }
            if popupWindow != nil { break }
            Thread.sleep(forTimeInterval: 0.5)
        }
        
        XCTAssertNotNil(popupWindow, "Popup window should have opened in Quiper (not Safari)")
        
        // 4. Close Popup Window manually
        let closeButton = popupWindow!.buttons[XCUIIdentifierCloseWindow]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 2.0))
        closeButton.click()
        
        // Reactivate app just in case to help XCUITest find the borderless window
        app.activate()
        
        // 5. Verify main window is still interactive (no freeze)
        // Note: XCUITest sometimes loses track of borderless windows after modal interaction.
        // The fact that we reached here without a crash/freeze confirms the fix.
        XCTAssertTrue(overlayWindow.waitForExistence(timeout: 5.0))
        
        // FUNCTIONAL FOCUS VERIFICATION:
        // Press a key and verify the webview receives it (title changes to "FOCUSED!")
        app.typeKey("f", modifierFlags: [])
        
        let focusedPredicate = NSPredicate(format: "label == 'FOCUSED!'")
        let focusedExpectation = XCTNSPredicateExpectation(predicate: focusedPredicate, object: webView)
        let result = XCTWaiter().wait(for: [focusedExpectation], timeout: 5.0)
        XCTAssertEqual(result, .completed, "WebView title should change to 'FOCUSED!' after keypress, proving focus was restored")
        
        overlayWindow.click()
    }
}

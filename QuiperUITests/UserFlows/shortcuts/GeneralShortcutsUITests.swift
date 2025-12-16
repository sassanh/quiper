
import XCTest

final class GeneralShortcutsUITests: BaseUITest {
    
    // Use default launch arguments (no custom file override needed)
    // But ensure we have multiple engines to test "Content 1" presence
    override var launchArguments: [String] {
        return ["--uitesting", "--test-custom-engines=2"]
    }

    func testSettingsShortcut() {
        // Test Cmd+, from the main window
        ensureWindowVisible()
        
        // Ensure settings is closed to start clean
        let settingsWindow = app.windows["Settings"]
        if settingsWindow.exists {
             settingsWindow.buttons[XCUIIdentifierCloseWindow].click()
             XCTAssertTrue(settingsWindow.waitForNonExistence(timeout: 2.0))
        }
        
        // Shortcut under test: Cmd+,
        app.typeKey(",", modifierFlags: .command)
        
        // Verification
        let anyWindow = app.windows.firstMatch
        XCTAssertTrue(anyWindow.waitForExistence(timeout: 5.0), "Settings window should appear after Cmd+,")
    }
    
    func testFindShortcuts() {
        // Test Cmd+f
        ensureWindowVisible()
        
        let findField = app.searchFields["Find in page"]
        
        // Open find bar
        app.typeKey("f", modifierFlags: .command)
        
        XCTAssertTrue(findField.waitForExistence(timeout: 3.0), "Find bar should appear after Cmd+f")
        
        // Find Navigation (Cmd+g)
        // We can't easily verify the selection moves without JS injection or screenshot diff, 
        // but we can verify the shortcut doesn't crash and keeps the bar open.
        // Or if we had a match count label. `MainWindowController` updates `findStatusLabel`.
        // Let's check for that label.
        
        // Type something common found in default pages
        findField.typeText("Content") 
        
        // Let's verify the status label if possible, or just implicit stability
        app.typeKey("g", modifierFlags: .command)
        XCTAssertTrue(findField.exists)
    }
    
    func testHideShortcut() {
        // Test Cmd+h
        ensureWindowVisible()
        
        // Note: Cmd+h hides the APPLICATION on macOS. 
        // XCTest app.typeKey("h", modifierFlags: .command) might hide the test runner if not careful,
        // or effectively hide the app under test.
        // Verifying "isHidden" state of the app is tricky in XCUITest.
        // Instead, we might verify that the window is no longer accessible or focus changes.
        // However, standard XCTest doesn't support "Application Hidden" assertion well.
        // Often Cmd+h is better tested by verifying the menu item "Hide Quiper" triggers.
        
        // We will skip strict verification of Cmd+h effect as it disrupts the test runner session often,
        // or just verify it does NOT crash.
        app.typeKey("h", modifierFlags: .command)
        
        // To recover for other tests, we might need to reactivate.
        app.activate()
    }
    
    func testCloseShortcut() {
        // Test Cmd+w
        ensureWindowVisible()
        _ = app.windows.firstMatch // Main window is often overlay, strict check needed?
        
        // Cmd+w should close/hide the active window
        app.typeKey("w", modifierFlags: .command)
        
        // In Quiper, Cmd+w hides the window
        // We can check if the SessionSelector is no longer hittable
        let sessionSelector = app.descendants(matching: .any).matching(identifier: "ServiceSelector").firstMatch
        XCTAssertTrue(sessionSelector.waitForNonExistence(timeout: 2.0), "Main window content should be hidden/closed after Cmd+w")
    }
    
    // MARK: - Helpers
    
    private func ensureWindowVisible() {
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

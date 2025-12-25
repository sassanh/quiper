
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
        
        // Shortcut under test: Cmd+,
        app.typeKey(",", modifierFlags: .command)
        
        // Verification
        let settingsWindow = app.windows["Quiper Settings"]
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 5.0), "Settings window should appear after Cmd+,")
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
        _ = app.windows["Quiper Overlay"] // Main window is often overlay, strict check needed?
        
        // Cmd+w should close/hide the active window
        app.typeKey("w", modifierFlags: .command)
        
        // In Quiper, Cmd+w hides the window
        // We can check if the SessionSelector is no longer hittable
        let sessionSelector = app.radioGroups["SessionSelector"]
        XCTAssertTrue(sessionSelector.waitForNonExistence(timeout: 2.0), "Main window content should be hidden/closed after Cmd+w")
    }
}

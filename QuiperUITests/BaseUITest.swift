import XCTest

/// Base class for all UI tests with common setup and utilities
class BaseUITest: XCTestCase {
    var app: XCUIApplication!
    
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = launchArguments
        app.launch()
    }
    
    /// Default launch arguments. Subclasses can override this.
    var launchArguments: [String] {
        return ["--uitesting"]
    }
    
    override func tearDown() {
        app.terminate()
        super.tearDown()
    }
    
    /// Wait for an element to exist
    func waitForElement(_ element: XCUIElement, timeout: TimeInterval = 1) -> Bool {
        return element.waitForExistence(timeout: timeout)
    }
    
    /// Open Settings window
    /// Open Settings window
    /// Open Settings window
    func openSettings() {
        // Try to activate the app first
        app.activate()
        
        // Wait for app to be idle
        _ = app.wait(for: .runningForeground, timeout: 1.0)
        
        // Use status menu exclusively as Cmd+, is unreliable when app is hidden/backgrounded
        
        // Find status item
        let statusItem = app.statusItems.firstMatch
        if statusItem.waitForExistence(timeout: 1.0) {
            statusItem.click()
            
            let settingsItem = app.menuItems["Settings"]
            
            if settingsItem.waitForExistence(timeout: 1.0) {
                // Use coordinate click to avoid "waiting for menu open notification" failure
                settingsItem.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
            }
        }
        
        // Verify window opens
        let settingsWindow = app.windows.firstMatch
        if !waitForElement(settingsWindow, timeout: 1) {
            app.typeKey(",", modifierFlags: .command)
            if waitForElement(settingsWindow, timeout: 1) {
                 return // Success
            }
            
            XCTFail("Settings window did not open")
        }
    }
    
    /// Switch to a specific Settings tab
    func switchToSettingsTab(_ tabName: String) {
        // Try to find the tab button by label
        // SwiftUI tabs often appear as buttons or radio buttons
        let tabButton = app.buttons[tabName]
        
        if tabButton.exists {
            tabButton.click()
        } else {
            // Try searching for any element with the tab name that is clickable
            // This handles cases where the tab might be a different element type
            let anyTabElement = app.descendants(matching: .any).matching(identifier: tabName).firstMatch
            if anyTabElement.exists {
                anyTabElement.click()
            } else {
                // Fallback: Try to find by label predicate
                let labelMatch = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", tabName)).firstMatch
                if labelMatch.exists {
                    labelMatch.click()
                } else {
                     XCTFail("Tab '\(tabName)' should exist")
                     return
                }
            }
        }
        // Wait for status item (primary interaction point)
        let statusItem = app.statusItems.firstMatch
        _ = statusItem.waitForExistence(timeout: 10.0)
    }
    
    /// Add a test service via Settings UI
    @discardableResult
    func addTestService(name: String, url: String) -> Bool {
        let addButton = app.descendants(matching: .any).matching(identifier: "Add Service").firstMatch
        guard waitForElement(addButton, timeout: 5) else {
            return false
        }
        
        addButton.click()
        
        let blankServiceMenuItem = app.menuItems["Blank Service"]
        guard waitForElement(blankServiceMenuItem, timeout: 1) else {
            return false
        }
        
        blankServiceMenuItem.click()
        // Wait for name field instead of sleep
        
        // Fill in name
        let nameField = app.textFields.element(boundBy: 0)
        guard waitForElement(nameField, timeout: 3) else {
            return false
        }
        
        nameField.click()
        nameField.typeKey("a", modifierFlags: .command)
        nameField.typeText(name)
        
        // Fill in URL
        let urlField = app.textFields.element(boundBy: 1)
        guard waitForElement(urlField, timeout: 3) else {
            return false
        }
        
        urlField.click()
        urlField.typeKey("a", modifierFlags: .command)
        urlField.typeText(url)
        
        return true
    }
    
    /// Standardized wait helper
    /// Uses Thread.sleep for granular waiting (e.g. 0.1s)
    func wait(_ duration: TimeInterval) {
        Thread.sleep(forTimeInterval: duration)
    }
}

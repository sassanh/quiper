
import XCTest

final class TemplateManagementUITests: BaseUITest {
    
    override var launchArguments: [String] {
        return ["--uitesting"]
    }

    func testTemplateLifecycle() throws {
        // --- Setup ---
        openSettings()
        
        // --- Step 1: Delete All (General Tab) ---
        switchToSettingsTab("General")
        
        // Erase Engines
        let eraseEnginesBtn = app.buttons["Erase All Engines"]
        eraseEnginesBtn.tap()
        eraseEnginesBtn.click()
        
        let engineAlert = app.sheets.firstMatch
        guard engineAlert.staticTexts["Erase all engines?"].exists else {
            XCTFail("Erase engines alert did not appear")
            return
        }
        XCTAssertTrue(engineAlert.waitForExistence(timeout: 3.0), "Erase engines alert should appear")
        engineAlert.buttons["Erase"].click()
        XCTAssertTrue(engineAlert.waitForNonExistence(timeout: 3.0))
        
        // Erase Actions
        let eraseActionsBtn = app.buttons["Erase All Actions"]
        eraseActionsBtn.tap()
        eraseActionsBtn.click()
        
        let actionAlert = app.sheets.firstMatch
        guard actionAlert.staticTexts["Erase all actions?"].exists else {
            XCTFail("Erase actions alert did not appear")
            return
        }
        XCTAssertTrue(actionAlert.waitForExistence(timeout: 3.0), "Erase actions alert should appear")
        actionAlert.buttons["Erase"].click()
        XCTAssertTrue(actionAlert.waitForNonExistence(timeout: 3.0))
        
        // --- Verify Empty ---
        switchToSettingsTab("Engines")
        XCTAssertEqual(app.outlines.firstMatch.outlineRows.count, 0, "Engines should be empty")
        
        // --- Step 2: Add One by One ---
        let engineTemplates = ["ChatGPT", "Gemini", "Grok", "X", "Ollama", "Google"]
        
        let addServiceBtn = app.descendants(matching: .any).matching(identifier: "Add Service").firstMatch
        
        for name in engineTemplates {
            if !addServiceBtn.exists {
                 // Try finding it again if hierarchy shifted
                 _ = addServiceBtn.waitForExistence(timeout: 1.0)
            }
            addServiceBtn.click()
            
            // Wait for menu to appear. Scope to toolbars to avoid matching Window menu items (e.g. "ChatGPT" window title)
            let menuItem = app.toolbars.menuItems[name]
            if menuItem.waitForExistence(timeout: 1.0) {
                menuItem.click()
            } else {
                let menuButton = app.buttons[name]
                if menuButton.waitForExistence(timeout: 1.0) {
                    menuButton.click()
                } else {
                    XCTFail("Could not find menu item '\(name)'")
                }
            }
        }
        XCTAssertEqual(app.outlines.firstMatch.outlineRows.count, 6, "Should have added 6 services")
        
        // Add Actions from Templates
        switchToSettingsTab("Shortcuts")
        
        let actionTemplates = ["New Session", "New Temporary Session", "Share", "History"]
        
        for name in actionTemplates {
            // "Add Action" button
            // Try standard button first, then toolbar fallback
            let addActionBtn = app.buttons["Add Action"]
            if addActionBtn.exists {
                addActionBtn.click()
            } else {
                let toolbarBtn = app.toolbars.buttons["Add Action"]
                if toolbarBtn.exists {
                    toolbarBtn.click()
                } else {
                     // Fallback: finding via label in descendants if needed
                     app.descendants(matching: .any).matching(identifier: "Add Action").firstMatch.click()
                }
            }
            
            // Click menu item
            let menuItem = app.menuItems[name]
            if menuItem.waitForExistence(timeout: 1.0) {
                menuItem.click()
            } else {
                let menuButton = app.buttons[name]
                if menuButton.waitForExistence(timeout: 1.0) {
                    menuButton.click()
                } else {
                    XCTFail("Could not find menu item '\(name)'")
                }
            }
        }
        
        // --- Step 3: Delete All Again ---
        switchToSettingsTab("General")
        
        eraseEnginesBtn.click()
        let secondEngineAlert = app.sheets.firstMatch
        XCTAssertTrue(secondEngineAlert.waitForExistence(timeout: 3.0))
        secondEngineAlert.buttons["Erase"].click()
        XCTAssertTrue(secondEngineAlert.waitForNonExistence(timeout: 3.0))
        
        eraseActionsBtn.click()
        let secondActionAlert = app.sheets.firstMatch
        XCTAssertTrue(secondActionAlert.waitForExistence(timeout: 3.0))
        secondActionAlert.buttons["Erase"].click()
        XCTAssertTrue(secondActionAlert.waitForNonExistence(timeout: 3.0))
        
        // --- Step 4: Add All via Add All Buttons ---
        
        // Engines
        switchToSettingsTab("Engines")
        addServiceBtn.click()
        
        let addAllEngines = app.menuItems["Add All Templates"]
        if addAllEngines.waitForExistence(timeout: 2.0) {
            addAllEngines.click()
        } else {
             let btn = app.buttons["Add All Templates"]
             XCTAssertTrue(btn.waitForExistence(timeout: 2.0), "Add All Templates button (Engines) not found")
             btn.click()
        }
        
        XCTAssertEqual(app.outlines.firstMatch.outlineRows.count, 6, "Step 4: Should have 6 engines")
        
        // Actions
        switchToSettingsTab("Shortcuts")
        
        var addActionBtn = app.buttons["Add Action"]
        if !addActionBtn.exists {
             addActionBtn = app.toolbars.buttons["Add Action"]
        }
        if !addActionBtn.exists {
             addActionBtn = app.descendants(matching: .any).matching(identifier: "Add Action").firstMatch
        }
        
        XCTAssertTrue(addActionBtn.waitForExistence(timeout: 2.0), "Add Action button not found in Step 4")
        addActionBtn.click()
        
        let addAllActions = app.menuItems["Add All Templates"]
        if addAllActions.waitForExistence(timeout: 2.0) {
            addAllActions.click()
        } else {
             let btn = app.buttons["Add All Templates"]
             XCTAssertTrue(btn.waitForExistence(timeout: 2.0), "Add All Templates button (Actions) not found")
             btn.click()
        }
        
        XCTAssertTrue(app.textFields["New Session"].waitForExistence(timeout: 5.0), "New Session action should exist in TextField")
    }
}

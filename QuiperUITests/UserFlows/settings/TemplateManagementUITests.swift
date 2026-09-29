
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
        let eraseEnginesBtn = app.buttons["Erase Engines"]
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
        let eraseActionsBtn = app.buttons["Erase Actions"]
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
        let engineTemplates = [
            "ChatGPT",
            "Claude",
            "DeepSeek",
            "Gemini",
            "Google",
            "Grok",
            "Kimi",
            "OpenClaw",
            "OpenCode",
            "Qwen",
            "X",
            "Z.ai",
            "llama.cpp",
            "oMLX",
            "Open WebUI"
        ]
        let expectedEngineCount = engineTemplates.count
        
        let addServiceBtn = app.descendants(matching: .any).matching(identifier: "Add Engine").firstMatch
        
        for name in engineTemplates {
            if !addServiceBtn.exists {
                 // Try finding it again if hierarchy shifted
                 _ = addServiceBtn.waitForExistence(timeout: 1.0)
            }
            addServiceBtn.click()
            
            // The Add Engine sheet opens; pick the template tile, then confirm.
            // Local templates sit below the sheet's fold, so the lazy grid
            // only builds their tiles once scrolling brings them into view.
            let templateTile = app.buttons["AddEngineTemplate-\(name)"]
            if !templateTile.waitForExistence(timeout: 2.0) {
                let sheetGrid = app.sheets.firstMatch.descendants(matching: .scrollView).firstMatch
                guard sheetGrid.waitForExistence(timeout: 2.0) else {
                    XCTFail("Could not find template tile '\(name)'")
                    return
                }
                for _ in 0..<4 where !templateTile.isHittable {
                    sheetGrid.scroll(byDeltaX: 0, deltaY: -300)
                    _ = templateTile.waitForExistence(timeout: 1.0)
                }
                guard templateTile.isHittable else {
                    XCTFail("Could not find template tile '\(name)'")
                    return
                }
            }
            templateTile.click()
            
            let confirmButton = app.buttons["AddEngineConfirm"]
            guard confirmButton.waitForExistence(timeout: 2.0) else {
                XCTFail("Confirm button should appear after selecting '\(name)'")
                return
            }
            confirmButton.click()
            XCTAssertTrue(confirmButton.waitForNonExistence(timeout: 2.0), "Sheet should close after adding '\(name)'")
        }
        XCTAssertEqual(app.outlines.firstMatch.outlineRows.count, expectedEngineCount, "Should have added all engine templates")
        
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
        
        // --- Step 4: Add All via Select All Not Added ---
        
        // Engines
        switchToSettingsTab("Engines")
        addServiceBtn.click()
        
        let selectNotAddedEngines = app.buttons["AddEngineSelectNotAdded"]
        XCTAssertTrue(selectNotAddedEngines.waitForExistence(timeout: 2.0), "Select All Not Added button (Engines) not found")
        selectNotAddedEngines.click()
        
        let confirmAllEngines = app.buttons["AddEngineConfirm"]
        XCTAssertTrue(confirmAllEngines.waitForExistence(timeout: 2.0), "Confirm button (Engines) not found")
        confirmAllEngines.click()
        XCTAssertTrue(confirmAllEngines.waitForNonExistence(timeout: 2.0), "Sheet should close after bulk add")
        
        XCTAssertEqual(app.outlines.firstMatch.outlineRows.count, expectedEngineCount, "Step 4: Should have all engine templates")
        
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

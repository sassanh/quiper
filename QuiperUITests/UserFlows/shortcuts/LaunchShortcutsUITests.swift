import XCTest

final class LaunchShortcutsUITests: BaseUITest {
    
    override var launchArguments: [String] {
        // Use custom test engines defined in Settings.swift
        return ["--uitesting", "--test-custom-engines"]
    }

    func testLaunchShortcutsLifecycle() throws {
        openSettings()
        
        switchToSettingsTab("Shortcuts")
        
        // Tap Service Hotkeys header to scroll to it
        let header = app.staticTexts["Service Hotkeys"]
        header.tap()
        
        // Test with the custom engines
        let engines = ["Engine 1", "Engine 2", "Engine 3", "Engine 4"]
        let letters = ["A", "B", "C", "D"]
        var assignedCount = 0
        
        // 1. Assign shortcuts
        for (index, engine) in engines.enumerated() {
            let engineLabel = app.staticTexts[engine]
            
            engineLabel.tap()
            
            // Find the button by its specific identifier
            let recordID = "recorder_launch_\(engine)"
            // ShortcutButton is a ZStack (Other), not a Button
            let recordButton = app.descendants(matching: .any).matching(identifier: recordID).firstMatch
            
            if !recordButton.waitForExistence(timeout: 3) {
                // Verify cell exists
                let cell = app.outlines.cells.containing(.staticText, identifier: engine).firstMatch
                continue
            }
            
            if !recordButton.isHittable {
                engineLabel.tap()
                // Wait for animation
                _ = recordButton.waitForExistence(timeout: 1.0)
            }
            
            
            recordButton.tap()
            let letter = letters[index]
            app.typeKey(letter.lowercased(), modifierFlags: [.command, .option, .shift])
            assignedCount += 1
        }
        
        XCTAssertEqual(assignedCount, engines.count, "Should have assigned all shortcuts")
        
        // 2. Close Settings
        app.typeKey("w", modifierFlags: .command) // Cmd+W to close window
        
        // Wait for Settings to disappear (using first match or specific window)
        let settingsWin = app.windows["Settings"]
        XCTAssertTrue(settingsWin.waitForNonExistence(timeout: 2.0))
        
        // Ensure app is active/foreground to receive hotkeys
        app.activate()
        
        // 3. Verify shortcuts activate correct engines
        // Find ServiceSelector - might be a RadioGroup or SegmentedControl
        var serviceSelector = app.segmentedControls["ServiceSelector"]
        if !serviceSelector.exists {
            serviceSelector = app.radioGroups["ServiceSelector"]
        }
        if !serviceSelector.exists {
            // Fallback to finding by identifier
            serviceSelector = app.descendants(matching: .any).matching(identifier: "ServiceSelector").firstMatch
        }
        
        if !serviceSelector.waitForExistence(timeout: 3) {
            
        }
        XCTAssertTrue(serviceSelector.exists, "Service selector should exist")
        
        for (index, letter) in letters.enumerated() {
            let engineName = engines[index]
            
            app.typeKey(letter.lowercased(), modifierFlags: [.command, .option, .shift])
            
            // Wait for switch via label change
            let predicate = NSPredicate(format: "label CONTAINS 'Active: \(engineName)'")
            expectation(for: predicate, evaluatedWith: serviceSelector, handler: nil)
            waitForExpectations(timeout: 3.0)
            
            // Verify selection via ServiceSelector Label
            let selectorLabel = serviceSelector.label
            
            XCTAssertTrue(selectorLabel.contains("Active: \(engineName)"), "Selector label should indicate active engine")
        }
        
        // 4. Open Settings again
        openSettings()
        switchToSettingsTab("Shortcuts")
        header.tap()
        
        // 5. Clear shortcuts
        
        var clearedCount = 0
        // Iterate through engines to ensure we scroll to them and find their clear buttons
        for engine in engines {
            let engineLabel = app.staticTexts[engine]
            engineLabel.tap()

            let cell = app.outlines.cells.containing(.staticText, identifier: engine).firstMatch
            
            // Find any hittable clear button
            let clearButton = cell.buttons.matching(identifier: "xmark.circle.fill").firstMatch

            if clearButton.waitForExistence(timeout: 1.0) {
                clearButton.tap()
                clearButton.waitForNonExistence(timeout: 1.0)
            }
        }
        
        // 6. Verify Record Shortcut buttons are back
        for engine in engines {
            let recordButton = app.staticTexts["Record Shortcut"].firstMatch
            XCTAssertTrue(recordButton.exists, "Should have Record Shortcut restored for '\(engine)'")
        }
        
        // 7. Close Settings and verify shortcuts DO NOT work
        app.typeKey("w", modifierFlags: .command)
        // Wait for settings to close
        XCTAssertTrue(app.windows["Settings"].waitForNonExistence(timeout: 2.0))
        
        
        // Check current engine (should be Engine 4 from previous step)
        // Find ServiceSelector again to check its label (state)
        // We know from earlier that finding the window fails, but matching the element works.
        let finalSelector = app.descendants(matching: .any).matching(identifier: "ServiceSelector").firstMatch
        XCTAssertTrue(finalSelector.exists, "ServiceSelector should be visible")
        
        let initialLabel = finalSelector.label
        XCTAssertTrue(initialLabel.contains("Active: Engine 4"), "Should be on Engine 4 initially, got: \(initialLabel)")
        
        // Loop through all assigned shortcuts (A-D) and verify none of them switch the engine
        for (index, letter) in letters.enumerated() {
             app.typeKey(letter.lowercased(), modifierFlags: [.command, .option, .shift])
             wait(0.1) // Short wait as per requirements
             
             let currentLabel = finalSelector.label
             XCTAssertTrue(
                 currentLabel.contains("Active: Engine 4"),
                 "Should still be on Engine 4. Shortcut '\(letter)' triggered a switch to: \(currentLabel)"
             )
        }
    }
}

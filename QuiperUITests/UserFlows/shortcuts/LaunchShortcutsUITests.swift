
import XCTest

final class LaunchShortcutsUITests: BaseUITest {
    
    override var launchArguments: [String] {
        // Use custom test engines defined in Settings.swift (Engine 1-4)
        return ["--uitesting", "--test-custom-engines", "--no-default-actions"]
    }

    /// Tests the lifecycle of launch shortcuts: Recording, Verification, Clearing.
    /// Refactored to match the robust patterns of NavigationShortcutsUITests.
    func testLaunchShortcutsLifecycle() throws {
        
        struct LaunchAssignment {
            let engineName: String
            let recorderId: String
            let letter: String
            let modifiers: XCUIElement.KeyModifierFlags
        }
        
        let assignments = [
            LaunchAssignment(engineName: "Engine 1", recorderId: "recorder_launch_Engine 1", letter: "a", modifiers: [.control, .option, .shift]),
            LaunchAssignment(engineName: "Engine 2", recorderId: "recorder_launch_Engine 2", letter: "b", modifiers: [.control, .option, .shift]),
            LaunchAssignment(engineName: "Engine 3", recorderId: "recorder_launch_Engine 3", letter: "c", modifiers: [.control, .option, .shift]),
            LaunchAssignment(engineName: "Engine 4", recorderId: "recorder_launch_Engine 4", letter: "d", modifiers: [.control, .option, .shift]),
        ]
        
        // ============================================================
        // SETUP
        // ============================================================
        openSettings()
        switchToSettingsTab("Shortcuts")
        
        let shortcutsList = app.descendants(matching: .any).matching(identifier: "ShortcutsList").firstMatch
        XCTAssertTrue(shortcutsList.waitForExistence(timeout: 2.0), "Shortcuts list not found")
        
        // ============================================================
        // 1. ASSIGN SHORTCUTS & VERIFY "SAVED" STATUS
        // ============================================================
        
        for assignment in assignments {
            let cell = app.outlines.cells.containing(.staticText, identifier: assignment.engineName).firstMatch

            // Find the record button WITHIN the cell
            let recordButton = cell.descendants(matching: .any).matching(identifier: assignment.recorderId).firstMatch
            recordButton.tap()
            app.typeKey(assignment.letter, modifierFlags: assignment.modifiers)

            // Verify "Saved" status message appears
            let savedMessage = cell.staticTexts["Saved"]
            XCTAssertTrue(savedMessage.waitForExistence(timeout: 1))
            XCTAssertTrue(savedMessage.waitForNonExistence(timeout: 1))
        }
        
        // ============================================================
        // 2. VERIFY ASSIGNMENTS (Functional Check)
        // ============================================================
        
        // Close Settings window to ensure global hotkeys work correctly (User feedback)
        app.typeKey("w", modifierFlags: .command)
        
        // Activate app to test global hotkeys (simulated keys go to active app)
        app.activate()
        // Wait for app to be ready
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5.0))
        
        // Identify Service Selector for verification
        // Note: App overlay must be visible. If hidden, type global toggle (Option+Space default) or check logic.
        // Assuming app is visible or hotkeys wake it.
        
        var serviceSelector = app.segmentedControls["ServiceSelector"]
        if !serviceSelector.exists { serviceSelector = app.radioGroups["ServiceSelector"] }
        if !serviceSelector.exists { serviceSelector = app.descendants(matching: .any).matching(identifier: "ServiceSelector").firstMatch }
        
        // Reorder assignments for verification: Test 2, 3, 4 first, then 1.
        // This ensures since we start at Engine 1, we verifying switching *away* then *back* to 1.
        
        var verificationOrder = assignments.filter { $0.engineName != "Engine 1" }
        if let engine1 = assignments.first(where: { $0.engineName == "Engine 1" }) {
            verificationOrder.append(engine1)
        }
        
        // Functional Verification Loop
        for assignment in verificationOrder {
            // Ensure app active and stable before typing
            app.activate()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5.0))
            
            // Type the assigned global hotkey
            app.typeKey(assignment.letter, modifierFlags: assignment.modifiers)
            
            // Verify the Engine Switch detected in UI
            let expectedEngineLabel = "Active: \(assignment.engineName)"
            let enginePred = NSPredicate(format: "label CONTAINS %@", expectedEngineLabel)
            let engineExp = XCTNSPredicateExpectation(predicate: enginePred, object: serviceSelector)
            
            if XCTWaiter.wait(for: [engineExp], timeout: 4.0) != .completed {
                 print("DEBUG: Verification failed. ServiceSelector Label: '\(serviceSelector.label)'")
                 XCTFail("Failed to switch to \(assignment.engineName) using global hotkey")
            }
        }
        
        // ============================================================
        // 3. CLEAR SHORTCUTS
        // ============================================================
        
        // Re-open settings for cleanup
        openSettings()
        switchToSettingsTab("Shortcuts")
        
        // No need to check shortcutsList.exists, we just opened it.
        
        for assignment in assignments {
            let cell = app.outlines.cells.containing(.staticText, identifier: assignment.engineName).firstMatch
            
            // The "xmark.circle.fill" is the clear button inside ShortcutButton
            // We need to find the specific one for this assignment
            // NavigationShortcutsUITests finds "xmark.circle.fill" inside the cell
            let clearButton = cell.buttons.matching(identifier: "xmark.circle.fill").firstMatch
            
            clearButton.tap()

            // Verify "Cleared" status message appears
            let clearedMessage = cell.staticTexts["Cleared"]
            XCTAssertTrue(clearedMessage.waitForExistence(timeout: 1))
            XCTAssertTrue(clearedMessage.waitForNonExistence(timeout: 1))
        }
        
        // ============================================================
        // 4. VERIFY CLEARED (Functional Check)
        // ============================================================
        
        // Close Settings window to ensure we are testing clean state (app focused)
        // User explicitly requested verifying "check shortcuts and see they are not working" with settings closed
        app.typeKey("w", modifierFlags: .command)
        
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5.0))
        
        // Capture current state
        let currentLabel = serviceSelector.label
        
        // Loop through ALL assignments to verify NONE work
        for assignment in assignments {
             // Type keys
             app.typeKey(assignment.letter, modifierFlags: assignment.modifiers)
             
             // Wait briefly to ensure NO change happens
             // If we were on Engine 1, and type Engine 2 key, checking it STAYS Engine 1 is valid.
             // If we were on Engine 1, and type Engine 1 key, it stays Engine 1 (which is correct but weak test).
             // But since we iterate ALL, we will inevitably test a switch-away case (e.g. Engine 2 key).
             
             wait(0.5)
             XCTAssertEqual(serviceSelector.label, currentLabel, "Global hotkey for \(assignment.engineName) triggered a switch after clearing!")
        }
    }
}

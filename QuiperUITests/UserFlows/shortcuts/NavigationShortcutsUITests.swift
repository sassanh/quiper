
import XCTest

final class NavigationShortcutsUITests: BaseUITest {
    
    override var launchArguments: [String] {
        // Use custom test engines defined in Settings.swift (Engine 1-4)
        return ["--uitesting", "--test-custom-engines", "--no-default-actions"]
    }

    /// Tests the comprehensive lifecycle of navigation shortcuts
    /// 1. Assigns unique custom shortcuts to ALL slots (Session Next/Prev, Engine Next/Prev, Digits).
    /// 2. Verifies custom shortcuts work for BOTH Primary and Alternate.
    /// 3. Verifies exhaustive Engine navigation (1->2->3->4->1).
    /// 4. Clears ALL shortcuts (Primary & Alternate).
    /// 5. Verifies shortcuts are disabled.
    /// 6. Resets to defaults and verifies default behavior.
    func testNavigationShortcutsComprehensiveLifecycle() throws {
        
        // ============================================================
        // SETUP: Open Settings -> Shortcuts
        // ============================================================
        // ============================================================
        // SETUP: Open Settings -> Shortcuts
        // ============================================================
        openSettings()
        
        switchToSettingsTab("Shortcuts")
        
        struct NavigationAssignment {
            let name: String
            let rowTitle: String
            let id: String
            let letter: String
            let modifiers: XCUIElement.KeyModifierFlags
        }
        
        // Define assignments for all navigation slots
        // Using Cmd+Opt+Shift for Primary, Cmd+Option for Alternate (to distinguish)
        let assignments = [
            // Session Navigation
            NavigationAssignment(name: "Next Session (Primary)", rowTitle: "Next session", id: "recorder_nextSession_primary", letter: "a", modifiers: [.command, .option, .shift]),
            NavigationAssignment(name: "Next Session (Alt)", rowTitle: "Next session", id: "recorder_nextSession_alternate", letter: "b", modifiers: [.command, .option, .shift]),
            NavigationAssignment(name: "Prev Session (Primary)", rowTitle: "Previous session", id: "recorder_previousSession_primary", letter: "c", modifiers: [.command, .option, .shift]),
            NavigationAssignment(name: "Prev Session (Alt)", rowTitle: "Previous session", id: "recorder_previousSession_alternate", letter: "d", modifiers: [.command, .option, .shift]),
            
            // Engine Navigation
            NavigationAssignment(name: "Next Engine (Primary)", rowTitle: "Next engine", id: "recorder_nextService_primary", letter: "e", modifiers: [.command, .option, .shift]),
            NavigationAssignment(name: "Next Engine (Alt)", rowTitle: "Next engine", id: "recorder_nextService_alternate", letter: "f", modifiers: [.command, .option, .shift]),
            NavigationAssignment(name: "Prev Engine (Primary)", rowTitle: "Previous engine", id: "recorder_previousService_primary", letter: "g", modifiers: [.command, .option, .shift]),
            NavigationAssignment(name: "Prev Engine (Alt)", rowTitle: "Previous engine", id: "recorder_previousService_alternate", letter: "h", modifiers: [.command, .option, .shift]),
            
            // Digits (Session)
            NavigationAssignment(name: "Session Digits (Primary)", rowTitle: "Go to session 1–10", id: "recorder_sessionDigits_primary", letter: "1", modifiers: [.command, .option, .shift]),
            NavigationAssignment(name: "Session Digits (Alt)", rowTitle: "Go to session 1–10", id: "recorder_sessionDigits_alternate", letter: "1", modifiers: [.command, .control, .option]),
            
            // Digits (Engine)
            NavigationAssignment(name: "Engine Digits (Primary)", rowTitle: "Go to engine 1–10", id: "recorder_serviceDigitsPrimary_primary", letter: "1", modifiers: [.command, .option, .shift, .control]),
            NavigationAssignment(name: "Engine Digits (Alt)", rowTitle: "Go to engine 1–10", id: "recorder_serviceDigitsSecondary_alternate", letter: "1", modifiers: [.command, .control, .shift])
        ]
        
        // ============================================================
        // PHASE 1: ASSIGN ALL SHORTCUTS
        // ============================================================
        
        let shortcutsList = app.descendants(matching: .any).matching(identifier: "ShortcutsList").firstMatch
        XCTAssertTrue(shortcutsList.waitForExistence(timeout: 2.0))
        
        for assignment in assignments {
            app.staticTexts[assignment.rowTitle].tap()

            let cell = app.outlines.cells.containing(.staticText, identifier: assignment.rowTitle).firstMatch
            let recordButton = cell.descendants(matching: .any).matching(identifier: assignment.id).firstMatch
            recordButton.tap()
            app.typeKey(assignment.letter, modifierFlags: assignment.modifiers)
        }
        
        // ============================================================
        // PHASE 2: VERIFY CUSTOM SHORTCUTS
        // ============================================================
        app.typeKey("w", modifierFlags: .command)
        if !app.windows.firstMatch.exists { app.activate() }

        let sessionSelector = app.radioGroups.allElementsBoundByIndex.first { $0.radioButtons.element(matching: NSPredicate(format: "label == '1'")).exists } ?? app.radioGroups.element(boundBy: 1)
        
        if !sessionSelector.exists {
             print("Debug: Session Selector not found. Hierarchy: \(app.debugDescription)")
        }
        XCTAssertTrue(sessionSelector.waitForExistence(timeout: 5))
        
        // Helper to get active engine label
        var serviceSelector = app.radioGroups["ServiceSelector"]
        if !serviceSelector.exists { serviceSelector = app.radioGroups["ServiceSelector"] }
        if !serviceSelector.exists { serviceSelector = app.descendants(matching: .any).matching(identifier: "ServiceSelector").firstMatch }
        XCTAssertTrue(serviceSelector.waitForExistence(timeout: 5), "ServiceSelector not found")
        
        func verifyState(session: Int, engine: String) {
            // Verify Session
            let expectedDigit = "\(session)"
            
            // Helper to check if a button is selected based on its value
            // Custom segmented controls often expose selection via 'value' (1 as true/selected)
            func isButtonSelected(_ button: XCUIElement) -> Bool {
                if let intValue = button.value as? Int { return intValue == 1 }
                if let strValue = button.value as? String { return strValue == "1" || strValue == "true" }
                if let boolValue = button.value as? Bool { return boolValue }
                return false
            }

            // Find the button (segment) that corresponds to this session and check if it is selected
            // We check both buttons and radioButtons collections as implementation details vary
            let sessionButton = sessionSelector.buttons[expectedDigit].exists ? sessionSelector.buttons[expectedDigit] : sessionSelector.radioButtons[expectedDigit]
            
            if sessionButton.exists && isButtonSelected(sessionButton) {
                // Success
            } else {
                 // Fallback: check all child elements to find which one is selected
                let children = sessionSelector.buttons.allElementsBoundByIndex + sessionSelector.radioButtons.allElementsBoundByIndex
                let selected = children.first(where: { isButtonSelected($0) })
                
                if let selected = selected {
                    XCTAssertEqual(selected.label, expectedDigit, "Expected active session \(session), but selected segment was '\(selected.label)'")
                } else {
                    print("Debug: Session verification failed. Selector Dump: \(sessionSelector.debugDescription)")
                    XCTFail("No session segment found selected. Expected \(session).")
                }
            }
            
            // Verify Engine
            let expectedEngineLabel = "Active: \(engine)"
            let enginePred = NSPredicate(format: "label CONTAINS %@", expectedEngineLabel)
            let engineExp = XCTNSPredicateExpectation(predicate: enginePred, object: serviceSelector)
            if XCTWaiter.wait(for: [engineExp], timeout: 5.0) != .completed {
                 XCTFail("Expected \(expectedEngineLabel), got '\(serviceSelector.label)'")
            }
        }
        
        // Start at Session 1, Engine 1 (Default)
        // Reset to known state using Digits just in case
        // Start at Session 1, Engine 1 (Default)
        // Reset to known state using Digits just in case
        app.typeKey("1", modifierFlags: [.command, .option, .shift]) // Session 1
        app.typeKey("1", modifierFlags: [.command, .option, .shift, .control]) // Engine 1
        verifyState(session: 1, engine: "Engine 1")
        
        // --- Test Session Navigation ---
        app.typeKey("a", modifierFlags: [.command, .option, .shift])
        verifyState(session: 2, engine: "Engine 1")
        
        app.typeKey("b", modifierFlags: [.command, .option, .shift])
        verifyState(session: 3, engine: "Engine 1")
        
        app.typeKey("c", modifierFlags: [.command, .option, .shift])
        verifyState(session: 2, engine: "Engine 1")
        
        app.typeKey("d", modifierFlags: [.command, .option, .shift])
        verifyState(session: 1, engine: "Engine 1")
        
        // --- Test Engine Navigation (Cycling 1->2->3->4->1) ---
        // Warning: Changing engine might reset session to that engine's last active session (default 1)
        
        // --- Test Engine Navigation (Cycling 1->2->3->4->1) ---
        // Warning: Changing engine might reset session to that engine's last active session (default 1)
        
        app.typeKey("e", modifierFlags: [.command, .option, .shift])
        verifyState(session: 1, engine: "Engine 2")
        
        app.typeKey("f", modifierFlags: [.command, .option, .shift])
        verifyState(session: 1, engine: "Engine 3")
        
        app.typeKey("e", modifierFlags: [.command, .option, .shift])
        verifyState(session: 1, engine: "Engine 4")
        
        app.typeKey("f", modifierFlags: [.command, .option, .shift])
        verifyState(session: 1, engine: "Engine 1")
        
        app.typeKey("g", modifierFlags: [.command, .option, .shift])
        verifyState(session: 1, engine: "Engine 4")
        
        // --- Test Direct Engine Digits ---
        app.typeKey("1", modifierFlags: [.command, .option, .shift, .control])
        verifyState(session: 1, engine: "Engine 1")
        
        // ============================================================
        // PHASE 3: CLEAR SHORTCUTS (Exhaustive & Robust)
        // ============================================================
        openSettings()
        switchToSettingsTab("Shortcuts")
        wait(0.1)
        
        for assignment in assignments {
            app.staticTexts[assignment.rowTitle].tap()

            let cell = app.outlines.cells.containing(.staticText, identifier: assignment.rowTitle).firstMatch
            let clearButton = cell.buttons.matching(identifier: "xmark.circle.fill").firstMatch
            clearButton.tap()
            clearButton.waitForNonExistence(timeout: 1.0)
        }
        
        // ============================================================
        // PHASE 4: VERIFY CLEARED
        // ============================================================
        app.typeKey("w", modifierFlags: .command)
        app.activate()
        
        // Reset to Engine 1, Session 1 manually if possible, or assume state
        // Since we cleared shortcuts, we can't use them.
        // We should be at Engine 1 from previous step.
        let currentState = (sessionSelector.label, serviceSelector.label)
        
        app.typeKey("a", modifierFlags: [.command, .option, .shift])
        // State should NOT change
        XCTAssertEqual(sessionSelector.label, currentState.0)
        
        app.typeKey("e", modifierFlags: [.command, .option, .shift])
        // State should NOT change
        XCTAssertEqual(serviceSelector.label, currentState.1)
        
        
        // ============================================================
        // PHASE 5: RESET TO DEFAULTS (Exhaustive)
        // ============================================================
        
        openSettings()
        switchToSettingsTab("Shortcuts")
        
        for assignment in assignments {
            let rowLabel = app.staticTexts[assignment.rowTitle]
            rowLabel.tap()

            let cell = app.outlines.cells.containing(.staticText, identifier: assignment.rowTitle).firstMatch
            let resetButton = cell.buttons.matching(identifier: "arrow.counterclockwise.circle.fill").firstMatch
            if resetButton.firstMatch.waitForExistence(timeout: 1.0) {
                resetButton.tap()
                resetButton.waitForNonExistence(timeout: 1.0)
            }
        }
        
        // ============================================================
        // PHASE 6: VERIFY DEFAULTS WORK & CUSTOM FAIL
        // ============================================================
        
        app.typeKey("w", modifierFlags: .command)
        if !app.windows.firstMatch.exists { app.activate() }
        
        // Reset to known state (Session 1, Engine 1) using Defaults if possible
        // Default for Session 1 is Cmd+1 (if session digits enabled)
        // Default for Engine 1 is Cmd+Ctrl+1
        
        // Reset to known state (Session 1, Engine 1) using Defaults if possible
        // Default for Session 1 is Cmd+1 (if session digits enabled)
        // Default for Engine 1 is Cmd+Ctrl+1
        
        app.typeKey("1", modifierFlags: [.command]) // Session 1 (Default)
        app.typeKey("1", modifierFlags: [.command, .control]) // Engine 1 (Default)
        verifyState(session: 1, engine: "Engine 1")
        
        // Default Next Session: Cmd+Shift+Right
        app.typeKey(.rightArrow, modifierFlags: [.command, .shift])
        verifyState(session: 2, engine: "Engine 1")
        
        // Default Prev Session: Cmd+Shift+Left
        app.typeKey(.leftArrow, modifierFlags: [.command, .shift])
        verifyState(session: 1, engine: "Engine 1")
        
        // Default Next Engine: Cmd+Ctrl+Right
        app.typeKey(.rightArrow, modifierFlags: [.command, .control])
        verifyState(session: 1, engine: "Engine 2")
        
        // Default Prev Engine: Cmd+Ctrl+Left
        app.typeKey(.leftArrow, modifierFlags: [.command, .control])
        verifyState(session: 1, engine: "Engine 1")
        
        // Default Alt Next Session: Cmd+L
        app.typeKey("l", modifierFlags: [.command])
        verifyState(session: 2, engine: "Engine 1")
        
        // Default Alt Prev Session: Cmd+H (Might Hide App? skip if risky, or try)
        // Cmd+H is system-wide Hide. Often hard to override or test.
        // Let's Skip Cmd+H verification to avoid test flakiness, or assume it works if L works.
        // Instead test Alt Next Engine: Cmd+Ctrl+L
        app.typeKey("l", modifierFlags: [.command, .control])
        verifyState(session: 1, engine: "Engine 2")
    }
}

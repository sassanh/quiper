
import XCTest

final class ShortcutConflictsUITests: BaseUITest {
    
    override var launchArguments: [String] {
        return ["--uitesting", "--no-default-actions"] 
    }

    func testShortcutConflictDetection() {
        openSettings()
        
        // 0. Set Global Launch Shortcut FIRST to test conflict later
        switchToSettingsTab("General")
        setGlobalLaunchShortcut(key: "l", modifiers: [.command, .shift])
        
        switchToSettingsTab("Shortcuts")
        
        // 1. Create Action A (First one)
        createCustomAction()
        let actionACell = getActionCell(index: 0)
        
        // Assign valid shortcut to A (Cmd+Shift+K)
        recordShortcut(cell: actionACell, key: "k", modifiers: [.command, .shift])
        
        // 2. Create Action B (Second one) to test against
        createCustomAction()
        let targetCell = getActionCell(index: 1) // Action B
        
        // 3. START EFFICIENT CHAINED CONFLICT TEST
        openRecorder(cell: targetCell)
        
        // A. Custom Action Conflict (Action A)
        verifyConflictInChain(key: "k", modifiers: [.command, .shift])
        
        // B. Global Launch Conflict
        verifyConflictInChain(key: "l", modifiers: [.command, .shift])

        // C. Hardcoded System Conflicts
        verifyConflictInChain(key: "i", modifiers: [.command, .option])
        
        verifyConflictInChain(key: "m", modifiers: [.command, .option])
        
        verifyConflictInChain(key: "=", modifiers: [.command])
        
        verifyConflictInChain(key: "-", modifiers: [.command])
        
        verifyConflictInChain(key: XCUIKeyboardKey.delete.rawValue, modifiers: [.command])

        verifyConflictInChain(key: "0", modifiers: [.command])

        verifyConflictInChain(key: ",", modifiers: [.command])
        
        verifyConflictInChain(key: "/", modifiers: [.command, .shift])
        
        verifyConflictInChain(key: "q", modifiers: [.command, .control])

        // D. App & Digit Conflicts
        verifySpecialConflictInChain(key: .rightArrow, modifiers: [.command, .shift])
        
        verifyConflictInChain(key: "1", modifiers: [.command])

        // 4. VERIFY TRUE NEGATIVE and Completion
        // Record a VALID shortcut (Cmd+I) - Should be accepted (TN for Inspector)
        app.typeKey("i", modifierFlags: [.command])
        
        // Recorder should close
        XCTAssertTrue(app.staticTexts["Press the new shortcut"].waitForNonExistence(timeout: 2.0), "Recorder did NOT close for valid shortcut!")
        
        // Verify Button Label updated
        let updatedCell = getActionCell(index: 1)
        let button = updatedCell.buttons.firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 2.0))
        
        // Wait for label to update from "Record Shortcut" or empty to "⌘I"
        // Retry loop for robustness
        var matched = false
        // Use predicate expectation instead of custom polling loop
        // Re-acquire cell and button
        let checkCell = getActionCell(index: 1)
        let btn = checkCell.buttons.firstMatch // Note: Earlier we changed this to descendants, verify what it should be
        // Wait, in previous task I updated lookups to descendants(matching: .any).
        // Let's check line 104 in viewed file.
        // It says: let finalBtn = finalCell.descendants(matching: .any).matching(identifier: "ShortcutRecorder").firstMatch
        // So I should use that lookup here.
        
        let recorderBtn = checkCell.descendants(matching: .any).matching(identifier: "ShortcutRecorder").firstMatch
        
        let exists = recorderBtn.waitForExistence(timeout: 2.0)
        
        if exists {
            let predicate = NSPredicate(format: "value == '⌘I' OR value == '⌘ I'")
            let expectation = XCTNSPredicateExpectation(predicate: predicate, object: recorderBtn)
            let result = XCTWaiter().wait(for: [expectation], timeout: 2.0)
            if result == .completed { matched = true }
        }
        
        // Final assertion
        // Final assertion
        let finalCell = getActionCell(index: 1)
        let finalBtn = finalCell.descendants(matching: .any).matching(identifier: "ShortcutRecorder").firstMatch
        let value = finalBtn.value as? String ?? ""
        // Normalize spaces (e.g. "⌘ I" vs "⌘I")
        // 5. Verify Self-Assignment (Idempotency)
        // Re-open recorder on the same cell
        let selfTestCell = getActionCell(index: 1)
        openRecorder(cell: selfTestCell)
        
        // Type the SAME shortcut (Cmd+I)
        app.typeKey("i", modifierFlags: [.command])
        
        // Assert Recorder Closes (Accepted)
        // If it was rejected, the overlay would remain with an error.
        XCTAssertTrue(app.staticTexts["Press the new shortcut"].waitForNonExistence(timeout: 2.0), "Re-assigning same shortcut failed (was rejected)!")
        
        // Final verify label is still ⌘I
        let selfTestBtn = selfTestCell.descendants(matching: .any).matching(identifier: "ShortcutRecorder").firstMatch
        XCTAssertTrue(selfTestBtn.waitForExistence(timeout: 2.0))
        
        let staticText = selfTestBtn.staticTexts.firstMatch
        XCTAssertTrue(staticText.waitForExistence(timeout: 1.0))
        // StaticText in dump showed 'value: ⌘ I', so use .value
        let label = selfTestBtn.staticTexts.firstMatch.value as? String ?? ""
        let selfVal = label.replacingOccurrences(of: " ", with: "")
        XCTAssertEqual(selfVal, "⌘I", "Label changed after self-assignment?")
    }
    
    func verifyConflictInChain(key: String, modifiers: XCUIElement.KeyModifierFlags) {
        verifyConflictInChainGeneric(input: key, modifiers: modifiers)
    }
    
    func verifySpecialConflictInChain(key: XCUIKeyboardKey, modifiers: XCUIElement.KeyModifierFlags) {
        verifyConflictInChainGeneric(input: key, modifiers: modifiers)
    }
    
    func verifyConflictInChainGeneric(input: Any, modifiers: XCUIElement.KeyModifierFlags) {
        if let str = input as? String {
            app.typeKey(str, modifierFlags: modifiers)
        } else if let key = input as? XCUIKeyboardKey {
            app.typeKey(key, modifierFlags: modifiers)
        }
        
        // 1. Assert Conflict Message Exists
        // Using Identifier for reliability
        XCTAssertTrue(app.staticTexts["ShortcutRecorderMessage"].waitForExistence(timeout: 2.0), "Conflict message missing for \(input)")
        
        // 2. Assert Recorder Stuck Open (Rejection)
        XCTAssertTrue(app.staticTexts["Press the new shortcut"].exists, "Recorder closed unexpectedly (Accepted conflict!) for \(input)")
    }
    
    func createCustomAction() {
        let addMenuBtn = app.toolbars.menuButtons["Add Action"]
        if addMenuBtn.exists {
            addMenuBtn.click()
        } else {
            app.toolbars.menuButtons.firstMatch.click()
        }
        
        let blankActionItem = app.menuItems["Blank Action"]
        XCTAssertTrue(blankActionItem.waitForExistence(timeout: 2.0))
        blankActionItem.click()
        
        // Wait for list update - find the new cell
        // Assuming it's added at the end or we can just look for the text field
        XCTAssertTrue(app.textFields["Action name"].waitForExistence(timeout: 2.0))
    }
    
    func getActionCell(index: Int) -> XCUIElement {
        let list = app.outlines["ShortcutsList"]
        XCTAssertTrue(list.waitForExistence(timeout: 2.0), "ShortcutsList not found")
        // Basic assumption: Index 0 is "Actions" header. Custom actions start at 1.
        return list.cells.element(boundBy: index + 1)
    }
    
    func recordShortcut(cell: XCUIElement, key: String, modifiers: XCUIElement.KeyModifierFlags) {
        XCTAssertTrue(cell.waitForExistence(timeout: 2.0), "Action cell does not exist")
        
        guard let btn = findRecordButton(in: cell) else {
            XCTFail("Could not find record button in cell")
            return
        }
        
        btn.click()
        
        let overlay = app.staticTexts["Press the new shortcut"]
        XCTAssertTrue(overlay.waitForExistence(timeout: 2.0), "Shortcut recording overlay did not appear")
        
        app.typeKey(key, modifierFlags: modifiers)
        XCTAssertTrue(overlay.waitForNonExistence(timeout: 2.0), "Overlay did not dismiss after recording")
    }
    
    func openRecorder(cell: XCUIElement) {
        guard let btn = findRecordButton(in: cell) else {
             XCTFail("Could not find record button")
             return
        }
        btn.click()
        XCTAssertTrue(app.staticTexts["Press the new shortcut"].waitForExistence(timeout: 2.0))
    }
    
    func cancelRecording() {
        if app.staticTexts["Press the new shortcut"].exists {
            app.typeKey(.escape, modifierFlags: [])
            XCTAssertTrue(app.staticTexts["Press the new shortcut"].waitForNonExistence(timeout: 2.0))
        }
    }
    
    func findRecordButton(in cell: XCUIElement) -> XCUIElement? {
        // Find by identifier "ShortcutRecorder" (default from ShortcutButton)
        return cell.descendants(matching: .any).matching(identifier: "ShortcutRecorder").firstMatch
    }
    
    func setGlobalLaunchShortcut(key: String, modifiers: XCUIElement.KeyModifierFlags) {
        let label = app.staticTexts["Show/Hide Quiper"]
        XCTAssertTrue(label.waitForExistence(timeout: 2.0))
        
        // Use the accessibility identifier added to SettingsView
        let btn = app.descendants(matching: .any).matching(identifier: "GlobalShortcutButton").firstMatch
        XCTAssertTrue(btn.waitForExistence(timeout: 2.0), "Global Shortcut Button not found")
        
        btn.click()
        
        // Check overlay
        guard app.staticTexts["Press the new shortcut"].waitForExistence(timeout: 2.0) else {
            XCTFail("Clicked button '\(btn.label)' but recording overlay didn't appear.")
            return
        }
        app.typeKey(key, modifierFlags: modifiers)
        
        // Verify it was assigned
        // Verify it was assigned
        // Re-query button value via StaticText child (Group value might be empty)
        let staticText = btn.staticTexts.firstMatch
        XCTAssertTrue(staticText.waitForExistence(timeout: 2.0))
        
        let predicate = NSPredicate(format: "value CONTAINS[c] %@", key) // StaticText value updates with shortcut
        expectation(for: predicate, evaluatedWith: staticText, handler: nil)
        waitForExpectations(timeout: 2.0)
    }
}

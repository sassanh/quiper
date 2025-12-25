import XCTest

final class CustomActionUITests: BaseUITest {

    override var launchArguments: [String] {
        // use --test-custom-engines to get 4 generic engines ("Engine 1"..."Engine 4")
        // use --no-default-actions to start with empty actions
        return ["--uitesting", "--test-custom-engines=2", "--no-default-actions"]
    }

    func testCustomActionLifecycle() throws {
        openSettings()
        
        // --- 1. Add Custom Action ---
        switchToSettingsTab("Shortcuts")
        
        let addActionButton = app.descendants(matching: .any).matching(identifier: "Add Action").firstMatch
        XCTAssertTrue(addActionButton.waitForExistence(timeout: 2.0), "Add Action button missing")
        addActionButton.click()
        
        let blankActionItem = app.menuItems["Blank Action"]
        if blankActionItem.waitForExistence(timeout: 2.0) {
            blankActionItem.click()
        } else {
             // Fallback: sometimes SwiftUI menus appear as buttons
             let blankActionButton = app.buttons["Blank Action"]
             if blankActionButton.waitForExistence(timeout: 2.0) {
                 blankActionButton.click()
             } else {
                 XCTFail("Could not find 'Blank Action' menu item or button")
             }
        }
        
        // Skip renaming to avoid focus issues with List interactions
        // Default name is "New Action" or "Action" (code says "New Action" for default action, or empty?)
        // ActionRow: Text(action.name.isEmpty ? "Action" : action.name)
        // Add Action logic: `CustomAction(name: "New Action", ...)`?
        // Let's verify default name. ActionsSettingsView:44 "New Action" (implied default if not empty)
        // Actually line 500: `let newService = Service(name: "New Service", ...)`
        // Settings.swift line 317 `CustomAction(name: "New Session")`
        // ActionsSettingsView logic for adding blank action:
        // `settings.customActions.append(CustomAction(name: "New Action", ...))`?
        // If I can't verifying the name, I'll assume "New Action".
        // If it's empty, it shows "Action".
        
        // Let's assume it's "New Action".
        let actionName = "New Action"
        XCTAssertTrue(app.textFields[actionName].waitForExistence(timeout: 2.0))
        
        // Record Shortcut
        // Use the same robust identifier for interaction
        let recorder = app.descendants(matching: .any).matching(identifier: "ShortcutRecorder").firstMatch
        XCTAssertTrue(recorder.waitForExistence(timeout: 2.0), "Recorder element not found")
        recorder.tap()
        
        // Cmd+Opt+Shift+K
        app.typeKey("k", modifierFlags: [.command, .option, .shift])
        
        // Wait for value to update to verify recording
        // We check that it's no longer the placeholder "Record Shortcut"
        let predicate = NSPredicate(format: "value != 'Record Shortcut'")
        let recorderExpectation = XCTNSPredicateExpectation(predicate: predicate, object: recorder)
        let result = XCTWaiter.wait(for: [recorderExpectation], timeout: 5.0)
        XCTAssertEqual(result, .completed, "Recorder value should have updated from 'Record Shortcut'")
        
        // --- 2. Implement Scripts ---
        switchToSettingsTab("Engines")
        
        func configureScript(engineName: String, script: String) {
            // Select Engine from sidebar
            let sidebarPredicate = NSPredicate(format: "label == %@", engineName)
            let engineLabel = app.staticTexts.matching(sidebarPredicate).firstMatch
            
            if engineLabel.exists && engineLabel.isHittable {
                engineLabel.click()
            } else {
                 let cell = app.outlines.cells.containing(.staticText, identifier: engineName).firstMatch
                 if cell.exists {
                     cell.click()
                 }
            }
            
            // Find "New Action" in the details list (Advanced Pane)
            let actionLabel = app.staticTexts["New Action"]
            XCTAssertTrue(actionLabel.waitForExistence(timeout: 2.0), "Action label in details missing for \(engineName)")
            actionLabel.click()
            
            // Type Script
            let editor = app.textViews.firstMatch
            XCTAssertTrue(editor.waitForExistence(timeout: 2.0), "Script editor missing")
            editor.click()
            editor.typeKey("a", modifierFlags: .command)
            editor.typeText(script)
        }
        
        // Engine 1: Sane script (updates DOM and Title for robust verification)
        configureScript(engineName: "Engine 1", script: "document.body.innerHTML = '<h1>SUCCESS</h1>'; document.title = 'SUCCESS';")
        
        // Engine 2: Error script
        configureScript(engineName: "Engine 2", script: "throw new Error('FAIL');")
        
        // --- 3. Verify ---
        // Close Settings
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(app.windows["Quiper Settings"].waitForNonExistence(timeout: 2.0))
        
        app.activate()
        // Wait for app to be ready and focused (Critical for CI hotkey delivery)
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5.0))
        
        // Select Engine 1
        selectService(at: 0)
        waitForEngine("Engine 1")
        
        // Use the validated WebView from waitForEngine
        let webView = app.webViews.firstMatch
        
        // Trigger Shortcut (Cmd+Opt+Shift+K)
        app.typeKey("k", modifierFlags: [.command, .option, .shift])
        
        // Robust verification: check accessibilityLabel (mapped to title 'SUCCESS')
        // Note: webview title update might be slightly delayed relative to JS execution, so use predicate wait
        let successPredicate = NSPredicate(format: "label == 'SUCCESS'")
        let successExpectation = XCTNSPredicateExpectation(predicate: successPredicate, object: webView)
        let successResult = XCTWaiter.wait(for: [successExpectation], timeout: 5.0)
        XCTAssertEqual(successResult, .completed, "WebView title did not update to 'SUCCESS'")
        
        // Select Engine 2
        selectService(at: 1)
        waitForEngine("Engine 2")
        
        // Verify success text is gone (new webview should have title 'Content 2')
        XCTAssertNotEqual(webView.label, "SUCCESS", "Engine 1 content verified persistent on Engine 2")
        
        // Verify failure caused a beep (via dedicated signal)
        // We expect the app to post a DistributedNotification "QuiperTestBeep"
        expectation(forNotification: NSNotification.Name("QuiperTestBeep"), object: nil, notificationCenter: DistributedNotificationCenter.default())
        
        // Trigger Shortcut (Should Error but not crash)
        app.typeKey("k", modifierFlags: [.command, .option, .shift])
        
        waitForExpectations(timeout: 5.0)
        
        // Switch back to Engine 1 to prove stability
        selectService(at: 0)
        
        // Wait for selector to update (confirms switch happened)
        let selector = serviceSelectorElement
        let activePredicate = NSPredicate(format: "label CONTAINS 'Active: Engine 1'")
        expectation(for: activePredicate, evaluatedWith: selector, handler: nil)
        waitForExpectations(timeout: 5.0)
        
        // Verify we are back on Engine 1 (Success script should still be loaded)
        let backPredicate = NSPredicate(format: "label == 'SUCCESS'")
        let backExpectation = XCTNSPredicateExpectation(predicate: backPredicate, object: webView)
        let backResult = XCTWaiter.wait(for: [backExpectation], timeout: 5.0)
        XCTAssertEqual(backResult, .completed, "Should be able to return to Engine 1 (showing SUCCESS)")
    }
    
    // Helper to robustly find the service selector
    var serviceSelectorElement: XCUIElement {
        let segmented = app.segmentedControls["ServiceSelector"]
        if segmented.exists { return segmented }
        
        let radio = app.radioGroups["ServiceSelector"]
        if radio.exists { return radio }
        
        return app.descendants(matching: .any).matching(identifier: "ServiceSelector").firstMatch
    }

    func selectService(at index: Int) {
        let selector = serviceSelectorElement
        XCTAssertTrue(selector.waitForExistence(timeout: 5.0), "ServiceSelector not found")
        
        // Use coordinate tapping as reliable fallback for custom segmented control
        // Assumes 2 engines as per --test-custom-engines=2
        let count = 2
        let segmentWidth = 1.0 / Double(count)
        let centerRatio = (Double(index) * segmentWidth) + (segmentWidth / 2.0)
        
        let coord = selector.coordinate(withNormalizedOffset: CGVector(dx: centerRatio, dy: 0.5))
        coord.tap()
    }
    
    func waitForEngine(_ name: String) {
        let selector = serviceSelectorElement
        
        // Wait for ServiceSelector to indicate active engine
        let predicate = NSPredicate(format: "label CONTAINS 'Active: \(name)'")
        expectation(for: predicate, evaluatedWith: selector, handler: nil)
        waitForExpectations(timeout: 5.0)
        
        // Wait for WebView content (Mapped to Accessibility Label via Title)
        // We injected <title>Content X</title>. The 'name' param is "Engine X".
        // We need to map "Engine X" -> "Content X" for verification.
        let contentLabel = name.replacingOccurrences(of: "Engine", with: "Content")
        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 5.0))
        
        // Robust verification: The app now maps document.title -> accessibilityLabel
        let titlePredicate = NSPredicate(format: "label == %@", contentLabel)
        let titleExpectation = XCTNSPredicateExpectation(predicate: titlePredicate, object: webView)
        let result = XCTWaiter.wait(for: [titleExpectation], timeout: 10.0)
        
        if result != .completed {
            // Fallback debugging
            print("DEBUG: WebView Label: '\(webView.label)', Expected: '\(contentLabel)'")
        }
        XCTAssertEqual(result, .completed, "WebView title (accessibilityLabel) did not update to '\(contentLabel)'")
    }
}

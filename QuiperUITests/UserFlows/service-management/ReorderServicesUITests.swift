import XCTest

final class ReorderServicesUITests: BaseUITest {
    
    override var launchArguments: [String] {
        // Use custom test engines defined in Settings.swift
        return ["--uitesting", "--test-custom-engines"]
    }

    func testComplexServiceReordering() throws {
        // Goal: Verify reordering with pre-loaded engines (Engine 1, Engine 2, Engine 3, Engine 4)
        // 1. Setup: Launch with --test-custom-engines (provides 4 engines)
        // 2. Drag Engine 3 (Bottom-ish) -> Engine 1 (Top). Order: 3, 1, 2, 4
        // 3. Drag Engine 2 (Bottom-ish) -> Engine 3 (Top). Order: 2, 3, 1, 4
        
        openSettings()
        
        // Custom engines should already be there
        let engine1 = "Engine 1"
        let engine2 = "Engine 2"
        let engine3 = "Engine 3"
        let engine4 = "Engine 4"
        
        XCTAssertTrue(app.staticTexts[engine1].waitForExistence(timeout: 2.0))
        XCTAssertTrue(app.staticTexts[engine2].waitForExistence(timeout: 2.0))
        XCTAssertTrue(app.staticTexts[engine3].waitForExistence(timeout: 2.0))
        XCTAssertTrue(app.staticTexts[engine4].waitForExistence(timeout: 2.0))
        
        // Initial Verification: 1, 2, 3, 4
        let e1 = app.staticTexts[engine1]
        let e2 = app.staticTexts[engine2]
        let e3 = app.staticTexts[engine3]
        let e4 = app.staticTexts[engine4]
        
        let f1 = e1.frame
        let f2 = e2.frame
        let f3 = e3.frame
        let f4 = e4.frame
        
        XCTAssertLessThan(f1.minY, f2.minY)
        XCTAssertLessThan(f2.minY, f3.minY)
        XCTAssertLessThan(f3.minY, f4.minY)
        
        // --- Step 1: Move Engine 3 to Top (above Engine 1) ---
        // --- Step 1: Move Engine 3 to Top (above Engine 1) ---
        dragService(source: engine3, target: engine1)
        
        // Expect: 3, 1, 2, 4
        // Engine 1 and 2 shift down.
        // Re-query
        let e1_s1 = app.staticTexts[engine1]
        let e2_s1 = app.staticTexts[engine2]
        let e3_s1 = app.staticTexts[engine3]
        let e4_s1 = app.staticTexts[engine4]
        XCTAssertTrue(e3_s1.waitForExistence(timeout: 2.0))
        
        // Wait for animation to settle
        _ = e3_s1.waitForExistence(timeout: 1.0)
        
        let f1_s1 = e1_s1.frame
        let f2_s1 = e2_s1.frame
        let f3_s1 = e3_s1.frame
        let f4_s1 = e4_s1.frame
        
        XCTAssertLessThan(f3_s1.minY, f1_s1.minY, "Engine 3 should be above Engine 1")
        XCTAssertLessThan(f1_s1.minY, f2_s1.minY, "Engine 1 should be above Engine 2")
        // Engine 4 stays at bottom
        XCTAssertLessThan(f2_s1.minY, f4_s1.minY, "Engine 2 should be above Engine 4")
        
        // --- Step 2: Move Engine 2 to Top (above Engine 3) ---
        // --- Step 2: Move Engine 2 to Top (above Engine 3) ---
        dragService(source: engine2, target: engine3)
        
        // Expect: 2, 3, 1, 4
        let e1_s2 = app.staticTexts[engine1]
        let e2_s2 = app.staticTexts[engine2]
        let e3_s2 = app.staticTexts[engine3]
        let e4_s2 = app.staticTexts[engine4]
        XCTAssertTrue(e2_s2.waitForExistence(timeout: 2.0))
        
        // Wait for animation
        _ = e2_s2.waitForExistence(timeout: 1.0)
        
        let f1_s2 = e1_s2.frame
        let f2_s2 = e2_s2.frame
        let f3_s2 = e3_s2.frame
        let f4_s2 = e4_s2.frame

        
        XCTAssertLessThan(f2_s2.minY, f3_s2.minY, "Engine 2 should be above Engine 3")
        XCTAssertLessThan(f3_s2.minY, f1_s2.minY, "Engine 3 should be above Engine 1")
        XCTAssertLessThan(f1_s2.minY, f4_s2.minY, "Engine 1 should be above Engine 4")
        
        XCTAssertLessThan(f1_s2.minY, f4_s2.minY, "Engine 1 should be above Engine 4")
        
        // --- Step 3: Verify Sync with Main Window ---
        
        // Close Settings Window
        app.typeKey("w", modifierFlags: .command)
        
        // Open Main Window (Overlay)
        // Replicating lookup logic from MainWindowReorderUITests
        var serviceSelector = app.segmentedControls["ServiceSelector"]
        if !serviceSelector.exists { serviceSelector = app.radioGroups["ServiceSelector"] }
        if !serviceSelector.exists { serviceSelector = app.descendants(matching: .any).matching(identifier: "ServiceSelector").firstMatch }
        
        if !serviceSelector.waitForExistence(timeout: 3.0) {
             app.typeKey(XCUIKeyboardKey.space, modifierFlags: [.command, .shift])
             
             if !serviceSelector.waitForExistence(timeout: 2.0) {
                 if let statusItem = app.statusItems.firstMatch as XCUIElement? {
                     statusItem.click()
                     let showMenuItem = app.menuItems["Show Quiper"]
                     if showMenuItem.waitForExistence(timeout: 2.0) { showMenuItem.click() }
                 }
             }
        }
        
        XCTAssertTrue(serviceSelector.waitForExistence(timeout: 5.0), "ServiceSelector should be visible")
        serviceSelector.click() // Ensure focus
        
        // Helper to verify index
        func verifySegment(index: Int, expectedLabel: String) {
            let width = serviceSelector.frame.width
            let segmentWidthFactor = 1.0 / 4.0
            let centerRatio = (Double(index) * segmentWidthFactor) + (segmentWidthFactor / 2.0)
            
            let coord = serviceSelector.coordinate(withNormalizedOffset: CGVector(dx: centerRatio, dy: 0.5))
            coord.tap()
            
            let predicate = NSPredicate(format: "label CONTAINS[c] %@", expectedLabel)
            let exp = XCTNSPredicateExpectation(predicate: predicate, object: serviceSelector)
            
            let result = XCTWaiter.wait(for: [exp], timeout: 2.0)
            if result != .completed {
                 XCTFail("Sync verification failed for Index \(index)")
            }
            XCTAssertTrue(serviceSelector.label.contains(expectedLabel), "Index \(index) should match \(expectedLabel)")
        }
        
        // Expected Order: 2, 3, 1, 4
        verifySegment(index: 0, expectedLabel: "Active: Engine 2")
        verifySegment(index: 1, expectedLabel: "Active: Engine 3")
        verifySegment(index: 2, expectedLabel: "Active: Engine 1")
        verifySegment(index: 3, expectedLabel: "Active: Engine 4")
    }
    
    // Helper for finding rows and dragging
    func dragService(source: String, target: String) {
        let sourceRow = app.outlines.firstMatch.outlineRows.containing(.staticText, identifier: source).firstMatch
        let targetRow = app.outlines.firstMatch.outlineRows.containing(.staticText, identifier: target).firstMatch
        
        XCTAssertTrue(sourceRow.exists, "Source row \(source) not found")
        XCTAssertTrue(targetRow.exists, "Target row \(target) not found")
        

        
        // Target the top part of the target row (inside the row, not outside)
        // dy: 0.1 is 10% from the top edge. 0.0 is top edge.
        // Trying to keep it strictly *inside* the target row's "upper half" which usually triggers "insert above".
        let startCoord = sourceRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let destCoord = targetRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
        
        startCoord.press(forDuration: 0.8, thenDragTo: destCoord)
    }
    
    func testServiceDeletion() throws {
        // Goal: Verify deletion of a pre-loaded engine (Engine 4)
        openSettings()
        
        // Verify Engine 4 exists
        let service = app.staticTexts["Engine 4"]
        XCTAssertTrue(service.waitForExistence(timeout: 2.0), "Engine 4 should exist")
        
        // Click on the service to select it
        service.click()
        
        // Look for delete button (trash icon) - wait for it to appear
        let deleteButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Delete' OR label CONTAINS[c] 'trash'")).firstMatch
        
        if deleteButton.waitForExistence(timeout: 2.0) {
            deleteButton.click()
            
            // Handle confirmation alert if it appears
            let deleteAlert = app.sheets.firstMatch
            if deleteAlert.waitForExistence(timeout: 2.0) {
                let confirmButton = deleteAlert.buttons["Delete"]
                if confirmButton.waitForExistence(timeout: 1.0) {
                    confirmButton.click()
                }
            }
            
            // Verify service is gone
            XCTAssertTrue(service.waitForNonExistence(timeout: 2.0), "Engine 4 should be deleted")
        } else {
            XCTFail("Delete button not found")
        }
    }
}

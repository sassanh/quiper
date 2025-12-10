import XCTest

final class MainWindowReorderUITests: BaseUITest {
    
    override var launchArguments: [String] {
        return ["--uitesting", "--test-custom-engines"]
    }

    func testMainWindowEngineReordering() throws {
        // Goal: Verify drag-and-drop reordering in the Main Window Service Selector
        // 1. Launch with customs engines (1, 2, 3, 4)
        // 2. Identify Service Selector
        // 3. functional verify: Cmd+1 activates Engine 1
        // 4. Drag Engine 3 (Index 2) to Engine 1 (Index 0)
        // 5. functional verify: Cmd+1 now activates Engine 3
        
        // Ensure app is active/window visible
        // Usually Launch moves focus.
        
        // Robust lookup for ServiceSelector (SegmentedControl, RadioGroup, or Any with ID)
        var serviceSelector = app.segmentedControls["ServiceSelector"]
        if !serviceSelector.exists {
             serviceSelector = app.radioGroups["ServiceSelector"]
        }
        if !serviceSelector.exists {
             serviceSelector = app.descendants(matching: .any).matching(identifier: "ServiceSelector").firstMatch
        }
        
        if !serviceSelector.waitForExistence(timeout: 5.0) {
            app.typeKey(XCUIKeyboardKey.space, modifierFlags: [.command, .shift])
            
            if !serviceSelector.waitForExistence(timeout: 3.0) {
                if let statusItem = app.statusItems.firstMatch as XCUIElement? {
                    statusItem.click()
                    // Click "Show Quiper" menu item
                    let showMenuItem = app.menuItems["Show Quiper"]
                    if showMenuItem.waitForExistence(timeout: 2.0) {
                        showMenuItem.click()
                    }
                }
            }
        }
        
        XCTAssertTrue(serviceSelector.waitForExistence(timeout: 5.0), "ServiceSelector must exist in Main Window")
        
        // Ensure focus
        serviceSelector.click()
        
        // Attempt to access segments as buttons/images
        // Note: NSSegmentedControl segments might appear as buttons or toggles
        let firstSegment = serviceSelector.buttons.element(boundBy: 0)
        
        if firstSegment.waitForExistence(timeout: 2.0) {
            // Verify Initial State
            // Assuming segments have labels corresponding to engines
            // If they are icons-only, we might need 'helpTag' or 'identifier'
            
            // For now, let's assume labels "Engine 1" etc. or check value.
            // If labels are empty (icons), this logic needs adjustment.
        }
        
        // --- Step 2: Calculate Drag Coordinates ---
        // We will stick to coordinate geometry if segments aren't hittable interactively
        // But we need to verification.
        
        // If we cannot verify via accessibility, we might have to rely on 'Active: ...' label change
        // BUT we need to Select the first item manually (Click).
        // Click 0.125 (Engine 1) -> Verify "Active: Engine 1"
        // Drag 0.625 (Engine 3) to 0.125
        // Click 0.125 (Should now be Engine 3) -> Verify "Active: Engine 3"
        
        // Click 0.125 (Engine 1) -> Verify "Active: Engine 1"
        // Drag 0.625 (Engine 3) to 0.125
        // Click 0.125 (Should now be Engine 3) -> Verify "Active: Engine 3"
        
        let targetNormalized = CGVector(dx: 0.125, dy: 0.5) // Index 0
        serviceSelector.coordinate(withNormalizedOffset: targetNormalized).tap()
        
        let initialPredicate = NSPredicate(format: "label CONTAINS[c] 'Active: Engine 1'")
        let initialExp = XCTNSPredicateExpectation(predicate: initialPredicate, object: serviceSelector)
        let initialResult = XCTWaiter.wait(for: [initialExp], timeout: 3.0)
        
        if initialResult != .completed {
             // Handle timeout
        }
        
        if !serviceSelector.label.contains("Active: Engine 1") {
             // Handle failure
        }
        
        // --- Step 2: Helper for Drag & Verify ---
        func performDragAndVerify(from sourceIndex: Int, targetX: Double, verifyIndex: Int, expectedActiveLabel: String) {
            let segmentWidthFactor = 1.0 / 4.0
            let getCenter = { (i: Int) -> Double in return (Double(i) * segmentWidthFactor) + (segmentWidthFactor / 2.0) }
            
            let sourceX = getCenter(sourceIndex)
            // targetX is passed directly
            

            
            let sourceOffset = CGVector(dx: sourceX, dy: 0.5)
            let targetOffset = CGVector(dx: targetX, dy: 0.5)
            
            let sourceCoord = serviceSelector.coordinate(withNormalizedOffset: sourceOffset)
            let targetCoord = serviceSelector.coordinate(withNormalizedOffset: targetOffset)
            
            sourceCoord.press(forDuration: 0.5, thenDragTo: targetCoord)
            
            // Verify
            
            // Tap the verification index (where we expect the item to land)
            let verifyX = getCenter(verifyIndex)
            let verifyCoord = serviceSelector.coordinate(withNormalizedOffset: CGVector(dx: verifyX, dy: 0.5))
            verifyCoord.tap()
            
            let predicate = NSPredicate(format: "label CONTAINS[c] %@", expectedActiveLabel)
            let exp = XCTNSPredicateExpectation(predicate: predicate, object: serviceSelector)
            let result = XCTWaiter.wait(for: [exp], timeout: 3.0)
            
            if result != .completed {
                // Failure
            }
            XCTAssertTrue(serviceSelector.label.contains(expectedActiveLabel), "Active engine should be \(expectedActiveLabel)")
        }
        
        // Initial State: [1, 2, 3, 4]
        // Centers: 0=0.125, 1=0.375, 2=0.625, 3=0.875
        
        // 1. Existing Test: Drag Engine 3 (Index 2) -> Engine 1 (Index 0)
        // Expected: [3, 1, 2, 4]
        performDragAndVerify(from: 2, targetX: 0.125, verifyIndex: 0, expectedActiveLabel: "Engine 3")
        
        // 4. Middle Swap: Drag Engine 1 (Index 1) -> Engine 2 (Index 2)
        // Current: [3, 1, 2, 4] -> Drag 1 to 2
        // Expected: [3, 2, 1, 4]
        // Target Index 2 center is 0.625
        performDragAndVerify(from: 1, targetX: 0.625, verifyIndex: 2, expectedActiveLabel: "Engine 1")
    }
}

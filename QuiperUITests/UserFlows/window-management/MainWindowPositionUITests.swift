import XCTest

final class MainWindowPositionUITests: BaseUITest {
    
    override var launchArguments: [String] {
        return ["--uitesting", "--no-default-services"]
    }

    func testMainWindowRepositioning() throws {
        // Goal: Verify that the Main Window can be dragged and repositioned
        
        if let statusItem = app.statusItems.firstMatch as XCUIElement? {
            statusItem.click()
            let showMenuItem = app.menuItems["Show Quiper"]
            if showMenuItem.waitForExistence(timeout: 2.0) { showMenuItem.click() }
        }
        
        // --- Step 1: Ensure Main Window is Visible (via ServiceSelector) ---
        // We trust ServiceSelector as a reliable indicator of the UI being present.
        var serviceSelector = app.segmentedControls["ServiceSelector"]
        if !serviceSelector.exists { serviceSelector = app.radioGroups["ServiceSelector"] }
        if !serviceSelector.exists { serviceSelector = app.descendants(matching: .any).matching(identifier: "ServiceSelector").firstMatch }
        
        XCTAssertTrue(serviceSelector.waitForExistence(timeout: 5.0), "ServiceSelector (and thus Main Window) must be visible")
        
        // --- Step 2: Identify the Window Object ---
        // Now that UI is up, find the window.
        // Try standard "Quiper" or first match.
        var mainWindow = app.windows["Quiper"]
        
        if !mainWindow.exists {
             // Fallback: Search top-level candidates
             let topLevel = app.children(matching: .any).allElementsBoundByIndex
             
             // Find element containing ServiceSelector (heuristic: frame intersection)
             let selectorFrame = serviceSelector.frame
             for element in topLevel {
                 // Skip small elements (menus etc) - arbitrary threshold
                 if element.frame.size.width > 200 && element.frame.size.height > 100 {
                     // Check intersection/containment
                     if element.frame.contains(selectorFrame) {
                         mainWindow = element
                         break
                     }
                 }
             }
        }
        
        if !mainWindow.exists {
            // Last ditch: Use the first window-like element found in previous loop or just firstMatch
             mainWindow = app.windows.firstMatch
        }
        
        XCTAssertTrue(mainWindow.exists, "Could not identify Main Window element.")
        
        // --- Step 3: Calculate Drag Source (Free Space between Selectors) ---
        // User Requirement: Drag from free space between Engine Selector and Session Selector.
        
        // serviceSelector is already defined and verified above.
        // Flexible lookup for SessionSelector
        var sessionSelector = app.radioGroups.allElementsBoundByIndex.first { $0.radioButtons.element(matching: NSPredicate(format: "label == '1'")).exists } ?? app.radioGroups.element(boundBy: 1)
        
        if !sessionSelector.waitForExistence(timeout: 5.0) {
             // Fail gracefully or try to proceed with heuristic? For now fail.
        }
        XCTAssertTrue(sessionSelector.exists, "SessionSelector missing")
        
        let serviceFrame = serviceSelector.frame
        let sessionFrame = sessionSelector.frame
        
        // Calculate midpoint between them
        let midX = (serviceFrame.midX + sessionFrame.midX) / 2.0
        let midY = (serviceFrame.midY + sessionFrame.midY) / 2.0
        
        // Calculate relative position within the window to avoid App-coordinate issues
        let initialFrame = mainWindow.frame
        let windowOrigin = initialFrame.origin
        let relX = midX - windowOrigin.x
        let relY = midY - windowOrigin.y
        
        // Create coordinate relative to the Window's top-left
        let startCoord = mainWindow.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0)).withOffset(CGVector(dx: relX, dy: relY))
        
        // Drag vector
        let dragVector = CGVector(dx: 150, dy: 100)
        let endCoord = startCoord.withOffset(dragVector)
        
        startCoord.press(forDuration: 0.5, thenDragTo: endCoord)
        
        // --- Step 5: Verify New Position ---
        let finalFrame = mainWindow.frame
        
        let dx = finalFrame.origin.x - initialFrame.origin.x
        let dy = finalFrame.origin.y - initialFrame.origin.y
        
        XCTAssertTrue(abs(dx) > 10 || abs(dy) > 10, "Window should have moved significantly")
        
        
        // --- Step 6: Move to Top-Center of Screen (Reset) ---
        
        // Target: Center X of screen, Top Y=100 (safely below menu bar)
        // We assume 1440x900 defaults or similar. Center approx 720.
        // Use finalFrame to calculate adjustment.
        
        let screenWidth = 1440.0
        let targetX = (screenWidth / 2) - (finalFrame.width / 2)
        let targetY = 100.0 // Vertically top-ish
        
        // Calculate required move to reach Top-Center
        let resetDeltaX = targetX - finalFrame.origin.x
        let resetDeltaY = targetY - finalFrame.origin.y
        
        // Use relative start coord again (same spot on window, even though window moved)
        let resetSourceCoord = mainWindow.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0)).withOffset(CGVector(dx: relX, dy: relY))
        let resetTargetCoord = resetSourceCoord.withOffset(CGVector(dx: resetDeltaX, dy: resetDeltaY))
        
        resetSourceCoord.press(forDuration: 0.5, thenDragTo: resetTargetCoord)
        
        // Verify
        let centeredFrame = mainWindow.frame
        // Loose assertion on Y being "top"
        XCTAssertLessThan(centeredFrame.minY, 200.0, "Window should be near the top")
    }
}

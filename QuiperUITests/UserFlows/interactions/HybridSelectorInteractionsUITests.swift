
import XCTest

final class HybridSelectorInteractionsUITests: BaseUITest {
    
    // Start in standard mode (Expanded) to test the resize to Collapsed
    override var launchArguments: [String] {
        return ["--uitesting", "--test-custom-engines", "--no-default-actions"]
    }

    func testComprehensiveSelectorInteractions() throws {
        if let statusItem = app.statusItems.firstMatch as XCUIElement? {
            statusItem.click()
            let showMenuItem = app.menuItems["Show Quiper"]
            if showMenuItem.waitForExistence(timeout: 2.0) { showMenuItem.click() }
        }
        
        // --- Identifying the Window Object ---
        // Helper to reliably find the main application window (ignoring tooltips/bars)
        func findMainWindow() -> XCUIElement {
            // 1. Try first match if it's large enough
            let first = app.windows.firstMatch
            if first.exists && first.frame.height > 200 { return first }
            
             // 2. Search all candidates (windows + top-level children)
             let candidates = app.windows.allElementsBoundByIndex + app.children(matching: .any).allElementsBoundByIndex
             for candidate in candidates {
                 // Lower threshold to accommodate 500px collapsed window
                 if candidate.frame.width >= 400 && candidate.frame.height > 300 {
                     print("Debug: Resolved Main Window with frame: \(candidate.frame)")
                     return candidate
                 }
             }
            // Fallback
            return first
        }
        
        let window = findMainWindow()
        if !window.waitForExistence(timeout: 5) {
            print("Debug: Window not found. Hierarchy: \(app.debugDescription)")
        }
        XCTAssertTrue(window.exists, "Main window not found")
        // Cache initial frame to avoid re-query issues in later phases
        let initialWindowFrame = window.frame
        XCTAssertTrue(initialWindowFrame.width > 800, "Window found is too small: \(initialWindowFrame)")
        
        // ============================================================
        // HELPERS
        // ============================================================
        
        // Use Global search for selectors as elements might not be direct children of the Window in XCUI hierarchy
        var sessionSelector: XCUIElement {
             // Find group containing any single digit label "^\\d+$"
             let globalCandidates = app.radioGroups.allElementsBoundByIndex + app.segmentedControls.allElementsBoundByIndex
             let digitPredicate = NSPredicate(format: "label MATCHES '^\\\\d+$'")
             
             if let match = globalCandidates.first(where: { group in
                 let children = group.buttons.allElementsBoundByIndex + group.radioButtons.allElementsBoundByIndex
                 return children.contains(where: { digitPredicate.evaluate(with: $0) })
             }) {
                 return match
             }
             XCTFail("Session selector not found")
             return app.radioGroups.firstMatch
        }
        
        var serviceSelector: XCUIElement {
             // Look for "Engine \d"
             let globalCandidates = app.radioGroups.allElementsBoundByIndex + app.segmentedControls.allElementsBoundByIndex
             let enginePredicate = NSPredicate(format: "label MATCHES '^Engine \\\\d+$'")

             if let match = globalCandidates.first(where: { group in
                 let children = group.buttons.allElementsBoundByIndex + group.radioButtons.allElementsBoundByIndex
                 return children.contains(where: { enginePredicate.evaluate(with: $0) })
             }) {
                 return match
             }
             XCTFail("Service selector not found")
             return app.radioGroups.firstMatch
        }

        func verifySession(_ expected: Int) {
            let sel = sessionSelector
            // Buttons are "1", "2", ...
            let btn = sel.radioButtons["\(expected)"].exists ? sel.radioButtons["\(expected)"] : sel.buttons["\(expected)"]
            
            XCTAssertTrue(btn.exists, "Session \(expected) button not found in \(sel.debugDescription)")
            
            // Wait for selected state (value=1 or selected=true)
            let selected = NSPredicate(format: "value == 1 OR selected == true")
            expectation(for: selected, evaluatedWith: btn, handler: nil)
            waitForExpectations(timeout: 2.0, handler: nil)
        }
        
        // ============================================================
        // PHASE 1: STATIC MODE INTERACTION
        // ============================================================
        print("PHASE 1: Static Mode")
        
        // 1. Click Session 2
        let sessionSel = sessionSelector
        let session2 = sessionSel.radioButtons["2"]

        XCTAssertTrue(session2.waitForExistence(timeout: 5))
        session2.click()
        verifySession(2)
        
        // 2. Click Service 2 (Index 1) - Change BOTH session and service
        let sSel = serviceSelector
        let service2 = sSel.buttons.element(boundBy: 1).exists ? sSel.buttons.element(boundBy: 1) : sSel.radioButtons.element(boundBy: 1)
        
        XCTAssertTrue(service2.waitForExistence(timeout: 2.0), "Service 2 button not found")
        service2.click()
        wait(0.5)
        // Verify service selection using class-level helper
        // Since session selections are PER-SERVICE, switching to a new service (Engine 2) 
        // should default to Session 1 initially, even if we were on Session 2 in the previous service.
        verifySession(1)
        // ============================================================
        // PHASE 2: RESIZE TO COLLAPSED
        // ============================================================
        print("PHASE 2: Resizing to Collapsed")
        
        // Use the CACHED initial frame to calculate coordinates relative to the window itself.
        // We re-resolve the window to ensure we have the correct element (not an overlay).
        let windowForDrag = findMainWindow()
        
        let winFrame = initialWindowFrame
        print("Debug: Using cached frame for resize calculation: \(winFrame)")
        
        // Anchor at Window Top-Left
        // coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0)) gives the top-left corner of the element
        let windowAnchor = windowForDrag.coordinate(withNormalizedOffset: .zero)
        
        // Target: Resize width from ~900 to ~500.
        // Strategy: Drag from Mid-Right Edge.
        
        // Start: Right edge (width), Vertically centered (height/2). Inset -1 to ensure we grab the window edge.
        let offsetX_Start = winFrame.width - 1
        let offsetY_Start = winFrame.height / 2.0
        
        // End: Drag LEFT to reduce width to 500. 
        // Target X offset = 500.
        let offsetX_End: CGFloat = 500.0
        let offsetY_End = offsetY_Start
        
        print("Debug: Window Anchor Drag from (\(offsetX_Start), \(offsetY_Start)) to (\(offsetX_End), \(offsetY_End))")
        
        let startCoord = windowAnchor.withOffset(CGVector(dx: offsetX_Start, dy: offsetY_Start))
        let endCoord = windowAnchor.withOffset(CGVector(dx: offsetX_End, dy: offsetY_End))
        
        // Execute Resize
        startCoord.press(forDuration: 0.5, thenDragTo: endCoord)
        
        // Re-find the window to check its new frame (cached frame is now old)
        // We use the same finding logic to ensure we get the main window, not overlay
        let newWindow = findMainWindow()
        print("Debug: New window frame: \(newWindow.frame)")
        
        XCTAssertLessThan(newWindow.frame.width, 600, "Window resize failed. Width is \(newWindow.frame.width)")
        
        // ============================================================
        // PHASE 3: COLLAPSED MODE INTERACTION (HOVER)
        // ============================================================
        print("PHASE 3: Collapsed Interactions")
        
        // 1. Session Switch via Hover
        // Session selector is positioned at the RIGHT (Top-Right). Active session is 1.
        // We use the element finder which looks for "1".
        let collapsedSessionSel = sessionSelector
        print("Debug: Session Selector Frame: \(collapsedSessionSel.frame)")
        
        collapsedSessionSel.hover()
        wait(0.5)
        
        // Click Session 3
        let session3Btn = app.radioButtons["3"]
        XCTAssertTrue(session3Btn.waitForExistence(timeout: 3.0), "Session 3 button not found after hover")
        session3Btn.click()

        wait(1)
        
        // 2. Service Switch via Hover
        // Service selector is at LEFT (Top-Left). Active service is Engine 1.
        let collapsedServiceSel = serviceSelector
        print("Debug: Service Selector Frame: \(collapsedServiceSel.frame)")
        
        collapsedServiceSel.hover()
        wait(0.5)
        
        // Click first service
        let engine1Btn = app.radioButtons["Engine 1"]
        XCTAssertTrue(engine1Btn.waitForExistence(timeout: 2.0), "Engine 1 button not found after hover on service selector")
        engine1Btn.click()
    }
}

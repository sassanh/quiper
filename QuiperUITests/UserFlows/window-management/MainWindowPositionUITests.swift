import XCTest

final class MainWindowPositionUITests: BaseUITest {
    
    override var launchArguments: [String] {
        return ["--uitesting", "--no-default-services"]
    }

    func testMainWindowRepositioning() throws {
        // Goal: Verify that the Main Window can be dragged and repositioned
        
        ensureWindowVisible()
        
        // --- Step 2: Identify the Window Object ---
        // Now that UI is up, find the window.
        // Try standard "Quiper" or first match.
        let mainWindow = app.windows["Quiper Overlay"]
        
        XCTAssertTrue(mainWindow.exists, "Could not identify Main Window element.")
        
        // --- Step 3: Calculate Drag Source (Free Space between Selectors) ---
        // User Requirement: Drag from free space between Engine Selector and Session Selector.
        
        // serviceSelector is already defined and verified above.
        // Flexible lookup for SessionSelector
        let sessionSelector = app.radioGroups["SessionSelector"]
        if !sessionSelector.waitForExistence(timeout: 5.0) {
             // Fail gracefully or try to proceed with heuristic? For now fail.
        }
        XCTAssertTrue(sessionSelector.exists, "SessionSelector missing")
        
        let serviceSelector = app.radioGroups["ServiceSelector"]
        if !serviceSelector.waitForExistence(timeout: 5.0) {
             // Fail gracefully or try to proceed with heuristic? For now fail.
        }
        XCTAssertTrue(serviceSelector.exists, "ServiceSelector missing")

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
        
        // Drag vector
        let dragVector = CGVector(dx: 150, dy: 100)

        // Synthesized drags are occasionally dropped on loaded CI runners:
        // retry until the frame reflects the drag instead of asserting on
        // a single gesture.
        var finalFrame = mainWindow.frame
        var didMove = false
        for _ in 0..<3 {
            dragOverlayWindow(mainWindow, relX: relX, relY: relY, by: dragVector)
            finalFrame = mainWindow.frame
            let dx = finalFrame.origin.x - initialFrame.origin.x
            let dy = finalFrame.origin.y - initialFrame.origin.y
            if abs(dx) > 10 || abs(dy) > 10 {
                didMove = true
                break
            }
        }

        // --- Step 5: Verify New Position ---
        XCTAssertTrue(didMove, "Window should have moved significantly")
        
        
        // --- Step 6: Move to Top-Center of Screen (Reset) ---
        
        // Target: Center X of screen, Top Y=100 (safely below menu bar)
        // We assume 1440x900 defaults or similar. Center approx 720.
        // Use finalFrame to calculate adjustment.

        let screenWidth = 1440.0
        let targetX = (screenWidth / 2) - (finalFrame.width / 2)
        let targetY = 100.0 // Vertically top-ish
        
        // Reset to top-center from a fresh frame each attempt: a single long
        // drag can fall short under load, so re-issue the remaining delta
        // until the window is near the top.
        for _ in 0..<4 {
            let current = mainWindow.frame
            if current.minY < 200.0 {
                break
            }
            let remaining = CGVector(
                dx: targetX - current.origin.x,
                dy: targetY - current.origin.y
            )
            dragOverlayWindow(mainWindow, relX: relX, relY: relY, by: remaining)
        }
        
        // Verify
        let centeredFrame = mainWindow.frame
        // Loose assertion on Y being "top"
        XCTAssertLessThan(centeredFrame.minY, 200.0, "Window should be near the top")
    }
}

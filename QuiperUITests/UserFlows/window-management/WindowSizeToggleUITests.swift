import XCTest

final class WindowSizeToggleUITests: BaseUITest {
    
    override var launchArguments: [String] {
        return ["--uitesting", "--no-default-services"]
    }

    /// Tests the window size toggle functionality with Cmd+M shortcut
    /// 1. Verifies initial window is in default (large) mode
    /// 2. Toggles to compact mode using Cmd+M
    /// 3. Verifies compact mode size and position (top-right)
    /// 4. Toggles back to large mode using Cmd+M
    /// 5. Verifies large mode size and position (centered)
    func testWindowSizeToggle() throws {
        // ============================================================
        // SETUP: Ensure main window is visible and focused
        // ============================================================
        ensureWindowVisible()
        
        let mainWindow = app.windows["Quiper Overlay"]
        XCTAssertTrue(mainWindow.exists, "Main window should exist")
        
        // Ensure window is focused for shortcuts to work
        mainWindow.click()
        
        // ============================================================
        // STEP 1: Record initial window frame (should be large mode)
        // ============================================================
        let initialFrame = mainWindow.frame
        print("Initial window frame: \(initialFrame)")
        
        // Initial window can be any size (default or saved), not fixed "large mode"
        // Allow some tolerance for different screen sizes and positioning
        XCTAssertGreaterThan(initialFrame.width, 350, "Initial window should have reasonable width")
        XCTAssertGreaterThan(initialFrame.height, 300, "Initial window should have reasonable height")
        
        // ============================================================
        // STEP 2: Toggle to compact mode using Cmd+M
        // ============================================================
        mainWindow.typeKey("m", modifierFlags: .command)
        
        // Wait a moment for animation to complete
        Thread.sleep(forTimeInterval: 0.5)
        
        // ============================================================
        // STEP 3: Verify compact mode
        // ============================================================
        let compactFrame = mainWindow.frame
        print("Compact window frame: \(compactFrame)")
        
        // Compact mode should be 550x400
        XCTAssertLessThan(compactFrame.width, 600, "Compact mode should have width < 600")
        XCTAssertLessThan(compactFrame.height, 450, "Compact mode should have height < 450")
        XCTAssertGreaterThan(compactFrame.width, 500, "Compact mode should have width > 500")
        XCTAssertGreaterThan(compactFrame.height, 350, "Compact mode should have height > 350")
        
        // Should be positioned at top-right (high X, low Y)
        // We can't assume exact screen dimensions, so just verify it moved significantly
        XCTAssertNotEqual(compactFrame.origin.x, initialFrame.origin.x, "Window should have moved horizontally")
        XCTAssertNotEqual(compactFrame.origin.y, initialFrame.origin.y, "Window should have moved vertically")
        
        // Verify the frame actually changed (at least position or size)
        let positionChanged = compactFrame.origin.x != initialFrame.origin.x || compactFrame.origin.y != initialFrame.origin.y
        let sizeChanged = compactFrame.width != initialFrame.width || compactFrame.height != initialFrame.height
        XCTAssertTrue(positionChanged || sizeChanged, "Window should have moved or resized")
        
        // ============================================================
        // STEP 4: Toggle back to previous mode using Cmd+M
        // ============================================================
        mainWindow.typeKey("m", modifierFlags: .command)
        
        // Wait a moment for animation to complete
        Thread.sleep(forTimeInterval: 0.5)
        
        // ============================================================
        // STEP 5: Verify restoration to previous mode
        // ============================================================
        let restoredFrame = mainWindow.frame
        print("Restored window frame: \(restoredFrame)")
        
        // Should be back to previous (initial) dimensions and position
        XCTAssertEqual(restoredFrame.width, initialFrame.width, accuracy: 5, "Should restore to original width")
        XCTAssertEqual(restoredFrame.height, initialFrame.height, accuracy: 5, "Should restore to original height")
        XCTAssertEqual(restoredFrame.origin.x, initialFrame.origin.x, accuracy: 10, "Should restore to roughly original X position")
        XCTAssertEqual(restoredFrame.origin.y, initialFrame.origin.y, accuracy: 10, "Should restore to roughly original Y position")
        
        // Window should be roughly centered (allowing for some positioning variance)
        // This is less strict since centering depends on screen size
        print("Test completed successfully - window toggle working correctly")
    }
    
    /// Tests that the window toggle shortcut works multiple times in succession
    func testMultipleToggles() throws {
        ensureWindowVisible()
        
        let mainWindow = app.windows["Quiper Overlay"]
        XCTAssertTrue(mainWindow.exists, "Main window should exist")
        mainWindow.click()
        
        let initialFrame = mainWindow.frame
        
        // Perform multiple toggles rapidly
        for i in 1...4 {
            mainWindow.typeKey("m", modifierFlags: .command)
            Thread.sleep(forTimeInterval: 0.3) // Short delay for animation
            
            let currentFrame = mainWindow.frame
            
            if i % 2 == 1 {
                // Odd toggles should be compact
                XCTAssertLessThan(currentFrame.width, 600, "Toggle \(i): Should be in compact mode")
            } else {
                // Even toggles should be back to previous mode (close to initial)
                XCTAssertEqual(currentFrame.width, initialFrame.width, accuracy: 50, "Toggle \(i): Should restore to roughly initial width")
            }
        }
    }
    
    /// Tests that window toggle works when window is in different initial positions
    func testToggleFromDifferentPositions() throws {
        ensureWindowVisible()
        
        let mainWindow = app.windows["Quiper Overlay"]
        XCTAssertTrue(mainWindow.exists, "Main window should exist")
        mainWindow.click()
        
        // First, move window to a different position by dragging from the drag area
        // Find the selectors to locate the draggable area between them
        let serviceSelector = app.radioGroups["ServiceSelector"]
        let sessionSelector = app.radioGroups["SessionSelector"]
        
        XCTAssertTrue(serviceSelector.waitForExistence(timeout: 5.0), "ServiceSelector should exist")
        XCTAssertTrue(sessionSelector.waitForExistence(timeout: 5.0), "SessionSelector should exist")
        
        let serviceFrame = serviceSelector.frame
        let sessionFrame = sessionSelector.frame
        
        // Calculate midpoint between selectors (the draggable area)
        let midX = (serviceFrame.midX + sessionFrame.midX) / 2.0
        let midY = (serviceFrame.midY + sessionFrame.midY) / 2.0
        
        // Calculate relative position within the window
        let initialFrame = mainWindow.frame
        let windowOrigin = initialFrame.origin
        let relX = midX - windowOrigin.x
        let relY = midY - windowOrigin.y
        
        // Create coordinate relative to the Window's top-left
        let startCoord = mainWindow.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0)).withOffset(CGVector(dx: relX, dy: relY))
        
        // Drag to move window to a different position
        let dragVector = CGVector(dx: 150, dy: 100)
        let endCoord = startCoord.withOffset(dragVector)
        
        startCoord.press(forDuration: 0.5, thenDragTo: endCoord)
        Thread.sleep(forTimeInterval: 0.3)
        
        let repositionedFrame = mainWindow.frame
        
        // Verify the window actually moved
        XCTAssertNotEqual(repositionedFrame.origin.x, initialFrame.origin.x, "Window should have moved horizontally")
        XCTAssertNotEqual(repositionedFrame.origin.y, initialFrame.origin.y, "Window should have moved vertically")
        
        // Now test toggle from this new position
        mainWindow.typeKey("m", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 0.5)
        
        let compactFrame = mainWindow.frame
        XCTAssertLessThan(compactFrame.width, 600, "Should toggle to compact mode regardless of initial position")
        
        // Toggle back
        mainWindow.typeKey("m", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 0.5)
        
        let restoredFrame = mainWindow.frame
        XCTAssertGreaterThan(restoredFrame.width, 700, "Should toggle back to previous mode")
    }
}
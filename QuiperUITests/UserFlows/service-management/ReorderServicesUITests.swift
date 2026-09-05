import XCTest

final class ReorderServicesUITests: BaseUITest {
    
    override var launchArguments: [String] {
        // Use custom test engines defined in Settings.swift
        return ["--uitesting", "--test-custom-engines=4"]
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
        
        // Scope to sidebar to avoid ambiguity with WebView content ("Engine 1" header)
        let sidebar = app.outlines.firstMatch
        XCTAssertTrue(sidebar.waitForExistence(timeout: 2.0))
        
        XCTAssertTrue(sidebar.staticTexts[engine1].waitForExistence(timeout: 2.0))
        XCTAssertTrue(sidebar.staticTexts[engine2].waitForExistence(timeout: 2.0))
        XCTAssertTrue(sidebar.staticTexts[engine3].waitForExistence(timeout: 2.0))
        XCTAssertTrue(sidebar.staticTexts[engine4].waitForExistence(timeout: 2.0))
        
        // Initial Verification: 1, 2, 3, 4
        let e1 = sidebar.staticTexts[engine1]
        let e2 = sidebar.staticTexts[engine2]
        let e3 = sidebar.staticTexts[engine3]
        let e4 = sidebar.staticTexts[engine4]
        
        let f1 = e1.frame
        let f2 = e2.frame
        let f3 = e3.frame
        let f4 = e4.frame
        
        XCTAssertLessThan(f1.minY, f2.minY)
        XCTAssertLessThan(f2.minY, f3.minY)
        XCTAssertLessThan(f3.minY, f4.minY)
        
        // --- Step 1: Move Engine 3 to Top (above Engine 1) ---
        // Expect: 3, 1, 2, 4
        // Engine 1 and 2 shift down.
        dragServiceAndWait(sidebar: sidebar, source: engine3, target: engine1,
                           expectedOrder: [engine3, engine1, engine2, engine4])
        
        // --- Step 2: Move Engine 2 to Top (above Engine 3) ---
        // Expect: 2, 3, 1, 4
        dragServiceAndWait(sidebar: sidebar, source: engine2, target: engine3,
                           expectedOrder: [engine2, engine3, engine1, engine4])
        
        // --- Step 3: Verify Sync with Main Window ---
        
        // Close Settings Window
        app.typeKey("w", modifierFlags: .command)
        
        // Open Main Window (Overlay)
        // Replicating lookup logic from MainWindowReorderUITests
        ensureWindowVisible()
        
        // Wait for transitions to settle
        _ = app.wait(for: .runningForeground, timeout: 2.0)
        
        let serviceSelector = app.radioGroups["ServiceSelector"]
        XCTAssertTrue(serviceSelector.waitForExistence(timeout: 5.0), "ServiceSelector should be visible")
        serviceSelector.click() // Ensure focus
        
        // Helper to verify index
        func verifySegment(index: Int, expectedLabel: String) {
            // Prefer direct element access if available
            let segments = serviceSelector.radioButtons
            if segments.count > index {
                segments.element(boundBy: index).click()
            } else {
                // Fallback to coordinate-based tap
                let segmentWidthFactor = 1.0 / 4.0
                let centerRatio = (Double(index) * segmentWidthFactor) + (segmentWidthFactor / 2.0)
                let coord = serviceSelector.coordinate(withNormalizedOffset: CGVector(dx: centerRatio, dy: 0.5))
                coord.tap()
            }
            
            if !waitForLabel(in: serviceSelector, contains: expectedLabel, timeout: 4.0) {
                // Retry tap once if it fails
                if segments.count > index {
                    segments.element(boundBy: index).click()
                } else {
                    let segmentWidthFactor = 1.0 / 4.0
                    let centerRatio = (Double(index) * segmentWidthFactor) + (segmentWidthFactor / 2.0)
                    serviceSelector.coordinate(withNormalizedOffset: CGVector(dx: centerRatio, dy: 0.5)).tap()
                }

                if !waitForLabel(in: serviceSelector, contains: expectedLabel, timeout: 2.0) {
                     XCTFail("Sync verification failed for Index \(index). Expected: \(expectedLabel), Found: \(serviceSelector.label)")
                }
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
        
        XCTAssertTrue(sourceRow.waitForExistence(timeout: 3.0), "Source row \(source) not found")
        XCTAssertTrue(targetRow.waitForExistence(timeout: 3.0), "Target row \(target) not found")
        
        let startCoord = sourceRow.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        let destCoord = targetRow.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.1))
        startCoord.tap()
        startCoord.click(forDuration: 0.8, thenDragTo: destCoord)
    }

    /// Current top-to-bottom engine order in the sidebar, or nil if any row is missing.
    /// Elements are re-queried on every call so frames are never read from a stale snapshot.
    func engineOrder(in sidebar: XCUIElement, names: [String]) -> [String]? {
        var rows: [(name: String, minY: CGFloat)] = []
        for name in names {
            let element = sidebar.staticTexts[name]
            guard element.exists else { return nil }
            rows.append((name, element.frame.minY))
        }
        return rows.sorted { $0.minY < $1.minY }.map { $0.name }
    }

    /// Drag source onto target, polling until the sidebar shows expectedOrder.
    /// A press-drag can silently fail to register a drop on a loaded CI runner,
    /// so the drag is retried until the order lands (or attempts run out).
    /// Asserts exactly once, at the end — never inside the retry loop.
    func dragServiceAndWait(sidebar: XCUIElement, source: String, target: String, expectedOrder: [String], attempts: Int = 3, timeoutPerAttempt: TimeInterval = 5.0) {
        for _ in 0..<attempts {
            if engineOrder(in: sidebar, names: expectedOrder) == expectedOrder { return }
            dragService(source: source, target: target)
            let deadline = Date().addingTimeInterval(timeoutPerAttempt)
            while Date() < deadline {
                wait(0.5)
                if engineOrder(in: sidebar, names: expectedOrder) == expectedOrder { return }
            }
        }
        XCTAssertEqual(engineOrder(in: sidebar, names: expectedOrder), expectedOrder,
                       "Sidebar order did not become \(expectedOrder) after dragging \(source) onto \(target)")
    }
    
    func testServiceDeletion() throws {
        // Goal: Verify deletion of a pre-loaded engine (Engine 4)
        openSettings()
        
        // Verify Engine 4 exists
        let sidebar = app.outlines.firstMatch
        let service = sidebar.staticTexts["Engine 4"]
        XCTAssertTrue(service.waitForExistence(timeout: 3.0), "Engine 4 should exist")
        
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

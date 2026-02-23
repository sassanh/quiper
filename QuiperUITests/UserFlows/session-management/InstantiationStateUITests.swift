import XCTest

final class InstantiationStateUITests: BaseUITest {

    override var launchArguments: [String] {
        return ["--uitesting", "--test-custom-engines", "--no-default-actions"]
    }

    // MARK: - Helpers

    private var mainWindow: XCUIElement {
        app.windows["Quiper Overlay"]
    }

    private var sessionSelector: XCUIElement {
        let byId = app.radioGroups["SessionSelector"]
        if byId.exists { return byId }
        return app.radioGroups.firstMatch
    }

    private var serviceSelector: XCUIElement {
        let candidates = app.radioGroups.allElementsBoundByIndex + app.segmentedControls.allElementsBoundByIndex
        // Service selector contains single-word engine labels like "Engine 1"
        let enginePredicate = NSPredicate(format: "label CONTAINS 'Engine'")
        if let match = candidates.first(where: { group in
            let children = group.buttons.allElementsBoundByIndex + group.radioButtons.allElementsBoundByIndex
            return children.contains(where: { enginePredicate.evaluate(with: $0) })
        }) { return match }
        return app.radioGroups["ServiceSelector"]
    }

    /// Returns the button element for a session number (1–9 map to labels "1"–"9", 10 maps to "0")
    private func sessionButton(_ number: Int) -> XCUIElement {
        let label = number == 10 ? "0" : "\(number)"
        let sel = sessionSelector
        let rb = sel.radioButtons[label]
        return rb.exists ? rb : sel.buttons[label]
    }

    /// Clicks a session segment and waits briefly for navigation to settle.
    private func clickSession(_ number: Int) {
        let btn = sessionButton(number)
        XCTAssertTrue(btn.waitForExistence(timeout: 3), "Session \(number) button not found")
        btn.click()
        wait(0.3)
    }

    /// Asserts that the given session number is selected in the session selector.
    private func verifyActiveSession(_ expected: Int, file: StaticString = #file, line: UInt = #line) {
        let btn = sessionButton(expected)
        XCTAssertTrue(btn.waitForExistence(timeout: 3), "Session \(expected) button not found", file: file, line: line)
        let isSelected = NSPredicate(format: "value == 1 OR selected == true")
        expectation(for: isSelected, evaluatedWith: btn)
        waitForExpectations(timeout: 3.0)
    }

    /// Sends Cmd+W to the main window and waits for navigation to settle.
    private func cmdW() {
        mainWindow.typeKey("w", modifierFlags: .command)
        wait(0.3)
    }

    // MARK: - Tests

    /// Cmd+W selects the nearest instantiated session to the LEFT (lower index).
    ///
    /// Scenario: Sessions 1, 2, 3 are all instantiated. Close Session 3.
    /// Expected: navigate to Session 2 (closest left neighbour).
    func testCmdWSelectsNearestLeftSession() throws {
        ensureWindowVisible()

        // Session 1 is auto-instantiated on launch. Instantiate 2 and 3 by visiting them.
        clickSession(2)
        clickSession(3)
        verifyActiveSession(3)

        cmdW()

        verifyActiveSession(2)
    }

    /// Cmd+W falls back to the RIGHT when no instantiated session exists to the left.
    ///
    /// Scenario: Launch (Session 1 instantiated). Jump directly to Session 3 (skipping 2).
    ///           Go back to Session 1. Close Session 1.
    /// Expected: navigate to Session 3 (closest right neighbour; Session 2 was never loaded).
    func testCmdWFallsBackRightWhenNothingLeft() throws {
        ensureWindowVisible()

        // Jump to Session 3 directly — Session 2 is never loaded.
        clickSession(3)
        verifyActiveSession(3)

        // Return to Session 1 and close it.
        clickSession(1)
        verifyActiveSession(1)

        cmdW()

        // Nothing instantiated to the left of Session 1; Session 3 is the nearest to the right.
        verifyActiveSession(3)
    }

    /// Cmd+W with only one instantiated session (and no others) falls back to session 1 (index 0).
    ///
    /// Scenario: Only Session 1 is instantiated at launch. Close it.
    /// Expected: stay on Session 1 (fallback index 0), now uninstantiated.
    func testCmdWFallbackWhenAloneInService() throws {
        ensureWindowVisible()

        // Only Session 1 is instantiated on a fresh launch.
        verifyActiveSession(1)

        cmdW()

        // No other sessions instantiated; fallback keeps focus on session index 0 (label "1").
        verifyActiveSession(1)
    }

    /// Cmd+W navigates to an adjacent service when the current service has no other
    /// instantiated sessions.
    ///
    /// Scenario: Engine 1 / Session 1 instantiated. Switch to Engine 2, visit Session 2.
    ///           Return to Engine 1 / Session 1. Close it.
    /// Expected: navigate to Engine 2 / Session 2 (nearest instantiated cross-service).
    func testCmdWNavigatesAcrossServices() throws {
        ensureWindowVisible()

        // Engine 1 / Session 1 is auto-instantiated.

        // Switch to Engine 2 and instantiate Session 2 there.
        let svcSel = serviceSelector
        XCTAssertTrue(svcSel.waitForExistence(timeout: 3), "Service selector not found")

        let engine2Btn = svcSel.buttons.element(boundBy: 1).exists
            ? svcSel.buttons.element(boundBy: 1)
            : svcSel.radioButtons.element(boundBy: 1)
        XCTAssertTrue(engine2Btn.waitForExistence(timeout: 3), "Engine 2 button not found")
        engine2Btn.click()
        wait(0.3)

        clickSession(2)
        verifyActiveSession(2)

        // Return to Engine 1 / Session 1 (only session instantiated there).
        let engine1Btn = svcSel.buttons.element(boundBy: 0).exists
            ? svcSel.buttons.element(boundBy: 0)
            : svcSel.radioButtons.element(boundBy: 0)
        XCTAssertTrue(engine1Btn.waitForExistence(timeout: 3), "Engine 1 button not found")
        engine1Btn.click()
        wait(0.3)
        verifyActiveSession(1)

        // Close Engine 1 / Session 1 — no other sessions instantiated in Engine 1.
        // Expects cross-service navigation to Engine 2 / Session 2.
        cmdW()

        verifyActiveSession(2)
    }
}

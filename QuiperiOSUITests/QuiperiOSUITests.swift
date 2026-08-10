import AppIntents
import XCTest

@MainActor
final class QuiperiOSUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launchEnvironment["QUIPER_UI_TESTING"] = "1"
        app.launch()

        XCTAssertTrue(app.buttons["session-0"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["needle first"].waitForExistence(timeout: 30))
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    func testSessionButtonsRemainReliablyTappable() {
        let first = app.buttons["session-0"]
        let second = app.buttons["session-1"]
        let third = app.buttons["session-2"]

        XCTAssertTrue(first.isHittable)
        XCTAssertTrue(second.isHittable)
        XCTAssertTrue(third.isHittable)
        XCTAssertEqual(first.value as? String, "active")

        second.tap()
        wait(forValue: "active", on: second)

        third.tap()
        wait(forValue: "active", on: third)

        first.tap()
        wait(forValue: "active", on: first)
    }

    func testFindBarSearchesNavigatesAndResets() {
        openFindBar()
        let field = app.textFields["find-field"]
        typeTextReliably("needle", into: field)

        wait(forLabel: "1 of 2", on: app.staticTexts["find-status"])
        app.buttons["Next match"].tap()
        wait(forLabel: "2 of 2", on: app.staticTexts["find-status"])
        app.buttons["Previous match"].tap()
        wait(forLabel: "1 of 2", on: app.staticTexts["find-status"])

        app.buttons["Close find"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 3))

        openFindBar()
        let reopenedField = app.textFields["find-field"]
        wait(forOneOfValues: ["needle", "needle "], on: reopenedField)
        typeTextReliably("missing", into: reopenedField)
    }

    func testNavigationRingDismissesKeyboard() {
        openFindBar()
        let field = app.textFields["find-field"]
        field.tap()
        field.typeText("needle")
        let ringButton = app.buttons["ui-test-open-ring"]
        wait(forValue: "find-focused", on: ringButton)

        ringButton.tap()

        let ring = app.descendants(matching: .any)["navigation-ring-overlay"]
        XCTAssertTrue(ring.waitForExistence(timeout: 10))
        wait(forValue: "find-unfocused", on: ringButton)
        XCTAssertTrue(app.descendants(matching: .any)["ring-session-1"].exists)
    }

    func testProtectionDisclosureExplainsExactBoundary() {
        app.buttons["actions-menu"].tap()
        let settings = app.buttons["Settings"]
        let engine = app.buttons["settings-engine-F0A38C27-2DB2-4922-9D52-0C94575CBA31"]
        XCTAssertTrue(tap(settings, until: engine))

        let editorNameIdentifier = "engine-edit-name-F0A38C27-2DB2-4922-9D52-0C94575CBA31"
        let editorName = app.textFields[editorNameIdentifier]
        XCTAssertTrue(tap(engine, until: editorName))

        let editor = app.collectionViews
            .containing(.textField, identifier: editorNameIdentifier)
            .firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10))

        let protect = app.buttons["protect-engine-F0A38C27-2DB2-4922-9D52-0C94575CBA31"]
        XCTAssertTrue(scrollToHittable(protect, in: editor))
        protect.tap()

        XCTAssertTrue(app.staticTexts["Encrypted by Quiper"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Website Data Is Isolated"].exists)
        XCTAssertTrue(app.staticTexts["What Remains Visible"].exists)
        XCTAssertTrue(app.staticTexts["Downloads Are Separate"].exists)
        XCTAssertTrue(app.staticTexts["No Recovery or Transfer"].exists)
    }

    private func openFindBar() {
        app.buttons["actions-menu"].tap()
        let findAction = app.buttons["Find in Page"]
        XCTAssertTrue(findAction.waitForExistence(timeout: 10))
        findAction.tap()
        XCTAssertTrue(app.textFields["find-field"].waitForExistence(timeout: 10))
    }

    private func tap(
        _ element: XCUIElement,
        until destination: XCUIElement,
        maximumAttempts: Int = 3
    ) -> Bool {
        for _ in 0..<maximumAttempts {
            if destination.exists { return true }
            guard waitForHittable(element, timeout: 5) else { continue }
            element.tap()
            if destination.waitForExistence(timeout: 5) { return true }
        }
        return destination.exists
    }

    private func waitForHittable(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND hittable == true"),
            object: element
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func scrollToHittable(
        _ element: XCUIElement,
        in form: XCUIElement,
        maximumSwipes: Int = 8
    ) -> Bool {
        guard form.waitForExistence(timeout: 10) else { return false }
        for _ in 0..<maximumSwipes {
            if element.exists, element.isHittable { return true }
            form.swipeUp()
        }
        return element.exists && element.isHittable
    }

    private func typeTextReliably(_ text: String, into field: XCUIElement) {
        let valueMissingFinalCharacter = String(text.dropLast())
        field.typeText(text)
        wait(forOneOfValues: [text, valueMissingFinalCharacter], on: field)
        if field.value as? String == valueMissingFinalCharacter,
           let finalCharacter = text.last {
            field.typeText(String(finalCharacter) + " ")
            wait(forOneOfValues: [text, text + " "], on: field)
        }
    }

    private func wait(
        forOneOfValues values: [String],
        on element: XCUIElement,
        timeout: TimeInterval = 15
    ) {
        let predicates = values.map { NSPredicate(format: "value == %@", $0) }
        let expectation = XCTNSPredicateExpectation(
            predicate: NSCompoundPredicate(orPredicateWithSubpredicates: predicates),
            object: element
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed)
    }

    private func wait(forValue value: String, on element: XCUIElement, timeout: TimeInterval = 15) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", value),
            object: element
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed)
    }

    private func wait(forLabel label: String, on element: XCUIElement, timeout: TimeInterval = 15) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", label),
            object: element
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed)
    }
}

@MainActor
final class QuiperiOSSecurityUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-protected-engine"]
        app.launchEnvironment["QUIPER_UI_TESTING"] = "1"
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    func testProtectedEngineUnlocksAndLocksWithoutExposingAWebViewWhileLocked() {
        let lockedTitle = app.staticTexts["UI Test Engine Is Locked"]
        XCTAssertTrue(lockedTitle.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["needle first"].exists)

        app.buttons["Unlock Engine"].tap()
        XCTAssertTrue(app.staticTexts["needle first"].waitForExistence(timeout: 10))

        app.buttons["actions-menu"].tap()
        let lock = app.buttons["Lock Engine"]
        XCTAssertTrue(lock.waitForExistence(timeout: 3))
        lock.tap()

        XCTAssertTrue(lockedTitle.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["needle first"].exists)
    }
}

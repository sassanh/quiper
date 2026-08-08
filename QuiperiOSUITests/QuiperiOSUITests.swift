import XCTest

@MainActor
final class QuiperiOSUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        XCTAssertTrue(app.buttons["session-0"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["needle first"].waitForExistence(timeout: 10))
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
        field.typeText("needle")

        wait(forLabel: "1 of 2", on: app.staticTexts["find-status"])
        app.buttons["Next match"].tap()
        wait(forLabel: "2 of 2", on: app.staticTexts["find-status"])
        app.buttons["Previous match"].tap()
        wait(forLabel: "1 of 2", on: app.staticTexts["find-status"])

        app.buttons["Close find"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 3))

        openFindBar()
        let reopenedField = app.textFields["find-field"]
        XCTAssertEqual(reopenedField.value as? String, "needle")
        reopenedField.typeText("missing")
        XCTAssertEqual(reopenedField.value as? String, "missing")
    }

    func testNavigationRingDismissesKeyboard() {
        openFindBar()
        let field = app.textFields["find-field"]
        field.typeText("needle")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))

        app.buttons["ui-test-open-ring"].tap()

        let ring = app.descendants(matching: .any)["navigation-ring-overlay"]
        XCTAssertTrue(ring.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["ring-session-1"].exists)
    }

    private func openFindBar() {
        app.buttons["actions-menu"].tap()
        let findAction = app.buttons["Find in Page"]
        XCTAssertTrue(findAction.waitForExistence(timeout: 3))
        findAction.tap()
        XCTAssertTrue(app.textFields["find-field"].waitForExistence(timeout: 3))
    }

    private func wait(forValue value: String, on element: XCUIElement) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", value),
            object: element
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
    }

    private func wait(forLabel label: String, on element: XCUIElement) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", label),
            object: element
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
    }
}

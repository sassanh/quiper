import XCTest
import AppKit
import Carbon
@testable import Quiper

@MainActor
final class LocationBarHUDTests: XCTestCase {

    // MARK: - URL Parsing

    func testNavigationURL_FullHTTPSURLPassesThrough() {
        let url = LocationBarHUDView.navigationURL(fromInput: "https://example.com/page?x=1#frag")
        XCTAssertEqual(url?.absoluteString, "https://example.com/page?x=1#frag")
    }

    func testNavigationURL_HTTPURLPassesThrough() {
        let url = LocationBarHUDView.navigationURL(fromInput: "http://example.com")
        XCTAssertEqual(url?.absoluteString, "http://example.com")
    }

    func testNavigationURL_BareDomainGetsHTTPSScheme() {
        let url = LocationBarHUDView.navigationURL(fromInput: "example.com")
        XCTAssertEqual(url?.absoluteString, "https://example.com")
    }

    func testNavigationURL_BareDomainWithPathGetsHTTPSScheme() {
        let url = LocationBarHUDView.navigationURL(fromInput: "example.com/chat/session")
        XCTAssertEqual(url?.absoluteString, "https://example.com/chat/session")
    }

    func testNavigationURL_LocalHostWithPortGetsHTTPS() {
        // "localhost:8080" parses with scheme "localhost" and no host, so it
        // must be rejected and re-parsed with an explicit https scheme.
        let url = LocationBarHUDView.navigationURL(fromInput: "localhost:8080/chat")
        XCTAssertEqual(url?.host, "localhost")
        XCTAssertEqual(url?.port, 8080)
        XCTAssertEqual(url?.scheme, "https")
    }

    func testNavigationURL_FileSchemePreserved() {
        let url = LocationBarHUDView.navigationURL(fromInput: "file:///tmp/page.html")
        XCTAssertEqual(url?.isFileURL, true)
        XCTAssertEqual(url?.path, "/tmp/page.html")
    }

    func testNavigationURL_AbsolutePathBecomesFileURL() {
        let url = LocationBarHUDView.navigationURL(fromInput: "/tmp/page.html")
        XCTAssertEqual(url?.isFileURL, true)
        XCTAssertEqual(url?.path, "/tmp/page.html")
    }

    func testNavigationURL_SpacesArePercentEncoded() {
        let url = LocationBarHUDView.navigationURL(fromInput: "https://example.com/a b")
        XCTAssertEqual(url?.absoluteString, "https://example.com/a%20b")
    }

    func testNavigationURL_TrimsWhitespace() {
        let url = LocationBarHUDView.navigationURL(fromInput: "  example.com  ")
        XCTAssertEqual(url?.absoluteString, "https://example.com")
    }

    func testNavigationURL_EmptyInputReturnsNil() {
        XCTAssertNil(LocationBarHUDView.navigationURL(fromInput: ""))
        XCTAssertNil(LocationBarHUDView.navigationURL(fromInput: "   \n\t "))
    }

    func testNavigationURL_UnparseableInputReturnsNil() {
        XCTAssertNil(LocationBarHUDView.navigationURL(fromInput: ":"))
        XCTAssertNil(LocationBarHUDView.navigationURL(fromInput: "!@#"))
    }

    // MARK: - Shortcut Wiring

    func testCommandShiftLShowsLocationBar() {
        let controller = makeController()
        defer { dismissLocationBar(controller) }

        let handled = controller.handleCommandShortcut(event: locationBarEvent())

        XCTAssertTrue(handled)
        let hud = controller.locationBarHUDView
        XCTAssertNotNil(hud)
        XCTAssertEqual(hud?.isHidden, false)
        XCTAssertNotNil(controller.locationBarHUDWindow)
    }

    func testCommandShiftLWithoutShiftIsNotHandled() {
        let controller = makeController()

        let handled = controller.handleCommandShortcut(
            event: locationBarEvent(modifiers: [.command])
        )

        XCTAssertFalse(handled)
        XCTAssertNil(controller.locationBarHUDWindow)
    }

    func testCommandShiftLTogglesLocationBarClosed() throws {
        let controller = makeController()
        defer { dismissLocationBar(controller) }

        XCTAssertTrue(controller.handleCommandShortcut(event: locationBarEvent()))
        let hud = try XCTUnwrap(controller.locationBarHUDView)
        XCTAssertEqual(hud.isHidden, false)

        XCTAssertTrue(controller.handleCommandShortcut(event: locationBarEvent()))
        XCTAssertTrue(hud.isHiding, "Second press must start dismissing the bar")
    }

    func testEscapeDismissesLocationBar() throws {
        let controller = makeController()
        defer { dismissLocationBar(controller) }

        XCTAssertTrue(controller.handleCommandShortcut(event: locationBarEvent()))
        let hud = try XCTUnwrap(controller.locationBarHUDView)

        let escape = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\u{1B}",
            charactersIgnoringModifiers: "\u{1B}",
            isARepeat: false,
            keyCode: UInt16(kVK_Escape)
        )!
        let swallowed = controller.handleLocalEvent(escape)

        XCTAssertNil(swallowed, "Escape must be swallowed while the bar is open")
        XCTAssertTrue(hud.isHiding, "Escape must start dismissing the bar")
    }

    // MARK: - Header Reveal in Auto-Hide Mode

    func testLocationBarRevealsHeaderWhenOpenedInHiddenMode() throws {
        let controller = makeController()
        defer { dismissLocationBar(controller) }
        enterHiddenTopBarMode(controller)

        let dragArea = try XCTUnwrap(controller.dragArea)
        XCTAssertEqual(dragArea.alphaValue, 0.0, accuracy: 0.01, "Header must start hidden")

        controller.showLocationBarHUD()

        XCTAssertTrue(controller.isHeaderForcedVisibleForLocationBar)
        XCTAssertEqual(dragArea.alphaValue, 1.0, accuracy: 0.01, "Opening the bar must reveal the toolbar")
    }

    func testLocationBarHidesHeaderAgainAfterDismissalInHiddenMode() throws {
        let controller = makeController()
        defer { dismissLocationBar(controller) }
        enterHiddenTopBarMode(controller)

        controller.showLocationBarHUD()
        // Second call mirrors the dismissal-completion finalize step.
        controller.hideLocationBarHUD()
        controller.hideLocationBarHUD()

        XCTAssertFalse(controller.isHeaderForcedVisibleForLocationBar)
        let dragArea = try XCTUnwrap(controller.dragArea)
        XCTAssertEqual(dragArea.alphaValue, 0.0, accuracy: 0.01, "Toolbar must hide again after dismissal")
    }

    func testDismissedBarDoesNotStealHeaderPinOnNextOpen() throws {
        // Regression test: opening the bar right after a previous close used to
        // release the fresh header pin because the dismissed HUD was still in
        // the isHidden state when windowDidResignKey ran mid-open.
        let controller = makeController()
        defer { dismissLocationBar(controller) }
        enterHiddenTopBarMode(controller)

        controller.showLocationBarHUD()
        controller.hideLocationBarHUD()
        controller.hideLocationBarHUD()

        controller.showLocationBarHUD()

        XCTAssertTrue(controller.isHeaderForcedVisibleForLocationBar, "Reopening must re-pin the header")
        let dragArea = try XCTUnwrap(controller.dragArea)
        XCTAssertEqual(dragArea.alphaValue, 1.0, accuracy: 0.01)
    }

    // MARK: - Helpers

    override func setUp() {
        super.setUp()
        Settings.shared.reset()
    }

    override func tearDown() {
        Settings.shared.reset()
        super.tearDown()
    }

    private func makeController() -> MainWindowController {
        let services = [
            Service(name: "Alpha", url: "https://alpha.test", focus_selector: "body"),
            Service(name: "Beta", url: "https://beta.test", focus_selector: "body")
        ]
        let controller = MainWindowController(services: services)
        controller.switchSession(to: 0)
        return controller
    }

    private func locationBarEvent(modifiers: NSEvent.ModifierFlags = [.command, .shift]) -> NSEvent {
        // Letter shortcuts are dispatched via charactersIgnoringModifiers, so
        // the synthetic event must carry the character like a real keypress.
        let character = modifiers.contains(.shift) ? "L" : "l"
        return NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: character,
            charactersIgnoringModifiers: character,
            isARepeat: false,
            keyCode: UInt16(kVK_ANSI_L)
        )!
    }

    private func enterHiddenTopBarMode(_ controller: MainWindowController) {
        controller.skipModalCheck = true
        Settings.shared.topBarVisibility = .hidden
        NotificationCenter.default.post(name: .topBarVisibilityChanged, object: nil)
    }

    /// Finalizes any in-flight dismissal and detaches leftover windows.
    private func dismissLocationBar(_ controller: MainWindowController) {
        controller.hideLocationBarHUD()
        controller.hideLocationBarHUD()
        controller.window?.orderOut(nil)
    }
}

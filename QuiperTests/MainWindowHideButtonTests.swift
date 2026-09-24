import XCTest
@testable import Quiper

@MainActor
final class MainWindowHideButtonTests: XCTestCase {

    /// The header's hide button must dismiss the overlay through the same
    /// `hide()` path as the shortcut: window gone, current tab untouched.
    func testHideButtonHidesTheOverlayWithoutClosingTheTab() {
        let controller = makeController()
        defer { controller.window?.orderOut(nil) }

        controller.show()
        guard let window = controller.window else {
            return XCTFail("The overlay window must exist")
        }
        XCTAssertTrue(window.isVisible, "Precondition: the overlay is on screen")

        let webViewBefore = controller.activeWebView
        XCTAssertNotNil(webViewBefore, "Precondition: a session tab is open")

        guard let hideButton = controller.hideWindowButton else {
            return XCTFail("The header must offer the hide button")
        }
        hideButton.performClick(nil)

        XCTAssertFalse(window.isVisible, "The hide button dismisses the overlay with the mouse")
        XCTAssertTrue(
            controller.activeWebView === webViewBefore,
            "Hiding keeps the current tab open instead of closing it"
        )
    }

    /// The hide button owns the header's trailing slot — right of the
    /// session-actions button whenever that shows — so it stays reachable
    /// in every header configuration.
    func testHideButtonOccupiesTheHeaderTrailingEdge() {
        let controller = makeController()
        defer { controller.window?.orderOut(nil) }

        guard let dragArea = controller.dragArea,
              let hideButton = controller.hideWindowButton else {
            return XCTFail("The header must exist")
        }

        let expectedInset: CGFloat = Settings.shared.topBarVisibility == .hidden ? 0 : 4
        XCTAssertFalse(hideButton.isHidden, "The hide button shows regardless of sessions or engine lock")
        XCTAssertEqual(
            hideButton.frame.maxX,
            dragArea.bounds.width - expectedInset,
            accuracy: 0.5,
            "The hide button sits flush against the header's trailing edge"
        )
        XCTAssertTrue(
            hideButton is WindowCloseButton,
            "The main window uses the same close-button implementation as popups"
        )
    }

    // MARK: - Helpers

    private func makeController() -> MainWindowController {
        let services = [
            Service(name: "Alpha", url: "https://alpha.test", focus_selector: "body"),
            Service(name: "Beta", url: "https://beta.test", focus_selector: "body")
        ]
        let controller = MainWindowController(services: services)
        controller.switchSession(to: 0)

        // The test host app launches its own real overlay at startup; order
        // out other visible windows so visibility asserts see only ours.
        NSApp.windows
            .filter { $0 !== controller.window && $0.isVisible }
            .forEach { $0.orderOut(nil) }

        return controller
    }
}

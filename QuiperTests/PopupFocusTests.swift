import XCTest
import AppKit
@testable import Quiper

/// The focus-loss dim judges each of the overlay's windows on its own:
/// only the key window renders clear while every other window — main or
/// popup — stays dimmed.
@MainActor
final class PopupFocusTests: XCTestCase {

    func testDimClearsOnlyTheKeyWindowAndDimsTheRest() throws {
        let originalFocusLossEffect = Settings.shared.focusLossEffectEnabled
        let originalOnboarding = Settings.shared.hasCompletedGhostOnboarding
        let originalServices = Settings.shared.services
        Settings.shared.focusLossEffectEnabled = true
        Settings.shared.hasCompletedGhostOnboarding = true
        defer {
            Settings.shared.focusLossEffectEnabled = originalFocusLossEffect
            Settings.shared.hasCompletedGhostOnboarding = originalOnboarding
            Settings.shared.services = originalServices
        }

        let services = [
            Service(name: "Alpha", url: "https://alpha.test", focus_selector: "body"),
            Service(name: "Beta", url: "https://beta.test", focus_selector: "body")
        ]
        Settings.shared.services = services
        let controller = MainWindowController(services: services)
        controller.switchSession(to: 0)
        defer { controller.window?.orderOut(nil) }

        // The focus gate must not be short-circuited by windows other tests
        // left on screen: both force `isOverlayInteractable` to false by design.
        AppDelegate.sharedSettingsWindow.orderOut(nil)
        UpdatePromptWindowController.shared.window?.orderOut(nil)

        controller.show()
        guard let manager = controller.webViewManager,
              let webView = controller.activeWebView else {
            XCTFail("The overlay's manager and tab must exist")
            return
        }

        manager.openLinkInNewWindow(URL(string: "about:blank")!, from: webView)
        guard let popupWindow = NSApp.windows.first(where: { manager.isPopupWindow($0) }) else {
            XCTFail("A managed popup window must open")
            return
        }
        defer { manager.removeWebView(for: services[0], sessionIndex: 0) }
        defer { popupWindow.close() }

        // Headless hosts can refuse key status; then there is no focus
        // transition to observe and nothing to verify.
        NSApp.activate(ignoringOtherApps: true)
        popupWindow.makeKeyAndOrderFront(nil)
        guard popupWindow.isKeyWindow, controller.window?.isKeyWindow == false else {
            throw XCTSkip("The test host refused key status to the popup")
        }

        // The resolver keeps its whole-overlay contract: Quiper counts as
        // in use while any of its own windows is key.
        XCTAssertEqual(
            controller.hasWindowFocus,
            NSApp.isActive,
            "A key popup must count as overlay focus like the main window"
        )

        // The popup's own key transition ran the shared focus gate with no
        // main-window event in between: the active popup renders clear under
        // an active host — dimmed under an inactive one, where nothing holds
        // usable focus — while the main window, not the active one, is
        // dimmed regardless of host state.
        XCTAssertEqual(
            manager.popupWebView(for: popupWindow)?.superview?.alphaValue,
            NSApp.isActive ? 1.0 : 0.5,
            "The active popup must render clear only while Quiper is usable"
        )
        XCTAssertEqual(
            controller.dragArea.subviews.first?.alphaValue,
            0.5,
            "The main window must stay dimmed while a popup is the active window"
        )

        // Focus returns to the main window: the two populations swap. The
        // main window follows whether Quiper is usable at all; the popup
        // stays dimmed because it is no longer the active window.
        controller.window?.makeKeyAndOrderFront(nil)
        XCTAssertEqual(
            controller.dragArea.subviews.first?.alphaValue,
            NSApp.isActive ? 1.0 : 0.5,
            "The active main window must render clear only while Quiper is usable"
        )
        XCTAssertEqual(
            manager.popupWebView(for: popupWindow)?.superview?.alphaValue,
            0.5,
            "A popup that lost key status must stay dimmed"
        )
    }
}

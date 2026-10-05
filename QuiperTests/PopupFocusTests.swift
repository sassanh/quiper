import XCTest
import AppKit
@testable import Quiper

/// The focus-loss dim judges each of the overlay's windows on its own:
/// only the key window renders clear; windows on the key window's
/// ancestor/descendant line take the standard dim; a window outside
/// that line renders dimmed harder and more transparent.
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

    /// The tier resolver reads the child-window tree, not creation or
    /// z-order: the key window renders clear, its ancestors and
    /// descendants take the standard dim, and a sibling subtree renders
    /// dimmed harder and more transparent than both.
    func testDimTiersFollowTheActiveWindowsLineInTheChildWindowTree() throws {
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
        // left on screen: both force the interactable check false by design.
        AppDelegate.sharedSettingsWindow.orderOut(nil)
        UpdatePromptWindowController.shared.window?.orderOut(nil)

        controller.show()
        guard let manager = controller.webViewManager,
              let webView = controller.activeWebView else {
            XCTFail("The overlay's manager and tab must exist")
            return
        }

        manager.openLinkInNewWindow(URL(string: "about:blank")!, from: webView)
        guard let firstPopup = NSApp.windows.first(where: { manager.isPopupWindow($0) }) else {
            XCTFail("A managed popup window must open")
            return
        }
        manager.openLinkInNewWindow(URL(string: "about:blank")!, from: webView)
        guard let secondPopup = NSApp.windows.first(where: { manager.isPopupWindow($0) && $0 !== firstPopup }) else {
            XCTFail("A second managed popup window must open")
            return
        }
        defer { firstPopup.close() }
        defer { secondPopup.close() }
        defer { manager.removeWebView(for: services[0], sessionIndex: 0) }

        // A host that refuses key status or stays inactive has no active
        // window to read a line from: everything takes the standard dim
        // by design, and there are no tiers to judge.
        NSApp.activate(ignoringOtherApps: true)
        firstPopup.makeKeyAndOrderFront(nil)
        guard firstPopup.isKeyWindow, NSApp.isActive else {
            throw XCTSkip("The test host refused key status or stayed inactive")
        }

        XCTAssertEqual(
            controller.focusLossLevel(for: firstPopup), .clear,
            "The active window must render clear"
        )
        XCTAssertEqual(
            controller.focusLossLevel(for: controller.window), .dimmed,
            "The overlay is the active popup's ancestor: the standard dim, not the deeper one"
        )
        XCTAssertEqual(
            controller.focusLossLevel(for: secondPopup), .deeplyDimmed,
            "A sibling subtree sits off the active window's line: dimmed harder"
        )
        XCTAssertEqual(
            manager.popupWebView(for: secondPopup)?.superview?.alphaValue, 0.3,
            "The deeper tier must reach the sibling popup's page, not just the resolver"
        )
    }

    /// Tiers derive from the identity of the key window, so a key move
    /// between two windows the overlay's own delegate events never see
    /// (HUD-like children of a popup and of the overlay) must still
    /// re-render the popup: on the key child's line it shows the standard
    /// dim, and once key moves to the other branch it drops to the deep
    /// tier — with no overlay or popup transition in between to drive
    /// the update.
    func testKeyMovesTheOverlayNeverSeesStillRederiveTheTiers() throws {
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
        // left on screen: both force the interactable check false by design.
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
        defer { popupWindow.close() }
        defer { manager.removeWebView(for: services[0], sessionIndex: 0) }

        // Two HUD-like children: one on the popup's branch, one on the
        // overlay's. Key moves between them involve neither the overlay
        // nor a popup itself.
        // Close must not free these while this function still holds them:
        // AppKit's default would release them on close (the double-release
        // WebViewManager's popup windows opt out of the same way).
        let popupChild = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 320, height: 80),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        popupChild.isReleasedWhenClosed = false
        popupWindow.addChildWindow(popupChild, ordered: .above)
        defer { popupChild.close() }

        let overlayChild = NSWindow(
            contentRect: NSRect(x: 100, y: 400, width: 320, height: 80),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        overlayChild.isReleasedWhenClosed = false
        controller.window?.addChildWindow(overlayChild, ordered: .above)
        defer { overlayChild.close() }

        // A host that refuses key status or stays inactive has no active
        // window to read a line from, and no transition to observe.
        NSApp.activate(ignoringOtherApps: true)
        popupChild.makeKeyAndOrderFront(nil)
        guard popupChild.isKeyWindow, NSApp.isActive else {
            throw XCTSkip("The test host refused key status or stayed inactive")
        }

        XCTAssertEqual(
            manager.popupWebView(for: popupWindow)?.superview?.alphaValue, 0.5,
            "The popup is the key child's ancestor: the standard dim"
        )

        // Key moves to the overlay's branch: the popup falls off the active
        // window's line and must drop to the deep tier, even though neither
        // the overlay nor any popup changed key status in this move.
        overlayChild.makeKeyAndOrderFront(nil)
        guard overlayChild.isKeyWindow else {
            throw XCTSkip("The test host refused key status to the overlay's child")
        }

        XCTAssertEqual(
            manager.popupWebView(for: popupWindow)?.superview?.alphaValue, 0.3,
            "A key move the overlay's delegate never sees must still re-render the popup's tier"
        )
    }
}

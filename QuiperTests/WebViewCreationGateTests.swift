import XCTest
import AppKit
import WebKit
@testable import Quiper

/// Guarantees of the single creation gate and shared teardown introduced to
/// make popup webviews first-class managed webviews.
@MainActor
final class WebViewCreationGateTests: XCTestCase {
    // WebViewManager holds its container weakly; the test must retain it.
    private var liveContainers: [NSView] = []
    private var liveWindows: [NSWindow] = []

    private func makeService() -> Service {
        Service(name: "Creation Gate Engine", url: "https://example.com", focus_selector: "input")
    }

    private func makeHostWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 800, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        liveWindows.append(window)
        return window
    }

    private func makeManager(with service: Service, in window: NSWindow) -> WebViewManager {
        let originalServices = Settings.shared.services
        addTeardownBlock {
            Settings.shared.services = originalServices
        }
        Settings.shared.services = [service]
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        liveContainers.append(container)
        window.contentView = container
        let manager = WebViewManager(containerView: container)
        manager.updateServices([service])
        return manager
    }

    private func makeSession(
        with service: Service,
        in window: NSWindow,
        isQuiperPrivate: Bool = false
    ) -> (manager: WebViewManager, sessionWebView: WKWebView) {
        let manager = makeManager(with: service, in: window)
        let sessionWebView = manager.getOrCreateWebView(
            for: service,
            sessionIndex: 0,
            dragArea: nil,
            loadImmediately: false,
            isQuiperPrivate: isQuiperPrivate
        )
        return (manager, sessionWebView)
    }

    private func openPopup(from manager: WebViewManager) -> (window: NSWindow, webView: WKWebView)? {
        guard let session = manager.webviewsByID.first?.value.first?.value else { return nil }
        manager.openLinkInNewWindow(URL(string: "about:blank")!, from: session)
        guard let popupWindow = NSApp.windows.first(where: { manager.isPopupWindow($0) }),
              let popupWebView = manager.popupWebView(for: popupWindow) else { return nil }
        return (popupWindow, popupWebView)
    }

    func testPopupIsCreatedThroughTheSameGateAsSessionTabs() {
        let service = makeService()
        let window = makeHostWindow()
        let (manager, sessionWebView) = makeSession(with: service, in: window)
        defer {
            manager.removeWebView(for: service, sessionIndex: 0)
            window.close()
        }

        guard let (popupWindow, popupWebView) = openPopup(from: manager) else {
            XCTFail("Opening a link in a new window must create a managed popup")
            return
        }
        defer { popupWindow.close() }

        XCTAssertTrue(
            popupWebView is ContextMenuWebView,
            "Popups must carry the context-menu subclass like session tabs"
        )
        XCTAssertNotNil(popupWebView.customUserAgent, "Popups must use the shared user agent")
        XCTAssertEqual(popupWebView.pageZoom, sessionWebView.pageZoom, "Popups open at the engine's current zoom")
        XCTAssertTrue(
            popupWebView.configuration.userContentController !== sessionWebView.configuration.userContentController,
            "Every managed webview owns its content controller so teardown cannot cross into another webview"
        )

        let sessionScripts = sessionWebView.configuration.userContentController.userScripts.map(\.source)
        let popupScripts = popupWebView.configuration.userContentController.userScripts.map(\.source)
        XCTAssertFalse(popupScripts.isEmpty, "Non-ephemeral popups receive the engine scripts")
        XCTAssertEqual(
            popupScripts.count,
            sessionScripts.count,
            "The gate installs the identical script set on tabs and popups"
        )
        XCTAssertTrue(
            popupScripts.contains { $0.contains("quiperNotification") },
            "The notification bridge installs for popups exactly as it does for tabs"
        )

        let membership = manager.findServiceAndSession(for: popupWebView)
        XCTAssertEqual(membership?.0.id, service.id, "Popup identity resolves to the owning engine")
        XCTAssertEqual(membership?.1, 0, "Popup identity resolves to the owning session")
        XCTAssertTrue(
            manager.webViewAllowsPageSelectorSuggest(popupWebView),
            "Selector-suggest gates on session membership, which now covers popups"
        )
    }

    func testClosingPopupUnregistersItAndLeavesOpenerScriptsIntact() {
        let service = makeService()
        let window = makeHostWindow()
        let (manager, sessionWebView) = makeSession(with: service, in: window)
        defer {
            manager.removeWebView(for: service, sessionIndex: 0)
            window.close()
        }

        let openerScriptsBefore = sessionWebView.configuration.userContentController.userScripts.map(\.source)
        guard let (popupWindow, popupWebView) = openPopup(from: manager) else {
            XCTFail("A popup must exist before it can be closed")
            return
        }

        popupWindow.close()

        let openerScriptsAfter = sessionWebView.configuration.userContentController.userScripts.map(\.source)
        XCTAssertEqual(
            openerScriptsBefore,
            openerScriptsAfter,
            "Closing a popup must never strip the opener tab's injected scripts"
        )
        XCTAssertFalse(manager.isPopupWindow(popupWindow), "Closing the popup unregisters its window")
        XCTAssertNil(
            manager.findServiceAndSession(for: popupWebView),
            "A closed popup has no session membership"
        )
    }

    func testPopupOfEphemeralTabStaysMarkerFree() {
        let service = makeService()
        let window = makeHostWindow()
        let (manager, sessionWebView) = makeSession(with: service, in: window, isQuiperPrivate: true)
        defer {
            manager.removeWebView(for: service, sessionIndex: 0)
            window.close()
        }

        XCTAssertTrue(
            sessionWebView.configuration.userContentController.userScripts.isEmpty,
            "Precondition: the ephemeral session itself carries no scripts"
        )
        guard let (popupWindow, popupWebView) = openPopup(from: manager) else {
            XCTFail("An ephemeral tab must still be able to open a managed popup")
            return
        }
        defer { popupWindow.close() }

        XCTAssertTrue(
            popupWebView.configuration.userContentController.userScripts.isEmpty,
            "A popup owned by an ephemeral tab stays marker-free through the same gate branch"
        )
    }

    func testSessionRecreationAfterTeardownKeepsObservationBalanced() {
        let service = makeService()
        let window = makeHostWindow()
        let manager = makeManager(with: service, in: window)
        defer { window.close() }

        _ = manager.getOrCreateWebView(
            for: service,
            sessionIndex: 0,
            dragArea: nil,
            loadImmediately: false
        )
        manager.removeWebView(for: service, sessionIndex: 0)

        let recreated = manager.getOrCreateWebView(
            for: service,
            sessionIndex: 0,
            dragArea: nil,
            loadImmediately: false
        )
        defer { manager.removeWebView(for: service, sessionIndex: 0) }

        XCTAssertNotNil(
            manager.findServiceAndSession(for: recreated),
            "A recreated session registers normally after a balanced teardown"
        )
        XCTAssertTrue(
            recreated is ContextMenuWebView,
            "Recreation runs through the same gate as first creation"
        )
    }

    func testPopupWebContentIsHostedByTheSameWrapperSessionsUse() {
        let service = makeService()
        let window = makeHostWindow()
        let (manager, sessionWebView) = makeSession(with: service, in: window)
        defer {
            manager.removeWebView(for: service, sessionIndex: 0)
            window.close()
        }

        guard let (popupWindow, popupWebView) = openPopup(from: manager) else {
            XCTFail("A popup must exist to inspect its hosting")
            return
        }

        let wrapper = popupWebView.superview as? WebViewWrapperView
        XCTAssertNotNil(wrapper, "Popup web content sits in the wrapper that hosts the load-error surface")
        XCTAssertTrue(
            wrapper?.subviews.contains { $0 is WebLoadErrorView } == true,
            "Popups install the same load-error surface as session tabs"
        )
        XCTAssertFalse(
            manager.hasVisibleLoadError(for: popupWebView),
            "A freshly opened popup starts without a load error"
        )
        XCTAssertFalse(
            manager.hasVisibleLoadError(for: sessionWebView),
            "The opener session also starts without a load error"
        )

        popupWindow.close()

        XCTAssertNil(wrapper?.superview, "Popup teardown removes the wrapper, leaving no ghost surface")
        XCTAssertNil(popupWebView.superview, "The webview leaves its wrapper with the popup")
    }

    func testZoomChangesPropagateToOpenPopups() {
        let service = makeService()
        let window = makeHostWindow()
        let (manager, sessionWebView) = makeSession(with: service, in: window)
        defer {
            manager.removeWebView(for: service, sessionIndex: 0)
            window.close()
        }

        guard let (popupWindow, popupWebView) = openPopup(from: manager) else {
            XCTFail("A popup must exist to receive propagation")
            return
        }
        defer { popupWindow.close() }

        manager.applyZoom(1.5, for: service.id)

        XCTAssertEqual(sessionWebView.pageZoom, 1.5, "Zoom reaches the session tab")
        XCTAssertEqual(popupWebView.pageZoom, 1.5, "Zoom reaches open popups, not just tabs")
    }

    func testFocusDimPropagatesToPopupWrappers() {
        let service = makeService()
        let window = makeHostWindow()
        let (manager, _) = makeSession(with: service, in: window)
        defer {
            manager.removeWebView(for: service, sessionIndex: 0)
            window.close()
        }

        guard let (popupWindow, popupWebView) = openPopup(from: manager),
              let wrapper = popupWebView.superview as? WebViewWrapperView else {
            XCTFail("A hosted popup wrapper must exist")
            return
        }
        defer { popupWindow.close() }

        manager.setContentTransparent(true)
        XCTAssertEqual(wrapper.alphaValue, 0.5, accuracy: 0.01, "Focus-loss dim reaches the popup wrapper")

        manager.setContentTransparent(false)
        XCTAssertEqual(wrapper.alphaValue, 1.0, accuracy: 0.01, "Restoring focus restores the popup wrapper")
    }

    func testVisibilityFollowsHostingForTabsAndPopups() {
        let service = makeService()
        let window = makeHostWindow()
        let (manager, sessionWebView) = makeSession(with: service, in: window)
        defer {
            manager.removeWebView(for: service, sessionIndex: 0)
            window.close()
        }
        // Host visible so its child popup can order in and out predictably.
        window.makeKeyAndOrderFront(nil)

        guard let (popupWindow, popupWebView) = openPopup(from: manager) else {
            XCTFail("A popup must exist to inspect visibility")
            return
        }
        defer { popupWindow.close() }

        XCTAssertTrue(manager.isWebContentVisible(popupWebView), "A shown popup reports visible")
        popupWindow.orderOut(nil)
        XCTAssertFalse(
            manager.isWebContentVisible(popupWebView),
            "An ordered-out popup reports hidden even though its wrapper stays visible"
        )
        popupWindow.makeKeyAndOrderFront(nil)
        XCTAssertTrue(manager.isWebContentVisible(popupWebView), "Re-showing the popup restores visibility")

        sessionWebView.superview?.isHidden = false
        XCTAssertTrue(manager.isWebContentVisible(sessionWebView), "A session tab follows its wrapper's flag")
        sessionWebView.superview?.isHidden = true
        XCTAssertFalse(manager.isWebContentVisible(sessionWebView), "A session tab behind a hidden wrapper reports hidden")
    }
}

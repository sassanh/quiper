import XCTest
import AppKit
import WebKit
@testable import Quiper

/// Guarantees of the single creation gate and shared teardown introduced to
/// make popup webviews first-class managed webviews, plus the popup
/// toolbar's chrome contracts: control placement and glyphs.
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
        // AppKit's default releases the window on close while this test
        // still holds it in liveWindows — the same double-release the app's
        // own windows opt out of.
        window.isReleasedWhenClosed = false
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
        in window: NSWindow
    ) -> (manager: WebViewManager, sessionWebView: WKWebView) {
        let manager = makeManager(with: service, in: window)
        let sessionWebView = manager.getOrCreateWebView(
            for: service,
            sessionIndex: 0,
            dragArea: nil,
            loadImmediately: false
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

    /// Opens a private sub-window owned by `owner` and returns it, picking
    /// it out of the popup population by its absence before the call.
    private func openPrivateSubWindow(
        from manager: WebViewManager,
        owner: TabIdentifier,
        in window: NSWindow
    ) -> (window: NSWindow, webView: WKWebView)? {
        let before = Set(NSApp.windows.filter { manager.isPopupWindow($0) }.map(ObjectIdentifier.init))
        manager.openPrivateWindow(
            url: URL(string: "about:blank")!,
            owner: owner,
            parentWindow: window
        )
        guard let popupWindow = NSApp.windows.first(where: {
            manager.isPopupWindow($0) && !before.contains(ObjectIdentifier($0))
        }),
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
        XCTAssertFalse(popupScripts.isEmpty, "Managed popups receive the engine scripts")
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

    func testPinnedEnginePopupsAreNotThePinnedTabSurface() {
        let service = Service(
            name: "Pinned Creation Gate",
            url: "",
            engineType: .pinnedTabs,
            pinnedTabURLs: Service.normalizedPinnedTabURLs(["https://one.example.com"]),
            focus_selector: "input"
        )
        let window = makeHostWindow()
        let manager = makeManager(with: service, in: window)
        let sessionWebView = manager.getOrCreateWebView(
            for: service,
            sessionIndex: 0,
            dragArea: nil,
            loadImmediately: false
        )
        defer {
            manager.removeWebView(for: service, sessionIndex: 0)
            window.close()
        }

        XCTAssertTrue(
            manager.isPinnedTabSurface(sessionWebView),
            "The pinned session's own tab is its pinned surface"
        )

        guard let (popupWindow, popupWebView) = openPopup(from: manager) else {
            XCTFail("Opening a link in a new window must create a managed popup")
            return
        }
        defer { popupWindow.close() }

        XCTAssertEqual(
            manager.findServiceAndSession(for: popupWebView)?.1,
            0,
            "A popup still resolves to the session that owns it"
        )
        XCTAssertFalse(
            manager.isPinnedTabSurface(popupWebView),
            "A popup opened from a pinned engine is not the pinned tab, so its own navigations stay in the popup"
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

    func testPopupOfPrivateWindowStaysMarkerFree() {
        let service = makeService()
        let window = makeHostWindow()
        let (manager, _) = makeSession(with: service, in: window)
        defer {
            manager.removeWebView(for: service, sessionIndex: 0)
            window.close()
        }

        guard let (privateWindow, privateWebView) = openPrivateSubWindow(
            from: manager,
            owner: TabIdentifier(serviceID: service.id, sessionIndex: 0),
            in: window
        ) else {
            XCTFail("A private sub-window must be openable from a live session")
            return
        }
        defer { privateWindow.close() }

        XCTAssertTrue(
            manager.isPrivateWebView(privateWebView),
            "A private sub-window registers its private identity with the manager"
        )
        XCTAssertTrue(
            privateWebView.configuration.userContentController.userScripts.isEmpty,
            "Precondition: the private sub-window itself carries no scripts"
        )
        XCTAssertEqual(
            privateWebView.configuration.websiteDataStore.isPersistent,
            false,
            "The private sub-window runs on an isolated non-persistent store"
        )

        manager.openLinkInNewWindow(URL(string: "about:blank")!, from: privateWebView)
        guard let popupWindow = NSApp.windows.first(where: { manager.isPopupWindow($0) && $0 !== privateWindow }),
              let popupWebView = manager.popupWebView(for: popupWindow) else {
            XCTFail("A private sub-window must still be able to open a managed popup")
            return
        }
        defer { popupWindow.close() }

        XCTAssertTrue(
            popupWebView.configuration.userContentController.userScripts.isEmpty,
            "A popup descended from a private sub-window stays marker-free"
        )
        XCTAssertTrue(
            manager.isPrivateWebView(popupWebView),
            "A popup descended from a private sub-window inherits the private identity"
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

    func testFocusDimAppliesToEachWindowIndependently() {
        let service = makeService()
        let window = makeHostWindow()
        let (manager, sessionWebView) = makeSession(with: service, in: window)
        defer {
            manager.removeWebView(for: service, sessionIndex: 0)
            window.close()
        }

        guard let (popupWindow, popupWebView) = openPopup(from: manager),
              let popupWrapper = popupWebView.superview as? WebViewWrapperView else {
            XCTFail("A hosted popup wrapper must exist")
            return
        }
        defer { popupWindow.close() }
        guard let sessionWrapper = sessionWebView.superview as? WebViewWrapperView else {
            XCTFail("A hosted session wrapper must exist")
            return
        }

        // Each population dims through its own window's gate: dimming the
        // main window's sessions leaves the popup untouched. A popup
        // seeds its starting dim from ambient app activity the test host
        // controls, so pin its baseline before comparing.
        manager.setPopupContentFocusLossLevel(.clear, for: popupWindow)
        manager.setSessionContentFocusLossLevel(.dimmed)
        XCTAssertEqual(sessionWrapper.alphaValue, 0.5, accuracy: 0.01, "Focus-loss dim reaches the session wrapper")
        XCTAssertEqual(popupWrapper.alphaValue, 1.0, accuracy: 0.01, "Session dimming never reaches the popup wrapper")

        // ...and the popup dims independently of the session tabs.
        manager.setPopupContentFocusLossLevel(.dimmed, for: popupWindow)
        XCTAssertEqual(popupWrapper.alphaValue, 0.5, accuracy: 0.01, "Focus-loss dim reaches the popup wrapper")
        XCTAssertEqual(sessionWrapper.alphaValue, 0.5, accuracy: 0.01, "Popup dimming never reaches the session wrappers")

        // Outside the key window's line the popup dims harder than the
        // standard tier: the page and its toolbar go more transparent
        // together, so a dimmed strip never reads as front.
        guard let popupChrome = popupWindow.contentView?.subviews,
              let popupToolbar = popupChrome.compactMap({ $0 as? PopupToolbarView }).first else {
            XCTFail("The popup's toolbar must exist to judge its dim")
            return
        }
        manager.setPopupContentFocusLossLevel(.deeplyDimmed, for: popupWindow)
        XCTAssertEqual(popupWrapper.alphaValue, 0.3, accuracy: 0.01, "A popup outside the active line renders more transparent than the standard dim")
        XCTAssertEqual(popupToolbar.alphaValue, 0.3, accuracy: 0.01, "The toolbar dims with the page, at the same tier")

        manager.setSessionContentFocusLossLevel(.clear)
        manager.setPopupContentFocusLossLevel(.clear, for: popupWindow)
        XCTAssertEqual(sessionWrapper.alphaValue, 1.0, accuracy: 0.01, "Restoring focus restores the session wrapper")
        XCTAssertEqual(popupWrapper.alphaValue, 1.0, accuracy: 0.01, "Restoring focus restores the popup wrapper")
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

    func testPopupWindowHasBorderlessMainWindowChrome() {
        let service = makeService()
        let window = makeHostWindow()
        let (manager, _) = makeSession(with: service, in: window)
        defer {
            manager.removeWebView(for: service, sessionIndex: 0)
            window.close()
        }

        guard let (popupWindow, popupWebView) = openPopup(from: manager) else {
            XCTFail("A popup must exist to inspect its chrome")
            return
        }
        defer { popupWindow.close() }

        XCTAssertTrue(
            popupWindow.styleMask.contains(.borderless),
            "Popups drop the macOS window shape for the overlay's borderless chrome"
        )
        XCTAssertFalse(
            popupWindow.styleMask.contains(.titled),
            "The native title bar is gone with the chrome"
        )
        XCTAssertTrue(
            popupWindow.canBecomeKey,
            "A borderless popup must still take key status for keyboard routing"
        )

        guard let toolbar = popupWindow.contentView?.subviews.compactMap({ $0 as? PopupToolbarView }).first else {
            XCTFail("Every popup hosts the toolbar")
            return
        }
        XCTAssertTrue(
            toolbar.subviews.contains { $0 === toolbar.refreshStopButton },
            "Refresh/stop belongs in the popup toolbar"
        )
        XCTAssertTrue(
            toolbar.subviews.contains { $0 === toolbar.closeButton },
            "A borderless window needs its own close affordance"
        )
        XCTAssertTrue(
            toolbar.refreshStopButton.target === toolbar,
            "The refresh control routes through the toolbar"
        )
        XCTAssertNotNil(
            toolbar.refreshStopButton.action,
            "The refresh control is wired to the shared reload/stop capability"
        )
        XCTAssertTrue(
            toolbar.navigationButtonGroup.isHidden,
            "A fresh popup has nowhere to go back or forward to"
        )
        XCTAssertEqual(
            toolbar.titleLabel.stringValue,
            service.name,
            "The toolbar title seeds with the engine name until the page reports one"
        )

        let wrapper = popupWebView.superview as? WebViewWrapperView
        XCTAssertNotNil(wrapper, "The web content still sits in the shared wrapper")
        XCTAssertEqual(
            wrapper?.frame.maxY ?? -1,
            toolbar.frame.minY,
            accuracy: 0.5,
            "Web content sits below the toolbar, like the main window's header"
        )
    }

    func testPopupToolbarCloseButtonRunsTheSharedTeardown() {
        let service = makeService()
        let window = makeHostWindow()
        let (manager, _) = makeSession(with: service, in: window)
        defer {
            manager.removeWebView(for: service, sessionIndex: 0)
            window.close()
        }

        guard let (popupWindow, popupWebView) = openPopup(from: manager),
              let toolbar = popupWindow.contentView?.subviews.compactMap({ $0 as? PopupToolbarView }).first else {
            XCTFail("A popup with a toolbar must exist")
            return
        }
        defer { popupWindow.close() }

        toolbar.closeButton.performClick(nil)

        XCTAssertFalse(
            manager.isPopupWindow(popupWindow),
            "The toolbar close button closes through the window's teardown"
        )
        XCTAssertNil(popupWebView.superview, "Closing unhosts the webview with its window")
    }

    func testPopupCloseButtonOccupiesTheToolbarTrailingEdge() {
        let service = makeService()
        let window = makeHostWindow()
        let (manager, _) = makeSession(with: service, in: window)
        defer {
            manager.removeWebView(for: service, sessionIndex: 0)
            window.close()
        }

        guard let (popupWindow, _) = openPopup(from: manager),
              let toolbar = popupWindow.contentView?.subviews.compactMap({ $0 as? PopupToolbarView }).first else {
            XCTFail("A popup with a toolbar must exist")
            return
        }
        defer { popupWindow.close() }

        toolbar.frame = NSRect(x: 0, y: 0, width: 480, height: 36)
        toolbar.layout()

        XCTAssertEqual(
            toolbar.closeButton.frame.maxX,
            toolbar.bounds.maxX - 4,
            accuracy: 0.5,
            "Close keeps the toolbar's trailing edge"
        )
        XCTAssertLessThan(
            toolbar.refreshStopButton.frame.maxX,
            toolbar.closeButton.frame.minX,
            "Refresh/stop sits left of close; their ■ and ✕ glyphs tell the two apart"
        )
    }

    func testCloseAndStopUseDistinctGlyphs() {
        XCTAssertEqual(
            WindowCloseButton.symbolName,
            "xmark",
            "Close keeps the standard plain ✕ every macOS window draws"
        )
        XCTAssertEqual(
            RefreshStopButton.stopSymbolName,
            "stop.fill",
            "Stop-loading keeps the filled square wherever Quiper shows it"
        )
        XCTAssertNotEqual(
            WindowCloseButton.symbolName,
            RefreshStopButton.stopSymbolName,
            "Two different controls can never share a glyph"
        )
    }

    /// The first click on an inactive popup is the activation click: it
    /// moves key status through the focus gate and never reaches the
    /// window's content, so the next click can act on it — the whole
    /// window, not just the web page.
    func testFirstClickOnAnInactivePopupActivatesWithoutReachingContent() async throws {
        let service = makeService()
        let window = makeHostWindow()
        let (manager, _) = makeSession(with: service, in: window)
        defer {
            manager.removeWebView(for: service, sessionIndex: 0)
            window.close()
        }

        guard let (popupWindow, _) = openPopup(from: manager) else {
            XCTFail("A hosted popup must exist")
            return
        }
        defer { popupWindow.close() }

        // A probe at the click point records whether the event reached the
        // window's views at all.
        let probe = ClickProbeView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        popupWindow.contentView?.addSubview(probe)

        // Park key status anywhere but the popup: the inactive-popup click
        // path below can only be judged once the popup has lost it.
        try await HostPrecondition.require(
            "The test host refused to deactivate the popup",
            requesting: {
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
            },
            until: { !popupWindow.isKeyWindow }
        )

        let click = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: NSPoint(x: 50, y: 50),
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: popupWindow.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            ),
            "A mouse-down event must be constructible"
        )

        popupWindow.sendEvent(click)
        XCTAssertEqual(
            probe.mouseDownCount, 0,
            "The activating click must not reach the window's content"
        )
        // The activating click itself must key the popup — no re-drive here,
        // because a click that fails to activate it is the failure this pins.
        try await HostPrecondition.require(
            "The test host refused key status to the popup",
            until: { popupWindow.isKeyWindow }
        )

        popupWindow.sendEvent(click)
        XCTAssertEqual(
            probe.mouseDownCount, 1,
            "With the popup key, the next click must reach the content"
        )
    }

    /// A minimized strip is nothing but a control, so it refuses the
    /// activation tax: the first click still moves key status through
    /// the focus gate, and the same click is delivered to the strip's
    /// views — the gesture that expands the window.
    func testFirstClickOnAMinimizedStripIsDeliveredWhileActivating() async throws {
        let service = makeService()
        let window = makeHostWindow()
        let (manager, _) = makeSession(with: service, in: window)
        defer {
            manager.removeWebView(for: service, sessionIndex: 0)
            window.close()
        }

        guard let (popupWindow, _) = openPopup(from: manager),
              let popup = popupWindow as? PopupWindow else {
            XCTFail("A hosted popup must exist")
            return
        }
        defer { popupWindow.close() }
        popup.setCollapsed(true, animated: false)

        // A probe at the click point records whether the event reached the
        // window's views at all. The collapsed window is only a toolbar
        // tall, so the click sits inside the strip.
        let probe = ClickProbeView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        popupWindow.contentView?.addSubview(probe)

        // Park key status anywhere but the strip: the inactive-strip click
        // path below can only be judged once the strip has lost it.
        try await HostPrecondition.require(
            "The test host refused to deactivate the popup",
            requesting: {
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
            },
            until: { !popupWindow.isKeyWindow }
        )

        let click = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: NSPoint(x: 50, y: 16),
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: popupWindow.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            ),
            "A mouse-down event must be constructible"
        )

        popupWindow.sendEvent(click)
        XCTAssertEqual(
            probe.mouseDownCount, 1,
            "The activating click lands on the strip: it expands in the same gesture"
        )
        XCTAssertTrue(
            popupWindow.isKeyWindow,
            "The strip still takes key status through the focus gate"
        )
    }
}

/// Records whether a mouse-down reached it, pinning what an event
/// routing decided: swallowed versus delivered.
private final class ClickProbeView: NSView {
    var mouseDownCount = 0

    override func mouseDown(with event: NSEvent) {
        mouseDownCount += 1
    }
}

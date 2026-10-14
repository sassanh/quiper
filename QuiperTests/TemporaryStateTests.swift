import XCTest
import AppKit
import WebKit
@testable import Quiper

/// Guarantees of the private browsing model: private identity lives on
/// webview tokens — a private sub-window or a popup descended from one —
/// never on main-window tabs, and private webviews stay marker-free,
/// isolated, and unpersisted.
@MainActor
final class TemporaryStateTests: XCTestCase {
    // WebViewManager holds its container weakly; the test must retain it.
    private var liveContainers: [NSView] = []
    private var liveWindows: [NSWindow] = []

    private func makeService() -> Service {
        Service(
            name: "Temporary Test Engine",
            url: "https://example.com",
            focus_selector: "input"
        )
    }

    private func makeManager(with service: Service) -> WebViewManager {
        let originalServices = Settings.shared.services
        addTeardownBlock {
            Settings.shared.services = originalServices
        }
        Settings.shared.services = [service]
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        liveContainers.append(container)
        let manager = WebViewManager(containerView: container)
        manager.updateServices([service])
        return manager
    }

    private func makeHostWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 800, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        liveWindows.append(window)
        return window
    }

    /// Opens a private sub-window owned by session 0 of `service`, picking
    /// the new popup out of the population by its absence before the call.
    private func openPrivateSubWindow(
        with manager: WebViewManager,
        service: Service,
        parentWindow: NSWindow
    ) -> (window: NSWindow, webView: WKWebView)? {
        let before = Set(manager.popupWindows.map(ObjectIdentifier.init))
        manager.openPrivateWindow(
            url: URL(string: "about:blank")!,
            owner: TabIdentifier(serviceID: service.id, sessionIndex: 0),
            parentWindow: parentWindow
        )
        guard let popupWindow = manager.popupWindows.first(where: { !before.contains(ObjectIdentifier($0)) }),
              let webView = manager.popupWebView(for: popupWindow) else { return nil }
        return (popupWindow, webView)
    }

    func testSessionWebviewsAreNeverPrivate() {
        let service = makeService()
        let manager = makeManager(with: service)
        let webView = manager.getOrCreateWebView(
            for: service,
            sessionIndex: 0,
            dragArea: nil,
            loadImmediately: false
        )
        defer { manager.removeWebView(for: service, sessionIndex: 0) }
        XCTAssertFalse(
            manager.isPrivateWebView(webView),
            "Main-window session webviews are never private"
        )
        XCTAssertFalse(
            webView.configuration.userContentController.userScripts.isEmpty,
            "Normal sessions carry the engine scripts, unlike private webviews"
        )
    }

    func testPrivateWindowIsMarkerFreeAndRegisteredToItsOwner() {
        let service = makeService()
        let manager = makeManager(with: service)
        let sessionWebView = manager.getOrCreateWebView(
            for: service,
            sessionIndex: 0,
            dragArea: nil,
            loadImmediately: false
        )
        let hostWindow = makeHostWindow()
        defer {
            manager.removeWebView(for: service, sessionIndex: 0)
            hostWindow.close()
        }
        guard let (privateWindow, privateWebView) = openPrivateSubWindow(
            with: manager,
            service: service,
            parentWindow: hostWindow
        ) else {
            XCTFail("A private sub-window must open from a live session")
            return
        }
        defer { privateWindow.close() }

        XCTAssertTrue(manager.isPrivateWebView(privateWebView))
        XCTAssertFalse(manager.isPrivateWebView(sessionWebView))
        XCTAssertTrue(
            privateWebView.configuration.userContentController.userScripts.isEmpty,
            "The private sub-window carries no injected scripts"
        )
        XCTAssertEqual(
            privateWebView.configuration.websiteDataStore.isPersistent,
            false,
            "The private sub-window runs on an isolated non-persistent store"
        )
        XCTAssertTrue(
            manager.isPopupWindow(privateWindow),
            "The private sub-window is a managed sub-window, window-scoped"
        )
        XCTAssertEqual(
            (privateWindow as? PopupWindow)?.isEphemeral,
            true,
            "The private sub-window carries the dashed-border visual signature"
        )
        let membership = manager.findServiceAndSession(for: privateWebView)
        XCTAssertEqual(membership?.0.id, service.id, "The private webview resolves to its owner engine")
        XCTAssertEqual(membership?.1, 0, "The private webview resolves to its owner session")
    }

    func testPrivateWindowStateNeverPersists() {
        let service = makeService()
        let manager = makeManager(with: service)
        _ = manager.getOrCreateWebView(
            for: service,
            sessionIndex: 0,
            dragArea: nil,
            loadImmediately: false
        )
        let hostWindow = makeHostWindow()
        defer {
            manager.removeWebView(for: service, sessionIndex: 0)
            hostWindow.close()
        }
        guard let (privateWindow, _) = openPrivateSubWindow(
            with: manager,
            service: service,
            parentWindow: hostWindow
        ) else {
            XCTFail("A private sub-window must open from a live session")
            return
        }
        defer { privateWindow.close() }

        XCTAssertTrue(
            manager.getPopupSnapshotState().isEmpty,
            "Private sub-windows never reach saved popup state"
        )
    }

    func testClosingPrivateWindowClearsPrivateState() {
        let service = makeService()
        let manager = makeManager(with: service)
        _ = manager.getOrCreateWebView(
            for: service,
            sessionIndex: 0,
            dragArea: nil,
            loadImmediately: false
        )
        let hostWindow = makeHostWindow()
        defer {
            manager.removeWebView(for: service, sessionIndex: 0)
            hostWindow.close()
        }
        guard let (privateWindow, privateWebView) = openPrivateSubWindow(
            with: manager,
            service: service,
            parentWindow: hostWindow
        ) else {
            XCTFail("A private sub-window must open from a live session")
            return
        }

        privateWindow.close()

        XCTAssertFalse(manager.isPopupWindow(privateWindow), "Closing the window unregisters it")
        XCTAssertFalse(
            manager.isPrivateWebView(privateWebView),
            "Teardown clears the private identity with the webview"
        )
        XCTAssertTrue(manager.getPopupSnapshotState().isEmpty)
    }

    func testDescendantPopupInheritsPrivateIdentity() {
        let service = makeService()
        let manager = makeManager(with: service)
        _ = manager.getOrCreateWebView(
            for: service,
            sessionIndex: 0,
            dragArea: nil,
            loadImmediately: false
        )
        let hostWindow = makeHostWindow()
        defer {
            manager.removeWebView(for: service, sessionIndex: 0)
            hostWindow.close()
        }
        guard let (privateWindow, privateWebView) = openPrivateSubWindow(
            with: manager,
            service: service,
            parentWindow: hostWindow
        ) else {
            XCTFail("A private sub-window must open from a live session")
            return
        }
        defer { privateWindow.close() }

        let before = Set(manager.popupWindows.map(ObjectIdentifier.init))
        manager.openLinkInNewWindow(URL(string: "about:blank")!, from: privateWebView)
        guard let popupWindow = manager.popupWindows.first(where: { !before.contains(ObjectIdentifier($0)) }),
              let childWebView = manager.popupWebView(for: popupWindow) else {
            XCTFail("A private sub-window must still be able to open a managed popup")
            return
        }
        defer { popupWindow.close() }

        XCTAssertTrue(
            manager.isPrivateWebView(childWebView),
            "A popup descended from a private sub-window inherits the private identity"
        )
        XCTAssertTrue(
            childWebView.configuration.userContentController.userScripts.isEmpty,
            "A descendant of a private sub-window stays marker-free"
        )
        XCTAssertTrue(
            manager.getPopupSnapshotState().isEmpty,
            "Descendants of private sub-windows never reach saved popup state either"
        )
    }
}

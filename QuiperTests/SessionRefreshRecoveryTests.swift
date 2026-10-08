import XCTest
import AppKit
import WebKit
@testable import Quiper

/// A session whose first load never lands — the typical bad-network
/// initialization — sits on the initial `about:blank`, a document with no
/// address of its own. Refresh must load the address the session was meant
/// to show, because re-requesting the blank document succeeds without
/// fetching anything and strands the session on an empty page.
///
/// Every address here is a local file, so the recovery rules are exercised
/// without a network.
@MainActor
final class SessionRefreshRecoveryTests: XCTestCase {
    // WebViewManager holds its container weakly; the test must retain it.
    private var liveContainers: [NSView] = []
    private var liveWindows: [NSWindow] = []
    private var temporaryDirectory: URL?

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
        liveContainers.removeAll()
        liveWindows.removeAll()
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("SessionRefreshRecoveryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectory = directory
        return directory
    }

    private func writePage(named name: String, in directory: URL) throws -> URL {
        let pageURL = directory.appendingPathComponent(name)
        try Data("<html><body>\(name)</body></html>".utf8).write(to: pageURL)
        return pageURL
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

    private func makeService(url: String) -> Service {
        Service(name: "Refresh Recovery Engine", url: url, focus_selector: "input")
    }

    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 5,
        condition: @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("Timed out waiting for \(description)")
    }

    /// Whether the web view shows `address`. Comparisons resolve symlinks:
    /// the committed file URL WebKit reports may spell the temporary
    /// directory through its `/private` alias.
    private func isShowing(_ webView: WKWebView, address: URL) -> Bool {
        guard let committedURL = webView.url else { return false }
        return committedURL.resolvingSymlinksInPath() == address.resolvingSymlinksInPath()
    }

    func testRefreshLoadsTheAddressOfASessionThatNeverStartedOne() async throws {
        let directory = try makeTemporaryDirectory()
        let engineAddress = try writePage(named: "engine.html", in: directory)
        let service = makeService(url: engineAddress.absoluteString)
        let window = makeHostWindow()
        let manager = makeManager(with: service, in: window)
        let webView = manager.getOrCreateWebView(
            for: service,
            sessionIndex: 0,
            dragArea: nil,
            loadImmediately: false
        )
        defer {
            manager.removeWebView(for: service, sessionIndex: 0)
            window.close()
        }

        XCTAssertEqual(
            manager.refreshPlan(for: webView),
            .loadSessionAddress(engineAddress),
            "A session that never started loading must refresh to its engine's address"
        )

        manager.reload(webView)
        await waitUntil("the session's address commits") {
            self.isShowing(webView, address: engineAddress)
        }
    }

    func testRefreshRecoversASessionStrandedOnBlank() async throws {
        let directory = try makeTemporaryDirectory()
        let sessionAddress = try writePage(named: "session.html", in: directory)
        let engineAddress = try writePage(named: "engine.html", in: directory)
        let service = makeService(url: engineAddress.absoluteString)
        let window = makeHostWindow()
        let manager = makeManager(with: service, in: window)
        let webView = manager.getOrCreateWebView(
            for: service,
            sessionIndex: 0,
            dragArea: nil,
            targetURL: sessionAddress.absoluteString,
            loadImmediately: true
        )
        defer {
            manager.removeWebView(for: service, sessionIndex: 0)
            window.close()
        }
        await waitUntil("the session's own address commits") {
            self.isShowing(webView, address: sessionAddress)
        }

        // The reported bad state: the session settles on the initial blank
        // document, which has no address of its own.
        webView.load(URLRequest(url: URL(string: "about:blank")!))
        await waitUntil("the page settles on about:blank") {
            webView.url?.absoluteString == "about:blank"
        }

        XCTAssertEqual(
            manager.refreshPlan(for: webView),
            .loadSessionAddress(sessionAddress),
            "A blank page must resolve to the address the session was meant to show"
        )
        manager.reload(webView)
        await waitUntil("refresh brings back the session's own address") {
            self.isShowing(webView, address: sessionAddress)
        }
    }

    func testRefreshKeepsAnAddressedPageOnItsOwnAddress() async throws {
        let directory = try makeTemporaryDirectory()
        let sessionAddress = try writePage(named: "session.html", in: directory)
        let engineAddress = try writePage(named: "engine.html", in: directory)
        let service = makeService(url: engineAddress.absoluteString)
        let window = makeHostWindow()
        let manager = makeManager(with: service, in: window)
        let webView = manager.getOrCreateWebView(
            for: service,
            sessionIndex: 0,
            dragArea: nil,
            targetURL: sessionAddress.absoluteString,
            loadImmediately: true
        )
        defer {
            manager.removeWebView(for: service, sessionIndex: 0)
            window.close()
        }
        await waitUntil("the session's own address commits") {
            self.isShowing(webView, address: sessionAddress)
        }

        XCTAssertEqual(
            manager.refreshPlan(for: webView),
            .reloadDocument(sessionAddress),
            "A page with an address of its own refreshes by re-requesting that address"
        )
        manager.reload(webView)
        await waitUntil("the refresh settles") { !webView.isLoading }
        XCTAssertTrue(
            isShowing(webView, address: sessionAddress),
            "Refresh must never redirect an addressed page to the engine's address"
        )
    }

    func testRefreshOfAFailedInitializationTargetsTheAddressItRequested() async throws {
        let directory = try makeTemporaryDirectory()
        let engineAddress = try writePage(named: "engine.html", in: directory)
        let failedAddress = directory.appendingPathComponent("missing.html")
        let service = makeService(url: engineAddress.absoluteString)
        let window = makeHostWindow()
        let manager = makeManager(with: service, in: window)
        let webView = manager.getOrCreateWebView(
            for: service,
            sessionIndex: 0,
            dragArea: nil,
            targetURL: failedAddress.absoluteString,
            loadImmediately: true
        )
        defer {
            manager.removeWebView(for: service, sessionIndex: 0)
            window.close()
        }

        await waitUntil("the failed initialization surfaces its load error") {
            manager.hasVisibleLoadError(for: webView)
        }
        XCTAssertEqual(
            manager.refreshPlan(for: webView),
            .loadSessionAddress(failedAddress),
            "Refresh must retry the address the session failed to load, not fall back to the engine's root"
        )
    }

    func testRefreshWithNothingKnownActsOnNothingAndTheCrashRetryExplainsItself() async throws {
        // An engine whose address is itself the blank document, on a tab
        // that never loaded anything: no queued, requested, or engine
        // address qualifies, so there is nothing real to refresh.
        let service = makeService(url: "about:blank")
        let window = makeHostWindow()
        let manager = makeManager(with: service, in: window)
        let webView = manager.getOrCreateWebView(
            for: service,
            sessionIndex: 0,
            dragArea: nil,
            loadImmediately: false
        )
        defer {
            manager.removeWebView(for: service, sessionIndex: 0)
            window.close()
        }

        XCTAssertEqual(
            manager.refreshPlan(for: webView),
            .nothing,
            "With no loadable address anywhere, a refresh has nothing real to act on"
        )
        manager.reload(webView)
        XCTAssertFalse(
            manager.hasVisibleLoadError(for: webView),
            "A refresh with nothing to do must not fabricate a load error"
        )

        manager.webViewWebContentProcessDidTerminate(webView)
        XCTAssertTrue(
            manager.hasVisibleLoadError(for: webView),
            "A crash retry with nothing to re-request must surface the crash instead of ending in silence"
        )
    }
}

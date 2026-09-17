import XCTest
import AppKit
import WebKit
@testable import Quiper

@MainActor
final class TemporaryStateTests: XCTestCase {
    // WebViewManager holds its container weakly; the test must retain it.
    private var liveContainers: [NSView] = []

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

    func testNormalTabSeedsNonTemporary() {
        let service = makeService()
        let manager = makeManager(with: service)
        _ = manager.getOrCreateWebView(
            for: service,
            sessionIndex: 0,
            dragArea: nil,
            loadImmediately: false
        )
        defer { manager.removeWebView(for: service, sessionIndex: 0) }

        XCTAssertFalse(manager.isTemporaryTab(serviceID: service.id, sessionIndex: 0))
        XCTAssertFalse(manager.isQuiperPrivateTab(serviceID: service.id, sessionIndex: 0))
    }

    func testQuiperPrivateTabSeedsTemporary() {
        let service = makeService()
        let manager = makeManager(with: service)
        _ = manager.getOrCreateWebView(
            for: service,
            sessionIndex: 1,
            dragArea: nil,
            loadImmediately: false,
            isQuiperPrivate: true
        )
        defer { manager.removeWebView(for: service, sessionIndex: 1) }

        XCTAssertTrue(manager.isTemporaryTab(serviceID: service.id, sessionIndex: 1))
        XCTAssertTrue(manager.isQuiperPrivateTab(serviceID: service.id, sessionIndex: 1))
    }

    func testTemporaryEqualsQuiperPrivateByConstruction() {
        let service = makeService()
        let manager = makeManager(with: service)
        _ = manager.getOrCreateWebView(
            for: service,
            sessionIndex: 0,
            dragArea: nil,
            loadImmediately: false
        )
        _ = manager.getOrCreateWebView(
            for: service,
            sessionIndex: 1,
            dragArea: nil,
            loadImmediately: false,
            isQuiperPrivate: true
        )
        defer {
            manager.removeWebView(for: service, sessionIndex: 0)
            manager.removeWebView(for: service, sessionIndex: 1)
        }

        XCTAssertEqual(
            manager.isTemporaryTab(serviceID: service.id, sessionIndex: 0),
            manager.isQuiperPrivateTab(serviceID: service.id, sessionIndex: 0)
        )
        XCTAssertEqual(
            manager.isTemporaryTab(serviceID: service.id, sessionIndex: 1),
            manager.isQuiperPrivateTab(serviceID: service.id, sessionIndex: 1)
        )
    }

    func testTemporaryTabsExcludedFromPersistedState() {
        let service = makeService()
        let manager = makeManager(with: service)
        _ = manager.getOrCreateWebView(
            for: service,
            sessionIndex: 0,
            dragArea: nil,
            loadImmediately: false
        )
        _ = manager.getOrCreateWebView(
            for: service,
            sessionIndex: 1,
            dragArea: nil,
            loadImmediately: false,
            isQuiperPrivate: true
        )
        defer {
            manager.removeWebView(for: service, sessionIndex: 0)
            manager.removeWebView(for: service, sessionIndex: 1)
        }

        manager.setTabInputState(
            TabInputState(text: "normal", isContentEditable: false, start: 0, end: 0),
            for: service.id,
            sessionIndex: 0
        )
        manager.setTabInputState(
            TabInputState(text: "private", isContentEditable: false, start: 0, end: 0),
            for: service.id,
            sessionIndex: 1
        )

        let urls = manager.getOpenSessionsState()[service.id] ?? [:]
        XCTAssertNotNil(urls[0])
        XCTAssertNil(urls[1])

        let titles = manager.getOpenSessionTitlesState()[service.id] ?? [:]
        XCTAssertNil(titles[1])

        let inputs = manager.getOpenSessionsInputState()[service.id] ?? [:]
        XCTAssertNotNil(inputs[0])
        XCTAssertNil(inputs[1])
    }

    func testQuiperPrivateTabReceivesNoInjectedScripts() {
        let service = makeService()
        let manager = makeManager(with: service)
        let normal = manager.getOrCreateWebView(
            for: service,
            sessionIndex: 0,
            dragArea: nil,
            loadImmediately: false
        )
        let privateView = manager.getOrCreateWebView(
            for: service,
            sessionIndex: 1,
            dragArea: nil,
            loadImmediately: false,
            isQuiperPrivate: true
        )
        defer {
            manager.removeWebView(for: service, sessionIndex: 0)
            manager.removeWebView(for: service, sessionIndex: 1)
        }

        XCTAssertFalse(normal.configuration.userContentController.userScripts.isEmpty)
        XCTAssertTrue(privateView.configuration.userContentController.userScripts.isEmpty)
    }
}

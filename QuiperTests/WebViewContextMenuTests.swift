import XCTest
import AppKit
import WebKit
@testable import Quiper

@MainActor
final class WebViewContextMenuTests: XCTestCase {
    func testClientPointFlipsYAndDividesZoom() {
        let point = MainWindowController.clientPoint(
            forViewPoint: NSPoint(x: 100, y: 450),
            viewHeight: 600,
            pageZoom: 2
        )
        XCTAssertEqual(point.x, 50, accuracy: 0.001)
        XCTAssertEqual(point.y, 75, accuracy: 0.001)
    }

    func testClientPointTreatsInvalidZoomAsOne() {
        let point = MainWindowController.clientPoint(
            forViewPoint: NSPoint(x: 100, y: 450),
            viewHeight: 600,
            pageZoom: 0
        )
        XCTAssertEqual(point.x, 100, accuracy: 0.001)
        XCTAssertEqual(point.y, 150, accuracy: 0.001)
    }

    func testDirectPickScriptPostsPick() {
        let script = WebScripts.makeSelectorDirectPickScript(x: 120.5, y: 340.25)
        XCTAssertTrue(script.contains("document.elementFromPoint(x, y)"))
        XCTAssertTrue(script.contains("quiperSelectorPicker"))
        XCTAssertTrue(script.contains("data-testid"))
        XCTAssertTrue(script.contains("return true"))
        XCTAssertTrue(script.contains("__quiperLastContextMenu"))
    }

    func testContextMenuRecorderScript() {
        let script = WebScripts.makeContextMenuRecorderScript().source
        XCTAssertTrue(script.contains("__quiperLastContextMenu"))
        XCTAssertTrue(script.contains("\"contextmenu\""))
        XCTAssertTrue(script.contains("clientX"))
        XCTAssertTrue(script.contains("Date.now()"))
    }

    func testPageMenuGainsSuggestItem() throws {
        @MainActor
        final class Spy: NSObject, WebViewContextMenuDelegate {
            var receivedView: WKWebView?
            var receivedPoint: NSPoint?
            var allowsSuggest = true
            func webView(_ webView: WKWebView, didRequestPageSelectorSuggestAt point: NSPoint) {
                receivedView = webView
                receivedPoint = point
            }
            func webViewAllowsPageSelectorSuggest(_ webView: WKWebView) -> Bool {
                allowsSuggest
            }
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let view = ContextMenuWebView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600),
            configuration: WKWebViewConfiguration()
        )
        window.contentView?.addSubview(view)
        let spy = Spy()
        view.contextMenuDelegate = spy

        let menu = NSMenu()
        menu.addItem(withTitle: "Reload Page", action: nil, keyEquivalent: "")
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: NSPoint(x: 100, y: 450),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))
        view.willOpenMenu(menu, with: event)

        let titles = menu.items.map { $0.isSeparatorItem ? "<separator>" : $0.title }
        XCTAssertEqual(titles, ["Suggest Selector...", "<separator>", "Reload Page"])

        let item = try XCTUnwrap(menu.items.first)
        XCTAssertEqual(item.identifier, ContextMenuWebView.suggestSelectorItemIdentifier)
        XCTAssertTrue(NSApplication.shared.sendAction(item.action!, to: item.target, from: item))
        XCTAssertTrue(spy.receivedView === view)
        // Assert wiring (delegate receives this view's conversion of the
        // event), not absolute numbers: synthetic event geometry is AppKit's
        // business, and the flip/zoom math has its own pure unit tests.
        let expectedPoint = view.convert(event.locationInWindow, from: nil)
        XCTAssertEqual(spy.receivedPoint?.x ?? -1, expectedPoint.x, accuracy: 0.5)
        XCTAssertEqual(spy.receivedPoint?.y ?? -1, expectedPoint.y, accuracy: 0.5)

        view.willOpenMenu(menu, with: event)
        XCTAssertEqual(menu.items.filter { $0.identifier == ContextMenuWebView.suggestSelectorItemIdentifier }.count, 1)
    }

    func testPageMenuUntouchedWithoutDelegate() throws {
        let view = ContextMenuWebView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600),
            configuration: WKWebViewConfiguration()
        )
        let menu = NSMenu()
        menu.addItem(withTitle: "Reload Page", action: nil, keyEquivalent: "")
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: NSPoint(x: 10, y: 10),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))
        view.willOpenMenu(menu, with: event)
        XCTAssertEqual(menu.items.map(\.title), ["Reload Page"])
    }

    func testPageMenuSkippedWhenDisallowed() throws {
        @MainActor
        final class DenySpy: NSObject, WebViewContextMenuDelegate {
            func webView(_ webView: WKWebView, didRequestPageSelectorSuggestAt point: NSPoint) {}
            func webViewAllowsPageSelectorSuggest(_ webView: WKWebView) -> Bool { false }
        }
        let view = ContextMenuWebView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600),
            configuration: WKWebViewConfiguration()
        )
        view.contextMenuDelegate = DenySpy()
        let menu = NSMenu()
        menu.addItem(withTitle: "Reload Page", action: nil, keyEquivalent: "")
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: NSPoint(x: 10, y: 10),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))
        view.willOpenMenu(menu, with: event)
        XCTAssertEqual(menu.items.map(\.title), ["Reload Page"])
    }

    func testEphemeralTabsDisallowSuggest() throws {
        let service = Service(
            id: UUID(),
            name: "Test Engine",
            url: "https://example.com",
            focus_selector: "#prompt",
            customCSS: nil
        )
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let manager = WebViewManager(containerView: container)
        manager.updateServices([service])
        let normal = manager.getOrCreateWebView(
            for: service,
            sessionIndex: 0,
            dragArea: nil,
            loadImmediately: false
        )
        let ephemeral = manager.getOrCreateWebView(
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
        XCTAssertTrue(manager.webViewAllowsPageSelectorSuggest(normal))
        XCTAssertFalse(manager.webViewAllowsPageSelectorSuggest(ephemeral))
        XCTAssertFalse(manager.webViewAllowsPageSelectorSuggest(WKWebView()))
    }
}

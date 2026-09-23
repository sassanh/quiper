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
        XCTAssertEqual(titles, ["Reload Page", "<separator>", "Suggest Selector..."])

        let item = try XCTUnwrap(menu.items.last)
        XCTAssertEqual(item.identifier, ContextMenuWebView.suggestSelectorItemIdentifier)
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
        // Held for the whole test: the delegate is weak, so a temporary would
        // die at the assignment and the menu would be skipped for the wrong
        // reason (no delegate, not a disallowing one).
        let denySpy = DenySpy()
        view.contextMenuDelegate = denySpy
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

    // MARK: - Link menu

    func testLinkHrefScriptResolvesAnchor() {
        let script = WebScripts.makeLinkHrefScript(x: 10, y: 20)
        XCTAssertTrue(script.contains("elementFromPoint"))
        XCTAssertTrue(script.contains("closest"))
        XCTAssertTrue(script.contains("a[href]"))
        XCTAssertTrue(script.contains("__quiperLastContextMenu"))
    }

    func testLinkMenuReplacesDefaultOpenItems() throws {
        @MainActor
        final class LinkSpy: NSObject, WebViewContextMenuDelegate {
            var actions: [ContextMenuLinkAction] = []
            func webView(_ webView: WKWebView, didRequestPageSelectorSuggestAt point: NSPoint) {}
            func webViewAllowsPageSelectorSuggest(_ webView: WKWebView) -> Bool { true }
            func webView(_ webView: WKWebView, didRequestLinkAction action: ContextMenuLinkAction, at point: NSPoint) {
                actions.append(action)
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
        let linkSpy = LinkSpy()
        view.contextMenuDelegate = linkSpy

        let menu = NSMenu()
        menu.addItem(withTitle: "Open Link in New Window", action: Selector(("openLink:")), keyEquivalent: "")
        menu.addItem(withTitle: "Copy Link", action: nil, keyEquivalent: "")
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

        let identifiers = Set(menu.items.compactMap(\.identifier))
        XCTAssertTrue(identifiers.contains(ContextMenuWebView.openLinkHereIdentifier))
        XCTAssertTrue(identifiers.contains(ContextMenuWebView.openLinkNewWindowIdentifier))
        XCTAssertTrue(identifiers.contains(ContextMenuWebView.openLinkSystemBrowserIdentifier))
        XCTAssertTrue(identifiers.contains(ContextMenuWebView.openLinkPrivateIdentifier))
        // The default untagged Open-Link item is gone; ours carries the same
        // title but with a Quiper identifier.
        let untaggedOpenLinks = menu.items.filter {
            $0.identifier == nil && $0.title.lowercased().hasPrefix("open") && $0.title.lowercased().contains("link")
        }
        XCTAssertTrue(untaggedOpenLinks.isEmpty)
        XCTAssertTrue(menu.items.contains(where: { $0.title == "Copy Link" }))
    }

    func testLinkActionsReachDelegate() throws {
        @MainActor
        final class ActionSpy: NSObject, WebViewContextMenuDelegate {
            var actions: [ContextMenuLinkAction] = []
            func webView(_ webView: WKWebView, didRequestPageSelectorSuggestAt point: NSPoint) {}
            func webViewAllowsPageSelectorSuggest(_ webView: WKWebView) -> Bool { true }
            func webView(_ webView: WKWebView, didRequestLinkAction action: ContextMenuLinkAction, at point: NSPoint) {
                actions.append(action)
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
        let spy = ActionSpy()
        view.contextMenuDelegate = spy

        let menu = NSMenu()
        menu.addItem(withTitle: "Open Link in New Window", action: nil, keyEquivalent: "")
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

        for identifier in [
            ContextMenuWebView.openLinkHereIdentifier,
            ContextMenuWebView.openLinkNewWindowIdentifier,
            ContextMenuWebView.openLinkSystemBrowserIdentifier,
            ContextMenuWebView.openLinkPrivateIdentifier
        ] {
            let item = try XCTUnwrap(menu.items.first(where: { $0.identifier == identifier }))
            XCTAssertTrue(NSApplication.shared.sendAction(item.action!, to: item.target, from: item))
        }
        XCTAssertEqual(spy.actions, [.openHere, .openNewWindow, .openSystemBrowser, .openPrivate])
    }

    func testFreshMenusEachGainOneLinkSet() throws {
        @MainActor
        final class ReuseSpy: NSObject, WebViewContextMenuDelegate {
            func webView(_ webView: WKWebView, didRequestPageSelectorSuggestAt point: NSPoint) {}
            func webViewAllowsPageSelectorSuggest(_ webView: WKWebView) -> Bool { true }
        }
        let view = ContextMenuWebView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600),
            configuration: WKWebViewConfiguration()
        )
        let reuseSpy = ReuseSpy()
        view.contextMenuDelegate = reuseSpy
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
        // WebKit builds a fresh menu per open; each must gain exactly one set.
        for _ in 0..<2 {
            let menu = NSMenu()
            menu.addItem(withTitle: "Open Link in New Window", action: nil, keyEquivalent: "")
            view.willOpenMenu(menu, with: event)
            XCTAssertEqual(menu.items.filter { $0.identifier == ContextMenuWebView.openLinkHereIdentifier }.count, 1)
            XCTAssertEqual(menu.items.filter { $0.identifier == ContextMenuWebView.openLinkPrivateIdentifier }.count, 1)
        }
    }

    func testLinkGroupEndsWithSeparator() throws {
        @MainActor
        final class SeparatorSpy: NSObject, WebViewContextMenuDelegate {
            func webView(_ webView: WKWebView, didRequestPageSelectorSuggestAt point: NSPoint) {}
            func webViewAllowsPageSelectorSuggest(_ webView: WKWebView) -> Bool { false }
        }
        let view = ContextMenuWebView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600),
            configuration: WKWebViewConfiguration()
        )
        let separatorSpy = SeparatorSpy()
        view.contextMenuDelegate = separatorSpy
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Link in New Window", action: nil, keyEquivalent: "")
        menu.addItem(withTitle: "Copy Link", action: nil, keyEquivalent: "")
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
        let titles = menu.items.map { $0.isSeparatorItem ? "<separator>" : $0.title }
        XCTAssertEqual(titles, [
            "Open Link Here",
            "Open Link in New Window",
            "Open Link in System Browser",
            "Open Private",
            "<separator>",
            "Copy Link"
        ])
    }

    func testSuggestSitsAfterInspect() throws {
        @MainActor
        final class InspectSpy: NSObject, WebViewContextMenuDelegate {
            func webView(_ webView: WKWebView, didRequestPageSelectorSuggestAt point: NSPoint) {}
            func webViewAllowsPageSelectorSuggest(_ webView: WKWebView) -> Bool { true }
        }
        let view = ContextMenuWebView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600),
            configuration: WKWebViewConfiguration()
        )
        let inspectSpy = InspectSpy()
        view.contextMenuDelegate = inspectSpy
        let menu = NSMenu()
        menu.addItem(withTitle: "Reload Page", action: nil, keyEquivalent: "")
        menu.addItem(withTitle: "Inspect Element", action: nil, keyEquivalent: "")
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
        let titles = menu.items.map { $0.isSeparatorItem ? "<separator>" : $0.title }
        XCTAssertEqual(titles, ["Reload Page", "Inspect Element", "Suggest Selector..."])
    }
}

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
        // The anchor is resolved in the frame that received the right-click
        // and posted to native, so links inside subframes survive
        // main-frame-only evaluation.
        XCTAssertTrue(script.contains(WebScripts.contextLinkHandlerName))
        XCTAssertTrue(script.contains("composedPath"))
        XCTAssertTrue(script.contains("closest"))
        XCTAssertTrue(script.contains("e.target.closest"))
        XCTAssertTrue(script.contains("postMessage"))
        // The anchor facts a plain click's destination depends on travel
        // with the href: the target attribute decides new-window requests,
        // the download attribute turns the click into a download.
        XCTAssertTrue(script.contains("getAttribute(\"target\")"))
        XCTAssertTrue(script.contains("hasAttribute(\"download\")"))
        XCTAssertTrue(script.contains("target: target"))
        XCTAssertTrue(script.contains("download: download"))
        // target=_parent lands on the main frame only when the posting
        // frame's parent is the main frame; the page reports it by
        // reference comparison, which stays allowed across origins.
        XCTAssertTrue(script.contains("window.parent === window.top"))
        XCTAssertTrue(script.contains("parentIsMainFrame: parentIsMainFrame"))
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

    func testLinkContextScriptResolvesAnchor() {
        let script = WebScripts.makeLinkContextScript(x: 10, y: 20)
        XCTAssertTrue(script.contains("elementFromPoint"))
        XCTAssertTrue(script.contains("closest"))
        XCTAssertTrue(script.contains("a[href]"))
        XCTAssertTrue(script.contains("__quiperLastContextMenu"))
        // The fallback reports the same dictionary shape the recorder posts,
        // so native parses one shape for both sources.
        XCTAssertTrue(script.contains("getAttribute(\"target\")"))
        XCTAssertTrue(script.contains("hasAttribute(\"download\")"))
        XCTAssertTrue(script.contains("href:"))
        XCTAssertTrue(script.contains("target:"))
        XCTAssertTrue(script.contains("download:"))
        // No link at the point answers empty values, never a bare string.
        XCTAssertTrue(script.contains("{ href: \"\", target: \"\", download: false }"))
    }

    func testContextLinkRecordingAnswersOnlyItsOwnMenu() {
        let webView = WKWebView()
        let otherWebView = WKWebView()
        let menuOpenedAt = Date()

        // Delivered just before the menu opened and just after it (delivery
        // trailing the menu) both answer this menu.
        let deliveredBefore = ContextLinkRecording(
            href: "https://example.com/before",
            target: "",
            isDownload: false,
            isMainFrame: true,
            parentFrameIsMainFrame: true,
            webViewIdentifier: ObjectIdentifier(webView),
            receivedAt: menuOpenedAt.addingTimeInterval(-0.5)
        )
        XCTAssertTrue(deliveredBefore.answers(menuOpenedAt: menuOpenedAt, on: webView))
        let deliveredAfter = ContextLinkRecording(
            href: "https://example.com/after",
            target: "",
            isDownload: false,
            isMainFrame: true,
            parentFrameIsMainFrame: true,
            webViewIdentifier: ObjectIdentifier(webView),
            receivedAt: menuOpenedAt.addingTimeInterval(1)
        )
        XCTAssertTrue(deliveredAfter.answers(menuOpenedAt: menuOpenedAt, on: webView))

        // A posting from an earlier menu (its own delivery lost) must never
        // answer this menu: opening the earlier link would be worse than
        // falling back to point resolution.
        let earlierMenu = ContextLinkRecording(
            href: "https://example.com/earlier",
            target: "",
            isDownload: false,
            isMainFrame: true,
            parentFrameIsMainFrame: true,
            webViewIdentifier: ObjectIdentifier(webView),
            receivedAt: menuOpenedAt.addingTimeInterval(-ContextLinkRecording.menuDeliveryAllowance - 1)
        )
        XCTAssertFalse(earlierMenu.answers(menuOpenedAt: menuOpenedAt, on: webView))

        // Another webview's posting never answers this menu.
        XCTAssertFalse(deliveredBefore.answers(menuOpenedAt: menuOpenedAt, on: otherWebView))
    }

    func testRecordedContextLinkURLGatesTheRecordingPath() {
        let webView = WKWebView()
        let otherWebView = WKWebView()
        let menuOpenedAt = Date()

        // The recording that answers this menu on this webview resolves —
        // the path that makes link actions work inside iframes.
        let recording = ContextLinkRecording(
            href: "https://example.com/link",
            target: "",
            isDownload: false,
            isMainFrame: true,
            parentFrameIsMainFrame: true,
            webViewIdentifier: ObjectIdentifier(webView),
            receivedAt: menuOpenedAt
        )
        XCTAssertEqual(
            WebViewManager.recordedContextLinkURL(recording: recording, menuOpenedAt: menuOpenedAt, for: webView),
            URL(string: "https://example.com/link")
        )

        // No recording, no recorded menu, or another webview's recording:
        // resolution falls back to the main-frame point path.
        XCTAssertNil(WebViewManager.recordedContextLinkURL(recording: nil, menuOpenedAt: menuOpenedAt, for: webView))
        XCTAssertNil(WebViewManager.recordedContextLinkURL(recording: recording, menuOpenedAt: nil, for: webView))
        XCTAssertNil(WebViewManager.recordedContextLinkURL(recording: recording, menuOpenedAt: menuOpenedAt, for: otherWebView))

        // A posting from outside the delivery allowance belongs to an
        // earlier menu and must not resolve.
        let stale = ContextLinkRecording(
            href: "https://example.com/stale",
            target: "",
            isDownload: false,
            isMainFrame: true,
            parentFrameIsMainFrame: true,
            webViewIdentifier: ObjectIdentifier(webView),
            receivedAt: menuOpenedAt.addingTimeInterval(-ContextLinkRecording.menuDeliveryAllowance - 1)
        )
        XCTAssertNil(WebViewManager.recordedContextLinkURL(recording: stale, menuOpenedAt: menuOpenedAt, for: webView))

        // Only http(s) hrefs qualify, the same rule the point path applies.
        for href in ["", "mailto:someone@example.com", "javascript:alert(1)"] {
            let invalid = ContextLinkRecording(
                href: href,
                target: "",
                isDownload: false,
                isMainFrame: true,
                parentFrameIsMainFrame: true,
                webViewIdentifier: ObjectIdentifier(webView),
                receivedAt: menuOpenedAt
            )
            XCTAssertNil(WebViewManager.recordedContextLinkURL(recording: invalid, menuOpenedAt: menuOpenedAt, for: webView))
        }
    }

    func testRecordedContextLinkCarriesAnchorAndFrameFacts() {
        let webView = WKWebView()
        let menuOpenedAt = Date()
        let recording = ContextLinkRecording(
            href: "https://example.com/link",
            target: "_blank",
            isDownload: true,
            isMainFrame: false,
            parentFrameIsMainFrame: true,
            webViewIdentifier: ObjectIdentifier(webView),
            receivedAt: menuOpenedAt
        )
        let link = WebViewManager.recordedContextLink(recording: recording, menuOpenedAt: menuOpenedAt, for: webView)
        XCTAssertEqual(link?.url, URL(string: "https://example.com/link"))
        XCTAssertEqual(link?.target, "_blank")
        XCTAssertEqual(link?.isDownload, true)
        XCTAssertEqual(link?.isMainFrame, false)
        XCTAssertEqual(link?.parentFrameIsMainFrame, true)
    }

    func testContextLinkFromPointEvaluationReadsTheFallbackDictionary() {
        let link = WebViewManager.contextLink(fromPointEvaluation: [
            "href": "https://example.com/page",
            "target": "_blank",
            "download": true
        ])
        XCTAssertEqual(link?.url, URL(string: "https://example.com/page"))
        XCTAssertEqual(link?.target, "_blank")
        XCTAssertEqual(link?.isDownload, true)
        // The fallback runs in the main frame, so whatever it finds sits in
        // the main frame with no parent above it.
        XCTAssertEqual(link?.isMainFrame, true)
        XCTAssertEqual(link?.parentFrameIsMainFrame, true)

        // A non-http href, or a result that is not the dictionary the script
        // returns, resolves to nothing rather than guessing.
        XCTAssertNil(WebViewManager.contextLink(fromPointEvaluation: [
            "href": "mailto:someone@example.com",
            "target": "",
            "download": false
        ]))
        XCTAssertNil(WebViewManager.contextLink(fromPointEvaluation: "not a dictionary"))
        XCTAssertNil(WebViewManager.contextLink(fromPointEvaluation: nil))
    }

    func testPlainClickPredictionCompletesOnlyForItsOwnWebview() {
        @MainActor
        final class AnswerLog {
            var answers: [ContextMenuLinkAction?] = []
        }
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let manager = WebViewManager(containerView: container)
        let webviewA = WKWebView()
        let webviewB = WKWebView()
        let answerLog = AnswerLog()
        manager.webViewWillOpenContextMenu(webviewA)
        manager.webView(webviewA, resolvePlainClickActionAt: .zero) { answerLog.answers.append($0) }

        // A posting from another webview may take the shared slot, but it
        // must never complete webview A's open menu: the gate compares the
        // posting against the prediction's webview, not against the
        // posting's own — which always matches itself.
        manager.recordContextLinkPosting(
            href: "https://example.com/b",
            target: "",
            isDownload: false,
            isMainFrame: true,
            parentFrameIsMainFrame: true,
            webView: webviewB
        )
        XCTAssertTrue(answerLog.answers.isEmpty)

        // The menu's own webview completing it — exactly once.
        manager.recordContextLinkPosting(
            href: "https://example.com/a",
            target: "",
            isDownload: false,
            isMainFrame: true,
            parentFrameIsMainFrame: true,
            webView: webviewA
        )
        XCTAssertEqual(answerLog.answers.count, 1)
    }

    func testPlainClickPredictionNeverCommitsToAPostingThatPredatesTheMenu() {
        @MainActor
        final class AnswerLog {
            var answers: [ContextMenuLinkAction?] = []
        }
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let manager = WebViewManager(containerView: container)
        let webview = WKWebView()
        // A recording left in the slot by an earlier right-click must not
        // answer the new menu the moment it opens: this request runs in the
        // same turn that stamped the menu's open time, so everything in the
        // slot predates the menu — and this menu's own posting, whose
        // delivery trails the menu, may still be in flight. The slot answers
        // only at the grace window, where a fresher posting supersedes it.
        manager.recordContextLinkPosting(
            href: "https://example.com/earlier",
            target: "",
            isDownload: false,
            isMainFrame: true,
            parentFrameIsMainFrame: true,
            webView: webview
        )
        manager.webViewWillOpenContextMenu(webview)
        let answerLog = AnswerLog()
        manager.webView(webview, resolvePlainClickActionAt: .zero) { answerLog.answers.append($0) }
        XCTAssertTrue(answerLog.answers.isEmpty)
    }

    func testWillOpenMenuNotifiesDelegate() throws {
        @MainActor
        final class MenuOpenSpy: NSObject, WebViewContextMenuDelegate {
            var openedCount = 0
            func webView(_ webView: WKWebView, didRequestPageSelectorSuggestAt point: NSPoint) {}
            func webViewAllowsPageSelectorSuggest(_ webView: WKWebView) -> Bool { false }
            func webViewWillOpenContextMenu(_ webView: WKWebView) {
                openedCount += 1
            }
        }
        let view = ContextMenuWebView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600),
            configuration: WKWebViewConfiguration()
        )
        let menuOpenSpy = MenuOpenSpy()
        view.contextMenuDelegate = menuOpenSpy
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
        XCTAssertEqual(menuOpenSpy.openedCount, 1)
    }

    func testContextMenuRecorderInjectedOnlyForEngineTabs() {
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
        let engineTab = manager.getOrCreateWebView(
            for: service,
            sessionIndex: 0,
            dragArea: nil,
            loadImmediately: false
        )
        let privateTab = manager.getOrCreateWebView(
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
        let engineScripts = engineTab.configuration.userContentController.userScripts.map(\.source)
        XCTAssertTrue(engineScripts.contains { $0.contains(WebScripts.contextLinkHandlerName) })
        // Private tabs stay marker-free: no recorder, so their link actions
        // keep resolving at the point in the main frame. Only the script half
        // is observable here — WKUserContentController exposes no way to list
        // registered message handlers.
        let privateScripts = privateTab.configuration.userContentController.userScripts.map(\.source)
        XCTAssertFalse(privateScripts.contains { $0.contains(WebScripts.contextLinkHandlerName) })
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

    // MARK: - Plain-click indicator

    private func predicted(
        target: String = "",
        isDownload: Bool = false,
        isMainFrame: Bool = true,
        parentFrameIsMainFrame: Bool = true,
        decision: RoutingResolver.Decision
    ) -> ContextMenuLinkAction? {
        ContextMenuLinkAction.predictedByClick(
            target: target,
            isDownload: isDownload,
            isMainFrame: isMainFrame,
            parentFrameIsMainFrame: parentFrameIsMainFrame,
            routingDecision: decision
        )
    }

    func testPlainClickPredictionMirrorsRouting() {
        // A plain main-frame click is exactly what routing decides, mapped
        // onto the menu item that performs it.
        XCTAssertEqual(predicted(decision: .openHere), .openHere)
        XCTAssertEqual(predicted(decision: .openNewWindow), .openNewWindow)
        XCTAssertEqual(predicted(decision: .openExternal), .openSystemBrowser)
        // The prompt and a cancelled navigation are no single menu item, so
        // nothing gets marked.
        XCTAssertNil(predicted(decision: .showPrompt))
        XCTAssertNil(predicted(decision: .cancel))
    }

    func testPlainClickPredictionHandlesTargetAndFrame() {
        // target=_blank always opens a Quiper popup — createWebViewWith
        // bypasses routing — in any frame, whatever routing would say.
        XCTAssertEqual(predicted(target: "_blank", decision: .openExternal), .openNewWindow)
        XCTAssertEqual(predicted(target: " _BLANK ", isMainFrame: false, decision: .openHere), .openNewWindow)
        // A download attribute turns the click into a download before
        // routing ever runs, so no menu item matches it.
        XCTAssertNil(predicted(target: "_blank", isDownload: true, decision: .openHere))
        XCTAssertNil(predicted(isDownload: true, decision: .openExternal))
        // A click that stays inside a subframe navigates that subframe,
        // which none of the menu's actions do.
        XCTAssertNil(predicted(isMainFrame: false, decision: .openExternal))
        XCTAssertNil(predicted(target: "_self", isMainFrame: false, decision: .openExternal))
        // target=_parent from a subframe: a main-frame parent routes, a
        // subframe parent keeps the click inside a frame.
        XCTAssertEqual(
            predicted(target: "_parent", isMainFrame: false, parentFrameIsMainFrame: true, decision: .openExternal),
            .openSystemBrowser
        )
        XCTAssertNil(predicted(target: "_parent", isMainFrame: false, parentFrameIsMainFrame: false, decision: .openExternal))
        // target=_top always reaches the main frame, so routing applies
        // even from deep inside a subframe.
        XCTAssertEqual(
            predicted(target: "_top", isMainFrame: false, parentFrameIsMainFrame: false, decision: .openHere),
            .openHere
        )
        // A named target frame may exist (navigating without routing) or
        // not (a new window), so it answers nothing rather than guessing.
        XCTAssertNil(predicted(target: "sidebar", decision: .openExternal))
    }

    /// Whether the item's title renders in bold — the plain-click emphasis.
    /// A plain title, or an attributed one without the bold trait, reads as
    /// unemphasized.
    private func isBold(_ item: NSMenuItem?) -> Bool {
        guard let title = item?.attributedTitle, title.length > 0 else { return false }
        let font = title.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        return font?.fontDescriptor.symbolicTraits.contains(.bold) ?? false
    }

    func testLinkMenuBoldsThePlainClickAction() throws {
        @MainActor
        final class IndicatorSpy: NSObject, WebViewContextMenuDelegate {
            var answer: ContextMenuLinkAction?
            func webView(_ webView: WKWebView, didRequestPageSelectorSuggestAt point: NSPoint) {}
            func webViewAllowsPageSelectorSuggest(_ webView: WKWebView) -> Bool { false }
            func webView(_ webView: WKWebView, resolvePlainClickActionAt point: NSPoint, completion: @escaping @MainActor @Sendable (ContextMenuLinkAction?) -> Void) {
                completion(answer)
            }
        }
        let view = ContextMenuWebView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600),
            configuration: WKWebViewConfiguration()
        )
        let spy = IndicatorSpy()
        view.contextMenuDelegate = spy
        spy.answer = .openSystemBrowser
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Link in New Window", action: nil, keyEquivalent: "")
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

        let item = { (identifier: NSUserInterfaceItemIdentifier) in
            menu.items.first { $0.identifier == identifier }
        }
        XCTAssertTrue(isBold(item(ContextMenuWebView.openLinkSystemBrowserIdentifier)))
        XCTAssertFalse(isBold(item(ContextMenuWebView.openLinkHereIdentifier)))
        XCTAssertFalse(isBold(item(ContextMenuWebView.openLinkNewWindowIdentifier)))
        XCTAssertFalse(isBold(item(ContextMenuWebView.openLinkPrivateIdentifier)))
        // Emphasis never rewrites the labels.
        XCTAssertEqual(item(ContextMenuWebView.openLinkSystemBrowserIdentifier)?.title, "Open Link in System Browser")
    }

    func testLinkMenuIgnoresAnAnswerFromAnEarlierMenu() throws {
        @MainActor
        final class DelayedIndicatorSpy: NSObject, WebViewContextMenuDelegate {
            var completions: [@MainActor @Sendable (ContextMenuLinkAction?) -> Void] = []
            func webView(_ webView: WKWebView, didRequestPageSelectorSuggestAt point: NSPoint) {}
            func webViewAllowsPageSelectorSuggest(_ webView: WKWebView) -> Bool { false }
            func webView(_ webView: WKWebView, resolvePlainClickActionAt point: NSPoint, completion: @escaping @MainActor @Sendable (ContextMenuLinkAction?) -> Void) {
                completions.append(completion)
            }
        }
        let view = ContextMenuWebView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600),
            configuration: WKWebViewConfiguration()
        )
        let spy = DelayedIndicatorSpy()
        view.contextMenuDelegate = spy
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
        let firstMenu = NSMenu()
        firstMenu.addItem(withTitle: "Open Link in New Window", action: nil, keyEquivalent: "")
        view.willOpenMenu(firstMenu, with: event)
        let secondMenu = NSMenu()
        secondMenu.addItem(withTitle: "Open Link in New Window", action: nil, keyEquivalent: "")
        view.willOpenMenu(secondMenu, with: event)
        XCTAssertEqual(spy.completions.count, 2)

        // The first menu's answer lands after a second menu opened; it must
        // emphasize neither the replaced menu nor the current one.
        spy.completions[0](.openHere)
        XCTAssertTrue(firstMenu.items.allSatisfy { !isBold($0) })
        XCTAssertTrue(secondMenu.items.allSatisfy { !isBold($0) })

        // The current menu's own answer emphasizes exactly its matching
        // item, and only there.
        spy.completions[1](.openHere)
        XCTAssertTrue(isBold(secondMenu.items.first { $0.identifier == ContextMenuWebView.openLinkHereIdentifier }))
        XCTAssertFalse(isBold(secondMenu.items.first { $0.identifier == ContextMenuWebView.openLinkSystemBrowserIdentifier }))
    }
}

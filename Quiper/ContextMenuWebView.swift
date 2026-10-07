import AppKit
import WebKit

/// Link action chosen from the webview's native context menu.
@MainActor
enum ContextMenuLinkAction {
    case openHere
    case openNewWindow
    case openSystemBrowser
    case openPrivate
}

/// Receives context menu actions from the webview's native menu, with the
/// right-click point in the webview's own coordinates.
@MainActor
protocol WebViewContextMenuDelegate: AnyObject {
    func webView(_ webView: WKWebView, didRequestPageSelectorSuggestAt point: NSPoint)
    /// Whether the webview's tab may offer Suggest Selector. Ephemeral tabs
    /// answer false, leaving the native menu pristine.
    func webViewAllowsPageSelectorSuggest(_ webView: WKWebView) -> Bool
    /// A link menu item was chosen. The manager resolves the href at `point`
    /// and performs the navigation, so the view never touches page content.
    func webView(_ webView: WKWebView, didRequestLinkAction action: ContextMenuLinkAction, at point: NSPoint)
    /// Resolves what a plain left-click on the link at `point` would do, so
    /// the menu can render that item bold. Href resolution crosses
    /// into the page, so the answer arrives asynchronously; nil when a click
    /// would do none of the menu's actions.
    func webView(_ webView: WKWebView, resolvePlainClickActionAt point: NSPoint, completion: @escaping @MainActor @Sendable (ContextMenuLinkAction?) -> Void)
    /// The native menu is about to open. The manager records the moment so a
    /// context-link posting can be tied to the menu that follows it.
    func webViewWillOpenContextMenu(_ webView: WKWebView)
}

extension WebViewContextMenuDelegate {
    func webView(_ webView: WKWebView, didRequestLinkAction action: ContextMenuLinkAction, at point: NSPoint) {}
    func webView(_ webView: WKWebView, resolvePlainClickActionAt point: NSPoint, completion: @escaping @MainActor @Sendable (ContextMenuLinkAction?) -> Void) {
        completion(nil)
    }
    func webViewWillOpenContextMenu(_ webView: WKWebView) {}
}

/// Session webview that edits WebKit's native context menu. WebKit exposes
/// no delegate API for this on macOS, but the native menu passes through
/// `NSView.willOpenMenu`, where items can be added to (never replacing) what
/// WebKit built. Link items replace WebKit's default Open-Link items when the
/// menu was built for a link; Suggest Selector sits right after Inspect. If a
/// future macOS stops routing the menu through here, the native menu simply
/// shows without our items: degradation is a missing item, never a broken
/// menu.
@MainActor
final class ContextMenuWebView: WKWebView {
    static let suggestSelectorItemIdentifier = NSUserInterfaceItemIdentifier("quiper-suggest-selector")
    static let openLinkHereIdentifier = NSUserInterfaceItemIdentifier("quiper-open-link-here")
    static let openLinkNewWindowIdentifier = NSUserInterfaceItemIdentifier("quiper-open-link-new-window")
    static let openLinkSystemBrowserIdentifier = NSUserInterfaceItemIdentifier("quiper-open-link-system-browser")
    static let openLinkPrivateIdentifier = NSUserInterfaceItemIdentifier("quiper-open-link-private")
    static let openLinkSeparatorIdentifier = NSUserInterfaceItemIdentifier("quiper-open-link-separator")

    private static let linkItemIdentifiers: Set<NSUserInterfaceItemIdentifier> = [
        openLinkHereIdentifier,
        openLinkNewWindowIdentifier,
        openLinkSystemBrowserIdentifier,
        openLinkPrivateIdentifier
    ]

    weak var contextMenuDelegate: WebViewContextMenuDelegate?
    private var lastMenuPoint: NSPoint = .zero
    /// Counts menu opens so the plain-click answer for an earlier menu — it
    /// crosses into the page and can land late — can never mark the items of
    /// a later one.
    private var menuGeneration = 0

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        lastMenuPoint = convert(event.locationInWindow, from: nil)
        menuGeneration += 1
        contextMenuDelegate?.webViewWillOpenContextMenu(self)
        if insertLinkItemsIfNeeded(into: menu) {
            requestPlainClickIndicator(for: menu, generation: menuGeneration)
        }
        insertSuggestItemIfNeeded(into: menu)
    }

    /// When WebKit builds a link menu it includes default Open-Link items.
    /// Their presence is the synchronous link signal: no JS round-trip is
    /// needed to decide whether this menu is for a link. Ours replace them.
    /// Returns whether this menu is a link menu.
    @discardableResult
    private func insertLinkItemsIfNeeded(into menu: NSMenu) -> Bool {
        // Strip ours first so a reused menu never stacks duplicates or shows
        // stale link items on a non-link menu.
        for item in menu.items where item.identifier.map({ Self.linkItemIdentifiers.contains($0) || $0 == Self.openLinkSeparatorIdentifier }) ?? false {
            menu.removeItem(item)
        }
        let openLinkIndexes = menu.items.indices.filter { Self.isDefaultOpenLinkItem(menu.items[$0]) }
        guard !openLinkIndexes.isEmpty else { return false }
        for index in openLinkIndexes.reversed() {
            menu.removeItem(at: index)
        }
        let items = [
            makeLinkItem(title: "Open Link Here", identifier: Self.openLinkHereIdentifier, action: #selector(openLinkHereFromPageMenu(_:))),
            makeLinkItem(title: "Open Link in New Window", identifier: Self.openLinkNewWindowIdentifier, action: #selector(openLinkInNewWindowFromPageMenu(_:))),
            makeLinkItem(title: "Open Link in System Browser", identifier: Self.openLinkSystemBrowserIdentifier, action: #selector(openLinkInSystemBrowserFromPageMenu(_:))),
            makeLinkItem(title: "Open Private", identifier: Self.openLinkPrivateIdentifier, action: #selector(openLinkPrivateFromPageMenu(_:)))
        ]
        let index = min(openLinkIndexes.min() ?? 0, menu.items.count)
        for (offset, item) in items.enumerated() {
            menu.insertItem(item, at: index + offset)
        }
        // Separate the link group from whatever native items follow. Skip
        // when at the end (nothing to separate from) or when WebKit already
        // left a separator there.
        let separatorIndex = index + items.count
        if separatorIndex < menu.items.count && !menu.items[separatorIndex].isSeparatorItem {
            let separator = NSMenuItem.separator()
            separator.identifier = Self.openLinkSeparatorIdentifier
            menu.insertItem(separator, at: separatorIndex)
        }
        return true
    }

    /// Renders the item a plain click on this link would perform in bold —
    /// the Finder-style default-action emphasis. The answer can arrive after
    /// the menu opened — the manager may still be resolving the href — so it
    /// is applied whenever it lands, while this menu is still the current
    /// one.
    private func requestPlainClickIndicator(for menu: NSMenu, generation: Int) {
        contextMenuDelegate?.webView(self, resolvePlainClickActionAt: lastMenuPoint) { [weak self, weak menu] action in
            guard let self, let menu, generation == self.menuGeneration else { return }
            self.applyPlainClickIndicator(action, in: menu)
        }
    }

    /// Bolds the title of the item matching `action` and restores the rest
    /// to plain titles, so exactly one item can ever be emphasized. Only the
    /// title font is set: AppKit keeps its own colors, so highlighted items
    /// still read correctly.
    private func applyPlainClickIndicator(_ action: ContextMenuLinkAction?, in menu: NSMenu) {
        let indicated = action.map(Self.linkItemIdentifier(for:))
        let boldFont = NSFontManager.shared.convert(NSFont.menuFont(ofSize: 0), toHaveTrait: .boldFontMask)
        for item in menu.items {
            guard let identifier = item.identifier, Self.linkItemIdentifiers.contains(identifier) else { continue }
            if identifier == indicated {
                item.attributedTitle = NSAttributedString(string: item.title, attributes: [.font: boldFont])
            } else {
                item.attributedTitle = nil
            }
        }
    }

    private static func linkItemIdentifier(for action: ContextMenuLinkAction) -> NSUserInterfaceItemIdentifier {
        switch action {
        case .openHere: return openLinkHereIdentifier
        case .openNewWindow: return openLinkNewWindowIdentifier
        case .openSystemBrowser: return openLinkSystemBrowserIdentifier
        case .openPrivate: return openLinkPrivateIdentifier
        }
    }

    private static func isDefaultOpenLinkItem(_ item: NSMenuItem) -> Bool {
        if item.identifier.map({ linkItemIdentifiers.contains($0) }) ?? false { return false }
        if item.isSeparatorItem { return false }
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard title.hasPrefix("open") else { return false }
        return title.contains("link")
    }

    private func makeLinkItem(title: String, identifier: NSUserInterfaceItemIdentifier, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.identifier = identifier
        item.target = self
        return item
    }

    /// Suggest Selector pairs with Inspect: it sits right after WebKit's
    /// Inspect item, falling back to the menu end (with a separating line)
    /// when no Inspect item exists, e.g. in tests or a future menu layout.
    private func insertSuggestItemIfNeeded(into menu: NSMenu) {
        guard contextMenuDelegate?.webViewAllowsPageSelectorSuggest(self) == true else { return }
        guard !menu.items.contains(where: { $0.identifier == Self.suggestSelectorItemIdentifier }) else { return }
        let item = NSMenuItem(
            title: "Suggest Selector...",
            action: #selector(suggestSelectorFromPageMenu(_:)),
            keyEquivalent: ""
        )
        item.identifier = Self.suggestSelectorItemIdentifier
        item.target = self
        if let inspectIndex = menu.items.firstIndex(where: { Self.isInspectItem($0) }) {
            menu.insertItem(item, at: inspectIndex + 1)
        } else if menu.items.isEmpty {
            menu.addItem(item)
        } else {
            if !menu.items.last!.isSeparatorItem {
                menu.addItem(.separator())
            }
            menu.addItem(item)
        }
    }

    private static func isInspectItem(_ item: NSMenuItem) -> Bool {
        if item.isSeparatorItem { return false }
        if item.identifier.map({ $0 == suggestSelectorItemIdentifier || linkItemIdentifiers.contains($0) || $0 == openLinkSeparatorIdentifier }) ?? false {
            return false
        }
        return item.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().contains("inspect")
    }

    @objc private func suggestSelectorFromPageMenu(_ sender: NSMenuItem) {
        contextMenuDelegate?.webView(self, didRequestPageSelectorSuggestAt: lastMenuPoint)
    }

    @objc private func openLinkHereFromPageMenu(_ sender: NSMenuItem) {
        contextMenuDelegate?.webView(self, didRequestLinkAction: .openHere, at: lastMenuPoint)
    }

    @objc private func openLinkInNewWindowFromPageMenu(_ sender: NSMenuItem) {
        contextMenuDelegate?.webView(self, didRequestLinkAction: .openNewWindow, at: lastMenuPoint)
    }

    @objc private func openLinkInSystemBrowserFromPageMenu(_ sender: NSMenuItem) {
        contextMenuDelegate?.webView(self, didRequestLinkAction: .openSystemBrowser, at: lastMenuPoint)
    }

    @objc private func openLinkPrivateFromPageMenu(_ sender: NSMenuItem) {
        contextMenuDelegate?.webView(self, didRequestLinkAction: .openPrivate, at: lastMenuPoint)
    }
}

extension ContextMenuLinkAction {
    /// What a plain left-click on a link performs, from the anchor's `target`
    /// and `download` attributes, the frame the anchor sits in, and the
    /// routing decision a main-frame destination takes. Routing decides
    /// same-origin and rule-matched targets in place, in a popup, or in the
    /// system browser; `target="_blank"` always opens a Quiper popup because
    /// `createWebViewWith` bypasses routing. A click that stays inside a
    /// subframe, a download, a named target frame that may or may not exist,
    /// and a routing prompt do none of the menu's actions, so they answer
    /// nil rather than a misleading emphasis.
    static func predictedByClick(
        target: String,
        isDownload: Bool,
        isMainFrame: Bool,
        parentFrameIsMainFrame: Bool,
        routingDecision: RoutingResolver.Decision
    ) -> ContextMenuLinkAction? {
        if isDownload { return nil }
        switch target.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "_blank":
            return .openNewWindow
        case "_top":
            break
        case "_parent":
            if !parentFrameIsMainFrame { return nil }
        case "_self", "":
            if !isMainFrame { return nil }
        default:
            return nil
        }
        switch routingDecision {
        case .openHere: return .openHere
        case .openNewWindow: return .openNewWindow
        case .openExternal: return .openSystemBrowser
        case .showPrompt, .cancel: return nil
        }
    }
}

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
}

extension WebViewContextMenuDelegate {
    func webView(_ webView: WKWebView, didRequestLinkAction action: ContextMenuLinkAction, at point: NSPoint) {}
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

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        lastMenuPoint = convert(event.locationInWindow, from: nil)
        insertLinkItemsIfNeeded(into: menu)
        insertSuggestItemIfNeeded(into: menu)
    }

    /// When WebKit builds a link menu it includes default Open-Link items.
    /// Their presence is the synchronous link signal: no JS round-trip is
    /// needed to decide whether this menu is for a link. Ours replace them.
    private func insertLinkItemsIfNeeded(into menu: NSMenu) {
        // Strip ours first so a reused menu never stacks duplicates or shows
        // stale link items on a non-link menu.
        for item in menu.items where item.identifier.map({ Self.linkItemIdentifiers.contains($0) || $0 == Self.openLinkSeparatorIdentifier }) ?? false {
            menu.removeItem(item)
        }
        let openLinkIndexes = menu.items.indices.filter { Self.isDefaultOpenLinkItem(menu.items[$0]) }
        guard !openLinkIndexes.isEmpty else { return }
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

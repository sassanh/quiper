import AppKit
import WebKit

/// Receives the Suggest Selector action from the webview's native context
/// menu, with the right-click point in the webview's own coordinates.
@MainActor
protocol WebViewContextMenuDelegate: AnyObject {
    func webView(_ webView: WKWebView, didRequestPageSelectorSuggestAt point: NSPoint)
    /// Whether the webview's tab may offer Suggest Selector. Ephemeral tabs
    /// answer false, leaving the native menu pristine.
    func webViewAllowsPageSelectorSuggest(_ webView: WKWebView) -> Bool
}

/// Session webview that inserts Suggest Selector into WebKit's native
/// context menu. WebKit exposes no delegate API for this on macOS, but the
/// native menu passes through `NSView.willOpenMenu`, where items can be
/// added to (never replacing) what WebKit built. If a future macOS stops
/// routing the menu through here, the native menu simply shows without our
/// item: degradation is a missing item, never a broken menu.
@MainActor
final class ContextMenuWebView: WKWebView {
    static let suggestSelectorItemIdentifier = NSUserInterfaceItemIdentifier("quiper-suggest-selector")

    weak var contextMenuDelegate: WebViewContextMenuDelegate?
    private var lastMenuPoint: NSPoint = .zero

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        guard contextMenuDelegate?.webViewAllowsPageSelectorSuggest(self) == true else { return }
        lastMenuPoint = convert(event.locationInWindow, from: nil)
        guard !menu.items.contains(where: { $0.identifier == Self.suggestSelectorItemIdentifier }) else { return }
        let item = NSMenuItem(
            title: "Suggest Selector...",
            action: #selector(suggestSelectorFromPageMenu(_:)),
            keyEquivalent: ""
        )
        item.identifier = Self.suggestSelectorItemIdentifier
        item.target = self
        menu.insertItem(item, at: 0)
        if menu.items.count > 1 {
            menu.insertItem(.separator(), at: 1)
        }
    }

    @objc private func suggestSelectorFromPageMenu(_ sender: NSMenuItem) {
        contextMenuDelegate?.webView(self, didRequestPageSelectorSuggestAt: lastMenuPoint)
    }
}

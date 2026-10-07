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

/// Which menu item a click on the link performs, resolved once per menu for
/// every held-modifier combination: `bare` is the plain click's item, the
/// others the items ⌘-, ⌘⇧-, ⌘⌥-, and ⌥-clicks perform. The open menu
/// re-reads this as modifiers are held and released, so the bold tracks the
/// click about to happen without resolving the link again.
struct PlainClickEmphasis {
    let bare: ContextMenuLinkAction?
    let command: ContextMenuLinkAction?
    let commandShift: ContextMenuLinkAction?
    let commandOption: ContextMenuLinkAction?
    let option: ContextMenuLinkAction?

    /// The item the click performs with `modifiers` held. Shift without ⌘
    /// means nothing; with ⌘ it names Open Private even if ⌥ rides along.
    func action(modifiers: ClickModifiers) -> ContextMenuLinkAction? {
        switch (modifiers.commandPressed, modifiers.optionPressed, modifiers.shiftPressed) {
        case (true, _, true): return commandShift
        case (true, true, false): return commandOption
        case (true, false, _): return command
        case (false, true, _): return option
        case (false, false, _): return bare
        }
    }
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
    /// Resolves which menu item a click on the link at `point` performs for
    /// each held-modifier combination, so the menu can render that item bold
    /// and keep the bold in sync while modifiers are held and released.
    /// Href resolution crosses into the page, so the answer arrives
    /// asynchronously; nil when no combination performs one of the actions.
    func webView(_ webView: WKWebView, resolvePlainClickActionAt point: NSPoint, completion: @escaping @MainActor @Sendable (PlainClickEmphasis?) -> Void)
    /// The native menu is about to open. The manager records the moment so a
    /// context-link posting can be tied to the menu that follows it.
    func webViewWillOpenContextMenu(_ webView: WKWebView)
}

extension WebViewContextMenuDelegate {
    func webView(_ webView: WKWebView, didRequestLinkAction action: ContextMenuLinkAction, at point: NSPoint) {}
    func webView(_ webView: WKWebView, resolvePlainClickActionAt point: NSPoint, completion: @escaping @MainActor @Sendable (PlainClickEmphasis?) -> Void) {
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
    /// The current link menu's per-modifier emphasis, set when its answer
    /// lands and re-rendered whenever the held modifiers change.
    private var plainClickEmphasis: PlainClickEmphasis?
    /// The indicator's last rendered item, so an unchanged outcome rewrites
    /// nothing and every menu starts from a clean slate.
    private var lastIndicatedItem: NSUserInterfaceItemIdentifier?
    /// Ticks while the menu tracks events, moving the bold to the item the
    /// click would perform as ⌘/⌥ are held and released.
    private var modifierWatch: Timer?
    /// The menu the watch ticks for — read from the main actor so the
    /// timer's closure never captures the menu itself.
    private weak var watchedMenu: NSMenu?

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        lastMenuPoint = convert(event.locationInWindow, from: nil)
        menuGeneration += 1
        plainClickEmphasis = nil
        lastIndicatedItem = nil
        contextMenuDelegate?.webViewWillOpenContextMenu(self)
        if insertLinkItemsIfNeeded(into: menu) {
            requestPlainClickIndicator(for: menu, generation: menuGeneration)
            startModifierWatch(for: menu)
        } else {
            stopModifierWatch()
        }
        insertSuggestItemIfNeeded(into: menu)
    }

    override func didCloseMenu(_ menu: NSMenu, with event: NSEvent?) {
        super.didCloseMenu(menu, with: event)
        stopModifierWatch()
        plainClickEmphasis = nil
        lastIndicatedItem = nil
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
            makeLinkItem(title: "Open Link Here", identifier: Self.openLinkHereIdentifier, action: #selector(openLinkHereFromPageMenu(_:)), keyEquivalentModifiers: [.option]),
            makeLinkItem(title: "Open Link in New Window", identifier: Self.openLinkNewWindowIdentifier, action: #selector(openLinkInNewWindowFromPageMenu(_:)), keyEquivalentModifiers: [.command]),
            makeLinkItem(title: "Open Link in System Browser", identifier: Self.openLinkSystemBrowserIdentifier, action: #selector(openLinkInSystemBrowserFromPageMenu(_:)), keyEquivalentModifiers: [.option, .command]),
            makeLinkItem(title: "Open Private", identifier: Self.openLinkPrivateIdentifier, action: #selector(openLinkPrivateFromPageMenu(_:)), keyEquivalentModifiers: [.shift, .command])
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

    /// Resolves the link's per-modifier emphasis for this menu. The answer
    /// can arrive after the menu opened — the manager may still be resolving
    /// the href — so it is applied whenever it lands, while this menu is
    /// still the current one.
    private func requestPlainClickIndicator(for menu: NSMenu, generation: Int) {
        contextMenuDelegate?.webView(self, resolvePlainClickActionAt: lastMenuPoint) { [weak self, weak menu] emphasis in
            guard let self, let menu, generation == self.menuGeneration else { return }
            self.plainClickEmphasis = emphasis
            self.renderPlainClickIndicator(in: menu, modifiers: .current)
        }
    }

    /// How often an open menu re-reads held modifiers — well under the
    /// threshold where the bold moving would read as lag.
    private static let modifierWatchInterval: TimeInterval = 0.05

    /// Watches held ⌘/⌥ for as long as this menu is open. The watch runs in
    /// the common run-loop modes because the menu's own event tracking runs
    /// the loop in tracking mode, where a default-mode timer would sleep
    /// until the menu closed.
    private func startModifierWatch(for menu: NSMenu) {
        stopModifierWatch()
        watchedMenu = menu
        let timer = Timer(timeInterval: Self.modifierWatchInterval, repeats: true) { [weak self] _ in
            // The timer fires on the main run loop; the watch's state and
            // rendering are main-actor work.
            MainActor.assumeIsolated {
                guard let self, let menu = self.watchedMenu, self.plainClickEmphasis != nil else { return }
                self.renderPlainClickIndicator(in: menu, modifiers: .current)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        modifierWatch = timer
    }

    private func stopModifierWatch() {
        modifierWatch?.invalidate()
        modifierWatch = nil
        watchedMenu = nil
    }

    /// Renders the item the click would perform with `modifiers` held in
    /// bold — the Finder-style default-action emphasis. Both states are
    /// written as full attributed strings: reverting a bolded item on a
    /// live menu with `attributedTitle = nil` does not fall back to its
    /// title — the item stops drawing and disappears. Only the font is
    /// set: AppKit keeps its own colors, so highlighted items still read
    /// correctly. An outcome that matches what is already rendered — a
    /// fresh menu included, its items plain — rewrites nothing.
    func renderPlainClickIndicator(in menu: NSMenu, modifiers: ClickModifiers) {
        let action = plainClickEmphasis?.action(modifiers: modifiers)
        let indicated = action.map(Self.linkItemIdentifier(for:))
        guard indicated != lastIndicatedItem else { return }
        lastIndicatedItem = indicated
        let boldFont = NSFontManager.shared.convert(NSFont.menuFont(ofSize: 0), toHaveTrait: .boldFontMask)
        let plainFont = NSFont.menuFont(ofSize: 0)
        for item in menu.items {
            guard let identifier = item.identifier, Self.linkItemIdentifiers.contains(identifier) else { continue }
            item.attributedTitle = NSAttributedString(
                string: item.title,
                attributes: [.font: identifier == indicated ? boldFont : plainFont]
            )
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

    private func makeLinkItem(
        title: String,
        identifier: NSUserInterfaceItemIdentifier,
        action: Selector,
        keyEquivalentModifiers: NSEvent.ModifierFlags = []
    ) -> NSMenuItem {
        let item: NSMenuItem
        if keyEquivalentModifiers.isEmpty {
            item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        } else {
            // The hint sits in AppKit's native right-aligned shortcut slot:
            // the mask renders the modifier glyphs in canonical order, and
            // the "key" is a zero-width space — it draws as nothing and can
            // never be typed, so the hint stays a hint and fires nothing.
            item = NSMenuItem(title: title, action: action, keyEquivalent: "\u{200B}")
            item.keyEquivalentModifierMask = keyEquivalentModifiers
        }
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
    /// What a click on a link performs, from the anchor's `target` and
    /// `download` attributes, the frame the anchor sits in, the routing
    /// decision a main-frame destination takes, and the modifiers held for
    /// this click. `routingDecision` comes from `RoutingResolver.route`
    /// already run with these same modifiers, so a main-frame destination is
    /// exactly what the click performs; `target="_blank"` always opens a
    /// Quiper popup because `createWebViewWith` bypasses routing, with held
    /// modifiers forcing against that bare outcome instead — ⌘⇧ opening the
    /// link in a private tab wherever it would have gone. A click that
    /// stays inside a subframe, a download, and a named target frame that
    /// may or may not exist answer nil when no modifier names a definite
    /// action; a routing prompt answers nil for a bare click and yields to
    /// ⌥. Downloads win over every modifier combination, because
    /// `shouldPerformDownload` runs before routing sees the click.
    static func predictedByClick(
        target: String,
        isDownload: Bool,
        isMainFrame: Bool,
        parentFrameIsMainFrame: Bool,
        routingDecision: RoutingResolver.Decision,
        modifiers: ClickModifiers = .none,
        isPinnedTabs: Bool = false
    ) -> ContextMenuLinkAction? {
        if isDownload { return nil }
        switch target.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "_blank":
            // createWebViewWith makes the bare outcome a popup whatever
            // routing says about the destination.
            let decision = RoutingResolver.modifierDecision(
                modifiers: modifiers,
                bareDecision: .openNewWindow,
                isPinnedTabs: isPinnedTabs
            ) ?? .openNewWindow
            return menuAction(for: decision)
        case "_top":
            break
        case "_parent":
            if !parentFrameIsMainFrame { return forcedAction(modifiers: modifiers, bareDecision: nil, isPinnedTabs: isPinnedTabs) }
        case "_self", "":
            if !isMainFrame { return forcedAction(modifiers: modifiers, bareDecision: nil, isPinnedTabs: isPinnedTabs) }
        default:
            // A named frame may exist (navigating it) or not (a new window).
            return forcedAction(modifiers: modifiers, bareDecision: nil, isPinnedTabs: isPinnedTabs)
        }
        return menuAction(for: routingDecision)
    }

    /// The item modifiers force on an outcome the bare click leaves
    /// undecided — a click that stays inside its frame, a named target that
    /// may not exist. ⌘, ⌘⇧, and ⌘⌥ always name a definite action. ⌥
    /// answers nothing: exact for a frame that exists, where the click
    /// keeps its frame-local outcome; deliberately silent for a named frame
    /// that may not exist, where the click really would open in place — the
    /// preview cannot know whether the frame is there, so it claims nothing.
    private static func forcedAction(
        modifiers: ClickModifiers,
        bareDecision: RoutingResolver.Decision?,
        isPinnedTabs: Bool
    ) -> ContextMenuLinkAction? {
        guard let decision = RoutingResolver.modifierDecision(
            modifiers: modifiers,
            bareDecision: bareDecision,
            isPinnedTabs: isPinnedTabs
        ) else { return nil }
        return menuAction(for: decision)
    }

    /// Maps a routing decision onto the menu item that performs it; the
    /// prompt and a cancelled navigation are no single menu item, so they
    /// answer nil rather than a misleading emphasis.
    private static func menuAction(for decision: RoutingResolver.Decision) -> ContextMenuLinkAction? {
        switch decision {
        case .openHere: return .openHere
        case .openNewWindow: return .openNewWindow
        case .openExternal: return .openSystemBrowser
        case .openPrivate: return .openPrivate
        case .showPrompt, .cancel: return nil
        }
    }
}

extension ClickModifiers {
    /// The click modifiers held right now: the menu's live bold preview
    /// reads the physical state, because the next click carries these.
    static var current: ClickModifiers {
        ClickModifiers(NSEvent.modifierFlags)
    }

    init(_ flags: NSEvent.ModifierFlags) {
        self.init(
            commandPressed: flags.contains(.command),
            optionPressed: flags.contains(.option),
            shiftPressed: flags.contains(.shift)
        )
    }
}

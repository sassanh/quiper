import AppKit

/// The toolbar strip of a popup window: the overlay's navigation, loading,
/// minimize/restore, and close controls without session chrome. Session
/// selectors, prompt history, and session actions are deliberately absent —
/// they describe a tab, not a popup page — while everything that operates on
/// the page itself (back/forward, refresh/stop, the title, the loading
/// border) behaves exactly like the main window's header. Drags move the
/// window, like the main window's bar.
final class PopupToolbarView: DraggableView {

    /// What a hold on the minimize toggle offers: the whole tree of
    /// windows this popup heads, minimized or restored in one gesture —
    /// the same hold that lists the navigation buttons' history.
    enum CollapseMenuItem {
        case collapseSubtree
        case expandSubtree
    }

    let navigationButtonGroup = NavigationButtonGroup()
    let titleLabel = HoverTextField(labelWithString: "")
    let loadingBorderView = LoadingBorderView()
    let refreshStopButton = RefreshStopButton()
    let collapseButton = WindowCollapseButton(target: nil, action: nil)
    let closeButton: WindowCloseButton

    var onBack: (() -> Void)?
    var onForward: (() -> Void)?
    var onLongPressBack: (() -> [(title: String, url: URL)])?
    var onLongPressForward: (() -> [(title: String, url: URL)])?
    var onNavigateToBackItem: ((Int) -> Void)?
    var onNavigateToForwardItem: ((Int) -> Void)?
    var onRefreshStop: (() -> Void)?
    var onToggleCollapse: (() -> Void)?
    /// Runs the tree action chosen from the hold menu; the window applies
    /// it to itself and every popup nested under it.
    var onCollapseMenuItemSelected: ((CollapseMenuItem) -> Void)?
    var onClose: (() -> Void)?

    /// Whether the strip is minimized: a minimized strip carries the page
    /// title and nothing else — no navigation, refresh/stop, minimize, or
    /// close controls. The title stays so the strip still names its window.
    private var areControlsHidden = false

    /// Whether the hold menu is tracking: a release that ends the hold
    /// must not also count as a click on the toggle.
    private var isCollapseMenuVisible = false

    override init(frame frameRect: NSRect) {
        // The trailing end pairs three controls: close draws ✕, the
        // minimize toggle draws −/+, and stop draws ■, so side by side
        // the glyphs keep the controls unmistakable.
        closeButton = WindowCloseButton(accessibilityDescription: "Close Window", target: nil, action: nil)

        super.init(frame: frameRect)
        setAccessibilityIdentifier("PopupToolbar")

        navigationButtonGroup.setAccessibilityIdentifier("PopupNavigationButtonGroup")
        // No navigation has happened yet; the window's observation syncs
        // this the moment the webview reports history.
        navigationButtonGroup.isHidden = true
        navigationButtonGroup.onBack = { [weak self] in self?.onBack?() }
        navigationButtonGroup.onForward = { [weak self] in self?.onForward?() }
        navigationButtonGroup.onLongPressBack = { [weak self] in self?.onLongPressBack?() ?? [] }
        navigationButtonGroup.onLongPressForward = { [weak self] in self?.onLongPressForward?() ?? [] }
        navigationButtonGroup.onNavigateToBackItem = { [weak self] in self?.onNavigateToBackItem?($0) }
        navigationButtonGroup.onNavigateToForwardItem = { [weak self] in self?.onNavigateToForwardItem?($0) }
        addSubview(navigationButtonGroup)

        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.alignment = .center
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.setAccessibilityIdentifier("PopupTitle")
        // A collapsed strip's tooltip comes from the strip itself — what a
        // click here does — and the truncated-title overlay would double it.
        titleLabel.shouldShowTooltip = { [weak self] _ in
            self?.areControlsHidden != true
        }
        addSubview(titleLabel)

        loadingBorderView.setAccessibilityIdentifier("PopupLoadingIndicator")
        loadingBorderView.enablesWindowDrag = true
        loadingBorderView.isHidden = true
        titleLabel.hitTestView = loadingBorderView
        addSubview(loadingBorderView, positioned: .below, relativeTo: titleLabel)

        refreshStopButton.setAccessibilityIdentifier("PopupRefreshStopButton")
        refreshStopButton.target = self
        refreshStopButton.action = #selector(refreshStopClicked)
        addSubview(refreshStopButton)

        closeButton.tooltipText = "Close Window"
        closeButton.tooltipShortcut = "⌘W"
        closeButton.setAccessibilityIdentifier("PopupCloseButton")
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        addSubview(closeButton)

        collapseButton.setAccessibilityIdentifier("PopupCollapseButton")
        collapseButton.target = self
        collapseButton.action = #selector(collapseClicked)
        collapseButton.onLongPress = { [weak self] in self?.showCollapseMenu() }
        addSubview(collapseButton)

        needsLayout = true
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Syncs back/forward availability. Relayouts because the title slot
    /// spans from the navigation group to the trailing controls. History
    /// can re-offer the group at any moment — a minimized strip shows no
    /// controls, and that rule wins until the window expands, so this is
    /// the one place the two states are reconciled.
    func updateNavigation(showBack: Bool, showForward: Bool) {
        navigationButtonGroup.update(showBack: showBack, showForward: showForward)
        if areControlsHidden {
            navigationButtonGroup.isHidden = true
        }
        needsLayout = true
    }

    /// Mirrors the page's loading state into the refresh/stop toggle and
    /// the animated title border — the same indicators the main window
    /// shows while its header is visible.
    func setLoading(_ loading: Bool) {
        refreshStopButton.isLoadingState = loading
        if loading {
            loadingBorderView.startAnimating()
        } else {
            loadingBorderView.stopAnimating()
        }
        needsLayout = true
    }

    func setTitleText(_ text: String) {
        titleLabel.stringValue = text
    }

    /// Mirrors the window's collapse state: the minimize toggle flips to
    /// the action the window will take next, and a minimized strip drops
    /// every control — the title alone remains, until the window expands.
    /// The bare strip teaches itself: the hand cursor and the tooltip
    /// that names a click's payoff both arrive with the collapse and
    /// leave with the expand. A state flip under a stationary cursor
    /// fires no enter/exit event, so the transition itself retires the
    /// affordances when it expands.
    func setCollapsed(_ collapsed: Bool) {
        collapseButton.isCollapsed = collapsed
        guard areControlsHidden != collapsed else { return }
        areControlsHidden = collapsed
        refreshStopButton.isHidden = collapsed
        collapseButton.isHidden = collapsed
        closeButton.isHidden = collapsed
        QuickTooltip.shared.hide(for: self)
        if !collapsed {
            NSCursor.arrow.set()
        }
        updateNavigation(
            showBack: navigationButtonGroup.showBack,
            showForward: navigationButtonGroup.showForward
        )
    }

    private var stripTrackingArea: NSTrackingArea?

    /// The strip's hand cursor and tooltip ride a tracking area, not
    /// cursor rects: AppKit only sets up a window's cursor rects once
    /// the window is key, and a strip the user has never clicked has
    /// never been key — precisely the hover these affordances exist for.
    /// Expanded, nothing happens here and the system's own cursors
    /// (controls, resize edges) stand.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = stripTrackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        stripTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        guard areControlsHidden else { return }
        NSCursor.pointingHand.set()
        QuickTooltip.shared.show(Self.expandTooltip, for: self)
    }

    override func mouseExited(with event: NSEvent) {
        guard areControlsHidden else { return }
        QuickTooltip.shared.hide(for: self)
        NSCursor.arrow.set()
    }

    /// Applies the focus-loss dim to the strip as a whole. Under any dim
    /// the title takes the full-strength label color: secondary gray at a
    /// fraction of the window's transparency, over whatever sits behind
    /// the strip, stops being readable — and the title is how a dimmed
    /// strip still names its window.
    func setFocusLossDimmed(_ level: FocusLossLevel) {
        alphaValue = level.alpha
        titleLabel.textColor = level == .clear ? .secondaryLabelColor : .labelColor
    }

    /// The tooltip a minimized strip carries: the one action a bare strip
    /// offers with a click.
    private static let expandTooltip = "Click to expand"

    override func layout() {
        super.layout()

        let headerHeight = bounds.height
        let buttonSize: CGFloat = 24
        let groupHeight: CGFloat = 25
        let gap: CGFloat = 4
        let inset: CGFloat = 4
        let titleAreaMargin: CGFloat = 2
        let titlePadding: CGFloat = 4
        let buttonY = (headerHeight - buttonSize) / 2
        let groupY = (headerHeight - groupHeight) / 2

        // Close keeps the trailing edge, the minimize toggle sits
        // immediately left of it, and refresh/stop left of that — the
        // three glyphs (✕, −/+, ■) keep the controls distinct — with
        // navigation and the page title leading at the left.
        closeButton.frame = NSRect(
            x: bounds.width - inset - buttonSize,
            y: buttonY,
            width: buttonSize,
            height: buttonSize
        )
        collapseButton.frame = NSRect(
            x: closeButton.frame.minX - gap - buttonSize,
            y: buttonY,
            width: buttonSize,
            height: buttonSize
        )
        refreshStopButton.frame = NSRect(
            x: collapseButton.frame.minX - gap - buttonSize,
            y: buttonY,
            width: buttonSize,
            height: buttonSize
        )

        let navWidth = navigationButtonGroup.idealWidth
        let leftMaxX: CGFloat
        if !navigationButtonGroup.isHidden && navWidth > 0 {
            navigationButtonGroup.frame = NSRect(x: inset, y: groupY, width: navWidth, height: groupHeight)
            leftMaxX = navigationButtonGroup.frame.maxX
        } else {
            leftMaxX = inset
        }

        let titleAreaX = leftMaxX + gap + titleAreaMargin
        // A minimized strip has no controls, so the title owns the full
        // width between the insets; otherwise it stops short of the slot
        // the refresh/stop button occupies.
        let titleRightEdge = areControlsHidden
            ? bounds.width - inset
            : refreshStopButton.frame.minX - gap
        let titleWidth = max(0, titleRightEdge - titleAreaMargin - titleAreaX)
        let shouldHideTitleArea = titleWidth < 40

        loadingBorderView.frame = NSRect(x: titleAreaX, y: groupY, width: titleWidth, height: groupHeight)
        loadingBorderView.isHidden = shouldHideTitleArea || !loadingBorderView.isAnimating

        let titleHeight = titleLabel.intrinsicContentSize.height
        titleLabel.frame = NSRect(
            x: titleAreaX + titlePadding,
            y: (headerHeight - titleHeight) / 2,
            width: max(0, titleWidth - titlePadding * 2),
            height: titleHeight
        )
        titleLabel.isHidden = shouldHideTitleArea
    }

    @objc private func refreshStopClicked() {
        onRefreshStop?()
    }

    @objc private func collapseClicked() {
        // A release that ends the hold menu must not also toggle the window.
        guard !isCollapseMenuVisible else { return }
        onToggleCollapse?()
    }

    /// Hold on the minimize toggle: the tree actions open beside the
    /// control, the way a hold on back/forward opens their history.
    private func showCollapseMenu() {
        let menu = makeCollapseMenu()
        isCollapseMenuVisible = true
        defer { isCollapseMenuVisible = false }
        let origin = NSPoint(x: 0, y: collapseButton.bounds.height + 4)
        menu.popUp(positioning: nil, at: origin, in: collapseButton)
    }

    /// The hold menu, built without opening it: titles, icons, and
    /// routing in one place, inspectable without a tracking session.
    func makeCollapseMenu() -> NSMenu {
        let menu = NSMenu()
        for item in [CollapseMenuItem.collapseSubtree, .expandSubtree] {
            let menuItem = NSMenuItem(
                title: Self.title(for: item),
                action: #selector(collapseMenuItemClicked(_:)),
                keyEquivalent: ""
            )
            menuItem.target = self
            menuItem.image = HoverIconButton.symbolImage(
                named: Self.symbolName(for: item),
                accessibilityDescription: Self.title(for: item)
            )
            menuItem.representedObject = item
            menu.addItem(menuItem)
        }
        return menu
    }

    private static func title(for item: CollapseMenuItem) -> String {
        switch item {
        case .collapseSubtree: "Collapse All Children"
        case .expandSubtree: "Expand All Children"
        }
    }

    private static func symbolName(for item: CollapseMenuItem) -> String {
        switch item {
        case .collapseSubtree: "rectangle.compress.vertical"
        case .expandSubtree: "rectangle.expand.vertical"
        }
    }

    @objc private func collapseMenuItemClicked(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? CollapseMenuItem else { return }
        onCollapseMenuItemSelected?(item)
    }

    @objc private func closeClicked() {
        onClose?()
    }
}

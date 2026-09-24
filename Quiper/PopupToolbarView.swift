import AppKit

/// The toolbar strip of a popup window: the overlay's navigation, loading,
/// and close controls without session chrome. Session selectors, prompt
/// history, and session actions are deliberately absent — they describe a
/// tab, not a popup page — while everything that operates on the page
/// itself (back/forward, refresh/stop, the title, the loading border)
/// behaves exactly like the main window's header. Drags move the window,
/// like the main window's bar.
final class PopupToolbarView: DraggableView {

    let navigationButtonGroup = NavigationButtonGroup()
    let titleLabel = HoverTextField(labelWithString: "")
    let loadingBorderView = LoadingBorderView()
    let refreshStopButton = RefreshStopButton()
    let closeButton: HoverIconButton

    var onBack: (() -> Void)?
    var onForward: (() -> Void)?
    var onLongPressBack: (() -> [(title: String, url: URL)])?
    var onLongPressForward: (() -> [(title: String, url: URL)])?
    var onNavigateToBackItem: ((Int) -> Void)?
    var onNavigateToForwardItem: ((Int) -> Void)?
    var onRefreshStop: (() -> Void)?
    var onClose: (() -> Void)?

    override init(frame frameRect: NSRect) {
        // Circled X: the stop-loading control uses the plain X, and the two
        // sit side by side in this toolbar while a page loads.
        let closeConfig = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        let closeImage = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: "Close Window")!
            .withSymbolConfiguration(closeConfig)!
        closeButton = HoverIconButton(image: closeImage, target: nil, action: nil)

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

        needsLayout = true
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Syncs back/forward availability. Relayouts because the title slot
    /// spans from the navigation group to the trailing buttons.
    func updateNavigation(showBack: Bool, showForward: Bool) {
        navigationButtonGroup.update(showBack: showBack, showForward: showForward)
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

        closeButton.frame = NSRect(
            x: bounds.width - inset - buttonSize,
            y: buttonY,
            width: buttonSize,
            height: buttonSize
        )
        refreshStopButton.frame = NSRect(
            x: closeButton.frame.minX - gap - buttonSize,
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
        let titleWidth = max(0, refreshStopButton.frame.minX - gap - titleAreaMargin - titleAreaX)
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

    @objc private func closeClicked() {
        onClose?()
    }
}

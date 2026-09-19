import AppKit
import WebKit

@MainActor
final class TabHistoryHUDView: NSView {
    
    private weak var wc: MainWindowController?
    private let visualEffectView: NSVisualEffectView
    private let rowsStackView = NSStackView()
    
    private(set) var currentItemsCount = 0
    private(set) var currentMaxItemsPerRow = 3

    /// Explicit item list for modifier-hold HUDs. When non-nil, the history
    /// ring items are bypassed and these cards are shown instead.
    private var overrideItems: [TabIdentifier]?
    private var overrideHighlight: TabIdentifier?
    private var overrideDigit: ((TabIdentifier) -> Int)?
    private var overrideTitle: ((TabIdentifier) -> String)?
    /// When non-nil, cards show engine icons instead of tab previews.
    private var overrideIcon: ((TabIdentifier) -> NSImage?)?

    func showOverride(
        items: [TabIdentifier],
        highlight: TabIdentifier?,
        digit: ((TabIdentifier) -> Int)?,
        title: ((TabIdentifier) -> String)?,
        icon: ((TabIdentifier) -> NSImage?)? = nil
    ) {
        overrideItems = items
        overrideHighlight = highlight
        overrideDigit = digit
        overrideTitle = title
        overrideIcon = icon
        lastHoveredTab = nil
        updateSelection()
    }

    func updateOverrideHighlight(_ highlight: TabIdentifier?) {
        guard overrideItems != nil else { return }
        overrideHighlight = highlight
        updateSelection()
    }

    func clearOverride() {
        overrideItems = nil
        overrideHighlight = nil
        overrideDigit = nil
        overrideTitle = nil
        overrideIcon = nil
        lastHoveredTab = nil
        onHoverTab = nil
        onSelectTab = nil
    }

    /// Hover entry from a card. Ignores re-entry for the card already under
    /// the cursor (rebuilds recreate views without cursor movement), so
    /// arrow-key highlight never snaps back while the mouse rests.
    func cardMouseEntered(_ tab: TabIdentifier) {
        guard tab != lastHoveredTab else { return }
        lastHoveredTab = tab
        onHoverTab?(tab)
    }

    /// Hover exit from a card. Only falls back to the current tab when the
    /// exiting card owns the highlight, so leaving a non-highlighted card
    /// never wipes an arrow-key selection.
    func cardMouseExited(_ tab: TabIdentifier) {
        guard lastHoveredTab == tab else { return }
        lastHoveredTab = nil
        if overrideHighlight == tab {
            onHoverTab?(nil)
        }
    }

    var isShowingOverride: Bool { overrideItems != nil }
    var currentOverrideItems: [TabIdentifier]? { overrideItems }
    var currentOverrideHighlight: TabIdentifier? { overrideHighlight }

    /// Card the cursor is physically inside, regardless of highlight. Guards
    /// against re-firing hover when card rebuilds (highlight/title/refresh)
    /// recreate the view under a stationary cursor.
    private var lastHoveredTab: TabIdentifier?

    /// Hover highlight for the card under the cursor. Set by the modifier
    /// ring; nil leaves the history ring mouse-inert as before.
    var onHoverTab: ((TabIdentifier?) -> Void)?
    /// Click selection for the card under the cursor. Nil keeps cards inert.
    var onSelectTab: ((TabIdentifier) -> Void)?
    
    init(frame frameRect: NSRect, windowController: MainWindowController) {
        self.wc = windowController
        
        visualEffectView = NSVisualEffectView(frame: NSRect(origin: .zero, size: frameRect.size))
        
        super.init(frame: frameRect)
        
        self.appearance = NSAppearance(named: .vibrantDark)
        self.autoresizingMask = [.width, .height]
        
        // Base view shadow styling
        self.wantsLayer = true
        self.layer?.cornerRadius = 16
        self.layer?.shadowColor = NSColor.black.cgColor
        self.layer?.shadowOpacity = 0.5
        self.layer?.shadowOffset = CGSize(width: 0, height: -6)
        self.layer?.shadowRadius = 16
        self.layer?.backgroundColor = NSColor.clear.cgColor
        
        // Visual Effect backdrop with rounded mask and border
        visualEffectView.autoresizingMask = [.width, .height]
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 16
        visualEffectView.layer?.masksToBounds = true
        visualEffectView.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        visualEffectView.layer?.borderWidth = 1
        visualEffectView.material = .hudWindow
        visualEffectView.state = .active
        visualEffectView.blendingMode = .withinWindow
        addSubview(visualEffectView)
        
        // Premium dark backing layer overlay to increase contrast
        let darkBacking = NSView(frame: bounds)
        darkBacking.autoresizingMask = [.width, .height]
        darkBacking.wantsLayer = true
        darkBacking.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.25).cgColor
        visualEffectView.addSubview(darkBacking)
        
        setupStackView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupStackView() {
        rowsStackView.orientation = .vertical
        rowsStackView.spacing = 12
        rowsStackView.alignment = .leading
        
        visualEffectView.addSubview(rowsStackView)
        rowsStackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            rowsStackView.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor, constant: 16),
            rowsStackView.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor, constant: -16),
            rowsStackView.topAnchor.constraint(equalTo: visualEffectView.topAnchor, constant: 16),
            rowsStackView.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor, constant: -16)
        ])
    }
    
    func updateSelection() {
        guard let wc = wc else { return }
        
        // Rebuild rowsStackView to display all items in the ring
        rowsStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        
        let override = overrideItems
        var items: [TabIdentifier] = []
        // The really selected tab. Drives the card border.
        var activeTab: TabIdentifier?
        // The prospective tab (hover/arrows). Drives the accent highlight.
        // Release commits it; digits move it together with the selection.
        var highlightedTab: TabIdentifier?
        var digitForTab: ((TabIdentifier) -> Int)?
        var titleForTab: ((TabIdentifier) -> String)?
        var iconForTab: ((TabIdentifier) -> NSImage?)?
        if let override {
            items = override
            activeTab = wc.currentTabIdentifier()
            highlightedTab = overrideHighlight ?? activeTab
            digitForTab = overrideDigit
            titleForTab = overrideTitle
            iconForTab = overrideIcon
        } else {
            if let start = wc.cyclingStartTab {
                items.append(start)
            }
            for tab in wc.tabHistory {
                if !items.contains(tab) {
                    items.append(tab)
                }
            }
            if wc.isCyclingHistory {
                activeTab = wc.highlightedTab
            } else {
                activeTab = wc.currentTabIdentifier()
            }
        }
        
        guard !items.isEmpty else { return }
        
        // Dynamic row items selection logic to maximize items in last row (choosing between 3, 4, and 5)
        let n = items.count
        self.currentItemsCount = n
        
        let lastRow3 = n % 3 == 0 ? 3 : n % 3
        let lastRow4 = n % 4 == 0 ? 4 : n % 4
        let lastRow5 = n % 5 == 0 ? 5 : n % 5
        
        let maxItemsPerRow: Int
        if lastRow5 >= lastRow4 && lastRow5 >= lastRow3 && n >= 5 {
            maxItemsPerRow = 5
        } else if lastRow4 >= lastRow3 && lastRow4 >= lastRow5 && n >= 4 {
            maxItemsPerRow = 4
        } else {
            maxItemsPerRow = 3
        }
        self.currentMaxItemsPerRow = maxItemsPerRow
        
        let itemWidth: CGFloat = 148
        
        // Split items into chunks of maxItemsPerRow
        var chunks: [[TabIdentifier]] = []
        var currentChunk: [TabIdentifier] = []
        for item in items {
            currentChunk.append(item)
            if currentChunk.count == maxItemsPerRow {
                chunks.append(currentChunk)
                currentChunk = []
            }
        }
        if !currentChunk.isEmpty {
            chunks.append(currentChunk)
        }
        
        for chunk in chunks {
            let rowStack = NSStackView()
            rowStack.orientation = .horizontal
            rowStack.spacing = 12
            rowStack.alignment = .centerY
            rowStack.distribution = .fill
            
            for tab in chunk {
                let isActive = (tab == activeTab)
                let isHighlighted = highlightedTab.map { $0 == tab } ?? false
                let iconMode = iconForTab != nil
                let card = createTabCard(
                    for: tab,
                    isActive: isActive,
                    isHighlighted: isHighlighted,
                    width: itemWidth,
                    digitOverride: digitForTab?(tab),
                    titleOverride: titleForTab?(tab),
                    iconMode: iconMode,
                    icon: iconMode ? iconForTab?(tab) : nil,
                    fallbackName: iconMode ? wc.services.first(where: { $0.id == tab.serviceID })?.name : nil
                )
                rowStack.addArrangedSubview(card)
            }
            
            rowsStackView.addArrangedSubview(rowStack)
        }
        
        self.needsLayout = true
    }
    
    private func createTabCard(for tab: TabIdentifier, isActive: Bool, isHighlighted: Bool = false, width: CGFloat, digitOverride: Int? = nil, titleOverride: String? = nil, iconMode: Bool = false, icon: NSImage? = nil, fallbackName: String? = nil) -> NSView {
        let card = HUDCardView()
        card.wantsLayer = true
        card.layer?.cornerRadius = 10
        card.layer?.masksToBounds = true
        card.tab = tab
        card.host = self
        card.onSelect = onSelectTab
        card.setAccessibilityRole(.button)
        
        card.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            card.widthAnchor.constraint(equalToConstant: width),
            card.heightAnchor.constraint(equalToConstant: 130)
        ])
        
        // Border marks the really selected tab; the accent border marks the
        // prospective (hover/arrow) highlight. Selection wins when both land
        // on one card.
        if isActive {
            card.layer?.borderColor = NSColor.black.cgColor
            card.layer?.borderWidth = 3.0
        } else if isHighlighted {
            card.layer?.borderColor = NSColor.controlAccentColor.cgColor
            card.layer?.borderWidth = 2.5
        } else {
            card.layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
            card.layer?.borderWidth = 1.0
        }
        
        // Find corresponding service
        let service = wc?.services.first { $0.id == tab.serviceID }
        let tabNum = digitOverride ?? (tab.sessionIndex == 9 ? 10 : tab.sessionIndex + 1)
        
        let pageTitle: String
        if let titleOverride {
            pageTitle = titleOverride
        } else if let svc = service, let wv = wc?.webViewManager.getWebView(for: svc, sessionIndex: tab.sessionIndex), let title = wv.title, !title.isEmpty {
            pageTitle = title
        } else {
            pageTitle = "Empty Session"
        }
        card.setAccessibilityLabel("\(tabNum): \(pageTitle)")
        
        if iconMode {
            let topArea = NSView()
            topArea.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(topArea)

            NSLayoutConstraint.activate([
                topArea.topAnchor.constraint(equalTo: card.topAnchor),
                topArea.leadingAnchor.constraint(equalTo: card.leadingAnchor),
                topArea.trailingAnchor.constraint(equalTo: card.trailingAnchor),
                topArea.heightAnchor.constraint(equalToConstant: 90)
            ])

            if let icon {
                let imageView = NSImageView()
                imageView.image = icon
                imageView.imageScaling = .scaleProportionallyUpOrDown
                imageView.wantsLayer = true
                imageView.layer?.cornerRadius = 10
                imageView.layer?.masksToBounds = true
                imageView.translatesAutoresizingMaskIntoConstraints = false
                topArea.addSubview(imageView)

                NSLayoutConstraint.activate([
                    imageView.centerXAnchor.constraint(equalTo: topArea.centerXAnchor),
                    imageView.centerYAnchor.constraint(equalTo: topArea.centerYAnchor),
                    imageView.widthAnchor.constraint(equalToConstant: 46),
                    imageView.heightAnchor.constraint(equalToConstant: 46)
                ])
            } else {
                let letter = fallbackName?.first.map { String($0) } ?? "?"
                let letterField = NSTextField(labelWithString: letter)
                letterField.font = .systemFont(ofSize: 30, weight: .light)
                letterField.textColor = NSColor.white.withAlphaComponent(0.45)
                letterField.alignment = .center
                letterField.translatesAutoresizingMaskIntoConstraints = false
                topArea.addSubview(letterField)

                NSLayoutConstraint.activate([
                    letterField.centerXAnchor.constraint(equalTo: topArea.centerXAnchor),
                    letterField.centerYAnchor.constraint(equalTo: topArea.centerYAnchor)
                ])
            }
        } else if let previewImage = wc?.tabPreviews[tab],
           let cgImage = previewImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            
            // Preview Image view at the top 90pt
            let previewView = NSView()
            previewView.wantsLayer = true
            previewView.layer?.contentsGravity = .resizeAspectFill
            previewView.layer?.contents = cgImage
            previewView.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(previewView)
            
            NSLayoutConstraint.activate([
                previewView.topAnchor.constraint(equalTo: card.topAnchor),
                previewView.leadingAnchor.constraint(equalTo: card.leadingAnchor),
                previewView.trailingAnchor.constraint(equalTo: card.trailingAnchor),
                previewView.heightAnchor.constraint(equalToConstant: 90)
            ])
            
        } else {
            // Leave background transparent if preview is not available
            card.layer?.backgroundColor = NSColor.clear.cgColor
        }
        
        // Bottom Overlay (identical layout for both preview/gradient cases)
        let overlayView = NSView()
        overlayView.wantsLayer = true
        overlayView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.82).cgColor
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(overlayView)
        
        NSLayoutConstraint.activate([
            overlayView.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            overlayView.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            overlayView.heightAnchor.constraint(equalToConstant: 40)
        ])
        
        // Digit on the Left
        let digitContainer = NSView()
        digitContainer.translatesAutoresizingMaskIntoConstraints = false
        overlayView.addSubview(digitContainer)
        
        let digitField = NSTextField(labelWithString: "\(tabNum)")
        digitField.font = .systemFont(ofSize: 22, weight: .bold)
        digitField.textColor = isActive ? NSColor.controlAccentColor : NSColor.white.withAlphaComponent(0.65)
        digitField.alignment = .center
        digitField.translatesAutoresizingMaskIntoConstraints = false
        digitContainer.addSubview(digitField)
        
        NSLayoutConstraint.activate([
            digitContainer.leadingAnchor.constraint(equalTo: overlayView.leadingAnchor),
            digitContainer.topAnchor.constraint(equalTo: overlayView.topAnchor),
            digitContainer.bottomAnchor.constraint(equalTo: overlayView.bottomAnchor),
            digitContainer.widthAnchor.constraint(equalToConstant: 28),
            
            digitField.centerXAnchor.constraint(equalTo: digitContainer.centerXAnchor),
            digitField.centerYAnchor.constraint(equalTo: digitContainer.centerYAnchor)
        ])
        
        // Title on the Right (2-line wrapping label)
        let titleField = NSTextField()
        titleField.isEditable = false
        titleField.isSelectable = false
        titleField.isBordered = false
        titleField.drawsBackground = false
        titleField.font = .systemFont(ofSize: 10, weight: .semibold)
        titleField.textColor = isActive ? .white : NSColor.white.withAlphaComponent(0.7)
        titleField.alignment = .left
        titleField.cell?.wraps = true
        titleField.cell?.usesSingleLineMode = false
        titleField.cell?.lineBreakMode = .byTruncatingTail
        titleField.maximumNumberOfLines = 2
        titleField.stringValue = pageTitle
        titleField.translatesAutoresizingMaskIntoConstraints = false
        overlayView.addSubview(titleField)
        
        NSLayoutConstraint.activate([
            titleField.leadingAnchor.constraint(equalTo: digitContainer.trailingAnchor, constant: 4),
            titleField.trailingAnchor.constraint(equalTo: overlayView.trailingAnchor, constant: -6),
            titleField.centerYAnchor.constraint(equalTo: overlayView.centerYAnchor),
            titleField.heightAnchor.constraint(equalToConstant: 28)
        ])
        
        return card
    }
}

// MARK: - Interactive card

/// A history-ring card that reports hover and click when the owning HUD
/// wires `onHover`/`onSelect`. With nil callbacks the card stays inert.
@MainActor
final class HUDCardView: NSView {
    var tab: TabIdentifier?
    weak var host: TabHistoryHUDView?
    var onSelect: ((TabIdentifier) -> Void)?

    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if onSelect != nil {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        if let tab {
            host?.cardMouseEntered(tab)
        }
    }

    override func mouseExited(with event: NSEvent) {
        if let tab {
            host?.cardMouseExited(tab)
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard event.buttonNumber == 0, let tab else { return }
        onSelect?(tab)
    }
}

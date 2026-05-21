import AppKit

private class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// A view shown when all sessions have been closed.
final class EmptyStateView: NSView {
    override var isFlipped: Bool { true }

    var onEngineSelected: ((Int) -> Void)?

    private let headerContainer = FlippedView()
    private let iconView = NSImageView()
    private let messageLabel = NSTextField(labelWithString: "No open sessions")
    private let hintLabel = NSTextField(labelWithString: "Use a shortcut or click an engine to start")
    
    private let scrollView = NSScrollView()
    private let documentView = FlippedView()
    private let detailsStack = NSStackView()
    private let clipMaskLayer = CALayer()
    
    private var detailsTopConstraint: NSLayoutConstraint!
    private var documentMinHeightConstraint: NSLayoutConstraint!
    private var snapTimer: Timer?
    private var isSnapping = false
    private var lastOffsetY: CGFloat = 0
    private var scrollDirection: CGFloat = 0 // 1 for down (collapsing), -1 for up (expanding)
    private var lastServices: [Service] = []
    private var lastAppShortcuts: AppShortcutBindings = .defaults

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        self.identifier = NSUserInterfaceItemIdentifier("EmptyStateView")
        setAccessibilityIdentifier("EmptyStateView")
        wantsLayer = true
        // ALMOST transparent background to catch mouse clicks without killing window blur
        layer?.backgroundColor = NSColor(white: 0, alpha: 0.001).cgColor
        layer?.masksToBounds = true
        
        addSubview(scrollView)
        addSubview(headerContainer) // Above scrollview in z-order
        
        headerContainer.addSubview(iconView)
        headerContainer.addSubview(messageLabel)
        headerContainer.addSubview(hintLabel)
        
        if let logo = loadLogo() {
            logo.isTemplate = true
            iconView.image = logo
        }
        iconView.contentTintColor = .labelColor
        
        [messageLabel, hintLabel].forEach {
            $0.isEditable = false
            $0.isSelectable = false
            $0.drawsBackground = false
            $0.isBezeled = false
        }
        messageLabel.textColor = .labelColor
        hintLabel.textColor = .secondaryLabelColor
        
        clipMaskLayer.backgroundColor = NSColor.black.cgColor
        scrollView.contentView.wantsLayer = true
        scrollView.contentView.layer?.mask = clipMaskLayer
        
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = documentView
        
        detailsStack.orientation = .vertical
        detailsStack.spacing = 24
        detailsStack.alignment = .centerX
        detailsStack.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(detailsStack)
        
        documentView.translatesAutoresizingMaskIntoConstraints = false
        detailsTopConstraint = detailsStack.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 260)
        documentMinHeightConstraint = documentView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.heightAnchor, constant: 188)
        
        NSLayoutConstraint.activate([
            detailsTopConstraint,
            detailsStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -40),
            detailsStack.centerXAnchor.constraint(equalTo: documentView.centerXAnchor),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            documentMinHeightConstraint
        ])
        
        NotificationCenter.default.addObserver(self, selector: #selector(onScroll), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        scrollView.contentView.postsBoundsChangedNotifications = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden else { return nil }
        let hit = super.hitTest(point)
        // Let standard UI elements like scrollbars and engine rows catch clicks
        if let subHit = hit, 
           subHit != self, 
           subHit != documentView, 
           subHit != scrollView.contentView, 
           subHit != headerContainer,
           subHit != scrollView {
            return subHit
        }
        // Otherwise, consume it to prevent click-through
        let localPoint = convert(point, from: superview)
        if bounds.contains(localPoint) {
            return self
        }
        return nil
    }

    override func mouseDown(with event: NSEvent) {
        // If we are on an engine row, let it handle its own click
        // hitTest already ensures we only get here if nothing important was hit.
        
        // Pass drag events if in the drag area
        let localPoint = convert(event.locationInWindow, from: nil)
        if localPoint.y < 32 { // Constants.DRAGGABLE_AREA_HEIGHT
             window?.performDrag(with: event)
        }
    }
    override func mouseUp(with event: NSEvent) {}
    
    // MARK: - Accessibility
    
    override func isAccessibilityElement() -> Bool {
        return true
    }
    
    override func accessibilityRole() -> NSAccessibility.Role? {
        return .group
    }
    
    override func accessibilityLabel() -> String? {
        return "Empty State View"
    }
    
    override func scrollWheel(with event: NSEvent) {
        scrollView.scrollWheel(with: event)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func layout() {
        super.layout()
        let isWide = bounds.width > 750
        
        if isWide {
            scrollView.contentView.layer?.mask = nil // No mask needed in wide mode
            
            let headerW = min(bounds.width * 0.45, 400)
            headerContainer.frame = NSRect(x: 0, y: 0, width: headerW, height: bounds.height)
            scrollView.frame = NSRect(x: headerW, y: 0, width: bounds.width - headerW, height: bounds.height)
            detailsTopConstraint.constant = 60
            documentMinHeightConstraint.constant = 0
            layoutHeader(progress: 0.0, isWide: true)
        } else {
            scrollView.contentView.layer?.mask = clipMaskLayer // Re-enable mask
            
            scrollView.frame = bounds
            detailsTopConstraint.constant = 260
            documentMinHeightConstraint.constant = 188
            
            // Explicitly force documentView height to be viewport + diff if needed
            // so we can ALWAYS scroll the full distance even with 0 items.
            let viewportH = scrollView.contentView.bounds.height
            if viewportH > 0 {
                let requiredH = viewportH + 188
                if documentView.frame.height < requiredH {
                    documentView.setFrameSize(NSSize(width: documentView.frame.width, height: requiredH))
                }
            }
            
            onScroll() // Update header based on current scroll offset
        }
    }
    
    @objc private func onScroll() {
        let isWide = bounds.width > 750
        if isWide { return }
        
        let maxH: CGFloat = 260
        let minH: CGFloat = 72
        let diff = maxH - minH
        
        let offsetY = scrollView.contentView.bounds.origin.y
        
        // Track momentum direction
        if offsetY > lastOffsetY + 1 {
            scrollDirection = 1
        } else if offsetY < lastOffsetY - 1 {
            scrollDirection = -1
        }
        lastOffsetY = offsetY
        
        let clampedY = min(diff, max(0, offsetY))
        let progress = clampedY / diff
        
        let headerH = maxH - clampedY
        headerContainer.frame = NSRect(x: 0, y: 0, width: bounds.width, height: headerH)
        
        // Mask frame should cover the entire visible area below the header.
        // Make it very tall to ensure bottom shortcuts are never clipped.
        clipMaskLayer.frame = NSRect(x: 0, y: offsetY + minH, width: bounds.width, height: 5000)
        
        layoutHeader(progress: progress, isWide: false)
        
        // Debounce timer for smooth snapping
        guard !isSnapping else { return }
        snapTimer?.invalidate()
        snapTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] _ in
            self?.snapIfNeeded()
        }
    }
    
    private func snapIfNeeded() {
        let isWide = bounds.width > 750
        if isWide { return }
        
        let maxH: CGFloat = 260
        let minH: CGFloat = 72
        let diff = maxH - minH
        
        let offsetY = scrollView.contentView.bounds.origin.y
        // Only snap if we are in the transition zone
        if offsetY > 0 && offsetY < diff {
            let targetY: CGFloat
            if scrollDirection > 0 {
                targetY = diff // Momentum down -> collapse
            } else if scrollDirection < 0 {
                targetY = 0    // Momentum up -> expand
            } else {
                targetY = (offsetY > diff / 2) ? diff : 0
            }
            
            isSnapping = true
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                scrollView.contentView.animator().setBoundsOrigin(NSPoint(x: 0, y: targetY))
            }, completionHandler: { [weak self] in
                guard let self = self else { return }
                self.scrollView.reflectScrolledClipView(self.scrollView.contentView)
                self.isSnapping = false
                self.scrollDirection = 0 // Reset momentum after snapping
            })
        }
    }
    
    private func layoutHeader(progress: CGFloat, isWide: Bool) {
        if isWide {
            let logoS: CGFloat = 100
            messageLabel.font = .systemFont(ofSize: 32, weight: .bold)
            hintLabel.font = .systemFont(ofSize: 16, weight: .regular)
            
            messageLabel.sizeToFit()
            hintLabel.sizeToFit()
            
            let totalH = logoS + 24 + messageLabel.bounds.height + 8 + hintLabel.bounds.height
            var y = (bounds.height - totalH) / 2
            let headerW = headerContainer.bounds.width
            
            iconView.frame = NSRect(x: (headerW - logoS) / 2, y: y, width: logoS, height: logoS)
            y += logoS + 24
            
            messageLabel.frame = NSRect(x: (headerW - messageLabel.bounds.width) / 2, y: y, width: messageLabel.bounds.width, height: messageLabel.bounds.height)
            y += messageLabel.bounds.height + 8
            
            hintLabel.frame = NSRect(x: (headerW - hintLabel.bounds.width) / 2, y: y, width: hintLabel.bounds.width, height: hintLabel.bounds.height)
            hintLabel.alphaValue = 1.0
        } else {
            let maxH: CGFloat = 260
            let minH: CGFloat = 72
            
            let logoS = lerp(from: 100, to: 32, p: progress)
            let msgFont = lerp(from: 32, to: 20, p: progress)
            
            messageLabel.font = .systemFont(ofSize: msgFont, weight: .bold)
            messageLabel.sizeToFit()
            
            hintLabel.font = .systemFont(ofSize: 16, weight: .regular)
            hintLabel.sizeToFit()
            hintLabel.alphaValue = max(0, 1.0 - (progress * 2.0))
            
            let expTotalH = 100 + 24 + messageLabel.bounds.height + 8 + hintLabel.bounds.height
            let expStartY = (maxH - expTotalH) / 2
            
            let expLogoX = (bounds.width - 100) / 2
            let expLogoY = expStartY
            let expMsgX = (bounds.width - messageLabel.bounds.width) / 2
            let expMsgY = expLogoY + 100 + 24
            let expHintX = (bounds.width - hintLabel.bounds.width) / 2
            let expHintY = expMsgY + messageLabel.bounds.height + 8
            
            let colLogoX: CGFloat = 24
            let colLogoY = (minH - 32) / 2
            let colMsgX = colLogoX + 32 + 12
            let colMsgY = (minH - messageLabel.bounds.height) / 2
            let colHintX = colMsgX
            let colHintY = colMsgY + messageLabel.bounds.height
            
            iconView.frame = NSRect(x: lerp(from: expLogoX, to: colLogoX, p: progress),
                                    y: lerp(from: expLogoY, to: colLogoY, p: progress),
                                    width: logoS, height: logoS)
            
            messageLabel.frame = NSRect(x: lerp(from: expMsgX, to: colMsgX, p: progress),
                                        y: lerp(from: expMsgY, to: colMsgY, p: progress),
                                        width: messageLabel.bounds.width, height: messageLabel.bounds.height)
            
            hintLabel.frame = NSRect(x: lerp(from: expHintX, to: colHintX, p: progress),
                                     y: lerp(from: expHintY, to: colHintY, p: progress),
                                     width: hintLabel.bounds.width, height: hintLabel.bounds.height)
        }
    }
    
    private func lerp(from: CGFloat, to: CGFloat, p: CGFloat) -> CGFloat {
        return from + (to - from) * p
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateShortcuts(services: lastServices, appShortcuts: lastAppShortcuts)
    }

    func updateShortcuts(services: [Service], appShortcuts: AppShortcutBindings) {
        self.lastServices = services
        self.lastAppShortcuts = appShortcuts
        detailsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let enginesSection = createSection(title: "ENGINES")
        let enginesGrid = NSStackView()
        enginesGrid.orientation = .vertical
        enginesGrid.spacing = 2
        enginesGrid.alignment = .centerX
        
        for (i, service) in services.enumerated() where i < 10 {
            let digit = (i + 1) % 10
            let row = EngineRowView(label: service.name, 
                                  modifiers: appShortcuts.serviceDigitsPrimaryModifiers, 
                                  secondaryModifiers: appShortcuts.serviceDigitsSecondaryModifiers,
                                  digitText: "\(digit)")
            row.onClick = { [weak self] in
                self?.onEngineSelected?(i)
            }
            enginesGrid.addArrangedSubview(row)
        }
        enginesSection.addArrangedSubview(enginesGrid)
        detailsStack.addArrangedSubview(enginesSection)

        let sessionsSection = createSection(title: "SESSIONS")
        let sessionRow = EngineRowView.createStaticRow(label: "Switch Session",
                                                   modifiers: appShortcuts.sessionDigitsModifiers,
                                                   secondaryModifiers: appShortcuts.sessionDigitsAlternateModifiers,
                                                   digitText: "1...0")
        sessionsSection.addArrangedSubview(sessionRow)
        detailsStack.addArrangedSubview(sessionsSection)
        
        documentView.layoutSubtreeIfNeeded()
    }

    private func createSection(title: String) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 14
        stack.alignment = .centerX
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11, weight: .bold)
        label.textColor = .secondaryLabelColor.withAlphaComponent(0.4)
        label.isEditable = false
        label.isSelectable = false
        label.drawsBackground = false
        label.isBezeled = false
        stack.addArrangedSubview(label)
        return stack
    }

    private func loadLogo() -> NSImage? {
        if let img = NSImage(named: "logo") { return img }
        if let url = Bundle.main.url(forResource: "logo", withExtension: "png") { return NSImage(contentsOf: url) }
        return NSImage(systemSymbolName: "globe", accessibilityDescription: "Quiper")
    }
}

// MARK: - Interactive Engine Row

private final class EngineRowView: NSView {
    var onClick: (() -> Void)?
    
    private let highlightView = NSView()
    private let contentStack = NSStackView()
    
    private var isHovered = false { didSet { updateHighlight() } }
    private var isPressed = false { didSet { updateHighlight() } }

    init(label: String, modifiers: UInt, secondaryModifiers: UInt?, digitText: String) {
        super.init(frame: .zero)
        setup(label: label, modifiers: modifiers, secondaryModifiers: secondaryModifiers, digitText: digitText)
    }
    
    static func createStaticRow(label: String, modifiers: UInt, secondaryModifiers: UInt?, digitText: String) -> NSView {
        let row = EngineRowView(label: label, modifiers: modifiers, secondaryModifiers: secondaryModifiers, digitText: digitText)
        row.onClick = nil 
        return row
    }

    required init?(coder: NSCoder) { fatalError() }
    
    private func setup(label: String, modifiers: UInt, secondaryModifiers: UInt?, digitText: String) {
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.backgroundColor = NSColor(white: 0, alpha: 0.001).cgColor
        
        highlightView.wantsLayer = true
        highlightView.layer?.cornerRadius = 10
        highlightView.translatesAutoresizingMaskIntoConstraints = false
        highlightView.alphaValue = 0
        addSubview(highlightView)
        
        contentStack.orientation = .horizontal
        contentStack.spacing = 24
        contentStack.alignment = .centerY
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentStack)
        
        let columnWidth: CGFloat = 160
        
        let nameLabel = NSTextField(labelWithString: label)
        nameLabel.font = .systemFont(ofSize: 14, weight: .medium)
        nameLabel.textColor = .labelColor.withAlphaComponent(0.9)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.alignment = .right
        nameLabel.isEditable = false
        nameLabel.isSelectable = false
        nameLabel.drawsBackground = false
        nameLabel.isBezeled = false
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.widthAnchor.constraint(equalToConstant: columnWidth).isActive = true
        contentStack.addArrangedSubview(nameLabel)
        
        let shortcutStack = NSStackView()
        shortcutStack.orientation = .horizontal
        shortcutStack.spacing = 8
        shortcutStack.addArrangedSubview(KeyPillView(modifiers: modifiers, digitText: digitText))
        
        if let secondary = secondaryModifiers, secondary > 0 {
            let separator = NSTextField(labelWithString: "/")
            separator.font = .systemFont(ofSize: 12)
            separator.textColor = .secondaryLabelColor.withAlphaComponent(0.3)
            separator.isEditable = false
            separator.isSelectable = false
            separator.drawsBackground = false
            separator.isBezeled = false
            shortcutStack.addArrangedSubview(separator)
            shortcutStack.addArrangedSubview(KeyPillView(modifiers: secondary, digitText: digitText))
        }
        
        let rightContainer = NSView()
        rightContainer.translatesAutoresizingMaskIntoConstraints = false
        rightContainer.widthAnchor.constraint(equalToConstant: columnWidth).isActive = true
        rightContainer.addSubview(shortcutStack)
        shortcutStack.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            shortcutStack.leadingAnchor.constraint(equalTo: rightContainer.leadingAnchor),
            shortcutStack.centerYAnchor.constraint(equalTo: rightContainer.centerYAnchor),
            rightContainer.heightAnchor.constraint(equalTo: shortcutStack.heightAnchor)
        ])
        
        contentStack.addArrangedSubview(rightContainer)
        
        NSLayoutConstraint.activate([
            highlightView.topAnchor.constraint(equalTo: topAnchor),
            highlightView.bottomAnchor.constraint(equalTo: bottomAnchor),
            highlightView.leadingAnchor.constraint(equalTo: leadingAnchor),
            highlightView.trailingAnchor.constraint(equalTo: trailingAnchor),
            
            contentStack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            contentStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
        ])
        
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self, userInfo: nil))
    }
    
    private func updateHighlight() {
        if onClick == nil { return }
        highlightView.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(isPressed ? 0.10 : 0.06).cgColor
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            highlightView.animator().alphaValue = (isHovered || isPressed) ? 1 : 0
        }
    }
    
    override func resetCursorRects() {
        super.resetCursorRects()
        if onClick != nil {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }
    
    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }
    override func mouseDown(with event: NSEvent) { isPressed = true }
    override func mouseUp(with event: NSEvent) {
        if isPressed && isHovered { onClick?() }
        isPressed = false
    }
    
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateHighlight()
    }
}

private final class KeyPillView: NSView {
    private let modifiers: UInt
    private let digitText: String
    
    init(modifiers: UInt, digitText: String) {
        self.modifiers = modifiers
        self.digitText = digitText
        super.init(frame: .zero)
        setup()
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 6
        updateColors()
        
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 3, left: 8, bottom: 3, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        
        let modStr = ShortcutFormatter.string(for: modifiers, digit: 1).replacingOccurrences(of: "1", with: "").trimmingCharacters(in: .whitespaces)
        for char in modStr {
            let label = NSTextField(labelWithString: String(char))
            label.font = .systemFont(ofSize: 14)
            label.textColor = .secondaryLabelColor
            label.isEditable = false
            label.isSelectable = false
            label.drawsBackground = false
            label.isBezeled = false
            stack.addArrangedSubview(label)
        }
        
        let digitLabel = NSTextField(labelWithString: digitText)
        digitLabel.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        digitLabel.textColor = .labelColor
        digitLabel.isEditable = false
        digitLabel.isSelectable = false
        digitLabel.drawsBackground = false
        digitLabel.isBezeled = false
        stack.addArrangedSubview(digitLabel)
        
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }
    
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }
    
    private func updateColors() {
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.06).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
    }
}

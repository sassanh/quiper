import AppKit

@MainActor
final class ModifierHUDView: NSView {
    
    private weak var wc: MainWindowController?
    private let visualEffectView: NSVisualEffectView
    private let containerView: NSView
    private(set) var isHiding = false
    
    private var searchField: NSTextField!
    private let enginesScrollView = NSScrollView()
    private let enginesStack = FlippedStackView()
    
    private let col1 = NSView()
    private let col2 = NSView()
    
    private struct FilteredItem {
        enum ItemType {
            case engine(service: Service, index: Int, shortcut: String?)
            case tab(session: (sessionIndex: Int, title: String), service: Service, serviceIndex: Int, isSelected: Bool, shortcut: String?)
        }
        let type: ItemType
        let view: NSView
        let button: NSControl
    }
    
    private var allItems: [FilteredItem] = []
    private var filteredItems: [FilteredItem] = []
    private var highlightedIndex: Int = -1
    private var sessionButtons: [HUDSessionButton] = []

    override var acceptsFirstResponder: Bool { true }
    
    init(frame frameRect: NSRect, windowController: MainWindowController) {
        self.wc = windowController
        
        visualEffectView = NSVisualEffectView(frame: NSRect(origin: .zero, size: frameRect.size))
        containerView = NSView()
        
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
        
        // Add a premium dark backing layer overlay to increase contrast
        let darkBacking = NSView(frame: bounds)
        darkBacking.autoresizingMask = [.width, .height]
        darkBacking.wantsLayer = true
        darkBacking.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.2).cgColor
        visualEffectView.addSubview(darkBacking)
        
        setupContainerCard()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func getShortcutString(for service: Service, index: Int, appShortcuts: AppShortcutBindings) -> String? {
        if let custom = service.activationShortcut, !custom.isDisabled {
            return ShortcutFormatter.string(for: custom)
        }
        if index < 10 {
            let mods = appShortcuts.serviceDigitsPrimaryModifiers
            if mods > 0 {
                return ShortcutFormatter.string(for: mods, digit: index == 9 ? 0 : index + 1)
            }
        }
        return nil
    }
    
    private func getSessionShortcutString(sessionIndex: Int, appShortcuts: AppShortcutBindings) -> String? {
        let mods = appShortcuts.sessionDigitsModifiers
        if mods > 0 {
            return ShortcutFormatter.string(for: mods, digit: sessionIndex == 9 ? 0 : sessionIndex + 1)
        }
        return nil
    }
    
    private func setupContainerCard() {
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.clear.cgColor
        containerView.autoresizingMask = [.width, .height]
        containerView.frame = visualEffectView.bounds
        visualEffectView.addSubview(containerView)
        
        // Header Title
        let headerTitle = NSTextField(labelWithString: "QUIPER CONTROL CENTER")
        headerTitle.font = NSFont.systemFont(ofSize: 13, weight: .black)
        headerTitle.textColor = .labelColor
        headerTitle.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(headerTitle)
        
        // Close Button
        let closeBtn = HUDCloseButton()
        closeBtn.onClick = { [weak self] in
            self?.hide()
        }
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(closeBtn)
        
        // Search Container Wrapper
        let searchContainer = NSView()
        searchContainer.wantsLayer = true
        searchContainer.layer?.cornerRadius = 8
        searchContainer.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.2).cgColor
        searchContainer.layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
        searchContainer.layer?.borderWidth = 1
        searchContainer.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(searchContainer)
        
        let searchIcon = NSImageView()
        if let searchImg = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil) {
            searchImg.isTemplate = true
            searchIcon.image = searchImg
        }
        searchIcon.contentTintColor = .secondaryLabelColor
        searchIcon.translatesAutoresizingMaskIntoConstraints = false
        searchContainer.addSubview(searchIcon)
        
        let searchField = NSTextField()
        searchField.placeholderString = "Search engines & tabs..."
        searchField.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.textColor = .labelColor
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchContainer.addSubview(searchField)
        self.searchField = searchField
        
        // Divider
        let divider = NSView()
        divider.wantsLayer = true
        divider.layer?.backgroundColor = self.resolvedCGColor(.separatorColor)
        divider.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(divider)
        
        // Column 1: Engines & Sessions
        col1.translatesAutoresizingMaskIntoConstraints = false
        
        let enginesTitle = NSTextField(labelWithString: "SELECT ENGINE")
        enginesTitle.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        enginesTitle.textColor = .secondaryLabelColor
        enginesTitle.translatesAutoresizingMaskIntoConstraints = false
        col1.addSubview(enginesTitle)
        
        enginesScrollView.drawsBackground = false
        enginesScrollView.hasVerticalScroller = true
        enginesScrollView.hasHorizontalScroller = false
        enginesScrollView.autohidesScrollers = true
        enginesScrollView.borderType = .noBorder
        enginesScrollView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        enginesScrollView.translatesAutoresizingMaskIntoConstraints = false
        col1.addSubview(enginesScrollView)
        
        enginesStack.orientation = .vertical
        enginesStack.spacing = 6
        enginesStack.alignment = .leading
        enginesStack.distribution = .fill
        enginesStack.translatesAutoresizingMaskIntoConstraints = false
        
        enginesScrollView.documentView = enginesStack
        
        // Column 2: Shortcuts / Global Actions
        col2.translatesAutoresizingMaskIntoConstraints = false
        
        let shortcutsTitle = NSTextField(labelWithString: "QUICK SHORTCUTS")
        shortcutsTitle.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        shortcutsTitle.textColor = .secondaryLabelColor
        shortcutsTitle.translatesAutoresizingMaskIntoConstraints = false
        col2.addSubview(shortcutsTitle)
        
        let shortcutsStack = NSStackView()
        shortcutsStack.orientation = .vertical
        shortcutsStack.spacing = 6
        shortcutsStack.alignment = .leading
        shortcutsStack.distribution = .fill
        shortcutsStack.translatesAutoresizingMaskIntoConstraints = false
        col2.addSubview(shortcutsStack)
        
        let itemsData: [(String, String, String, () -> Void)] = [
            ("Settings...", "gearshape", "⌘ ,", {
                NotificationCenter.default.post(name: .showSettings, object: nil)
            }),
            ("Find in Page...", "magnifyingglass", "⌘ F", { [weak self] in
                self?.wc?.findBarViewController?.show()
            }),
            ("Toggle Web Inspector", "ladybug", "⌘ ⌥ I", { [weak self] in
                self?.wc?.performMenuToggleInspector(nil)
            }),
            ("Reset Web Zoom", "arrow.uturn.backward", "⌘ ⇧ ⌫", { [weak self] in
                self?.wc?.performMenuResetZoom(nil)
            }),
            ("Hide Quiper Window", "eye.slash", "⌥ Space", { [weak self] in
                self?.wc?.hide()
            })
        ]
        
        for item in itemsData {
            let row = HUDShortcutRow(title: item.0, iconName: item.1, shortcut: item.2)
            row.onClick = { [weak self] in
                item.3()
                self?.hide()
            }
            row.translatesAutoresizingMaskIntoConstraints = false
            row.heightAnchor.constraint(equalToConstant: 34).isActive = true
            shortcutsStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: shortcutsStack.widthAnchor).isActive = true
        }
        
        let sessionsTitle = NSTextField(labelWithString: "SESSION SLOTS")
        sessionsTitle.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        sessionsTitle.textColor = .secondaryLabelColor
        sessionsTitle.translatesAutoresizingMaskIntoConstraints = false
        col2.addSubview(sessionsTitle)
        
        // Grid of 10 slots (arranged in 2 rows of 5)
        let slotsGrid = NSGridView()
        slotsGrid.rowSpacing = 6
        slotsGrid.columnSpacing = 6
        slotsGrid.translatesAutoresizingMaskIntoConstraints = false
        col2.addSubview(slotsGrid)
        
        var rowViews: [NSView] = []
        self.sessionButtons.removeAll()
        for i in 0..<10 {
            let sessionNum = i == 9 ? 0 : i + 1
            let btn = HUDSessionButton(number: sessionNum)
            btn.onClick = { [weak self, i] in
                self?.wc?.switchSession(to: i)
                self?.hide()
            }
            btn.translatesAutoresizingMaskIntoConstraints = false
            btn.heightAnchor.constraint(equalToConstant: 32).isActive = true
            rowViews.append(btn)
            self.sessionButtons.append(btn)
            
            if rowViews.count == 5 {
                slotsGrid.addRow(with: rowViews)
                rowViews.removeAll()
            }
        }
        if !rowViews.isEmpty {
            slotsGrid.addRow(with: rowViews)
        }
        
        // Activate width constraints once they all share the slotsGrid as their ancestor
        if let first = self.sessionButtons.first {
            first.widthAnchor.constraint(equalTo: slotsGrid.widthAnchor, multiplier: 0.2, constant: -4.8).isActive = true
            for btn in self.sessionButtons.dropFirst() {
                btn.widthAnchor.constraint(equalTo: first.widthAnchor).isActive = true
            }
        }
        
        let columnsStack = NSStackView(views: [col1, col2])
        columnsStack.orientation = .horizontal
        columnsStack.spacing = 24
        columnsStack.distribution = .fillEqually
        columnsStack.alignment = .top
        columnsStack.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(columnsStack)
        
        // Layout constraints
        NSLayoutConstraint.activate([
            
            headerTitle.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 18),
            headerTitle.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 18),
            
            closeBtn.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            closeBtn.centerYAnchor.constraint(equalTo: headerTitle.centerYAnchor),
            closeBtn.widthAnchor.constraint(equalToConstant: 24),
            closeBtn.heightAnchor.constraint(equalToConstant: 24),
            
            searchContainer.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            searchContainer.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            searchContainer.topAnchor.constraint(equalTo: headerTitle.bottomAnchor, constant: 12),
            searchContainer.heightAnchor.constraint(equalToConstant: 34),
            
            searchIcon.leadingAnchor.constraint(equalTo: searchContainer.leadingAnchor, constant: 10),
            searchIcon.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor),
            searchIcon.widthAnchor.constraint(equalToConstant: 14),
            searchIcon.heightAnchor.constraint(equalToConstant: 14),
            
            searchField.leadingAnchor.constraint(equalTo: searchIcon.trailingAnchor, constant: 8),
            searchField.trailingAnchor.constraint(equalTo: searchContainer.trailingAnchor, constant: -10),
            searchField.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor),
            
            divider.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            divider.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            divider.topAnchor.constraint(equalTo: searchContainer.bottomAnchor, constant: 12),
            divider.heightAnchor.constraint(equalToConstant: 1),
            
            columnsStack.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 18),
            columnsStack.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -18),
            columnsStack.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 16),
            columnsStack.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -16),
            
            // Col 1 Inner Constraints
            col1.bottomAnchor.constraint(equalTo: columnsStack.bottomAnchor),
            
            enginesTitle.leadingAnchor.constraint(equalTo: col1.leadingAnchor, constant: 4),
            enginesTitle.topAnchor.constraint(equalTo: col1.topAnchor),
            
            enginesScrollView.leadingAnchor.constraint(equalTo: col1.leadingAnchor),
            enginesScrollView.trailingAnchor.constraint(equalTo: col1.trailingAnchor),
            enginesScrollView.topAnchor.constraint(equalTo: enginesTitle.bottomAnchor, constant: 8),
            enginesScrollView.bottomAnchor.constraint(equalTo: col1.bottomAnchor),
            
            enginesStack.topAnchor.constraint(equalTo: enginesScrollView.contentView.topAnchor),
            enginesStack.leadingAnchor.constraint(equalTo: enginesScrollView.contentView.leadingAnchor),
            enginesStack.widthAnchor.constraint(equalTo: enginesScrollView.contentView.widthAnchor, constant: -18),
            
            // Col 2 Inner Constraints
            col2.bottomAnchor.constraint(equalTo: columnsStack.bottomAnchor),
            
            shortcutsTitle.leadingAnchor.constraint(equalTo: col2.leadingAnchor, constant: 4),
            shortcutsTitle.topAnchor.constraint(equalTo: col2.topAnchor),
            
            shortcutsStack.leadingAnchor.constraint(equalTo: col2.leadingAnchor),
            shortcutsStack.trailingAnchor.constraint(equalTo: col2.trailingAnchor),
            shortcutsStack.topAnchor.constraint(equalTo: shortcutsTitle.bottomAnchor, constant: 8),
            
            sessionsTitle.leadingAnchor.constraint(equalTo: col2.leadingAnchor, constant: 4),
            sessionsTitle.topAnchor.constraint(equalTo: shortcutsStack.bottomAnchor, constant: 20),
            
            slotsGrid.leadingAnchor.constraint(equalTo: col2.leadingAnchor),
            slotsGrid.trailingAnchor.constraint(equalTo: col2.trailingAnchor),
            slotsGrid.topAnchor.constraint(equalTo: sessionsTitle.bottomAnchor, constant: 8),
            slotsGrid.bottomAnchor.constraint(lessThanOrEqualTo: col2.bottomAnchor)
        ])
        
        refreshData()
    }
    
    func refreshData() {
        guard let wc = wc else { return }
        let currentSvcURL = wc.currentServiceURL
        let activeSession = wc.activeIndicesByURL[currentSvcURL ?? ""] ?? 0
        let appShortcuts = Settings.shared.appShortcutBindings
        
        for view in enginesStack.arrangedSubviews {
            enginesStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        
        allItems.removeAll()
        
        for (idx, service) in wc.services.enumerated() {
            let shortcutStr = getShortcutString(for: service, index: idx, appShortcuts: appShortcuts)
            let btn = HUDEngineButton(title: service.name, shortcut: shortcutStr)
            btn.isSelected = (service.url == currentSvcURL)
            btn.onHover = { [weak self, weak btn] in
                guard let self, let btn,
                      let index = self.filteredItems.firstIndex(where: { $0.button === btn }) else { return }
                self.highlightedIndex = index
                self.updateHighlighting()
            }
            btn.onClick = { [weak self, idx] in
                self?.wc?.selectService(at: idx)
                self?.hide()
            }
            btn.translatesAutoresizingMaskIntoConstraints = false
            btn.heightAnchor.constraint(equalToConstant: 28).isActive = true
            
            allItems.append(FilteredItem(
                type: .engine(service: service, index: idx, shortcut: shortcutStr),
                view: btn,
                button: btn
            ))
            
            if let openSessions = wc.webViewManager?.getOpenSessions(for: service) {
                for session in openSessions {
                    let isTabSelected = (service.url == currentSvcURL && session.sessionIndex == activeSession)
                    
                    let sessionShortcutStr: String?
                    if service.url == currentSvcURL {
                        sessionShortcutStr = getSessionShortcutString(sessionIndex: session.sessionIndex, appShortcuts: appShortcuts)
                    } else {
                        sessionShortcutStr = nil
                    }
                    
                    let tabBtn = HUDTabButton(title: session.title, isSelected: isTabSelected, shortcut: sessionShortcutStr)
                    tabBtn.onHover = { [weak self, weak tabBtn] in
                        guard let self, let tabBtn,
                              let index = self.filteredItems.firstIndex(where: { $0.button === tabBtn }) else { return }
                        self.highlightedIndex = index
                        self.updateHighlighting()
                    }
                    tabBtn.onClick = { [weak self, idx, sessionIdx = session.sessionIndex] in
                        self?.wc?.selectService(at: idx)
                        self?.wc?.switchSession(to: sessionIdx)
                        self?.hide()
                    }
                    tabBtn.translatesAutoresizingMaskIntoConstraints = false
                    
                    let indentContainer = NSView()
                    indentContainer.translatesAutoresizingMaskIntoConstraints = false
                    indentContainer.addSubview(tabBtn)
                    
                    NSLayoutConstraint.activate([
                        indentContainer.heightAnchor.constraint(equalToConstant: 24),
                        tabBtn.leadingAnchor.constraint(equalTo: indentContainer.leadingAnchor, constant: 16),
                        tabBtn.trailingAnchor.constraint(equalTo: indentContainer.trailingAnchor),
                        tabBtn.topAnchor.constraint(equalTo: indentContainer.topAnchor),
                        tabBtn.bottomAnchor.constraint(equalTo: indentContainer.bottomAnchor)
                    ])
                    
                    allItems.append(FilteredItem(
                        type: .tab(session: session, service: service, serviceIndex: idx, isSelected: isTabSelected, shortcut: sessionShortcutStr),
                        view: indentContainer,
                        button: tabBtn
                    ))
                }
            }
        }
        
        for (i, btn) in sessionButtons.enumerated() {
            btn.isSelected = (i == activeSession)
        }
        
        updateFilteredList(filter: searchField.stringValue)
    }
    
    // Swallow mouse clicks to prevent click-through to the webview
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if !containerView.frame.contains(point) {
            hide()
        }
    }
    override func mouseUp(with event: NSEvent) {}
    override func mouseMoved(with event: NSEvent) {}
    override func scrollWheel(with event: NSEvent) {}

    func focusSearchField() {
        window?.makeFirstResponder(searchField)
    }
    
    func show() {
        isHiding = false
        isHidden = false
        self.frame = bounds
        self.visualEffectView.frame = bounds
        self.containerView.frame = bounds
        col2.isHidden = bounds.width < 480
        self.alphaValue = 0
        
        self.searchField.stringValue = ""
        self.refreshData()
        
        focusSearchField()
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if isHiding || isHidden {
            return nil
        }
        return super.hitTest(point)
    }
    
    func hide() {
        guard !isHiding else {
            return
        }
        isHiding = true
        window?.makeFirstResponder(self)
        Self.removeTrackingAreasRecursively(from: self)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self else {
                    return
                }
                if self.window?.firstResponder === self {
                    self.window?.makeFirstResponder(self.window?.contentView)
                }
                self.isHidden = true
                self.isHiding = false
                self.wc?.hideModifierHUD()
            }
        }
    }

    private static func removeTrackingAreasRecursively(from view: NSView) {
        for trackingArea in view.trackingAreas {
            view.removeTrackingArea(trackingArea)
        }
        for subview in view.subviews {
            removeTrackingAreasRecursively(from: subview)
        }
    }
}

// MARK: - HUD Elements

@MainActor
final class HUDCloseButton: NSControl {
    var onClick: (() -> Void)?
    private var isHovered = false {
        didSet { updateAppearance() }
    }
    private var trackingArea: NSTrackingArea?
    private let iconView = NSImageView()
    
    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 12
        refusesFirstResponder = true
        
        if let image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil) {
            image.isTemplate = true
            iconView.image = image
        }
        iconView.contentTintColor = .secondaryLabelColor
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)
        
        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 10),
            iconView.heightAnchor.constraint(equalToConstant: 10)
        ])
        
        updateAppearance()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways]
        trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }
    
    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }
    
    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }
    
    override func mouseDown(with event: NSEvent) {
        layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.4).cgColor
    }
    
    override func mouseUp(with event: NSEvent) {
        updateAppearance()
        let point = convert(event.locationInWindow, from: nil)
        if bounds.contains(point) {
            onClick?()
        }
    }
    
    private func updateAppearance() {
        if isHovered {
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
            iconView.contentTintColor = .labelColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
            iconView.contentTintColor = .secondaryLabelColor
        }
    }
}

@MainActor
final class HUDEngineButton: NSControl {
    var onHover: (() -> Void)?
    var onClick: (() -> Void)?
    var isSelected = false {
        didSet { updateAppearance() }
    }
    var isKeyboardHighlighted = false {
        didSet { updateAppearance() }
    }
    private var isHovered = false {
        didSet { updateAppearance() }
    }
    private var trackingArea: NSTrackingArea?
    
    private let activeDot = NSView()
    private let titleField = NSTextField(labelWithString: "")
    private let shortcutContainer = NSView()
    private let shortcutField = NSTextField(labelWithString: "")
    
    init(title: String, shortcut: String?) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        refusesFirstResponder = true
        
        activeDot.wantsLayer = true
        activeDot.layer?.cornerRadius = 3.5
        activeDot.translatesAutoresizingMaskIntoConstraints = false
        addSubview(activeDot)
        
        titleField.stringValue = title
        titleField.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        titleField.cell?.lineBreakMode = .byTruncatingTail
        titleField.cell?.usesSingleLineMode = true
        titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleField.setContentHuggingPriority(.defaultLow - 10, for: .horizontal)
        titleField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleField)
        
        var constraints = [
            activeDot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            activeDot.centerYAnchor.constraint(equalTo: centerYAnchor),
            activeDot.widthAnchor.constraint(equalToConstant: 7),
            activeDot.heightAnchor.constraint(equalToConstant: 7),
            
            titleField.leadingAnchor.constraint(equalTo: activeDot.trailingAnchor, constant: 8),
            titleField.centerYAnchor.constraint(equalTo: centerYAnchor)
        ]
        
        if let shortcut = shortcut, !shortcut.isEmpty {
            shortcutContainer.wantsLayer = true
            shortcutContainer.layer?.cornerRadius = 5
            shortcutContainer.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.2).cgColor
            shortcutContainer.layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
            shortcutContainer.layer?.borderWidth = 1
            shortcutContainer.translatesAutoresizingMaskIntoConstraints = false
            addSubview(shortcutContainer)
            
            shortcutField.stringValue = shortcut
            shortcutField.font = NSFont.systemFont(ofSize: 9, weight: .bold)
            shortcutField.textColor = .secondaryLabelColor
            shortcutField.alignment = .center
            shortcutField.setContentHuggingPriority(.required, for: .horizontal)
            shortcutField.setContentCompressionResistancePriority(.required, for: .horizontal)
            shortcutField.translatesAutoresizingMaskIntoConstraints = false
            shortcutContainer.addSubview(shortcutField)
            
            constraints.append(contentsOf: [
                shortcutContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
                shortcutContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
                shortcutContainer.heightAnchor.constraint(equalToConstant: 18),
                
                shortcutField.leadingAnchor.constraint(equalTo: shortcutContainer.leadingAnchor, constant: 5),
                shortcutField.trailingAnchor.constraint(equalTo: shortcutContainer.trailingAnchor, constant: -5),
                shortcutField.centerYAnchor.constraint(equalTo: shortcutContainer.centerYAnchor),
                
                titleField.trailingAnchor.constraint(equalTo: shortcutContainer.leadingAnchor, constant: -8)
            ])
            
            shortcutContainer.isHidden = false
        } else {
            constraints.append(titleField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10))
            shortcutContainer.isHidden = true
        }
        
        NSLayoutConstraint.activate(constraints)
        updateAppearance()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways]
        trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }
    
    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        onHover?()
    }
    
    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }
    
    override func mouseDown(with event: NSEvent) {
        layer?.backgroundColor = resolvedCGColor(NSColor.controlAccentColor.withAlphaComponent(0.3))
    }
    
    override func mouseUp(with event: NSEvent) {
        updateAppearance()
        let point = convert(event.locationInWindow, from: nil)
        if bounds.contains(point) {
            onClick?()
        }
    }
    
    private func updateAppearance() {
        if isSelected {
            layer?.backgroundColor = resolvedCGColor(NSColor.controlAccentColor.withAlphaComponent(0.2))
            if isKeyboardHighlighted {
                layer?.borderColor = NSColor.white.cgColor
                layer?.borderWidth = 1.5
            } else {
                layer?.borderColor = resolvedCGColor(.controlAccentColor)
                layer?.borderWidth = 1
            }
            titleField.textColor = .labelColor
            activeDot.layer?.backgroundColor = resolvedCGColor(.controlAccentColor)
            activeDot.isHidden = false
            shortcutContainer.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
            shortcutField.textColor = .labelColor
        } else if isHovered || isKeyboardHighlighted {
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
            layer?.borderColor = isKeyboardHighlighted ? NSColor.white.withAlphaComponent(0.3).cgColor : NSColor.white.withAlphaComponent(0.12).cgColor
            layer?.borderWidth = isKeyboardHighlighted ? 1.5 : 1
            titleField.textColor = .labelColor
            activeDot.layer?.backgroundColor = resolvedCGColor(.secondaryLabelColor)
            activeDot.isHidden = true
            shortcutContainer.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.3).cgColor
            shortcutField.textColor = .labelColor
        } else {
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.03).cgColor
            layer?.borderColor = NSColor.white.withAlphaComponent(0.05).cgColor
            layer?.borderWidth = 1
            titleField.textColor = .secondaryLabelColor
            activeDot.layer?.backgroundColor = resolvedCGColor(.tertiaryLabelColor)
            activeDot.isHidden = true
            shortcutContainer.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.15).cgColor
            shortcutField.textColor = .secondaryLabelColor
        }
    }
}

@MainActor
final class HUDSessionButton: NSControl {
    var onClick: (() -> Void)?
    var isSelected = false {
        didSet { updateAppearance() }
    }
    private var isHovered = false {
        didSet { updateAppearance() }
    }
    private var trackingArea: NSTrackingArea?
    private let label = NSTextField(labelWithString: "")
    
    init(number: Int) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        refusesFirstResponder = true
        
        label.stringValue = "\(number)"
        label.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        label.alignment = .center
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        
        updateAppearance()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways]
        trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }
    
    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }
    
    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }
    
    override func mouseDown(with event: NSEvent) {
        layer?.backgroundColor = resolvedCGColor(NSColor.controlAccentColor.withAlphaComponent(0.4))
    }
    
    override func mouseUp(with event: NSEvent) {
        updateAppearance()
        let point = convert(event.locationInWindow, from: nil)
        if bounds.contains(point) {
            onClick?()
        }
    }
    
    private func updateAppearance() {
        if isSelected {
            layer?.backgroundColor = resolvedCGColor(.controlAccentColor)
            label.textColor = .white
            layer?.borderWidth = 0
        } else if isHovered {
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
            layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor
            layer?.borderWidth = 1
            label.textColor = .labelColor
        } else {
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.04).cgColor
            layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
            layer?.borderWidth = 1
            label.textColor = .secondaryLabelColor
        }
    }
}

@MainActor
final class HUDShortcutRow: NSControl {
    var onClick: (() -> Void)?
    private var isHovered = false {
        didSet { updateAppearance() }
    }
    private var trackingArea: NSTrackingArea?
    
    private let iconView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let shortcutContainer = NSView()
    private let shortcutField = NSTextField(labelWithString: "")
    
    init(title: String, iconName: String, shortcut: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        refusesFirstResponder = true
        
        if let image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil) {
            image.isTemplate = true
            iconView.image = image
        }
        iconView.contentTintColor = .secondaryLabelColor
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)
        
        titleField.stringValue = title
        titleField.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        titleField.textColor = .labelColor
        titleField.cell?.lineBreakMode = .byTruncatingTail
        titleField.cell?.usesSingleLineMode = true
        titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleField)
        
        shortcutContainer.wantsLayer = true
        shortcutContainer.layer?.cornerRadius = 5
        shortcutContainer.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.2).cgColor
        shortcutContainer.layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
        shortcutContainer.layer?.borderWidth = 1
        shortcutContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(shortcutContainer)
        
        shortcutField.stringValue = shortcut
        shortcutField.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        shortcutField.textColor = .secondaryLabelColor
        shortcutField.alignment = .center
        shortcutField.translatesAutoresizingMaskIntoConstraints = false
        shortcutContainer.addSubview(shortcutField)
        
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 14),
            iconView.heightAnchor.constraint(equalToConstant: 14),
            
            titleField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            titleField.centerYAnchor.constraint(equalTo: centerYAnchor),
            
            shortcutContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            shortcutContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
            shortcutContainer.heightAnchor.constraint(equalToConstant: 18),
            
            shortcutField.leadingAnchor.constraint(equalTo: shortcutContainer.leadingAnchor, constant: 5),
            shortcutField.trailingAnchor.constraint(equalTo: shortcutContainer.trailingAnchor, constant: -5),
            shortcutField.centerYAnchor.constraint(equalTo: shortcutContainer.centerYAnchor),
            
            titleField.trailingAnchor.constraint(lessThanOrEqualTo: shortcutContainer.leadingAnchor, constant: -8)
        ])
        
        updateAppearance()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways]
        trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }
    
    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }
    
    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }
    
    override func mouseDown(with event: NSEvent) {
        layer?.backgroundColor = resolvedCGColor(NSColor.controlAccentColor.withAlphaComponent(0.3))
    }
    
    override func mouseUp(with event: NSEvent) {
        updateAppearance()
        let point = convert(event.locationInWindow, from: nil)
        if bounds.contains(point) {
            onClick?()
        }
    }
    
    private func updateAppearance() {
        if isHovered {
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
            layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
            layer?.borderWidth = 1
            iconView.contentTintColor = .controlAccentColor
            shortcutContainer.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
            shortcutField.textColor = .labelColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
            layer?.borderColor = NSColor.clear.cgColor
            layer?.borderWidth = 0
            iconView.contentTintColor = .secondaryLabelColor
            shortcutContainer.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.15).cgColor
            shortcutField.textColor = .secondaryLabelColor
        }
    }
}

@MainActor
final class HUDTabButton: NSControl {
    var onHover: (() -> Void)?
    var onClick: (() -> Void)?
    var isSelected = false {
        didSet { updateAppearance() }
    }
    var isKeyboardHighlighted = false {
        didSet { updateAppearance() }
    }
    private var isHovered = false {
        didSet { updateAppearance() }
    }
    private var trackingArea: NSTrackingArea?
    
    private let activeDot = NSView()
    private let titleField = NSTextField(labelWithString: "")
    private let shortcutContainer = NSView()
    private let shortcutField = NSTextField(labelWithString: "")
    
    init(title: String, isSelected: Bool, shortcut: String?) {
        self.isSelected = isSelected
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 4
        refusesFirstResponder = true
        
        activeDot.wantsLayer = true
        activeDot.layer?.cornerRadius = 2.5
        activeDot.translatesAutoresizingMaskIntoConstraints = false
        addSubview(activeDot)
        
        titleField.stringValue = title
        titleField.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        titleField.cell?.lineBreakMode = .byTruncatingTail
        titleField.cell?.usesSingleLineMode = true
        titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleField.setContentHuggingPriority(.defaultLow - 10, for: .horizontal)
        titleField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleField)
        
        var constraints = [
            // Indent the contents to show nesting hierarchy
            // Indent the contents to show nesting hierarchy
            activeDot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            activeDot.centerYAnchor.constraint(equalTo: centerYAnchor),
            activeDot.widthAnchor.constraint(equalToConstant: 5),
            activeDot.heightAnchor.constraint(equalToConstant: 5),
            
            titleField.leadingAnchor.constraint(equalTo: activeDot.trailingAnchor, constant: 6),
            titleField.centerYAnchor.constraint(equalTo: centerYAnchor)
        ]
        
        if let shortcut = shortcut, !shortcut.isEmpty {
            shortcutContainer.wantsLayer = true
            shortcutContainer.layer?.cornerRadius = 5
            shortcutContainer.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.2).cgColor
            shortcutContainer.layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
            shortcutContainer.layer?.borderWidth = 1
            shortcutContainer.translatesAutoresizingMaskIntoConstraints = false
            addSubview(shortcutContainer)
            
            shortcutField.stringValue = shortcut
            shortcutField.font = NSFont.systemFont(ofSize: 9, weight: .bold)
            shortcutField.textColor = .secondaryLabelColor
            shortcutField.alignment = .center
            shortcutField.setContentHuggingPriority(.required, for: .horizontal)
            shortcutField.setContentCompressionResistancePriority(.required, for: .horizontal)
            shortcutField.translatesAutoresizingMaskIntoConstraints = false
            shortcutContainer.addSubview(shortcutField)
            
            constraints.append(contentsOf: [
                shortcutContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
                shortcutContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
                shortcutContainer.heightAnchor.constraint(equalToConstant: 18),
                
                shortcutField.leadingAnchor.constraint(equalTo: shortcutContainer.leadingAnchor, constant: 5),
                shortcutField.trailingAnchor.constraint(equalTo: shortcutContainer.trailingAnchor, constant: -5),
                shortcutField.centerYAnchor.constraint(equalTo: shortcutContainer.centerYAnchor),
                
                titleField.trailingAnchor.constraint(equalTo: shortcutContainer.leadingAnchor, constant: -8)
            ])
            
            shortcutContainer.isHidden = false
        } else {
            constraints.append(titleField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10))
            shortcutContainer.isHidden = true
        }
        
        NSLayoutConstraint.activate(constraints)
        updateAppearance()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways]
        trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }
    
    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        onHover?()
    }
    
    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }
    
    override func mouseDown(with event: NSEvent) {
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.2).cgColor
    }
    
    override func mouseUp(with event: NSEvent) {
        updateAppearance()
        let point = convert(event.locationInWindow, from: nil)
        if bounds.contains(point) {
            onClick?()
        }
    }
    
    private func updateAppearance() {
        layer?.borderWidth = 0
        layer?.borderColor = nil
        
        if isSelected {
            layer?.backgroundColor = NSColor.controlAccentColor.cgColor
            titleField.textColor = .white
            titleField.font = NSFont.systemFont(ofSize: 11, weight: .bold)
            activeDot.layer?.backgroundColor = NSColor.white.cgColor
            activeDot.isHidden = false
            shortcutContainer.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.25).cgColor
            shortcutField.textColor = .white
            if isKeyboardHighlighted {
                layer?.borderWidth = 1.5
                layer?.borderColor = NSColor.white.withAlphaComponent(0.8).cgColor
            }
        } else if isHovered || isKeyboardHighlighted {
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
            titleField.textColor = .labelColor
            titleField.font = NSFont.systemFont(ofSize: 11, weight: .medium)
            activeDot.layer?.backgroundColor = NSColor.secondaryLabelColor.cgColor
            activeDot.isHidden = true
            shortcutContainer.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.25).cgColor
            shortcutField.textColor = .labelColor
            if isKeyboardHighlighted {
                layer?.borderWidth = 1
                layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor
            }
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
            titleField.textColor = .secondaryLabelColor
            titleField.font = NSFont.systemFont(ofSize: 11, weight: .regular)
            activeDot.layer?.backgroundColor = NSColor.tertiaryLabelColor.cgColor
            activeDot.isHidden = true
            shortcutContainer.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.15).cgColor
            shortcutField.textColor = .secondaryLabelColor
        }
    }
}

// MARK: - Filtering and Keyboard Navigation Helpers
extension ModifierHUDView {
    private func updateFilteredList(filter: String) {
        for view in enginesStack.arrangedSubviews {
            enginesStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        
        let query = filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        if query.isEmpty {
            filteredItems = allItems
        } else {
            var matchedServices = Set<String>()
            var matchedTabs = Set<String>()
            
            for item in allItems {
                switch item.type {
                case .engine(let service, _, _):
                    if service.name.lowercased().contains(query) {
                        matchedServices.insert(service.url)
                    }
                case .tab(let session, let service, _, _, _):
                    if session.title.lowercased().contains(query) {
                        matchedServices.insert(service.url)
                        matchedTabs.insert("\(service.url)_\(session.sessionIndex)")
                    }
                }
            }
            
            filteredItems = allItems.filter { item in
                switch item.type {
                case .engine(let service, _, _):
                    return matchedServices.contains(service.url)
                case .tab(let session, let service, _, _, _):
                    if service.name.lowercased().contains(query) {
                        return true
                    }
                    return matchedTabs.contains("\(service.url)_\(session.sessionIndex)")
                }
            }
        }
        
        for item in filteredItems {
            enginesStack.addArrangedSubview(item.view)
            item.view.widthAnchor.constraint(equalTo: enginesStack.widthAnchor).isActive = true
        }
        
        updateHighlighting()
    }
    
    private func updateHighlighting() {
        for item in allItems {
            if let engineBtn = item.button as? HUDEngineButton {
                engineBtn.isKeyboardHighlighted = false
            } else if let tabBtn = item.button as? HUDTabButton {
                tabBtn.isKeyboardHighlighted = false
            }
        }
        
        if filteredItems.isEmpty {
            highlightedIndex = -1
        } else {
            if highlightedIndex >= filteredItems.count {
                highlightedIndex = filteredItems.count - 1
            }
            if highlightedIndex < 0 {
                highlightedIndex = 0
            }
            
            let activeItem = filteredItems[highlightedIndex]
            if let engineBtn = activeItem.button as? HUDEngineButton {
                engineBtn.isKeyboardHighlighted = true
            } else if let tabBtn = activeItem.button as? HUDTabButton {
                tabBtn.isKeyboardHighlighted = true
            }
            
            scrollToHighlightedItem()
        }
    }
    
    private func scrollToHighlightedItem() {
        guard highlightedIndex >= 0, highlightedIndex < filteredItems.count else { return }
        let item = filteredItems[highlightedIndex]
        _ = item.view.scrollToVisible(item.view.bounds)
    }
}

// MARK: - NSTextFieldDelegate
extension ModifierHUDView: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard let textField = obj.object as? NSTextField else { return }
        updateFilteredList(filter: textField.stringValue)
    }
    
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.moveDown(_:)) {
            if highlightedIndex < filteredItems.count - 1 {
                highlightedIndex += 1
                updateHighlighting()
            }
            return true
        } else if commandSelector == #selector(NSResponder.moveUp(_:)) {
            if highlightedIndex > 0 {
                highlightedIndex -= 1
                updateHighlighting()
            }
            return true
        } else if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            if highlightedIndex >= 0 && highlightedIndex < filteredItems.count {
                let activeItem = filteredItems[highlightedIndex]
                switch activeItem.type {
                case .engine(_, let idx, _):
                    wc?.selectService(at: idx)
                case .tab(let session, _, let serviceIndex, _, _):
                    wc?.selectService(at: serviceIndex)
                    wc?.switchSession(to: session.sessionIndex)
                }
                hide()
            }
            return true
        } else if commandSelector == #selector(NSResponder.insertTab(_:)) ||
                  commandSelector == #selector(NSResponder.insertBacktab(_:)) {
            return true
        }
        return false
    }
}

// MARK: - Flipped Stack View
final class FlippedStackView: NSStackView {
    override var isFlipped: Bool { true }
}

extension NSView {
    fileprivate func resolvedCGColor(_ color: NSColor) -> CGColor {
        var result = color.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            result = color.cgColor
        }
        return result
    }
}

import AppKit

@MainActor
final class PromptHistoryHUDView: NSView {
    var isHiding: Bool = false
    
    private weak var wc: MainWindowController?
    private let visualEffectView: NSVisualEffectView
    private let containerView: NSView
    
    private var searchField: NSTextField!
    private let recordSwitch = PromptHistoryHUDSwitchRow()
    private let clearAllButton = PromptHistoryHUDButton()
    
    private let scrollView = NSScrollView()
    private let stackView = PromptHistoryHUDFlippedStackView()
    private let emptyLabel = NSTextField(labelWithString: "No History")
    
    private struct FilteredItem {
        let entry: PromptHistoryEntry
        let view: PromptHistoryHUDRow
    }
    
    private var allItems: [FilteredItem] = []
    private var filteredItems: [FilteredItem] = []
    private var highlightedIndex: Int = -1
    
    init(frame frameRect: NSRect, windowController: MainWindowController) {
        self.wc = windowController
        
        visualEffectView = NSVisualEffectView(frame: frameRect)
        containerView = NSView()
        
        super.init(frame: frameRect)
        
        self.appearance = NSAppearance(named: .vibrantDark)
        self.autoresizingMask = [.width, .height]
        
        visualEffectView.autoresizingMask = [.width, .height]
        visualEffectView.material = .hudWindow
        visualEffectView.state = .active
        visualEffectView.blendingMode = .withinWindow
        addSubview(visualEffectView)
        
        // Premium dark backing layer to increase contrast
        let darkBacking = NSView(frame: bounds)
        darkBacking.autoresizingMask = [.width, .height]
        darkBacking.wantsLayer = true
        darkBacking.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.25).cgColor
        visualEffectView.addSubview(darkBacking)
        
        setupContainerCard()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupContainerCard() {
        guard let wc = wc, let service = wc.currentService() else { return }
        let sessionIdx = wc.activeIndicesByURL[service.url] ?? 0
        
        containerView.wantsLayer = true
        containerView.layer?.cornerRadius = 16
        containerView.layer?.backgroundColor = NSColor(white: 0.12, alpha: 0.95).cgColor
        containerView.layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
        containerView.layer?.borderWidth = 1
        containerView.layer?.shadowColor = NSColor.black.cgColor
        containerView.layer?.shadowOpacity = 0.35
        containerView.layer?.shadowOffset = CGSize(width: 0, height: -4)
        containerView.layer?.shadowRadius = 16
        containerView.translatesAutoresizingMaskIntoConstraints = false
        visualEffectView.addSubview(containerView)
        
        // Header Title
        let headerTitle = NSTextField(labelWithString: "PROMPT HISTORY")
        headerTitle.font = NSFont.systemFont(ofSize: 13, weight: .black)
        headerTitle.textColor = .labelColor
        headerTitle.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(headerTitle)
        
        // Close Button
        let closeBtn = PromptHistoryHUDCloseButton()
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
        searchField.placeholderString = "Search past prompts..."
        searchField.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.textColor = .labelColor
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchContainer.addSubview(searchField)
        self.searchField = searchField
        
        // Subheader Control Bar Row
        let controlBar = NSView()
        controlBar.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(controlBar)
        
        // Record History switch
        let isRecordEnabled = wc.webViewManager?.isPromptHistoryEnabled(for: service.url, sessionIndex: sessionIdx) ?? true
        recordSwitch.isOn = isRecordEnabled
        recordSwitch.onToggle = { [weak self, service, sessionIdx] isOn in
            guard let self = self else { return }
            self.wc?.webViewManager?.setPromptHistoryEnabled(isOn, for: service.url, sessionIndex: sessionIdx)
            self.wc?.saveTabsState()
        }
        recordSwitch.translatesAutoresizingMaskIntoConstraints = false
        controlBar.addSubview(recordSwitch)
        
        // Clear All button
        clearAllButton.title = "Clear All"
        clearAllButton.iconName = "trash"
        clearAllButton.shortcut = "⌘K"
        clearAllButton.onClick = { [weak self, service, sessionIdx] in
            guard let self = self else { return }
            self.wc?.webViewManager?.clearPromptHistory(for: service.url, sessionIndex: sessionIdx)
            self.wc?.saveTabsState()
            self.reloadEntries()
        }
        clearAllButton.translatesAutoresizingMaskIntoConstraints = false
        controlBar.addSubview(clearAllButton)
        
        // Divider
        let divider = NSView()
        divider.wantsLayer = true
        divider.layer?.backgroundColor = self.resolvedCGColor(.separatorColor)
        divider.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(divider)
        
        // Scroll view for history list
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(scrollView)
        
        stackView.orientation = .vertical
        stackView.spacing = 6
        stackView.alignment = .leading
        stackView.distribution = .fill
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = stackView
        
        // Empty State Label
        emptyLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.isHidden = true
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(emptyLabel)
        
        // Layout constraints
        NSLayoutConstraint.activate([
            containerView.centerXAnchor.constraint(equalTo: visualEffectView.centerXAnchor),
            containerView.centerYAnchor.constraint(equalTo: visualEffectView.centerYAnchor),
            containerView.widthAnchor.constraint(equalToConstant: 520),
            containerView.heightAnchor.constraint(equalToConstant: 480),
            
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
            
            controlBar.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            controlBar.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            controlBar.topAnchor.constraint(equalTo: searchContainer.bottomAnchor, constant: 8),
            controlBar.heightAnchor.constraint(equalToConstant: 32),
            
            recordSwitch.leadingAnchor.constraint(equalTo: controlBar.leadingAnchor),
            recordSwitch.centerYAnchor.constraint(equalTo: controlBar.centerYAnchor),
            recordSwitch.heightAnchor.constraint(equalToConstant: 30),
            recordSwitch.widthAnchor.constraint(equalToConstant: 200),
            
            clearAllButton.trailingAnchor.constraint(equalTo: controlBar.trailingAnchor),
            clearAllButton.centerYAnchor.constraint(equalTo: controlBar.centerYAnchor),
            clearAllButton.heightAnchor.constraint(equalToConstant: 28),
            clearAllButton.widthAnchor.constraint(equalToConstant: 130),
            
            divider.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            divider.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            divider.topAnchor.constraint(equalTo: controlBar.bottomAnchor, constant: 8),
            divider.heightAnchor.constraint(equalToConstant: 1),
            
            scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            scrollView.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 12),
            scrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -16),
            
            stackView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            stackView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            
            emptyLabel.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor)
        ])
        
        reloadEntries()
    }
    
    func reloadEntries() {
        guard let wc = wc, let service = wc.currentService() else { return }
        let sessionIdx = wc.activeIndicesByURL[service.url] ?? 0
        let history = wc.webViewManager?.getPromptHistory(for: service.url, sessionIndex: sessionIdx) ?? []
        
        // Clear old stack subviews
        for view in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        
        // Sort newest first
        let sortedHistory = history.sorted(by: { $0.timestamp > $1.timestamp })
        
        allItems = sortedHistory.map { entry in
            let row = PromptHistoryHUDRow(entry: entry)
            row.onClick = { [weak self, entry] in
                self?.selectEntry(entry)
            }
            row.onDelete = { [weak self, entry] in
                self?.deleteEntry(entry)
            }
            row.onCopy = { [weak self, entry] in
                self?.copyEntryText(entry)
            }
            row.translatesAutoresizingMaskIntoConstraints = false
            row.heightAnchor.constraint(equalToConstant: 52).isActive = true
            
            return FilteredItem(entry: entry, view: row)
        }
        
        clearAllButton.isEnabled = !history.isEmpty
        updateFilteredList(filter: searchField.stringValue)
    }
    
    private func selectEntry(_ entry: PromptHistoryEntry) {
        guard let wc = wc, let service = wc.currentService() else { return }
        let sessionIdx = wc.activeIndicesByURL[service.url] ?? 0
        let inputState = TabInputState(text: entry.text, isContentEditable: false, start: entry.text.count, end: entry.text.count)
        wc.webViewManager?.setTabInputState(inputState, for: service.url, sessionIndex: sessionIdx)
        wc.focusInputInActiveWebview()
        hide()
    }
    
    private func copyEntryText(_ entry: PromptHistoryEntry) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(entry.text, forType: .string)
        hide()
    }
    
    private func deleteEntry(_ entry: PromptHistoryEntry) {
        guard let wc = wc, let service = wc.currentService() else { return }
        let sessionIdx = wc.activeIndicesByURL[service.url] ?? 0
        
        // Retain current highlight offset or adjust it
        let selectedItemText = highlightedIndex >= 0 && highlightedIndex < filteredItems.count ? filteredItems[highlightedIndex].entry.text : nil
        
        wc.webViewManager?.deletePromptHistoryEntry(entry, for: service.url, sessionIndex: sessionIdx)
        wc.saveTabsState()
        
        // Reload and restore highlighted index if appropriate
        reloadEntries()
        
        if let text = selectedItemText, let newIndex = filteredItems.firstIndex(where: { $0.entry.text == text }) {
            highlightedIndex = newIndex
        } else {
            highlightedIndex = min(highlightedIndex, filteredItems.count - 1)
        }
        updateHighlighting()
    }
    
    private func deleteHighlightedEntry() {
        guard highlightedIndex >= 0 && highlightedIndex < filteredItems.count else { return }
        let targetItem = filteredItems[highlightedIndex]
        deleteEntry(targetItem.entry)
    }
    
    private func updateFilteredList(filter: String) {
        for view in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        
        let query = filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        if query.isEmpty {
            filteredItems = allItems
        } else {
            filteredItems = allItems.filter { $0.entry.text.lowercased().contains(query) }
        }
        
        for item in filteredItems {
            stackView.addArrangedSubview(item.view)
            item.view.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
        }
        
        let hasItems = !filteredItems.isEmpty
        emptyLabel.isHidden = hasItems
        if !hasItems {
            emptyLabel.stringValue = query.isEmpty ? "No History" : "No Matching Results"
        }
        
        updateHighlighting()
    }
    
    private func updateHighlighting() {
        for item in allItems {
            item.view.isKeyboardHighlighted = false
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
            activeItem.view.isKeyboardHighlighted = true
            
            scrollToHighlightedItem()
        }
    }
    
    private func scrollToHighlightedItem() {
        guard highlightedIndex >= 0, highlightedIndex < filteredItems.count else { return }
        let item = filteredItems[highlightedIndex]
        _ = item.view.scrollToVisible(item.view.bounds)
    }
    
    // Swallow mouse clicks to prevent click-through to webview
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if !containerView.frame.contains(point) {
            hide()
        }
    }
    override func mouseUp(with event: NSEvent) {}
    override func mouseMoved(with event: NSEvent) {}
    override func scrollWheel(with event: NSEvent) {}
    
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let isCmdPressed = event.modifierFlags.contains(.command)
        let isDeleteKey = (event.keyCode == 51 || event.keyCode == 117)
        if isCmdPressed && isDeleteKey {
            deleteHighlightedEntry()
            return true
        }
        if isCmdPressed {
            let key = event.charactersIgnoringModifiers?.lowercased()
            if key == "r" {
                toggleRecordHistory()
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }
    
    private func toggleRecordHistory() {
        guard let wc = wc, let service = wc.currentService() else { return }
        let sessionIdx = wc.activeIndicesByURL[service.url] ?? 0
        let currentVal = wc.webViewManager?.isPromptHistoryEnabled(for: service.url, sessionIndex: sessionIdx) ?? true
        let newVal = !currentVal
        recordSwitch.isOn = newVal
        wc.webViewManager?.setPromptHistoryEnabled(newVal, for: service.url, sessionIndex: sessionIdx)
        wc.saveTabsState()
    }
    
    func handleHUDShortcut(_ event: NSEvent) -> Bool {
        let isCmdPressed = event.modifierFlags.contains(.command)
        let isControlPressed = event.modifierFlags.contains(.control)
        let isOptionPressed = event.modifierFlags.contains(.option)
        
        guard isCmdPressed && !isControlPressed && !isOptionPressed else { return false }
        
        let keyCode = event.keyCode
        
        // 1. Cmd+R -> Toggle History recording
        if keyCode == 15 {
            toggleRecordHistory()
            return true
        }
        
        // 2. Cmd+K -> Clear all
        if keyCode == 40 {
            if clearAllButton.isEnabled {
                clearAllButton.onClick?()
            }
            return true
        }
        
        // 3. Cmd+Delete -> Delete highlighted entry
        if keyCode == 51 || keyCode == 117 {
            deleteHighlightedEntry()
            return true
        }
        
        // 4. Cmd+C -> Copy highlighted entry
        if keyCode == 8 {
            if highlightedIndex >= 0 && highlightedIndex < filteredItems.count {
                let targetItem = filteredItems[highlightedIndex]
                copyEntryText(targetItem.entry)
            }
            return true
        }
        
        return false
    }

    func show(in view: NSView) {
        self.isHiding = false
        self.frame = view.bounds
        self.autoresizingMask = [.width, .height]
        self.alphaValue = 0
        view.addSubview(self)
        
        if let window = self.window {
            window.makeFirstResponder(self.searchField)
        }
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1
        }
    }
    
    func hide() {
        self.isHiding = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.removeFromSuperview()
                if self.wc?.promptHistoryHUDView === self {
                    self.wc?.promptHistoryHUDView = nil
                }
            }
        }
    }
}

// MARK: - NSTextFieldDelegate
extension PromptHistoryHUDView: NSTextFieldDelegate {
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
                selectEntry(activeItem.entry)
            }
            return true
        } else if commandSelector == #selector(NSResponder.insertTab(_:)) ||
                  commandSelector == #selector(NSResponder.insertBacktab(_:)) {
            return true
        }
        return false
    }
}

// MARK: - Custom Elements

@MainActor
fileprivate final class PromptHistoryHUDCloseButton: NSControl {
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
fileprivate final class PromptHistoryHUDToggleSwitch: NSControl {
    var isOn = false {
        didSet {
            updateAppearance(animated: true)
        }
    }
    var onToggle: ((Bool) -> Void)?
    
    private var isHovered = false {
        didSet {
            updateHoverState()
        }
    }
    private var trackingArea: NSTrackingArea?
    
    private let trackView = NSView()
    private let thumbView = NSView()
    
    private var thumbLeadingConstraint: NSLayoutConstraint!
    
    init() {
        super.init(frame: .zero)
        wantsLayer = true
        refusesFirstResponder = true
        
        trackView.wantsLayer = true
        trackView.layer?.cornerRadius = 9
        trackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(trackView)
        
        thumbView.wantsLayer = true
        thumbView.layer?.cornerRadius = 7
        thumbView.layer?.backgroundColor = NSColor.white.cgColor
        thumbView.layer?.shadowColor = NSColor.black.cgColor
        thumbView.layer?.shadowOpacity = 0.25
        thumbView.layer?.shadowOffset = CGSize(width: 0, height: 1)
        thumbView.layer?.shadowRadius = 1.5
        thumbView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(thumbView)
        
        thumbLeadingConstraint = thumbView.leadingAnchor.constraint(equalTo: trackView.leadingAnchor, constant: 2)
        
        NSLayoutConstraint.activate([
            trackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            trackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            trackView.widthAnchor.constraint(equalToConstant: 32),
            trackView.heightAnchor.constraint(equalToConstant: 18),
            
            thumbView.centerYAnchor.constraint(equalTo: trackView.centerYAnchor),
            thumbView.widthAnchor.constraint(equalToConstant: 14),
            thumbView.heightAnchor.constraint(equalToConstant: 14),
            thumbLeadingConstraint
        ])
        
        updateAppearance(animated: false)
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
        trackView.layer?.opacity = 0.8
    }
    
    override func mouseUp(with event: NSEvent) {
        trackView.layer?.opacity = 1.0
        let point = convert(event.locationInWindow, from: nil)
        if bounds.contains(point) {
            isOn.toggle()
            onToggle?(isOn)
        }
    }
    
    private func updateHoverState() {
        if isHovered {
            trackView.layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor
            trackView.layer?.borderWidth = 0.5
        } else {
            trackView.layer?.borderWidth = 0
        }
    }
    
    private func updateAppearance(animated: Bool) {
        let targetConstant: CGFloat = isOn ? 16 : 2
        let targetColor = isOn ? resolvedColor(.controlAccentColor) : NSColor(white: 0.25, alpha: 0.8)
        
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                thumbLeadingConstraint.animator().constant = targetConstant
                trackView.animator().layer?.backgroundColor = targetColor.cgColor
            }
        } else {
            thumbLeadingConstraint.constant = targetConstant
            trackView.layer?.backgroundColor = targetColor.cgColor
        }
    }
}

@MainActor
fileprivate final class PromptHistoryHUDSwitchRow: NSControl {
    var isOn = false {
        didSet {
            toggleSwitch.isOn = isOn
        }
    }
    var onToggle: ((Bool) -> Void)?
    
    private var isHovered = false {
        didSet { updateAppearance() }
    }
    private var trackingArea: NSTrackingArea?
    
    private let toggleSwitch = PromptHistoryHUDToggleSwitch()
    private let label = NSTextField(labelWithString: "Record History")
    private let badgeContainer = NSView()
    private let badgeLabel = NSTextField(labelWithString: "⌘R")
    
    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        refusesFirstResponder = true
        
        toggleSwitch.translatesAutoresizingMaskIntoConstraints = false
        addSubview(toggleSwitch)
        
        label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        
        badgeContainer.wantsLayer = true
        badgeContainer.layer?.cornerRadius = 4
        badgeContainer.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        badgeContainer.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        badgeContainer.layer?.borderWidth = 0.5
        badgeContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(badgeContainer)
        
        badgeLabel.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        badgeLabel.textColor = .tertiaryLabelColor
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeContainer.addSubview(badgeLabel)
        
        NSLayoutConstraint.activate([
            toggleSwitch.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            toggleSwitch.centerYAnchor.constraint(equalTo: centerYAnchor),
            toggleSwitch.widthAnchor.constraint(equalToConstant: 32),
            toggleSwitch.heightAnchor.constraint(equalToConstant: 18),
            
            label.leadingAnchor.constraint(equalTo: toggleSwitch.trailingAnchor, constant: 10),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            
            badgeContainer.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
            badgeContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
            badgeContainer.heightAnchor.constraint(equalToConstant: 16),
            badgeContainer.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            
            badgeLabel.leadingAnchor.constraint(equalTo: badgeContainer.leadingAnchor, constant: 5),
            badgeLabel.trailingAnchor.constraint(equalTo: badgeContainer.trailingAnchor, constant: -5),
            badgeLabel.centerYAnchor.constraint(equalTo: badgeContainer.centerYAnchor)
        ])
        
        toggleSwitch.onToggle = { [weak self] isOn in
            self?.isOn = isOn
            self?.onToggle?(isOn)
        }
        
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
        layer?.backgroundColor = resolvedCGColor(NSColor.controlAccentColor.withAlphaComponent(0.15))
    }
    
    override func mouseUp(with event: NSEvent) {
        updateAppearance()
        let point = convert(event.locationInWindow, from: nil)
        if bounds.contains(point) {
            isOn.toggle()
            onToggle?(isOn)
        }
    }
    
    private func updateAppearance() {
        if isHovered {
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
            label.textColor = .labelColor
            badgeLabel.textColor = .secondaryLabelColor
            badgeContainer.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
            label.textColor = .secondaryLabelColor
            badgeLabel.textColor = .tertiaryLabelColor
            badgeContainer.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        }
    }
}

@MainActor
fileprivate final class PromptHistoryHUDButton: NSControl {
    var title = "" {
        didSet { label.stringValue = title }
    }
    var iconName = "" {
        didSet { updateIcon() }
    }
    var shortcut = "" {
        didSet {
            shortcutLabel.stringValue = shortcut
            shortcutContainer.isHidden = shortcut.isEmpty
        }
    }
    override var isEnabled: Bool {
        didSet { updateAppearance() }
    }
    var onClick: (() -> Void)?
    
    private var isHovered = false {
        didSet { updateAppearance() }
    }
    private var trackingArea: NSTrackingArea?
    
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let shortcutContainer = NSView()
    private let shortcutLabel = NSTextField(labelWithString: "")
    
    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        refusesFirstResponder = true
        
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)
        
        label.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        
        shortcutContainer.wantsLayer = true
        shortcutContainer.layer?.cornerRadius = 4
        shortcutContainer.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        shortcutContainer.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        shortcutContainer.layer?.borderWidth = 0.5
        shortcutContainer.translatesAutoresizingMaskIntoConstraints = false
        shortcutContainer.isHidden = true
        addSubview(shortcutContainer)
        
        shortcutLabel.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        shortcutLabel.textColor = .tertiaryLabelColor
        shortcutLabel.translatesAutoresizingMaskIntoConstraints = false
        shortcutContainer.addSubview(shortcutLabel)
        
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 12),
            iconView.heightAnchor.constraint(equalToConstant: 12),
            
            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            
            shortcutContainer.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
            shortcutContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            shortcutContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
            shortcutContainer.heightAnchor.constraint(equalToConstant: 16),
            
            shortcutLabel.leadingAnchor.constraint(equalTo: shortcutContainer.leadingAnchor, constant: 5),
            shortcutLabel.trailingAnchor.constraint(equalTo: shortcutContainer.trailingAnchor, constant: -5),
            shortcutLabel.centerYAnchor.constraint(equalTo: shortcutContainer.centerYAnchor)
        ])
        
        updateAppearance()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func updateIcon() {
        if let img = NSImage(systemSymbolName: iconName, accessibilityDescription: nil) {
            img.isTemplate = true
            iconView.image = img
        }
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
        guard isEnabled else { return }
        isHovered = true
    }
    
    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }
    
    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
    }
    
    override func mouseUp(with event: NSEvent) {
        updateAppearance()
        guard isEnabled else { return }
        let point = convert(event.locationInWindow, from: nil)
        if bounds.contains(point) {
            onClick?()
        }
    }
    
    private func updateAppearance() {
        if !isEnabled {
            iconView.contentTintColor = .tertiaryLabelColor
            label.textColor = .tertiaryLabelColor
            shortcutLabel.textColor = .tertiaryLabelColor
            shortcutContainer.layer?.backgroundColor = NSColor.clear.cgColor
            layer?.backgroundColor = NSColor.clear.cgColor
            return
        }
        
        if isHovered {
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
            label.textColor = .labelColor
            iconView.contentTintColor = .labelColor
            shortcutLabel.textColor = .secondaryLabelColor
            shortcutContainer.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
            label.textColor = .secondaryLabelColor
            iconView.contentTintColor = .secondaryLabelColor
            shortcutLabel.textColor = .tertiaryLabelColor
            shortcutContainer.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        }
    }
}

@MainActor
fileprivate final class PromptHistoryHUDActionPill: NSControl {
    var onClick: (() -> Void)?
    private var isHovered = false {
        didSet { updateAppearance() }
    }
    private var trackingArea: NSTrackingArea?
    private let iconView = NSImageView()
    private let shortcutLabel = NSTextField(labelWithString: "")
    private let isDestructive: Bool
    
    init(iconName: String, shortcut: String, isDestructive: Bool = false) {
        self.isDestructive = isDestructive
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.borderWidth = 0.5
        refusesFirstResponder = true
        
        if let image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil) {
            image.isTemplate = true
            iconView.image = image
        }
        iconView.contentTintColor = .secondaryLabelColor
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)
        
        shortcutLabel.font = NSFont.systemFont(ofSize: 9, weight: .bold)
        shortcutLabel.textColor = .secondaryLabelColor
        shortcutLabel.stringValue = shortcut
        shortcutLabel.drawsBackground = false
        shortcutLabel.isBordered = false
        shortcutLabel.isEditable = false
        shortcutLabel.isSelectable = false
        shortcutLabel.cell?.usesSingleLineMode = true
        shortcutLabel.cell?.lineBreakMode = .byClipping
        shortcutLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(shortcutLabel)
        
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 11),
            iconView.heightAnchor.constraint(equalToConstant: 11),
            
            shortcutLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 4),
            shortcutLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            shortcutLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
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
        if isDestructive {
            layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.3).cgColor
        } else {
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.2).cgColor
        }
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
            if isDestructive {
                layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.12).cgColor
                layer?.borderColor = NSColor.systemRed.withAlphaComponent(0.3).cgColor
                iconView.contentTintColor = .systemRed
                shortcutLabel.textColor = .systemRed
            } else {
                layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
                layer?.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor
                iconView.contentTintColor = .labelColor
                shortcutLabel.textColor = .labelColor
            }
        } else {
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.04).cgColor
            layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
            iconView.contentTintColor = .secondaryLabelColor
            shortcutLabel.textColor = .secondaryLabelColor
        }
    }
}

@MainActor
fileprivate final class PromptHistoryHUDRow: NSControl {
    var onClick: (() -> Void)?
    var onDelete: (() -> Void)?
    var onCopy: (() -> Void)?
    
    var isKeyboardHighlighted = false {
        didSet { updateAppearance() }
    }
    private var isHovered = false {
        didSet { updateAppearance() }
    }
    private var trackingArea: NSTrackingArea?
    
    private let textLabel = NSTextField()
    private let timeLabel = NSTextField()
    private let deletePill = PromptHistoryHUDActionPill(iconName: "trash", shortcut: "⌘⌫", isDestructive: true)
    private let copyPill = PromptHistoryHUDActionPill(iconName: "doc.on.doc", shortcut: "⌘C")
    
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
    
    init(entry: PromptHistoryEntry) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        refusesFirstResponder = true
        
        let singleLine = entry.text.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
        textLabel.stringValue = singleLine
        textLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        textLabel.textColor = .labelColor
        textLabel.drawsBackground = false
        textLabel.isBordered = false
        textLabel.isEditable = false
        textLabel.isSelectable = false
        textLabel.cell?.lineBreakMode = .byTruncatingTail
        textLabel.cell?.usesSingleLineMode = false
        textLabel.cell?.wraps = true
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textLabel)
        
        timeLabel.stringValue = Self.dateFormatter.string(from: entry.timestamp)
        timeLabel.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        timeLabel.textColor = .secondaryLabelColor
        timeLabel.drawsBackground = false
        timeLabel.isBordered = false
        timeLabel.isEditable = false
        timeLabel.isSelectable = false
        timeLabel.cell?.lineBreakMode = .byTruncatingTail
        timeLabel.cell?.usesSingleLineMode = true
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(timeLabel)
        
        deletePill.onClick = { [weak self] in
            self?.onDelete?()
        }
        deletePill.translatesAutoresizingMaskIntoConstraints = false
        deletePill.isHidden = true
        addSubview(deletePill)
        
        copyPill.onClick = { [weak self] in
            self?.onCopy?()
        }
        copyPill.translatesAutoresizingMaskIntoConstraints = false
        copyPill.isHidden = true
        addSubview(copyPill)
        
        NSLayoutConstraint.activate([
            textLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            textLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            textLabel.trailingAnchor.constraint(equalTo: copyPill.leadingAnchor, constant: -12),
            textLabel.heightAnchor.constraint(lessThanOrEqualToConstant: 24),
            
            timeLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            timeLabel.topAnchor.constraint(equalTo: textLabel.bottomAnchor, constant: 2),
            timeLabel.trailingAnchor.constraint(equalTo: copyPill.leadingAnchor, constant: -12),
            timeLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            
            deletePill.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            deletePill.centerYAnchor.constraint(equalTo: centerYAnchor),
            deletePill.heightAnchor.constraint(equalToConstant: 22),
            
            copyPill.trailingAnchor.constraint(equalTo: deletePill.leadingAnchor, constant: -8),
            copyPill.centerYAnchor.constraint(equalTo: centerYAnchor),
            copyPill.heightAnchor.constraint(equalToConstant: 22)
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
        let point = convert(event.locationInWindow, from: nil)
        if deletePill.frame.contains(point) || copyPill.frame.contains(point) {
            return
        }
        layer?.backgroundColor = resolvedCGColor(NSColor.controlAccentColor.withAlphaComponent(0.3))
    }
    
    override func mouseUp(with event: NSEvent) {
        updateAppearance()
        let point = convert(event.locationInWindow, from: nil)
        if deletePill.frame.contains(point) || copyPill.frame.contains(point) {
            return
        }
        if bounds.contains(point) {
            onClick?()
        }
    }
    
    private func updateAppearance() {
        let showControls = isHovered || isKeyboardHighlighted
        copyPill.isHidden = !showControls
        deletePill.isHidden = !showControls
        
        if isKeyboardHighlighted {
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
            layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor
            layer?.borderWidth = 1.5
            textLabel.textColor = .labelColor
        } else if isHovered {
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
            layer?.borderColor = NSColor.white.withAlphaComponent(0.1).cgColor
            layer?.borderWidth = 1
            textLabel.textColor = .labelColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
            layer?.borderColor = NSColor.clear.cgColor
            layer?.borderWidth = 0
            textLabel.textColor = .labelColor
        }
    }
}

// MARK: - Flipped Stack View
fileprivate final class PromptHistoryHUDFlippedStackView: NSStackView {
    override var isFlipped: Bool { true }
}

// MARK: - NSView Color Helpers
extension NSView {
    fileprivate func resolvedColor(_ color: NSColor) -> NSColor {
        var result = color
        effectiveAppearance.performAsCurrentDrawingAppearance {
            result = color.usingColorSpace(.deviceRGB) ?? color
        }
        return result
    }
    
    fileprivate func resolvedCGColor(_ color: NSColor) -> CGColor {
        return resolvedColor(color).cgColor
    }
}

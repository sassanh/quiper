import AppKit

final class NavigationButtonGroup: NSView {
    
    var onBack: (() -> Void)?
    var onForward: (() -> Void)?
    var onLongPressBack: (() -> [(title: String, url: URL)])?
    var onLongPressForward: (() -> [(title: String, url: URL)])?
    var onNavigateToBackItem: ((Int) -> Void)?
    var onNavigateToForwardItem: ((Int) -> Void)?
    
    private(set) var showBack = false
    private(set) var showForward = false
    
    private let buttonSize: CGFloat = 24
    private let spacing: CGFloat = 0
    
    let backButton: HoverIconButton
    let forwardButton: HoverIconButton
    
    override var acceptsFirstResponder: Bool { false }
    
    init() {
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        let backImage = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Go Back")!
            .withSymbolConfiguration(config)!
        let forwardImage = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Go Forward")!
            .withSymbolConfiguration(config)!
        
        backButton = HoverIconButton(image: backImage, target: nil, action: nil)
        backButton.tooltipText = "Go Back"
        backButton.tooltipShortcut = "⌘["
        forwardButton = HoverIconButton(image: forwardImage, target: nil, action: nil)
        forwardButton.tooltipText = "Go Forward"
        forwardButton.tooltipShortcut = "⌘]"
        
        super.init(frame: .zero)
        setAccessibilityIdentifier("NavigationButtonGroup")
        
        backButton.target = self
        backButton.action = #selector(backClicked)
        forwardButton.target = self
        forwardButton.action = #selector(forwardClicked)
        
        backButton.onLongPress = { [weak self] in self?.showHistoryMenu(forBack: true) }
        forwardButton.onLongPress = { [weak self] in self?.showHistoryMenu(forBack: false) }
        
        addSubview(backButton)
        addSubview(forwardButton)
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    func update(showBack: Bool, showForward: Bool) {
        self.showBack = showBack
        self.showForward = showForward
        isHidden = !showBack && !showForward
        
        backButton.isHidden = !showBack
        forwardButton.isHidden = !showForward
        
        if showBack && showForward {
            backButton.borderMode = .leftSegment
            forwardButton.borderMode = .rightSegment
        } else {
            backButton.borderMode = .single
            forwardButton.borderMode = .single
        }
        
        updateFrames()
        needsDisplay = true
    }
    
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateFrames()
    }
    
    private func updateFrames() {
        let y = (bounds.height - buttonSize) / 2
        if showBack && showForward {
            backButton.frame = NSRect(x: 0, y: y, width: buttonSize, height: buttonSize)
            forwardButton.frame = NSRect(x: buttonSize + spacing, y: y, width: buttonSize, height: buttonSize)
        } else if showBack {
            backButton.frame = NSRect(x: 0, y: y, width: buttonSize, height: buttonSize)
        } else if showForward {
            forwardButton.frame = NSRect(x: 0, y: y, width: buttonSize, height: buttonSize)
        }
    }
    
    var idealWidth: CGFloat {
        if showBack && showForward { return buttonSize * 2 + spacing }
        if showBack || showForward { return buttonSize }
        return 0
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        if showBack && showForward {
            let grayColor = NSColor.tertiaryLabelColor
            grayColor.setStroke()
            
            // Draw a single unified border capsule around both buttons
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
            path.lineWidth = 1.0
            path.stroke()
            
            // Draw the vertical separator in the middle
            let separator = NSBezierPath()
            let midX = bounds.width / 2
            separator.move(to: NSPoint(x: midX, y: 0.5))
            separator.line(to: NSPoint(x: midX, y: bounds.height - 0.5))
            separator.lineWidth = 1.0
            separator.stroke()
        }
    }
    
    @objc private func backClicked() { onBack?() }
    @objc private func forwardClicked() { onForward?() }
    
    private func showHistoryMenu(forBack isBack: Bool) {
        let items: [(title: String, url: URL)]
        let handler: ((Int) -> Void)?
        let anchorView: NSView
        
        if isBack {
            items = onLongPressBack?() ?? []
            handler = onNavigateToBackItem
            anchorView = backButton
        } else {
            items = onLongPressForward?() ?? []
            handler = onNavigateToForwardItem
            anchorView = forwardButton
        }
        
        guard !items.isEmpty else { return }
        
        let menu = NSMenu()
        for (index, item) in items.enumerated() {
            let title = item.title.isEmpty ? item.url.absoluteString : item.title
            let menuItem = NSMenuItem(title: title, action: #selector(historyItemClicked(_:)), keyEquivalent: "")
            menuItem.target = self
            menuItem.tag = index
            menuItem.representedObject = handler
            menu.addItem(menuItem)
        }
        
        let origin = NSPoint(x: 0, y: anchorView.bounds.height + 4)
        menu.popUp(positioning: nil, at: origin, in: anchorView)
    }
    
    @objc private func historyItemClicked(_ sender: NSMenuItem) {
        if let handler = sender.representedObject as? (Int) -> Void {
            handler(sender.tag)
        }
    }
}

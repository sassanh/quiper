import AppKit
import QuartzCore

// MARK: - Delegates and Protocols

@MainActor
protocol CollapsibleSelectorDelegate: AnyObject {
    /// Called to check if segment at index is loading (for spinners, etc.)
    func isLoading(index: Int) -> Bool
    
    /// Called when a drag reorder completes
    func selector(_ selector: CollapsibleSelector, didDragSegment index: Int, to newIndex: Int)
    
    /// Called when the selector is about to expand
    func selectorWillExpand(_ selector: CollapsibleSelector)
}

// Default implementation for optional methods
extension CollapsibleSelectorDelegate {
    func isLoading(index: Int) -> Bool { false }
    func selector(_ selector: CollapsibleSelector, didDragSegment index: Int, to newIndex: Int) {}
    func selectorWillExpand(_ selector: CollapsibleSelector) {}
}

// MARK: - Collapsible Selector

@MainActor
class CollapsibleSelector: NSView {
    
    // Prevent focus from being stolen from webview
    override var acceptsFirstResponder: Bool { false }
    
    // MARK: - Properties
    
    /// Enable drag reordering of segments
    var enableDragReorder: Bool = false
    
    /// Padding around segment labels
    var labelPadding: CGFloat = 20
    
    /// Controls whether hover/click interaction is enabled (set to false when window loses focus)
    var isInteractionEnabled: Bool = true
    
    private let collapsedControl: SegmentedControl
    
    // Expanded State
    private(set) var expandedPanel: NSPanel?
    private var expandedControl: SegmentedControl?
    private(set) var isExpanded = false
    private var collapseTimer: Timer?
    
    // State
    private var _selectedSegment: Int = 0
    var selectedSegment: Int {
        get { _selectedSegment }
        set {
            _selectedSegment = newValue
            updateCollapsedControlTitle()
            expandedControl?.selectedSegment = newValue
            invalidateIntrinsicContentSize()
        }
    }
    
    /// Whether to always show tooltips (like session numbers) or only when truncated (like long service names)
    var alwaysShowTooltips: Bool = true {
        didSet {
            collapsedControl.alwaysShowTooltips = alwaysShowTooltips
            expandedControl?.alwaysShowTooltips = alwaysShowTooltips
        }
    }
    
    // Data
    var items: [String] = [] {
        didSet {
            // Refresh logic if implemented
        }
    }
    var tooltips: [Int: String] = [:]
    
    // Actions
    var target: AnyObject?
    var action: Selector?
    weak var delegate: CollapsibleSelectorDelegate?
    
    // Drag handlers
    var mouseDownSegmentHandler: ((Int) -> Void)?
    var dragBeganHandler: ((Int) -> Void)?
    var dragChangedHandler: ((Int) -> Void)?
    var dragEndedHandler: (() -> Void)?
    
    // Constants
    private let animationDuration: TimeInterval = 0.15
    private let collapseDelay: TimeInterval = 0.3
    var safeAreaPadding: CGFloat = 50
    
    // MARK: - Initialization
    
    init() {
        self.collapsedControl = SegmentedControl(frame: .zero)
        super.init(frame: .zero)
        setupCollapsedControl()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupCollapsedControl() {
        collapsedControl.segmentStyle = .texturedSquare // Allow custom background
        collapsedControl.trackingMode = .selectOne
        collapsedControl.segmentCount = 1
        collapsedControl.selectedSegment = 0 // Force selection so it draws blue
        collapsedControl.segmentDistribution = .fit  // Size to content, don't center
        collapsedControl.target = self
        collapsedControl.action = #selector(collapsedControlClicked)
        collapsedControl.alwaysShowTooltips = alwaysShowTooltips
        addSubview(collapsedControl)
    }
    
    override func layout() {
        super.layout()
        collapsedControl.frame = bounds
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow], owner: self, userInfo: nil))
    }
    
    // MARK: - API
    
    func setLabel(_ label: String, forSegment segment: Int) {
        if items.count <= segment {
             // Extend if needed, or just assume items populated
        }
        // In this simplified version, let's assume caller sets `items` array or strict api.
        // To match NSSegmentedControl API:
        // We actually just need to store current label for collapsed view
        // and all labels for expanded view.
    }
    
    func setToolTip(_ toolTip: String?, forSegment segment: Int) {
        tooltips[segment] = toolTip
        expandedControl?.setToolTip(toolTip, forSegment: segment)
        
        // Dynamic update: if tooltip is visible for this segment, update the content
        if let tip = toolTip, let expanded = expandedControl {
            let isLoading = delegate?.isLoading(index: segment) ?? false
            QuickTooltip.shared.updateIfVisible(with: tip, for: (expanded, segment), isLoading: isLoading)
        }
    }
    
    func setItems(_ newItems: [String]) {
        self.items = newItems
        updateCollapsedControlTitle()
        invalidateIntrinsicContentSize()
        
        // Update active expanded control if visible
        if let control = expandedControl {
            if control.segmentCount != newItems.count {
                control.segmentCount = newItems.count
            }
            
            for (i, item) in newItems.enumerated() {
                control.setLabel(item, forSegment: i)
                control.setImage(nil, forSegment: i)
                if let tip = tooltips[i] { control.setToolTip(tip, forSegment: i) }
            }
            
            // Re-fit
            control.sizeToFit()
            // Update panel frame if needed? 
            // For pure reorder total width is same, but for change it might differ.
            // Let's at least ensure control frame is valid in the container.
            if let container = control.superview as? NSVisualEffectView {
                 container.frame = control.bounds
                 // We'd ideally re-center the panel here using the same logic as expand()
                 // But simply updating the control content handles the visual reorder requirement.
                 // If total width changes, centering might drift, but usually reorder is same items.
            }
        }
    }
    
    // MARK: - Internal Logic
    
    private func updateCollapsedControlTitle() {
        let label = items.indices.contains(_selectedSegment) ? items[_selectedSegment] : "?"
        collapsedControl.setLabel(label, forSegment: 0)
        
        // Calculate dynamic width + padding
        let font = NSFont.systemFont(ofSize: 13)
        let w = (label as NSString).size(withAttributes: [.font: font]).width + labelPadding
        
        collapsedControl.sizeToFit()
        
        // Ensure the control's frame matches the calculated width
        var frame = collapsedControl.frame
        frame.size.width = w
        collapsedControl.frame = frame
    }
    
    var currentWidth: CGFloat {
        let label = items.indices.contains(_selectedSegment) ? items[_selectedSegment] : "?"
        let width = (label as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13)]).width + labelPadding
        return width
    }
    
    override var intrinsicContentSize: NSSize {
        return NSSize(width: currentWidth, height: 25)
    }
    
    @objc private func collapsedControlClicked() {
        guard isInteractionEnabled else { return }
        isExpanded ? collapse() : expand()
    }
    
    // MARK: - Safe Area & Mouse Events
    
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        guard isInteractionEnabled else { return }
        expand()
    }
    
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        scheduleCollapse()
    }
    
    private func scheduleCollapse() {
        collapseTimer?.invalidate()
        collapseTimer = Timer.scheduledTimer(withTimeInterval: collapseDelay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                
                // Safe Area Logic
                if let panel = self.expandedPanel {
                    let mouseInScreen = NSEvent.mouseLocation
                    let safeFrame = panel.frame.insetBy(dx: -self.safeAreaPadding, dy: -self.safeAreaPadding)
                    // If mouse is in safe area, keep open
                    if safeFrame.contains(mouseInScreen) {
                        self.scheduleCollapse()
                        return
                    }
                }
                self.collapse()
            }
        }
    }

    // MARK: - Expansion Logic
    
    private func expand() {
        guard !isExpanded, let window = window, !items.isEmpty else { return }
        
        // Notify delegate before expanding
        delegate?.selectorWillExpand(self)
        
        isExpanded = true
        collapseTimer?.invalidate()
        
        // 1. Create Control
        let control = SegmentedControl(frame: .zero)
        control.forceHighlight = true
        control.segmentStyle = .texturedSquare // Removes default rounded bezel/background
        control.trackingMode = .selectOne
        control.segmentCount = items.count
        control.selectedSegment = _selectedSegment
        if #available(macOS 10.12.2, *) {
            control.selectedSegmentBezelColor = .controlAccentColor
        }
        control.selectorDelegate = delegate
        
        // 2. Configure Items & Events
        
        for (i, item) in items.enumerated() {
            control.setLabel(item, forSegment: i)
            control.setImage(nil, forSegment: i)
            if let tip = tooltips[i] { control.setToolTip(tip, forSegment: i) }
        }
        
        control.target = self
        control.action = #selector(overlayAction(_:))
        control.enableDragReorder = enableDragReorder
        control.mouseDownSegmentHandler = mouseDownSegmentHandler
        control.dragBeganHandler = dragBeganHandler
        control.dragChangedHandler = dragChangedHandler
        control.dragEndedHandler = dragEndedHandler
        control.alwaysShowTooltips = alwaysShowTooltips
        
        control.sizeToFit()
        
        // 3. Layout & Positioning
        let controlWidth = control.frame.width
        
        let controlHeight = max(bounds.height, control.frame.height)
        control.frame = NSRect(x: 0, y: 0, width: controlWidth, height: controlHeight)
        
        // 4. Panel Creation
        let panel = ActivePanel(contentRect: control.bounds, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.backgroundColor = .clear
        panel.level = .popUpMenu
        panel.hasShadow = true
        panel.worksWhenModal = true
        
        if #available(macOS 10.14, *) {
            panel.appearance = NSApp.effectiveAppearance
        }
        
        let container = NSVisualEffectView(frame: control.bounds)
        container.setAccessibilityIdentifier("ExpandedSelectorPanel")
        container.material = .popover // Popover usually supports active state better than menu
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 6
        container.layer?.masksToBounds = true
        container.addSubview(control)
        panel.contentView = container
        
        control.setAccessibilityIdentifier("ExpandedSegmentedControl")
        
        // 5. Calculate Position (Center Alignment)
        let collapsedRect = window.convertToScreen(convert(bounds, to: nil))
        let collapsedCenter = collapsedRect.midX
        
        // Calculate Active Segment Center using Measured Strategy (Unified)
        var currentX: CGFloat = 0
        for i in 0..<_selectedSegment {
            let w = (items[i] as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13)]).width + labelPadding + 1 // Segment separator is 1pt
            currentX += w
        }
        
        let selectedWidth = (items[_selectedSegment] as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13)]).width + labelPadding
        let selectedCenter = currentX + selectedWidth / 2
        
        let panelX = collapsedCenter - selectedCenter
        panel.setFrameOrigin(NSPoint(x: panelX, y: collapsedRect.minY))
        
        window.addChildWindow(panel, ordered: .above)
        panel.alphaValue = 0
        panel.animator().alphaValue = 1
        
        self.expandedPanel = panel
        self.expandedControl = control
    }
    
    func collapse() {
        guard isExpanded, let panel = expandedPanel else { return }
        isExpanded = false
        
        NSAnimationContext.runAnimationGroup { context in
             context.duration = animationDuration
             panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
             Task { @MainActor [weak self] in
                 guard let self = self else { return }
                 
                 // Clean up the specific panel that was collapsed
                 panel.parent?.removeChildWindow(panel)
                 panel.orderOut(nil)
                 
                 // Only clear the main reference if it still points to THIS panel.
                 // If user re-expanded during animation, expandedPanel will be a different, new panel.
                 if self.expandedPanel == panel {
                     self.expandedPanel = nil
                     self.expandedControl = nil
                 }
             }
        }
    }
    
    @objc private func overlayAction(_ sender: NSSegmentedControl) {
        _selectedSegment = sender.selectedSegment
        updateCollapsedControlTitle()
        
        // Forward to main target, passing SENDER (the control) not self
        if let target = target, let action = action {
            _ = target.perform(action, with: sender)
        }
    }
}


// MARK: - Active Panel

class ActivePanel: NSPanel {
    override var isKeyWindow: Bool { true }
    override var isMainWindow: Bool { true }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}


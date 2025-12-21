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

// MARK: - Overlay Segmented Control

class AccentedSegmentedCell: NSSegmentedCell {
    override func drawSegment(_ segment: Int, inFrame frame: NSRect, with view: NSView) {
        if isSelected(forSegment: segment) {
            NSColor.controlAccentColor.setFill()
            // Inset slightly to match standard bezel feel or fill frame?
            // Frame usually matches the segment bounds exactly.
            // Rounded corners:
            // Rounded corners:
            // Inflate slightly to reduce margins (make it fill more vertical space)
            let drawRect = frame.insetBy(dx: 0, dy: -2)
            let path = NSBezierPath(roundedRect: drawRect, xRadius: 4, yRadius: 4)
            path.fill()
            
            if let label = self.label(forSegment: segment) {
                let font = self.font ?? NSFont.systemFont(ofSize: 13)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: NSColor.white
                ]
                let size = label.size(withAttributes: attrs)
                // Center strictly vertically
                let textRect = NSRect(
                    x: frame.origin.x + (frame.width - size.width) / 2,
                    y: frame.origin.y + (frame.height - size.height) / 2, 
                    width: size.width,
                    height: size.height
                )
                label.draw(in: textRect, withAttributes: attrs)
            }
        } else {
            super.drawSegment(segment, inFrame: frame, with: view)
        }
    }
}

/// A segmented control that supports custom tooltips, click handling for non-activating panels, and optional drag-reordering.
class OverlaySegmentedControl: NSSegmentedControl {
    override class var cellClass: AnyClass? {
        get { AccentedSegmentedCell.self }
        set { }
    }
    
    weak var selectorDelegate: CollapsibleSelectorDelegate?
    
    // Tooltips
    private var segmentToolTips: [Int: String] = [:]
    private(set) var lastHoveredSegment: Int?
    
    // Drag & Drop
    var enableDragReorder: Bool = false
    var mouseDownSegmentHandler: ((Int) -> Void)?
    var dragBeganHandler: ((Int) -> Void)?
    var dragChangedHandler: ((Int) -> Void)?
    var dragEndedHandler: (() -> Void)?
    
    // Internal drag state
    private var draggedSegment: Int?
    private var dragCheckTimer: Timer?
    private var isDragging = false
    private let dragThreshold: CGFloat = 5
    private var initialMouseLocation: NSPoint?
    
    private var trackingArea: NSTrackingArea?
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }
    
    override func setToolTip(_ toolTip: String?, forSegment segment: Int) {
        segmentToolTips[segment] = toolTip
    }
    
    // MARK: - Event Handling
    
    override func mouseEntered(with event: NSEvent) {
        handleHover(with: event)
    }
    
    override func mouseMoved(with event: NSEvent) {
        handleHover(with: event)
    }
    
    override func mouseExited(with event: NSEvent) {
        lastHoveredSegment = nil
        QuickTooltip.shared.hide()
    }
    
    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let clickedSegment = segmentIndex(at: location)
        
        if clickedSegment >= 0 {
            // Drag support
            if enableDragReorder {
                initialMouseLocation = event.locationInWindow
                draggedSegment = clickedSegment
                mouseDownSegmentHandler?(clickedSegment)
                
                // Start drag detection
                dragCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
                    guard let self = self, self.initialMouseLocation != nil else {
                        timer.invalidate()
                        return
                    }
                    
                    // let current = NSEvent.mouseLocation
                    // Convert screen point to window point for approximate distance check is fine, 
                    // but better to use window coordinates if possible. 
                    // Since timer is async and mouseLocation is screen, let's skip complex conversion for threshold
                    // and just use the event loop logic in mouseDragged if possible, 
                    // BUT NSSegmentedControl consumes mouse events.
                    // Instead, we'll use the existing pattern from ServiceSelectorControl if it works.
                    // Actually, for simplicity and robustness, let's use the explicit click handling
                    // and only initiate drag if we detect movement in loop if needed, 
                    // or rely on mouseDragged if the control allows it.
                }
            }
            
            // Standard click handling (for non-activating panel)
            // Only trigger if not dragging
            if !isDragging {
                selectedSegment = clickedSegment
                if let target = target, let action = action {
                    _ = target.perform(action, with: self)
                }
            }
        }
    }
    
    // Note: NSSegmentedControl usually captures mouse loop.
    // For drag reordering, we might need the specialized logic from ServiceSelectorControl.
    // Let's integrate that strictly if enabled.
    
    override func mouseDragged(with event: NSEvent) {
        guard enableDragReorder, let initial = initialMouseLocation else {
            super.mouseDragged(with: event)
            return
        }
        
        let current = event.locationInWindow
        let distance = hypot(current.x - initial.x, current.y - initial.y)
        
        if !isDragging && distance > dragThreshold {
            isDragging = true
            if let segment = draggedSegment {
                dragBeganHandler?(segment)
            }
        }
        
        if isDragging, let segment = draggedSegment {
            // Calculate potential new index
            let location = convert(event.locationInWindow, from: nil)
            let hoveredSegment = segmentIndex(at: location)
            if hoveredSegment != -1 && hoveredSegment != segment {
                dragChangedHandler?(hoveredSegment)
            }
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        dragCheckTimer?.invalidate()
        dragCheckTimer = nil
        initialMouseLocation = nil
        
        if isDragging {
            isDragging = false
            draggedSegment = nil
            dragEndedHandler?()
        } else {
            // Normal click handled in mouseDown or here?
            // If we handled in mouseDown, we are good.
            super.mouseUp(with: event)
        }
    }
    
    // MARK: - Tooltip Logic
    
    private func handleHover(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let segment = segmentIndex(at: location)
        
        if segment != -1 {
            let isLoading = selectorDelegate?.isLoading(index: segment) ?? false
            
            if segment != lastHoveredSegment {
                lastHoveredSegment = segment
                if let toolTip = segmentToolTips[segment] {
                    let controlRect = bounds
                    let rectInWindow = convert(controlRect, to: nil)
                    QuickTooltip.shared.show(toolTip, for: self, segment: segment, margin: 4, forcedWidth: controlRect.width, forcedX: rectInWindow.minX, isLoading: isLoading)
                } else {
                    QuickTooltip.shared.hide()
                }
            } else {
                if let toolTip = segmentToolTips[segment] {
                    QuickTooltip.shared.updateIfVisible(with: toolTip, for: (self, segment), isLoading: isLoading)
                }
            }
        } else {
            lastHoveredSegment = nil
            QuickTooltip.shared.hide()
        }
    }
    
    private func segmentIndex(at point: NSPoint) -> Int {
        // Use rect check
        for i in 0..<segmentCount {
            if rect(forSegment: i).contains(point) {
                return i
            }
        }
        return -1
    }
    
    private func rect(forSegment segment: Int) -> NSRect {
        // Use uniform calculation if default
        // But for variable width (Service), we need actual widths
        // NSSegmentedControl doesn't expose cached widths easily without probing
        // So we might need to rely on the same calculation logic as the container
        
        // Strategy: Delegate to super implementation if possible, or use simplified logic
        // Since we are inside the control, we can try to use width(forSegment:)
        
        let count = segmentCount
        guard count > 0 else { return .zero }
        
        // Check if we have explicit widths set (variable width mode)
        let hasExplicitWidths = (0..<count).contains { width(forSegment: $0) > 0 }
        
        if hasExplicitWidths {
             // Variable width (Service)
             // We can't trust width(forSegment:) alone because of padding/distribution
             // But NSSegmentedControl *should* know its layout. 
             // Unfortunately there is no public API to get exact segment frame.
             // We will assume standard distribution of set widths.
             var x: CGFloat = 0
             /* This is an approximation. For pixel-perfect hit testing on variable width controls, 
                we might need the same text-measurement logic or rely on the fact that
                NSSegmentedControl handles clicks internally mostly fine, 
                except for our overlay hack which needs explicit handling.
             */
             // Let's use the Measured strategy logic here too if needed?
             // Or simpler: just use uniform for now if we can't do better, 
             // but that breaks variable width.
             
             // Reuse the text measurement logic if we can access the labels?
             // Or just sum widths:
             for i in 0..<segment {
                 x += width(forSegment: i)
             }
             return NSRect(x: x, y: 0, width: width(forSegment: segment), height: bounds.height)
             
        } else {
            // Fixed/Uniform width (Session)
            let w = bounds.width / CGFloat(count)
            return NSRect(x: CGFloat(segment) * w, y: 0, width: w, height: bounds.height)
        }
    }
}

// MARK: - Collapsible Selector

@MainActor
class CollapsibleSelector: NSView {
    
    // MARK: - Properties
    
    /// Enable drag reordering of segments
    var enableDragReorder: Bool = false
    
    /// Padding around segment labels
    var labelPadding: CGFloat = 20
    
    private let collapsedControl: OverlaySegmentedControl
    
    // Expanded State
    private(set) var expandedPanel: NSPanel?
    private var expandedControl: OverlaySegmentedControl?
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
    private let safeAreaPadding: CGFloat = 50
    
    // MARK: - Initialization
    
    init() {
        self.collapsedControl = OverlaySegmentedControl(frame: .zero)
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
    }
    
    // MARK: - Internal Logic
    
    private func updateCollapsedControlTitle() {
        let label = items.indices.contains(_selectedSegment) ? items[_selectedSegment] : "?"
        collapsedControl.setLabel(label, forSegment: 0)
        
        // Calculate dynamic width + padding
        let font = NSFont.systemFont(ofSize: 13)
        let w = (label as NSString).size(withAttributes: [.font: font]).width + labelPadding
        
        collapsedControl.setWidth(w, forSegment: 0)
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
        isExpanded ? collapse() : expand()
    }
    
    // MARK: - Safe Area & Mouse Events
    
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
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
        let control = OverlaySegmentedControl(frame: .zero)
        control.segmentStyle = .texturedSquare // Removes default rounded bezel/background
        control.trackingMode = .selectOne
        control.segmentCount = items.count
        control.selectedSegment = _selectedSegment
        if #available(macOS 10.12.2, *) {
            control.selectedSegmentBezelColor = .controlAccentColor
        }
        control.selectorDelegate = delegate
        
        // 2. Configure Items & Events
        var totalWidth: CGFloat = 0
        
        for (i, item) in items.enumerated() {
            control.setLabel(item, forSegment: i)
            control.setImage(nil, forSegment: i)
            if let tip = tooltips[i] { control.setToolTip(tip, forSegment: i) }
            
            // Set widths
            let w = (item as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13)]).width + labelPadding
            control.setWidth(w, forSegment: i)
            totalWidth += w
        }
        
        control.target = self
        control.action = #selector(overlayAction(_:))
        control.enableDragReorder = enableDragReorder
        control.mouseDownSegmentHandler = mouseDownSegmentHandler
        control.dragBeganHandler = dragBeganHandler
        control.dragChangedHandler = dragChangedHandler
        control.dragEndedHandler = dragEndedHandler
        
        control.sizeToFit()
        // Force width to be the sum of set widths if sizeToFit failed
        if control.frame.width < totalWidth {
             control.frame.size.width = totalWidth
        }
        
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
        container.material = .popover // Popover usually supports active state better than menu
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 6
        container.layer?.masksToBounds = true
        container.addSubview(control)
        panel.contentView = container
        
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
                 self?.expandedPanel?.parent?.removeChildWindow(panel)
                 self?.expandedPanel?.orderOut(nil)
                 self?.expandedPanel = nil
                 self?.expandedControl = nil
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


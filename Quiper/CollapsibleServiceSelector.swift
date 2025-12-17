import AppKit
import QuartzCore

/// A service selector that collapses to show only the current service,
/// expanding on hover to show all services as an overlay fixed at top-left.
@MainActor
class CollapsibleServiceSelector: NSView {
    
    // MARK: - Properties
    
    // Collapsed state - single-segment control showing current service name
    private let collapsedControl: NSSegmentedControl
    
    // Expanded state - segmented control as overlay
    private var expandedContainer: NSVisualEffectView?
    private var expandedControl: ServiceSelectorControl?
    
    private(set) var isExpanded = false
    private var trackingArea: NSTrackingArea?
    private var expandedTrackingArea: NSTrackingArea?
    private var collapseTimer: Timer?
    private var _selectedSegment: Int = 0
    private var serviceNames: [String] = []
    
    var selectedSegment: Int {
        get { _selectedSegment }
        set {
            guard newValue >= 0 && newValue < max(1, serviceNames.count) else { return }
            _selectedSegment = newValue
            updateCollapsedControlTitle()
            expandedControl?.selectedSegment = newValue
        }
    }
    
    var target: AnyObject?
    var action: Selector?
    
    // Drag handlers to forward to the expanded control
    var mouseDownSegmentHandler: ((Int) -> Void)?
    var dragBeganHandler: ((Int) -> Void)?
    var dragChangedHandler: ((Int) -> Void)?
    var dragEndedHandler: (() -> Void)?
    
    weak var layoutDelegate: CollapsibleServiceSelectorDelegate?
    
    // MARK: - Constants
    
    private let minSegmentWidth: CGFloat = 40
    private let animationDuration: TimeInterval = 0.15
    private let collapseDelay: TimeInterval = 0.3
    
    var collapsedWidth: CGFloat {
        // Width of current service name + padding
        let title = serviceNames.isEmpty ? "?" : serviceNames[safe: _selectedSegment] ?? "?"
        let font = NSFont.systemFont(ofSize: 13)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let titleWidth = (title as NSString).size(withAttributes: attrs).width
        return max(minSegmentWidth, titleWidth + 20)
    }
    
    var currentWidth: CGFloat { collapsedWidth }
    
    // MARK: - Initialization
    
    override init(frame frameRect: NSRect) {
        // Create collapsed control as single-segment control
        collapsedControl = NSSegmentedControl(frame: .zero)
        collapsedControl.segmentStyle = .rounded
        collapsedControl.trackingMode = .selectOne
        collapsedControl.segmentCount = 1
        collapsedControl.setLabel("?", forSegment: 0)
        collapsedControl.selectedSegment = 0
        
        super.init(frame: frameRect)
        
        addSubview(collapsedControl)
        collapsedControl.target = self
        collapsedControl.action = #selector(collapsedControlClicked)
        
        setupAccessibility()
        updateTrackingArea()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupAccessibility() {
        setAccessibilityElement(true)
        setAccessibilityIdentifier("ServiceSelector")
        updateAccessibilityLabel()
    }
    
    private func updateAccessibilityLabel() {
        let name = serviceNames.isEmpty ? "None" : serviceNames[safe: _selectedSegment] ?? "Unknown"
        setAccessibilityLabel("Active Service: \(name)")
    }
    
    private func updateCollapsedControlTitle() {
        let name = serviceNames.isEmpty ? "?" : serviceNames[safe: _selectedSegment] ?? "?"
        collapsedControl.setLabel(name, forSegment: 0)
        collapsedControl.setWidth(collapsedWidth - 4, forSegment: 0)  // Slight padding adjustment
        updateAccessibilityLabel()
        layoutDelegate?.serviceSelectorDidChangeSize(self)
    }
    
    @objc private func collapsedControlClicked() {
        if isExpanded {
            collapse()
        } else {
            expand()
        }
    }
    
    // MARK: - Configuration
    
    func configure(with names: [String], selectedIndex: Int) {
        serviceNames = names
        _selectedSegment = max(0, min(selectedIndex, names.count - 1))
        updateCollapsedControlTitle()
        
        // Also update expanded control if it exists (e.g., during drag reorder)
        if let expanded = expandedControl {
            // Temporarily remove action to prevent triggering during reconfiguration
            let savedAction = expanded.action
            expanded.action = nil
            
            expanded.segmentCount = names.count
            for (i, name) in names.enumerated() {
                expanded.setLabel(name, forSegment: i)
            }
            expanded.selectedSegment = _selectedSegment
            
            expanded.action = savedAction
        }
    }
    
    // MARK: - Layout
    
    override func layout() {
        super.layout()
        collapsedControl.frame = bounds
        updateTrackingArea()
    }
    
    private func updateTrackingArea() {
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }
    
    // MARK: - Expand/Collapse
    
    private func expand() {
        guard !isExpanded, let parentView = superview, !serviceNames.isEmpty else { return }
        isExpanded = true
        collapseTimer?.invalidate()
        collapseTimer = nil
        
        // Create expanded control (using ServiceSelectorControl for drag support)
        let control = ServiceSelectorControl(frame: .zero)
        control.segmentStyle = .rounded
        control.trackingMode = .selectOne
        control.segmentCount = serviceNames.count
        for (i, name) in serviceNames.enumerated() {
            control.setLabel(name, forSegment: i)
        }
        control.selectedSegment = _selectedSegment
        control.target = self
        control.action = #selector(overlaySegmentChanged(_:))
        
        // Forward drag handlers
        control.mouseDownSegmentHandler = mouseDownSegmentHandler
        control.dragBeganHandler = dragBeganHandler
        control.dragChangedHandler = dragChangedHandler
        control.dragEndedHandler = dragEndedHandler
        
        control.sizeToFit()
        let controlWidth = control.frame.width
        let controlHeight = max(bounds.height, control.frame.height)
        control.frame = NSRect(x: 0, y: 0, width: controlWidth, height: controlHeight)
        expandedControl = control
        
        // Create container with background
        let container = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: controlWidth, height: controlHeight))
        container.material = .menu
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 6
        container.layer?.masksToBounds = true
        container.addSubview(control)
        container.alphaValue = 0
        expandedContainer = container
        
        // Position at the same location as collapsed control (left-aligned in parent)
        let containerFrame = NSRect(
            x: frame.minX,
            y: frame.minY,
            width: controlWidth,
            height: controlHeight
        )
        container.frame = containerFrame
        
        // Add to parent view above everything
        parentView.addSubview(container, positioned: .above, relativeTo: nil)
        
        // Add tracking area for expanded container
        expandedTrackingArea = NSTrackingArea(
            rect: container.bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self,
            userInfo: ["expanded": true]
        )
        container.addTrackingArea(expandedTrackingArea!)
        
        // Fade in
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            container.animator().alphaValue = 1
        }
    }
    
    private func collapse() {
        guard isExpanded, let container = expandedContainer else { return }
        isExpanded = false
        
        // Remove tracking area
        if let trackingArea = expandedTrackingArea {
            container.removeTrackingArea(trackingArea)
            expandedTrackingArea = nil
        }
        
        // Fade out and remove
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            container.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                self?.expandedContainer?.removeFromSuperview()
                self?.expandedContainer = nil
                self?.expandedControl = nil
            }
        })
    }
    
    @objc private func overlaySegmentChanged(_ sender: NSSegmentedControl) {
        let newSelection = sender.selectedSegment
        _selectedSegment = newSelection
        updateCollapsedControlTitle()
        
        // Trigger the original action
        if let target = target, let action = action {
            _ = target.perform(action, with: self)
        }
    }
    
    func scheduleCollapse() {
        collapseTimer?.invalidate()
        collapseTimer = Timer.scheduledTimer(withTimeInterval: collapseDelay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.collapse()
            }
        }
    }
    
    func cancelCollapseTimer() {
        collapseTimer?.invalidate()
        collapseTimer = nil
    }
    
    // MARK: - Public Methods
    
    func selectService(_ index: Int, animated: Bool = true) {
        guard index >= 0 && index < serviceNames.count else { return }
        _selectedSegment = index
        updateCollapsedControlTitle()
        expandedControl?.selectedSegment = index
    }
    
    // MARK: - Mouse Tracking
    
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        
        if let userInfo = event.trackingArea?.userInfo as? [String: Bool],
           userInfo["expanded"] == true {
            cancelCollapseTimer()
            return
        }
        
        cancelCollapseTimer()
        expand()
    }
    
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        
        if isExpanded, let container = expandedContainer {
            let mouseLocation = convert(event.locationInWindow, from: nil)
            let containerInSelf = convert(container.frame, from: superview)
            if containerInSelf.contains(mouseLocation) {
                return
            }
        }
        
        scheduleCollapse()
    }
}

// MARK: - Delegate Protocol

@MainActor
protocol CollapsibleServiceSelectorDelegate: AnyObject {
    func serviceSelectorDidChangeSize(_ selector: CollapsibleServiceSelector)
}

// MARK: - Safe Array Subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

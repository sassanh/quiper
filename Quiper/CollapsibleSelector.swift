import AppKit
import QuartzCore

// MARK: - Delegates and Protocols

@MainActor
protocol CollapsibleSelectorDelegate: AnyObject {
    /// Called to check if segment at index is loading (for spinners, etc.)
    func isLoading(index: Int) -> Bool
    
    /// Called to check if segment at index represents an instantiated session/service (CollapsibleSelector)
    func selector(_ selector: CollapsibleSelector, isInstantiated index: Int) -> Bool
    
    /// Called to check if segment at index represents an instantiated session/service (standalone SegmentedControl)
    func segmentedControl(_ control: SegmentedControl, isInstantiated index: Int) -> Bool
    
    /// Called to check if segment at index represents a locked service (CollapsibleSelector)
    func selector(_ selector: CollapsibleSelector, isLocked index: Int) -> Bool
    
    /// Called to check if segment at index represents a locked service (standalone SegmentedControl)
    func segmentedControl(_ control: SegmentedControl, isLocked index: Int) -> Bool
    
    /// Called when a drag reorder completes
    func selector(_ selector: CollapsibleSelector, didDragSegment index: Int, to newIndex: Int)
    
    /// Called when the selector is about to expand
    func selectorWillExpand(_ selector: CollapsibleSelector)
    
    /// Called when the expansion state changes
    func collapsibleSelector(_ selector: CollapsibleSelector, didChangeExpansionState isExpanded: Bool)
}

// Default implementation for optional methods
extension CollapsibleSelectorDelegate {
    func isLoading(index: Int) -> Bool { false }
    func selector(_ selector: CollapsibleSelector, isInstantiated index: Int) -> Bool { true } // Default: assume instantiated
    func segmentedControl(_ control: SegmentedControl, isInstantiated index: Int) -> Bool { true } // Default: assume instantiated
    func selector(_ selector: CollapsibleSelector, isLocked index: Int) -> Bool { false } // Default: not locked
    func segmentedControl(_ control: SegmentedControl, isLocked index: Int) -> Bool { false } // Default: not locked
    func selector(_ selector: CollapsibleSelector, didDragSegment index: Int, to newIndex: Int) {}
    func selectorWillExpand(_ selector: CollapsibleSelector) {}
    func collapsibleSelector(_ selector: CollapsibleSelector, didChangeExpansionState isExpanded: Bool) {}
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
    var labelPadding: CGFloat = 16
    
    /// Controls whether hover/click interaction is enabled (set to false when window loses focus)
    var isInteractionEnabled: Bool = true
    
    var showInstantiationState: Bool = false {
        didSet {
            collapsedControl.showInstantiationState = showInstantiationState
            expandedControl?.showInstantiationState = showInstantiationState
            needsDisplay = true
            collapsedControl.needsDisplay = true
            expandedControl?.needsDisplay = true
        }
    }
    
    private let collapsedControl: SegmentedControl
    
    // Expanded State
    var expandedPanel: NSPanel? {
        guard let window else { return nil }
        return window.childWindows?
            .compactMap { $0 as? NSPanel }
            .first { expandedControl(in: $0) != nil }
    }

    private var expandedControl: SegmentedControl? {
        guard let expandedPanel else { return nil }
        return expandedControl(in: expandedPanel)
    }

    var isExpanded: Bool {
        expandedPanel != nil
    }
    
    var isTrackingMouse: Bool {
        return expandedControl?.isTrackingMouse ?? false
    }

    private func expandedControl(in panel: NSPanel) -> SegmentedControl? {
        panel.contentView?.subviews
            .compactMap { $0 as? SegmentedControl }
            .first { $0.parentSelector === self }
    }
    
    // State
    private var _selectedSegment: Int = 0
    
    /// Alignment preference when in empty state (_selectedSegment < 0)
    enum EmptyStateAlignment {
        case center
        case left   // Open to the left of the button (right edge aligned with button left edge)
        case right  // Open to the right of the button (left edge aligned with button right edge)
    }
    var emptyStateAlignment: EmptyStateAlignment = .center
    
    /// Label shown when no segment is selected (empty state)
    var placeholderLabel: String = "—"
    
    var selectedSegment: Int {
        get { _selectedSegment }
        set {
            _selectedSegment = newValue
            updateCollapsedControlTitle()
            if newValue >= 0 {
                expandedControl?.selectedSegment = newValue
            } else {
                expandedControl?.selectedSegment = -1
            }
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

    var requiresInstantiatedSegmentForTooltip: Bool = false {
        didSet {
            collapsedControl.requiresInstantiatedSegmentForTooltip = requiresInstantiatedSegmentForTooltip
            expandedControl?.requiresInstantiatedSegmentForTooltip = requiresInstantiatedSegmentForTooltip
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
    weak var delegate: CollapsibleSelectorDelegate? {
        didSet {
            collapsedControl.selectorDelegate = delegate
            collapsedControl.parentSelector = self
            expandedControl?.selectorDelegate = delegate
            expandedControl?.parentSelector = self
        }
    }
    
    // Drag handlers
    var mouseDownSegmentHandler: ((Int) -> Void)?
    var middleClickHandler: ((Int) -> Void)?
    var dragBeganHandler: ((Int) -> Void)?
    var dragChangedHandler: ((Int) -> Void)?
    var dragEndedHandler: (() -> Void)?
    
    // Constants
    private let animationDuration: TimeInterval = 0.15
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
        collapsedControl.segmentStyle = .capsule
        collapsedControl.trackingMode = .selectOne
        collapsedControl.segmentCount = 1
        collapsedControl.selectedSegment = 0 // Force selection so it draws blue
        collapsedControl.segmentDistribution = .fill
        collapsedControl.target = self
        collapsedControl.action = #selector(collapsedControlClicked)
        collapsedControl.alwaysShowTooltips = alwaysShowTooltips
        collapsedControl.showInstantiationState = showInstantiationState
        collapsedControl.selectorDelegate = delegate
        collapsedControl.parentSelector = self
        addSubview(collapsedControl)
    }
    
    private var trackingArea: NSTrackingArea?
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .mouseMoved, .activeAlways]
        trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }
    
    override func layout() {
        super.layout()
        collapsedControl.frame = bounds
    }
    
    // MARK: - API
    
    func setToolTip(_ toolTip: String?, forSegment segment: Int) {
        let trimmedToolTip = toolTip?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedToolTip = trimmedToolTip?.isEmpty == false ? trimmedToolTip : nil
        tooltips[segment] = normalizedToolTip
        expandedControl?.setToolTip(normalizedToolTip, forSegment: segment)
        
        // Dynamic update: if tooltip is visible for this segment, update the content
        if let tip = normalizedToolTip, let expanded = expandedControl {
            let isLoading = delegate?.isLoading(index: segment) ?? false
            QuickTooltip.shared.updateIfVisible(with: tip, for: expanded, segment: segment, isLoading: isLoading)
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
            
            control.customLockedStates = newItems.indices.map { delegate?.selector(self, isLocked: $0) == true }
            control.customLabels = newItems
            
            for (i, item) in newItems.enumerated() {
                control.setLabel(item, forSegment: i)
                control.setImage(nil, forSegment: i)
                control.setToolTip(tooltips[i], forSegment: i)
            }
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
    
    /// Refresh the display to update instantiation state styling
    func refreshInstantiationState() {
        collapsedControl.needsDisplay = true
        if let expandedControl = expandedControl {
            expandedControl.customInstantiatedStates = items.indices.map { delegate?.selector(self, isInstantiated: $0) == true }
            expandedControl.customLockedStates = items.indices.map { delegate?.selector(self, isLocked: $0) == true }
            expandedControl.needsDisplay = true
        }
    }
    
    // MARK: - Internal Logic
    
    private func updateCollapsedControlTitle() {
        let label: String
        let isLocked: Bool
        let isInstantiated: Bool
        if _selectedSegment >= 0, items.indices.contains(_selectedSegment) {
            label = items[_selectedSegment]
            isLocked = delegate?.selector(self, isLocked: _selectedSegment) ?? false
            isInstantiated = delegate?.selector(self, isInstantiated: _selectedSegment) ?? false
        } else {
            label = placeholderLabel
            isLocked = false
            isInstantiated = false
        }
        
        collapsedControl.customLabels = [label]
        collapsedControl.customLockedStates = [isLocked]
        collapsedControl.customInstantiatedStates = [isInstantiated]
        
        collapsedControl.setLabel(label, forSegment: 0)
        collapsedControl.setImage(nil, forSegment: 0)
        collapsedControl.selectedSegment = _selectedSegment >= 0 ? 0 : -1
    }
    
    var currentWidth: CGFloat {
        return collapsedControl.width(forSegment: 0)
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
    
    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        guard isInteractionEnabled, !isExpanded else { return }
        expand()
    }
    
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        // Collapse policy is owned by the parent controller via cursor monitoring.
        // Nothing to do here.
    }
    
    override func otherMouseDown(with event: NSEvent) {
        guard event.buttonNumber == 2 else {
            super.otherMouseDown(with: event)
            return
        }
        // When collapsed, the single visible segment represents _selectedSegment
        middleClickHandler?(_selectedSegment)
    }

    // MARK: - Expansion Logic
    
    func expand() {
        guard !isExpanded, let window = window, !items.isEmpty else { return }
        
        // 1. Create Control
        let control = SegmentedControl(frame: .zero)
        control.forceHighlight = true
        control.segmentStyle = .texturedSquare // Removes default rounded bezel/background
        control.trackingMode = .selectOne
        control.segmentCount = items.count
        if _selectedSegment >= 0 && _selectedSegment < items.count {
            control.selectedSegment = _selectedSegment
        } else {
            control.selectedSegment = -1
        }
        if #available(macOS 10.12.2, *) {
            control.selectedSegmentBezelColor = .controlAccentColor
        }
        control.selectorDelegate = delegate
        control.showInstantiationState = showInstantiationState
        control.requiresInstantiatedSegmentForTooltip = requiresInstantiatedSegmentForTooltip
        control.parentSelector = self
        
        // 2. Configure Items & Events
        
        control.customLockedStates = items.indices.map { delegate?.selector(self, isLocked: $0) == true }
        control.customInstantiatedStates = items.indices.map { delegate?.selector(self, isInstantiated: $0) == true }
        control.customLabels = items
        control.showInstantiationState = showInstantiationState
        
        for (i, item) in items.enumerated() {
            control.setLabel(item, forSegment: i)
            control.setImage(nil, forSegment: i)
            if let tip = tooltips[i] { control.setToolTip(tip, forSegment: i) }
        }
        
        control.target = self
        control.action = #selector(overlayAction(_:))
        control.enableDragReorder = enableDragReorder
        control.mouseDownSegmentHandler = mouseDownSegmentHandler
        control.middleClickHandler = middleClickHandler
        control.dragBeganHandler = dragBeganHandler
        control.dragChangedHandler = dragChangedHandler
        control.dragEndedHandler = { [weak self] in
            self?.dragEndedHandler?()
        }
        control.alwaysShowTooltips = alwaysShowTooltips
        
        if items.count > 0 {
            control.sizeToFit()
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
        panel.collectionBehavior = Settings.shared.showOnAllSpaces
            ? [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            : [.transient, .ignoresCycle, .fullScreenAuxiliary]
        
        if #available(macOS 10.14, *) {
            panel.appearance = Settings.shared.colorScheme.nsAppearance ?? NSApp.effectiveAppearance
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
        
        let panelX: CGFloat
        if _selectedSegment >= 0, items.indices.contains(_selectedSegment) {
            var currentX: CGFloat = 0
            for i in 0..<_selectedSegment {
                currentX += control.width(forSegment: i)
            }
            let selectedWidth = control.width(forSegment: _selectedSegment)
            let selectedCenter = currentX + selectedWidth / 2
            panelX = collapsedCenter - selectedCenter
        } else {
            // No segment selected — position based on alignment preference
            switch emptyStateAlignment {
            case .center:
                panelX = collapsedCenter - controlWidth / 2
            case .left:
                // Panel's right edge aligned with button's left edge
                panelX = collapsedRect.minX - controlWidth - 4
            case .right:
                // Panel's left edge aligned with button's right edge
                panelX = collapsedRect.maxX + 4
            }
        }
        panel.setFrameOrigin(NSPoint(x: panelX, y: collapsedRect.minY))
        
        // Attaching the selector-owned panel is the single expanded-state transition.
        // Do this before notifying the delegate so reentrant callbacks see the same state.
        panel.alphaValue = 0.4
        window.addChildWindow(panel, ordered: .above)
        delegate?.selectorWillExpand(self)
        delegate?.collapsibleSelector(self, didChangeExpansionState: true)
        panel.animator().alphaValue = 1
    }
    
    func collapse() {
        guard let panel = expandedPanel else { return }

        // Detaching immediately makes the selector collapsed before the old panel
        // finishes fading, allowing a new expansion without shared-state races.
        panel.parent?.removeChildWindow(panel)
        delegate?.collapsibleSelector(self, didChangeExpansionState: false)
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animationDuration
            panel.animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor in
                // The captured panel owns only its own visual cleanup. It never
                // mutates the state of a panel created by a later expansion.
                panel.orderOut(nil)
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

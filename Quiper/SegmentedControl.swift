import AppKit

// MARK: - Segmented Cell

class SegmentedCell: NSSegmentedCell {
    /// Frames captured during the most recent draw pass, keyed by segment index.
    /// Used by SegmentedControl.draw(_:) to apply overlays at exact positions.
    var capturedFrames: [Int: NSRect] = [:]

    override func drawSegment(_ segment: Int, inFrame frame: NSRect, with view: NSView) {
        capturedFrames[segment] = frame
        super.drawSegment(segment, inFrame: frame, with: view)
    }
}

// MARK: - Segmented Control

/// A segmented control that supports custom tooltips, click handling for non-activating panels, and optional drag-reordering.
class SegmentedControl: NSSegmentedControl {
    override class var cellClass: AnyClass? {
        get { SegmentedCell.self }
        set { }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }
    
    // Prevent focus from being stolen from webview
    override var acceptsFirstResponder: Bool { false }
    
    weak var selectorDelegate: CollapsibleSelectorDelegate?
    
    /// Reference to parent CollapsibleSelector for delegate calls
    weak var parentSelector: CollapsibleSelector?
    
    /// Whether to show instantiation state (grayed out uninstantiated segments)
    var showInstantiationState: Bool = false {
        didSet { needsDisplay = true }
    }
    
    // Tooltips
    private var segmentToolTips: [Int: String] = [:]
    private(set) var lastHoveredSegment: Int?
    var alwaysShowTooltips: Bool = true

    var forceHighlight: Bool = false

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard showInstantiationState else {
            super.draw(dirtyRect)
            return
        }

        let uninstantiatedFontColor = parentSelector == nil
            ? NSColor.controlBackgroundColor.withAlphaComponent(0.2)
            : NSColor.underPageBackgroundColor.withAlphaComponent(0.3)
        let instantiatedFontColor = NSColor.textColor
        let uninstantiatedBackgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.5)
        let instantiatedBackgroundColor = NSColor.underPageBackgroundColor.withAlphaComponent(0.3)
        
        let isOuterPill = segmentStyle == .rounded || segmentStyle == .automatic

        // Determine instantiation state per segment up front
        var instantiated = [Bool](repeating: false, count: segmentCount)
        for i in 0..<segmentCount {
            if let sel = parentSelector {
                instantiated[i] = selectorDelegate?.selector(sel, isInstantiated: i) == true
            } else {
                instantiated[i] = selectorDelegate?.segmentedControl(self, isInstantiated: i) == true
            }
        }

        NSGraphicsContext.saveGraphicsState()
        if isOuterPill {
            NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).setClip()
        }

        super.draw(dirtyRect) // capturedFrames updated by drawSegment during this call

        let segFont = font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize(for: controlSize))
        for i in 0..<segmentCount {
            let isSelected = (i == selectedSegment)
            guard let originalLabel = label(forSegment: i), !originalLabel.isEmpty else { continue }

            let captured = (cell as? SegmentedCell)?.capturedFrames[i]
            let segX = captured?.minX ?? (bounds.width / CGFloat(segmentCount) * CGFloat(i))
            let segW = captured?.width ?? (bounds.width / CGFloat(segmentCount))
            let segFrame = backingAlignedRect(NSRect(x: segX, y: bounds.minY, width: segW, height: bounds.height), options: .alignAllEdgesNearest)

            let attrs: [NSAttributedString.Key: Any] = [
                .font: segFont,
                .foregroundColor: isSelected
                    ? NSColor.white
                    : instantiated[i] ? instantiatedFontColor : uninstantiatedFontColor
            ]
            let size = (originalLabel as NSString).size(withAttributes: attrs)
            let textRect = NSRect(
                x: segFrame.midX - size.width / 2,
                y: segFrame.midY - size.height / 2,
                width: size.width,
                height: size.height
            )

            NSGraphicsContext.saveGraphicsState()
            if isSelected {
                NSColor.controlAccentColor.setFill()
                segFrame.fill(using: .sourceOver)
            } else if (instantiated[i]) {
                instantiatedBackgroundColor.setFill()
                segFrame.insetBy(dx: 0, dy: 1).fill(using: .sourceOver)
            } else {
                uninstantiatedBackgroundColor.setFill()
                segFrame.insetBy(dx: 0, dy: 1).fill(using: .sourceOver)
                // textRect.insetBy(dx: -1, dy: -2).fill()
            }
            NSGraphicsContext.restoreGraphicsState()

            (originalLabel as NSString).draw(in: textRect, withAttributes: attrs)
        }

        NSGraphicsContext.restoreGraphicsState()
    }

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
    
    var isTrackingMouse: Bool {
        return draggedSegment != nil || initialMouseLocation != nil || isDragging
    }
    
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
            if enableDragReorder {
                initialMouseLocation = event.locationInWindow
                draggedSegment = clickedSegment
                mouseDownSegmentHandler?(clickedSegment)
            }
            
            // If dragging is enabled, we MUST wait for mouseUp to distinguish between a click and a drag.
            // Sending the action here would trigger a collapse in collapsible selectors, killing the drag.
            if !enableDragReorder {
                selectedSegment = clickedSegment
                sendAction(action, to: target)
            }
        }
    }
    
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
        
        if isDragging {
            let location = convert(event.locationInWindow, from: nil)
            let hoveredSegment = segmentIndex(at: location)
            
            if hoveredSegment != -1 {
                dragChangedHandler?(hoveredSegment)
            }
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        let wasDragging = isDragging
        initialMouseLocation = nil
        isDragging = false
        
        if wasDragging {
            draggedSegment = nil
            dragEndedHandler?()
        } else if let segment = draggedSegment {
            // It was a click, not a drag. Send action now.
            selectedSegment = segment
            sendAction(action, to: target)
        }
        
        draggedSegment = nil
    }
    
    // MARK: - Tooltip Logic
    
    private func handleHover(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let segment = segmentIndex(at: location)
        
        if segment != -1 {
            let isLoading = selectorDelegate?.isLoading(index: segment) ?? false
            
            if segment != lastHoveredSegment {
                lastHoveredSegment = segment
                if let toolTip = segmentToolTips[segment], alwaysShowTooltips || isTextTruncated(segment: segment) {
                    let controlRect = bounds
                    let rectInWindow = convert(controlRect, to: nil)
                    QuickTooltip.shared.show(toolTip, for: self, segment: segment, margin: 4, forcedWidth: controlRect.width, forcedX: rectInWindow.minX, isLoading: isLoading)
                } else {
                    QuickTooltip.shared.hide()
                }
            } else {
                if let toolTip = segmentToolTips[segment], alwaysShowTooltips || isTextTruncated(segment: segment) {
                    QuickTooltip.shared.updateIfVisible(with: toolTip, for: (self, segment), isLoading: isLoading)
                } else {
                    QuickTooltip.shared.hide()
                }
            }
        } else {
            lastHoveredSegment = nil
            QuickTooltip.shared.hide()
        }
    }
    
    private func isTextTruncated(segment: Int) -> Bool {
        guard let label = self.label(forSegment: segment) else { return false }
        let segmentWidth = width(forSegment: segment)
        guard segmentWidth > 0 else { return false }
        
        let font = self.font ?? NSFont.systemFont(ofSize: 13)
        let labelWidth = (label as NSString).size(withAttributes: [.font: font]).width
        
        return labelWidth > (segmentWidth - 8)
    }
    
    private func segmentIndex(at point: NSPoint) -> Int {
        for i in 0..<segmentCount {
            if rect(forSegment: i).contains(point) {
                return i
            }
        }
        return -1
    }
    
    private func rect(forSegment segment: Int) -> NSRect {
        guard segment >= 0 && segment < segmentCount else { return .zero }
        
        // Use actually captured frames if available (accurate for variable widths)
        if let captured = (cell as? SegmentedCell)?.capturedFrames[segment] {
            return captured
        }
        
        // Fallback: Use programmed width if set, otherwise equal distribution
        var xOffset: CGFloat = 0
        for i in 0..<segment {
            let w = width(forSegment: i)
            xOffset += (w > 0 ? w : bounds.width / CGFloat(segmentCount))
        }
        let w = width(forSegment: segment)
        let segW = w > 0 ? w : bounds.width / CGFloat(segmentCount)
        return NSRect(x: xOffset, y: 0, width: segW, height: bounds.height)
    }
}


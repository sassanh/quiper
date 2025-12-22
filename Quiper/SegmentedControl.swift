import AppKit

// MARK: - Accented Segmented Cell

class AccentedSegmentedCell: NSSegmentedCell {
    override func drawSegment(_ segment: Int, inFrame frame: NSRect, with view: NSView) {
        // Only apply custom accent drawing if the control has forceHighlight enabled
        guard let control = view as? SegmentedControl, control.forceHighlight else {
            super.drawSegment(segment, inFrame: frame, with: view)
            return
        }
        
        if isSelected(forSegment: segment) {
            NSColor.controlAccentColor.setFill()
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

// MARK: - Segmented Control

/// A segmented control that supports custom tooltips, click handling for non-activating panels, and optional drag-reordering.
class SegmentedControl: NSSegmentedControl {
    override class var cellClass: AnyClass? {
        get { AccentedSegmentedCell.self }
        set { }
    }
    
    weak var selectorDelegate: CollapsibleSelectorDelegate?
    
    // Tooltips
    private var segmentToolTips: [Int: String] = [:]
    private(set) var lastHoveredSegment: Int?
    var alwaysShowTooltips: Bool = true

    var forceHighlight: Bool = false

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
            if enableDragReorder {
                initialMouseLocation = event.locationInWindow
                draggedSegment = clickedSegment
                mouseDownSegmentHandler?(clickedSegment)
            }
            
            if !isDragging {
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
        initialMouseLocation = nil
        
        if isDragging {
            isDragging = false
            draggedSegment = nil
            dragEndedHandler?()
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
        let count = segmentCount
        guard count > 0 else { return .zero }
        
        let w = bounds.width / CGFloat(count)
        return NSRect(x: CGFloat(segment) * w, y: 0, width: w, height: bounds.height)
    }
}

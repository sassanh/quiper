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
        super.draw(dirtyRect)

        guard showInstantiationState else { return }

        let selectedColor = NSColor.controlAccentColor
        let color = parentSelector == nil ? NSColor.windowBackgroundColor.withAlphaComponent(0.6) : NSColor.black.withAlphaComponent(0.5)
        // .rounded has a single outer pill; .automatic/.separated render each segment as its own pill.
        let isOuterPill = segmentStyle == .rounded || segmentStyle == .automatic

        NSGraphicsContext.saveGraphicsState()
        if isOuterPill {
            NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).setClip()
        }

        for i in 0..<segmentCount {
            let isSelected = (i == selectedSegment)
            if let sel = parentSelector {
                guard selectorDelegate?.selector(sel, isInstantiated: i) == false || isSelected else {
                    continue
                }
            } else {
                guard selectorDelegate?.segmentedControl(self, isInstantiated: i) == false else {
                    continue
                }
            }

            // Use x/width from captured frame for exact AppKit positioning;
            // always use full bounds height so the overlay matches the visual control height.
            let captured = (cell as? SegmentedCell)?.capturedFrames[i]
            let segX = captured?.minX ?? (bounds.width / CGFloat(segmentCount) * CGFloat(i))
            let segW = captured?.width ?? (bounds.width / CGFloat(segmentCount))
            let segFrame = self.backingAlignedRect(NSRect(x: segX, y: bounds.minY, width: segW, height: bounds.height), options: .alignAllEdgesNearest)

            if (isSelected) {
                selectedColor.setFill()
            } else {
                color.setFill()
            }
            segFrame.fill(using: .sourceOver)

            // Draw lighter text over the gray overlay for better contrast.
            if let label = self.label(forSegment: i), !label.isEmpty {
                let font = self.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize(for: controlSize))
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: isSelected ? NSColor.white : NSColor.black.withAlphaComponent(0.1)
                ]
                let size = (label as NSString).size(withAttributes: attrs)
                let textRect = NSRect(
                    x: segFrame.midX - size.width / 2,
                    y: segFrame.midY - size.height / 2,
                    width: size.width,
                    height: size.height
                )
                (label as NSString).draw(in: textRect, withAttributes: attrs)
            }
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


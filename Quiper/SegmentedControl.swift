import AppKit

// MARK: - Segmented Control

/// A segmented control that supports custom tooltips, click handling for non-activating panels, and optional drag-reordering.
class SegmentedControl: NSSegmentedControl {
    override class var cellClass: AnyClass? {
        get { NSSegmentedCell.self }
        set { }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        if self.cell == nil {
            self.cell = NSSegmentedCell()
        }
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        if self.cell == nil {
            self.cell = NSSegmentedCell()
        }
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
    
    // Tooltips and properties
    var customLabels: [String] = [] {
        didSet {
            updateAllSegmentWidths()
            needsDisplay = true
        }
    }
    var customLockedStates: [Bool]? = nil {
        didSet {
            updateAllSegmentWidths()
            needsDisplay = true
        }
    }
    var customInstantiatedStates: [Bool]? = nil {
        didSet {
            updateAllSegmentWidths()
            needsDisplay = true
        }
    }
    override var segmentCount: Int {
        didSet {
            updateAllSegmentWidths()
        }
    }
    
    private var segmentToolTips: [Int: String] = [:]
    private(set) var lastHoveredSegment: Int?
    var alwaysShowTooltips: Bool = true

    var forceHighlight: Bool = false

    // MARK: - Width Helpers

    override func setLabel(_ label: String, forSegment segment: Int) {
        super.setLabel(label, forSegment: segment)
        updateWidth(for: segment)
    }

    private func updateAllSegmentWidths() {
        guard segmentCount > 0 else { return }
        let font = self.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize(for: self.controlSize))
        for i in 0..<segmentCount {
            let label = customLabels.indices.contains(i) ? customLabels[i] : (self.label(forSegment: i) ?? "")
            let textWidth = (label as NSString).size(withAttributes: [.font: font]).width
            var w = textWidth + 16 // standard labelPadding
            
            let isLocked: Bool
            if let customL = customLockedStates, customL.indices.contains(i) {
                isLocked = customL[i]
            } else if let sel = parentSelector {
                isLocked = selectorDelegate?.selector(sel, isLocked: i) == true
            } else {
                isLocked = selectorDelegate?.segmentedControl(self, isLocked: i) == true
            }
            
            if isLocked {
                w += 13
            }
            super.setWidth(w, forSegment: i)
        }
    }
    
    private func updateWidth(for segment: Int) {
        guard segment >= 0 && segment < segmentCount else { return }
        let font = self.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize(for: self.controlSize))
        let label = customLabels.indices.contains(segment) ? customLabels[segment] : (self.label(forSegment: segment) ?? "")
        let textWidth = (label as NSString).size(withAttributes: [.font: font]).width
        var w = textWidth + 16
        
        let isLocked: Bool
        if let customL = customLockedStates, customL.indices.contains(segment) {
            isLocked = customL[segment]
        } else if let sel = parentSelector {
            isLocked = selectorDelegate?.selector(sel, isLocked: segment) == true
        } else {
            isLocked = selectorDelegate?.segmentedControl(self, isLocked: segment) == true
        }
        
        if isLocked {
            w += 13
        }
        super.setWidth(w, forSegment: segment)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        let isOuterPill = segmentStyle == .rounded || segmentStyle == .automatic || segmentStyle == .capsule

        // Determine instantiation state per segment up front
        var instantiated = [Bool](repeating: true, count: segmentCount)
        var locked = [Bool](repeating: false, count: segmentCount)
        for i in 0..<segmentCount {
            if let customL = customLockedStates, customL.indices.contains(i) {
                locked[i] = customL[i]
            } else if let sel = parentSelector {
                locked[i] = selectorDelegate?.selector(sel, isLocked: i) == true
            } else {
                locked[i] = selectorDelegate?.segmentedControl(self, isLocked: i) == true
            }
            
            if let customI = customInstantiatedStates, customI.indices.contains(i) {
                instantiated[i] = customI[i]
            } else if let sel = parentSelector {
                instantiated[i] = selectorDelegate?.selector(sel, isInstantiated: i) == true
            } else {
                instantiated[i] = selectorDelegate?.segmentedControl(self, isInstantiated: i) == true
            }
        }

        // Temporarily clear labels so super.draw doesn't draw native text (ghosting)
        // We MUST do this because we draw our own text to support lock icons and custom colors.
        let actualLabels = (0..<segmentCount).map { label(forSegment: $0) ?? "" }
        for i in 0..<segmentCount {
            super.setLabel("", forSegment: i)
        }

        NSGraphicsContext.saveGraphicsState()
        if isOuterPill {
            NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).setClip()
        }

        super.draw(dirtyRect)

        let uninstantiatedFontColor = NSColor.textColor.withAlphaComponent(0.5)
        let instantiatedFontColor = NSColor.textColor
        let uninstantiatedBackgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.5)
        let instantiatedBackgroundColor = NSColor.underPageBackgroundColor.withAlphaComponent(0.3)
        
        let segFont = font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize(for: controlSize))
        for i in 0..<segmentCount {
            let isSelected = (i == selectedSegment)
            
            // Read from customLabels if available, otherwise fallback to the real native label
            let originalLabel = customLabels.indices.contains(i) ? customLabels[i] : actualLabels[i]
            guard !originalLabel.isEmpty else { continue }

            let rawFrame = rect(forSegment: i)
            let segFrame = backingAlignedRect(rawFrame, options: .alignAllEdgesNearest)

            NSGraphicsContext.saveGraphicsState()
            if isSelected {
                NSColor.controlAccentColor.setFill()
                segFrame.fill(using: .sourceOver)
            } else if showInstantiationState {
                if instantiated[i] {
                    instantiatedBackgroundColor.setFill()
                } else {
                    uninstantiatedBackgroundColor.setFill()
                }
                segFrame.insetBy(dx: 0, dy: 1).fill(using: .sourceOver)
            }
            NSGraphicsContext.restoreGraphicsState()

            var fontColor: NSColor
            let isLockedSegment = locked[i]
            
            if isSelected {
                fontColor = .white
            } else if isLockedSegment {
                fontColor = uninstantiatedFontColor.withAlphaComponent(0.4) // requested low contrast
            } else if showInstantiationState && !instantiated[i] {
                fontColor = uninstantiatedFontColor
            } else {
                fontColor = instantiatedFontColor
            }

            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineBreakMode = .byTruncatingTail
            
            let attrs: [NSAttributedString.Key: Any] = [
                .font: segFont,
                .foregroundColor: fontColor,
                .paragraphStyle: paragraphStyle
            ]
            let size = (originalLabel as NSString).size(withAttributes: attrs)
            
            var lockImg: NSImage?
            var lockWidth: CGFloat = 0
            if isLockedSegment {
                let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
                if let img = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config)?.copy() as? NSImage {
                    img.isTemplate = true
                    lockImg = img
                    lockWidth = img.size.width
                }
            }
            
            let lockSpacing: CGFloat = 4
            let totalWidth = isLockedSegment ? (size.width + lockSpacing + lockWidth) : size.width
            
            let availableWidth = segFrame.width - 8
            var actualTotalWidth = totalWidth
            var textDrawWidth = size.width
            
            if actualTotalWidth > availableWidth {
                actualTotalWidth = availableWidth
                textDrawWidth = actualTotalWidth - (isLockedSegment ? (lockSpacing + lockWidth) : 0)
                if textDrawWidth < 0 { textDrawWidth = 0 }
            }
            
            let startX = segFrame.midX - actualTotalWidth / 2
            
            let textRect = NSRect(
                x: startX,
                y: segFrame.midY - size.height / 2,
                width: textDrawWidth,
                height: size.height
            )

            (originalLabel as NSString).draw(in: textRect, withAttributes: attrs)
            
            if isLockedSegment, let finalLockImg = lockImg {
                var lockColor = fontColor
                if let rgbColor = fontColor.usingColorSpace(.sRGB) {
                    var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
                    rgbColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
                    lockColor = NSColor(hue: hue, saturation: saturation, brightness: 1.0 - brightness, alpha: alpha)
                }
                
                finalLockImg.lockFocus()
                lockColor.set()
                NSRect(origin: .zero, size: finalLockImg.size).fill(using: .sourceAtop)
                finalLockImg.unlockFocus()
                
                let imgRect = NSRect(
                    x: textRect.maxX + lockSpacing,
                    y: segFrame.midY - finalLockImg.size.height / 2,
                    width: finalLockImg.size.width,
                    height: finalLockImg.size.height
                )
                finalLockImg.draw(in: imgRect, from: .zero, operation: .sourceOver, fraction: 1.0, respectFlipped: true, hints: nil)
            }
        }

        NSGraphicsContext.restoreGraphicsState()

        // Restore native labels so accessibility and UI tests see them
        for i in 0..<segmentCount {
            super.setLabel(actualLabels[i], forSegment: i)
        }
    }

    var enableDragReorder: Bool = false
    var mouseDownSegmentHandler: ((Int) -> Void)?
    var middleClickHandler: ((Int) -> Void)?
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
    
    override func otherMouseDown(with event: NSEvent) {
        guard event.buttonNumber == 2 else {
            super.otherMouseDown(with: event)
            return
        }
        let location = convert(event.locationInWindow, from: nil)
        let clickedSegment = segmentIndex(at: location)
        if clickedSegment >= 0 {
            middleClickHandler?(clickedSegment)
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
    
    func rect(forSegment segment: Int) -> NSRect {
        guard segment >= 0 && segment < segmentCount else { return .zero }
        
        if let cell = cell as? NSSegmentedCell {
            let selector = Selector(("rectForSegment:inFrame:"))
            if cell.responds(to: selector),
               let imp = cell.method(for: selector) {
                typealias RectForSegment = @convention(c) (AnyObject, Selector, Int, NSRect) -> NSRect
                let fn = unsafeBitCast(imp, to: RectForSegment.self)
                return fn(cell, selector, segment, bounds)
            }
        }
        
        // Fallback: Use programmed width if set, otherwise equal distribution
        let count = segmentCount
        var totalWidth: CGFloat = 0
        for i in 0..<count {
            totalWidth += width(forSegment: i)
        }
        
        let availableWidth = bounds.width
        let padding = count > 0 ? (availableWidth - totalWidth) / CGFloat(count) : 0
        
        var currentX: CGFloat = 0
        for i in 0..<segment {
            currentX += width(forSegment: i) + padding
        }
        
        let segW = width(forSegment: segment) + padding
        return NSRect(x: currentX, y: 0, width: segW, height: bounds.height)
    }
}


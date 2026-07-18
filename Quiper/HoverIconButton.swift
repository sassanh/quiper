import AppKit

class HoverIconButton: NSButton {
    
    enum BorderMode {
        case single
        case leftSegment
        case rightSegment
    }
    
    var borderMode: BorderMode = .single {
        didSet { needsDisplay = true }
    }
    
    /// Main label text shown in the QuickTooltip.
    var tooltipText: String? {
        didSet {
            // Clear native tooltip to prevent the system tooltip from appearing
            super.toolTip = nil
        }
    }

    /// Preserve the standard NSView tooltip value for callers while QuickTooltip owns presentation.
    override var toolTip: String? {
        get { tooltipText }
        set { tooltipText = newValue }
    }

    /// Optional shortcut string displayed as a pill badge inside the QuickTooltip (e.g. "⌘Y").
    var tooltipShortcut: String?

    private var trackingArea: NSTrackingArea?
    private var isHovered = false { didSet { needsDisplay = true } }
    private var isPressed = false { didSet { needsDisplay = true } }
    
    var onLongPress: (() -> Void)? {
        didSet {
            if onLongPress != nil && pressGesture == nil {
                let gesture = NSPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
                gesture.minimumPressDuration = 0.35
                addGestureRecognizer(gesture)
                pressGesture = gesture
            }
        }
    }
    private var pressGesture: NSPressGestureRecognizer?
    
    override var acceptsFirstResponder: Bool { false }
    
    init(image: NSImage, target: AnyObject?, action: Selector?) {
        super.init(frame: .zero)
        self.image = image
        self.target = target
        self.action = action
        self.bezelStyle = .regularSquare
        self.isBordered = false
        self.setButtonType(.momentaryPushIn)
        self.imagePosition = .imageOnly
        self.contentTintColor = .secondaryLabelColor
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = trackingArea { removeTrackingArea(trackingArea) }
        let newTrackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(newTrackingArea)
        self.trackingArea = newTrackingArea
    }
    
    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        contentTintColor = .labelColor
        if let text = tooltipText {
            QuickTooltip.shared.show(text, shortcut: tooltipShortcut, for: self)
        }
    }
    
    override func mouseExited(with event: NSEvent) {
        isHovered = false
        contentTintColor = .secondaryLabelColor
        QuickTooltip.shared.hide(for: self)
    }
    
    override func mouseDown(with event: NSEvent) {
        isPressed = true
        super.mouseDown(with: event)
        isPressed = false
    }
    
    @objc private func handleLongPress(_ gesture: NSPressGestureRecognizer) {
        if gesture.state == .began {
            onLongPress?()
            isPressed = false
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        let grayColor = NSColor.tertiaryLabelColor
        
        let path: NSBezierPath
        let shouldStroke: Bool
        
        switch borderMode {
        case .single:
            path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
            shouldStroke = true
        case .leftSegment:
            let pathRect = NSRect(x: 0.5, y: 0.5, width: bounds.width - 0.5, height: bounds.height - 1.0)
            path = NSBezierPath.roundedRect(pathRect, topLeft: 6, topRight: 0, bottomLeft: 6, bottomRight: 0)
            shouldStroke = false
        case .rightSegment:
            let pathRect = NSRect(x: 0.0, y: 0.5, width: bounds.width - 0.5, height: bounds.height - 1.0)
            path = NSBezierPath.roundedRect(pathRect, topLeft: 0, topRight: 6, bottomLeft: 0, bottomRight: 6)
            shouldStroke = false
        }
        
        if isHovered || isPressed {
            grayColor.setFill()
            path.fill()
        }
        
        if shouldStroke {
            grayColor.setStroke()
            path.lineWidth = 1.0
            path.stroke()
        }
        
        super.draw(dirtyRect)
    }
}

extension NSBezierPath {
    static func roundedRect(_ rect: NSRect, topLeft: CGFloat, topRight: CGFloat, bottomLeft: CGFloat, bottomRight: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        let minX = rect.minX
        let maxX = rect.maxX
        let minY = rect.minY
        let maxY = rect.maxY
        
        path.move(to: NSPoint(x: minX + topLeft, y: maxY))
        
        // Top line and top-right corner
        path.line(to: NSPoint(x: maxX - topRight, y: maxY))
        if topRight > 0 {
            path.appendArc(withCenter: NSPoint(x: maxX - topRight, y: maxY - topRight), radius: topRight, startAngle: 90, endAngle: 0, clockwise: true)
        }
        
        // Right line and bottom-right corner
        path.line(to: NSPoint(x: maxX, y: minY + bottomRight))
        if bottomRight > 0 {
            path.appendArc(withCenter: NSPoint(x: maxX - bottomRight, y: minY + bottomRight), radius: bottomRight, startAngle: 0, endAngle: 270, clockwise: true)
        }
        
        // Bottom line and bottom-left corner
        path.line(to: NSPoint(x: minX + bottomLeft, y: minY))
        if bottomLeft > 0 {
            path.appendArc(withCenter: NSPoint(x: minX + bottomLeft, y: minY + bottomLeft), radius: bottomLeft, startAngle: 270, endAngle: 180, clockwise: true)
        }
        
        // Left line and top-left corner
        path.line(to: NSPoint(x: minX, y: maxY - topLeft))
        if topLeft > 0 {
            path.appendArc(withCenter: NSPoint(x: minX + topLeft, y: maxY - topLeft), radius: topLeft, startAngle: 180, endAngle: 90, clockwise: true)
        }
        
        path.close()
        return path
    }
}

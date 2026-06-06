import AppKit

@MainActor
final class GhostOnboardingHUDView: NSView {
    
    private let backdropView: NSView
    private let cardView: NSVisualEffectView
    private let stepLabel: NSTextField
    private let titleLabel: NSTextField
    private let bodyLabel: NSTextField
    private let nextButton: HoverButton
    
    private weak var targetView: NSView?
    private var currentStep: Int = 1
    
    var onNextHandler: (() -> Void)?
    
    init() {
        // Backdrop (blocking clicks but translucent)
        backdropView = NSView()
        backdropView.wantsLayer = true
        backdropView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.45).cgColor
        
        // Card (Glassmorphic)
        cardView = NSVisualEffectView()
        cardView.material = .hudWindow
        cardView.state = .active
        cardView.wantsLayer = true
        cardView.layer?.cornerRadius = 12
        cardView.layer?.borderColor = NSColor(white: 1.0, alpha: 0.15).cgColor
        cardView.layer?.borderWidth = 1.0
        cardView.layer?.shadowColor = NSColor.black.cgColor
        cardView.layer?.shadowOpacity = 0.3
        cardView.layer?.shadowOffset = CGSize(width: 0, height: -4)
        cardView.layer?.shadowRadius = 8
        
        stepLabel = NSTextField(labelWithString: "")
        stepLabel.font = .systemFont(ofSize: 12, weight: .bold)
        stepLabel.textColor = .secondaryLabelColor
        stepLabel.isEditable = false
        stepLabel.isSelectable = false
        stepLabel.isBezeled = false
        stepLabel.drawsBackground = false
        
        titleLabel = NSTextField(labelWithString: "")
        titleLabel.font = .systemFont(ofSize: 15, weight: .bold)
        titleLabel.textColor = .labelColor
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        titleLabel.isBezeled = false
        titleLabel.drawsBackground = false
        
        bodyLabel = NSTextField(labelWithString: "")
        bodyLabel.font = .systemFont(ofSize: 15)
        bodyLabel.textColor = .labelColor
        bodyLabel.isEditable = false
        bodyLabel.isSelectable = false
        bodyLabel.isBezeled = false
        bodyLabel.drawsBackground = false
        bodyLabel.cell?.lineBreakMode = .byWordWrapping
        bodyLabel.cell?.wraps = true
        
        nextButton = HoverButton(frame: .zero)
        nextButton.title = "Next"
        
        super.init(frame: .zero)
        
        addSubview(backdropView)
        addSubview(cardView)
        
        cardView.addSubview(stepLabel)
        cardView.addSubview(titleLabel)
        cardView.addSubview(bodyLabel)
        cardView.addSubview(nextButton)
        
        nextButton.target = self
        nextButton.action = #selector(nextButtonClicked)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func nextButtonClicked() {
        onNextHandler?()
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
    
    // Swallow mouse hover/movement events
    override func mouseMoved(with event: NSEvent) {}
    override func mouseEntered(with event: NSEvent) {}
    override func mouseExited(with event: NSEvent) {}
    
    // Swallow all mouse clicks, drag, and scroll events to prevent background interaction
    override func mouseDown(with event: NSEvent) { handleMouseEvent(event) }
    override func mouseUp(with event: NSEvent) { handleMouseEvent(event) }
    override func mouseDragged(with event: NSEvent) { handleMouseEvent(event) }
    override func rightMouseDown(with event: NSEvent) { handleMouseEvent(event) }
    override func rightMouseUp(with event: NSEvent) { handleMouseEvent(event) }
    override func rightMouseDragged(with event: NSEvent) { handleMouseEvent(event) }
    override func otherMouseDown(with event: NSEvent) { handleMouseEvent(event) }
    override func otherMouseUp(with event: NSEvent) { handleMouseEvent(event) }
    override func otherMouseDragged(with event: NSEvent) { handleMouseEvent(event) }
    override func scrollWheel(with event: NSEvent) {}
    
    private func handleMouseEvent(_ event: NSEvent) {
        // Fully swallow event, no pass-through
    }
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        // If it's inside the cardView or nextButton, standard hit test
        let localCardPoint = cardView.convert(point, from: self)
        if cardView.bounds.contains(localCardPoint) {
            return super.hitTest(point)
        }
        
        // Return self to swallow all other clicks (modal behavior)
        return self
    }
    
    func update(step: Int, title: String, text: String, target: NSView?) {
        self.currentStep = step
        self.targetView = target
        
        stepLabel.stringValue = "STEP \(step) OF 3"
        titleLabel.stringValue = title
        bodyLabel.attributedStringValue = parseMarkdownToAttributed(text)
        
        if step == 3 {
            nextButton.title = "Finish"
        } else {
            nextButton.title = "Next"
        }
        
        needsLayout = true
    }
    
    private func parseMarkdownToAttributed(_ text: String) -> NSAttributedString {
        let systemFont = NSFont.systemFont(ofSize: 15)
        let attrString = NSMutableAttributedString()
        
        let parts = text.components(separatedBy: "`")
        for (index, part) in parts.enumerated() {
            if index % 2 == 0 {
                if !part.isEmpty {
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: systemFont,
                        .foregroundColor: NSColor.labelColor
                    ]
                    attrString.append(NSAttributedString(string: part, attributes: attrs))
                }
            } else {
                if !part.isEmpty {
                    let keycapImage = createKeycapImage(text: part)
                    let attachment = NSTextAttachment()
                    attachment.image = keycapImage
                    
                    // Shift down slightly to align keycap height with text line
                    let yOffset: CGFloat = -4.0
                    attachment.bounds = NSRect(x: 0, y: yOffset, width: keycapImage.size.width, height: keycapImage.size.height)
                    
                    attrString.append(NSAttributedString(attachment: attachment))
                }
            }
        }
        return attrString
    }
    
    private func createKeycapImage(text: String) -> NSImage {
        let font = NSFont.systemFont(ofSize: 12, weight: .bold)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle
        ]
        
        let string = NSAttributedString(string: text, attributes: attributes)
        let textSize = string.size()
        
        let horizontalPadding: CGFloat = 6
        let verticalPadding: CGFloat = 3
        
        let width = max(textSize.width + horizontalPadding * 2, 20)
        let height = textSize.height + verticalPadding * 2
        
        let size = NSSize(width: width, height: height)
        
        return NSImage(size: size, flipped: false) { rect in
            // Draw keycap body background
            let roundedRect = rect.insetBy(dx: 0.5, dy: 0.5)
            
            // Keycap background color
            NSColor.textColor.withAlphaComponent(0.14).setFill()
            let path = NSBezierPath(roundedRect: roundedRect, xRadius: 4, yRadius: 4)
            path.fill()
            
            // Keycap border
            NSColor.textColor.withAlphaComponent(0.18).setStroke()
            path.lineWidth = 1.0
            path.stroke()
            
            // Draw text centered
            let textRect = NSRect(
                x: (size.width - textSize.width) / 2,
                y: (size.height - textSize.height) / 2 - 0.5,
                width: textSize.width,
                height: textSize.height
            )
            string.draw(in: textRect)
            
            return true
        }
    }
    
    override func layout() {
        super.layout()
        
        backdropView.frame = bounds
        
        // Size the card
        let cardWidth: CGFloat = 360
        let padding: CGFloat = 16
        
        // Measure body label
        let maxLabelWidth = cardWidth - (padding * 2)
        bodyLabel.preferredMaxLayoutWidth = maxLabelWidth
        let bodySize = bodyLabel.cell!.cellSize(forBounds: NSRect(x: 0, y: 0, width: maxLabelWidth, height: .greatestFiniteMagnitude))
        
        let buttonHeight: CGFloat = 28
        let buttonWidth: CGFloat = 80
        
        let cardHeight = padding + 16 + 8 + 20 + 8 + bodySize.height + 16 + buttonHeight + padding
        
        // Position cardView relative to targetView
        var cardX = (bounds.width - cardWidth) / 2
        var cardY = (bounds.height - cardHeight) / 2
        
        let isBottom = Settings.shared.dragAreaPosition == .bottom
        var useCenterPosition = true
        
        if let target = targetView, !target.isHidden, target.bounds.width > 0, target.bounds.height > 0 {
            useCenterPosition = false
            let targetRect = target.convert(target.bounds, to: self)
            
            // Center horizontally relative to target
            cardX = targetRect.midX - (cardWidth / 2)
            // Clamp cardX within window bounds with margin
            cardX = max(16, min(bounds.width - cardWidth - 16, cardX))
            
            if isBottom {
                // Position above the target
                cardY = targetRect.maxY + 12
            } else {
                // Position below the target
                cardY = targetRect.minY - cardHeight - 12
            }
        }
        
        if useCenterPosition {
            cardX = (bounds.width - cardWidth) / 2
            cardY = (bounds.height - cardHeight) / 2
        }
        
        cardView.frame = NSRect(x: cardX, y: cardY, width: cardWidth, height: cardHeight)
        
        // Update spotlight cutout mask
        updateBackdropMask()
        
        // Layout card subviews
        var currentY = cardHeight - padding
        
        // Step label
        let stepSize = stepLabel.intrinsicContentSize
        currentY -= stepSize.height
        stepLabel.frame = NSRect(x: padding, y: currentY, width: maxLabelWidth, height: stepSize.height)
        
        // Title
        currentY -= 6
        let titleSize = titleLabel.intrinsicContentSize
        currentY -= titleSize.height
        titleLabel.frame = NSRect(x: padding, y: currentY, width: maxLabelWidth, height: titleSize.height)
        
        // Body description
        currentY -= 10
        currentY -= bodySize.height
        bodyLabel.frame = NSRect(x: padding, y: currentY, width: maxLabelWidth, height: bodySize.height)
        
        // Next button (bottom right)
        nextButton.frame = NSRect(
            x: cardWidth - padding - buttonWidth,
            y: padding,
            width: buttonWidth,
            height: buttonHeight
        )
    }
    
    private func updateBackdropMask() {
        guard let target = targetView, !target.isHidden, target.bounds.width > 0, target.bounds.height > 0 else {
            backdropView.layer?.mask = nil
            return
        }
        
        let maskLayer = CAShapeLayer()
        let path = CGMutablePath()
        
        // Full bounds
        path.addRect(bounds)
        
        // Cutout rect
        let targetRect = target.convert(target.bounds, to: self)
        let roundedPath = CGPath(roundedRect: targetRect.insetBy(dx: -4, dy: -4), cornerWidth: 6, cornerHeight: 6, transform: nil)
        path.addPath(roundedPath)
        
        maskLayer.path = path
        maskLayer.fillRule = .evenOdd
        backdropView.layer?.mask = maskLayer
    }
    
    override var acceptsFirstResponder: Bool { true }
    
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 49 { // Return = 36, Space = 49
            onNextHandler?()
            return
        }
        // Swallow everything else
    }
    
    override func keyUp(with event: NSEvent) {
        // Swallow
    }
    
    override func flagsChanged(with event: NSEvent) {
        // Swallow
    }
}

// MARK: - HoverButton

@MainActor
final class HoverButton: NSButton {
    private var trackingArea: NSTrackingArea?
    private var isHovered = false { didSet { needsDisplay = true } }
    private var isPressed = false { didSet { needsDisplay = true } }
    
    override var acceptsFirstResponder: Bool { false }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.bezelStyle = .regularSquare
        self.isBordered = false
        self.setButtonType(.momentaryPushIn)
        self.wantsLayer = true
        self.layer?.cornerRadius = 6
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
    }
    
    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }
    
    override func mouseDown(with event: NSEvent) {
        isPressed = true
        super.mouseDown(with: event)
        isPressed = false
    }
    
    override func draw(_ dirtyRect: NSRect) {
        let accent = NSColor.controlAccentColor
        let bg: NSColor
        if isPressed {
            bg = accent.withAlphaComponent(0.6)
        } else if isHovered {
            bg = accent.withAlphaComponent(0.85)
        } else {
            bg = accent.withAlphaComponent(0.7)
        }
        
        bg.setFill()
        let path = NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6)
        path.fill()
        
        // Draw centered title
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .bold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph
        ]
        
        let stringSize = title.size(withAttributes: attributes)
        let stringRect = NSRect(
            x: 0,
            y: (bounds.height - stringSize.height) / 2,
            width: bounds.width,
            height: stringSize.height
        )
        title.draw(in: stringRect, withAttributes: attributes)
    }
}

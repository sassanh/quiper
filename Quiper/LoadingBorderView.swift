import AppKit
import QuartzCore

/// A custom view that displays an animated gradient border around its bounds.
/// Used to indicate loading state when the title is visible but resources are still loading.
@MainActor
class LoadingBorderView: NSView {
    
    private var containerLayer: CALayer?
    
    private(set) var isAnimating = false
    
    var cornerRadius: CGFloat = 6 {
        didSet { if isAnimating { updateLayers() } }
    }
    
    var borderWidth: CGFloat = 2 {
        didSet { if isAnimating { updateLayers() } }
    }
    
    var lineColor: NSColor = .controlAccentColor {
        didSet { if isAnimating { updateLayers() } }
    }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        wantsLayer = true
        layer?.masksToBounds = false
        setAccessibilityIdentifier("LoadingIndicator")
    }
    
    override func layout() {
        super.layout()
        if isAnimating {
            updateLayers()
        }
    }
    
    private func updateLayers() {
        // Remove existing layers
        containerLayer?.removeFromSuperlayer()
        
        guard bounds.width > 0, bounds.height > 0 else { return }
        
        // Create the container for animation
        let container = CALayer()
        container.frame = bounds
        layer?.addSublayer(container)
        containerLayer = container
        
        // Create the border path (inset for stroke to be inside bounds)
        let inset = borderWidth / 2
        let borderRect = bounds.insetBy(dx: inset, dy: inset)
        let borderPath = CGPath(roundedRect: borderRect,
                                cornerWidth: cornerRadius,
                                cornerHeight: cornerRadius,
                                transform: nil)
        
        // Create a shape layer to draw the border
        let borderFull = CAShapeLayer()
        borderFull.path = borderPath
        borderFull.fillColor = nil
        borderFull.strokeColor = lineColor.withAlphaComponent(0.2).cgColor
        borderFull.lineWidth = borderWidth
        container.addSublayer(borderFull)
        
        // Create the animated "bright" segment using dash animation for perfect continuity
        let brightSegment = CAShapeLayer()
        brightSegment.path = borderPath
        brightSegment.fillColor = nil
        brightSegment.strokeColor = lineColor.cgColor
        brightSegment.lineWidth = borderWidth
        brightSegment.lineCap = .round
        
        // Calculate path length for perfect dash wrapping
        // Perimeter of rounded rect: 2(w-2r) + 2(h-2r) + 2*pi*r
        let w = borderRect.width
        let h = borderRect.height
        let r = cornerRadius
        let pathLength = 2 * (w - 2 * r) + 2 * (h - 2 * r) + 2 * .pi * r
        
        let segmentLength = pathLength * 0.15
        brightSegment.lineDashPattern = [segmentLength, pathLength - segmentLength] as [NSNumber]
        container.addSublayer(brightSegment)
        
        // Add animation to move the bright segment around the path using lineDashPhase
        let dashAnimation = CABasicAnimation(keyPath: "lineDashPhase")
        dashAnimation.fromValue = 0
        dashAnimation.toValue = -pathLength // Negative to move clockwise
        dashAnimation.duration = 1.5
        dashAnimation.repeatCount = .infinity
        dashAnimation.timingFunction = CAMediaTimingFunction(name: .linear)
        
        brightSegment.add(dashAnimation, forKey: "lineDashPhaseAnimation")
    }
    
    func startAnimating() {
        guard !isAnimating else { return }
        isAnimating = true
        isHidden = false
        setAccessibilityElement(true)
        updateLayers()
    }
    
    func stopAnimating() {
        guard isAnimating else { return }
        isAnimating = false
        isHidden = true
        setAccessibilityElement(false)
        containerLayer?.removeFromSuperlayer()
        containerLayer = nil
    }
}

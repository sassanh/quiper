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
        
        // Create the animated "bright" segment using stroke animation
        let brightSegment = CAShapeLayer()
        brightSegment.path = borderPath
        brightSegment.fillColor = nil
        brightSegment.strokeColor = lineColor.cgColor
        brightSegment.lineWidth = borderWidth
        brightSegment.lineCap = .round
        brightSegment.strokeStart = 0
        brightSegment.strokeEnd = 0.15  // 15% of the path is "lit up"
        container.addSublayer(brightSegment)
        
        // Add animation to move the bright segment around the path
        let startAnimation = CABasicAnimation(keyPath: "strokeStart")
        startAnimation.fromValue = 0
        startAnimation.toValue = 1
        
        let endAnimation = CABasicAnimation(keyPath: "strokeEnd")
        endAnimation.fromValue = 0.15
        endAnimation.toValue = 1.15  // Goes past 1.0 and wraps
        
        let animationGroup = CAAnimationGroup()
        animationGroup.animations = [startAnimation, endAnimation]
        animationGroup.duration = 1.5
        animationGroup.repeatCount = .infinity
        animationGroup.timingFunction = CAMediaTimingFunction(name: .linear)
        
        brightSegment.add(animationGroup, forKey: "strokeAnimation")
    }
    
    func startAnimating() {
        guard !isAnimating else { return }
        isAnimating = true
        isHidden = false
        updateLayers()
    }
    
    func stopAnimating() {
        guard isAnimating else { return }
        isAnimating = false
        isHidden = true
        containerLayer?.removeFromSuperlayer()
        containerLayer = nil
    }
}

import AppKit
import QuartzCore

/// A view that renders a resilient, self-healing border around the window content.
/// In auto-hide mode, it "thickens" one edge to reveal the header/footer outside the content area.
@MainActor
class WindowFrameView: NSView {
    
    // MARK: - Properties
    
    var cornerRadius: CGFloat = Constants.WINDOW_CORNER_RADIUS
    /// How far the content (webview + bar) is inset from the window edge.
    /// Should match MainWindowController.barBorderWidth. Drives border fill width and corner radii.
    var contentInset: CGFloat = 7 {
        didSet { updatePath(animated: false) }
    }
    
    enum ThickEdge {
        case top
        case bottom
        case none
    }
    
    private(set) var currentThickEdge: ThickEdge = .none
    private(set) var isRevealed: Bool = false
    /// Tracks the bar edge independently of revealed state so the outline always knows which slot to exclude.
    private var barEdge: ThickEdge = .none
    
    /// Set this once at layout time so the outline is correct before the first reveal.
    func configureBarEdge(_ edge: ThickEdge) {
        guard barEdge != edge else { return }
        barEdge = edge
        updatePath(animated: false)
    }
    
    private let borderLayer = CAShapeLayer()
    private let outlineLayer = CAShapeLayer()
    /// Fills the margin ring with a near-zero alpha so the Window Server routes mouse events
    /// (including resize drags) to this window instead of the window behind it.
    /// Visually invisible at alpha 0.02 but sufficient to prevent transparency passthrough.
    private let hitTargetLayer = CAShapeLayer()
    
    // MARK: - Initialization
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLayers()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayers()
    }
    
    private func setupLayers() {
        wantsLayer = true
        layer?.masksToBounds = false

        // hitTargetLayer sits below everything — always on, purely for event routing.
        hitTargetLayer.fillRule = .evenOdd
        hitTargetLayer.strokeColor = nil
        hitTargetLayer.lineWidth = 0
        hitTargetLayer.fillColor = NSColor(white: 0.5, alpha: 0.01).cgColor
        hitTargetLayer.opacity = 1.0
        layer?.addSublayer(hitTargetLayer)

        borderLayer.fillColor = nil
        borderLayer.strokeColor = NSColor.windowFrameTextColor.withAlphaComponent(0.2).cgColor
        borderLayer.lineWidth = 0
        borderLayer.opacity = 0
        layer?.addSublayer(borderLayer)
        
        outlineLayer.fillColor = nil
        outlineLayer.lineWidth = 1.0
        outlineLayer.opacity = 1.0
        layer?.addSublayer(outlineLayer)
        
        updateColors()
    }
    
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }
    
    private func updateColors() {
        if effectiveAppearance.name.rawValue.contains("Dark") {
            borderLayer.fillColor = NSColor(calibratedWhite: 0.15, alpha: 0.95).cgColor
            borderLayer.strokeColor = NSColor(calibratedWhite: 0.4, alpha: 0.6).cgColor
            outlineLayer.strokeColor = NSColor(calibratedWhite: 1.0, alpha: 0.15).cgColor
        } else {
            borderLayer.fillColor = NSColor(calibratedWhite: 0.92, alpha: 0.97).cgColor
            borderLayer.strokeColor = NSColor(calibratedWhite: 0.65, alpha: 0.6).cgColor
            outlineLayer.strokeColor = NSColor(calibratedWhite: 0.0, alpha: 0.55).cgColor
        }
    }
    
    // MARK: - Layout
    
    override func layout() {
        super.layout()
        updatePath(animated: false)
    }
    
    /// The "content rect" is the area inside the border where the webview lives.
    /// This area is 1px inside the 5px border (so 4px of the border is outside).
    var contentRect: NSRect {
        var rect = bounds.insetBy(dx: contentInset, dy: contentInset)
        if isRevealed {
            let barHeight = CGFloat(Constants.DRAGGABLE_AREA_HEIGHT)
            if currentThickEdge == .top {
                rect.size.height -= barHeight
            } else if currentThickEdge == .bottom {
                rect.size.height -= barHeight
                rect.origin.y += barHeight
            }
        }
        return rect
    }
    
    // MARK: - Animation
    
    func setRevealed(_ revealed: Bool, edge: ThickEdge, animated: Bool = true) {
        guard isRevealed != revealed || currentThickEdge != edge else { return }
        
        isRevealed = revealed
        currentThickEdge = edge
        if edge != .none { barEdge = edge }
        
        // Path snaps immediately — no shape animation to avoid directional reveal artifacts.
        // Only opacity is animated.
        updatePath(animated: false)
        
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                borderLayer.opacity = revealed ? 1.0 : 0.0
                outlineLayer.opacity = revealed ? 0.0 : 1.0
            }
        } else {
            borderLayer.opacity = revealed ? 1.0 : 0.0
            outlineLayer.opacity = revealed ? 0.0 : 1.0
        }
    }
    
    private func updatePath(animated: Bool) {
        let path = CGMutablePath()
        
        let outerRect = bounds
        let innerRect = contentRect
        
        // Add outer rounded rect
        path.addPath(CGPath(roundedRect: outerRect, cornerWidth: cornerRadius + contentInset, cornerHeight: cornerRadius + contentInset, transform: nil))
        // Add inner rounded rect (the hole) — even-odd fill
        path.addPath(CGPath(roundedRect: innerRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil))
        
        // Outline traces the webview-only area (excludes the transparent bar slot).
        // Uses barEdge (set at last reveal) so it's correct even after the border hides.
        let barHeight = CGFloat(Constants.DRAGGABLE_AREA_HEIGHT)
        var outlineRect = bounds.insetBy(dx: contentInset - 1, dy: contentInset - 1)
        switch barEdge {
        case .top:
            outlineRect.size.height -= barHeight
        case .bottom:
            outlineRect.size.height -= barHeight
            outlineRect.origin.y += barHeight
        case .none:
            break
        }
        let outlinePath = CGPath(roundedRect: outlineRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        
        if animated {
            let outlineAnimation = CABasicAnimation(keyPath: "path")
            outlineAnimation.duration = 0.2
            outlineAnimation.fromValue = outlineLayer.path
            outlineAnimation.toValue = outlinePath
            outlineAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            outlineLayer.add(outlineAnimation, forKey: "pathAnimation")
        }
        
        borderLayer.path = path
        borderLayer.fillRule = .evenOdd
        outlineLayer.path = outlinePath
        hitTargetLayer.path = path
    }
}

import AppKit
import QuartzCore

/// A view that renders the thick margin ring around the window content and handles window dragging hits.
/// Placed in the main window hierarchy, positioned below the drag area to ensure the thick border
/// stays visually behind the top bar controls while still capturing resize events in the margin.
@MainActor
class WindowMarginView: NSView {
    
    // MARK: - Properties
    
    var cornerRadius: CGFloat = Constants.WINDOW_CORNER_RADIUS
    var contentInset: CGFloat = 0 {
        didSet { updatePath(animated: false) }
    }
    
    enum ThickEdge {
        case top
        case bottom
        case none
    }
    
    private(set) var currentThickEdge: ThickEdge = .none
    private(set) var isRevealed: Bool = false
    
    func configureBarEdge(_ edge: ThickEdge) {
        updatePath(animated: false)
    }
    
    private let borderLayer = CAShapeLayer()
    /// Fills the margin ring with a near-zero alpha so the Window Server routes mouse events
    /// (including resize drags) to this window.
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
        
        updateColors()
        
        NotificationCenter.default.addObserver(self, selector: #selector(appearanceSettingsChanged), name: .windowAppearanceChanged, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil // Let mouse events fall through to the window background for resize tracking
    }
    
    @objc private func appearanceSettingsChanged() {
        updateColors()
        updatePath(animated: false)
    }
    
    private func updateColors() {
        let isDark = effectiveAppearance.name.rawValue.contains("Dark")
        if isDark {
            borderLayer.fillColor = NSColor(calibratedWhite: 0.15, alpha: 0.95).cgColor
            borderLayer.strokeColor = NSColor(calibratedWhite: 0.4, alpha: 0.6).cgColor
        } else {
            borderLayer.fillColor = NSColor(calibratedWhite: 0.92, alpha: 0.97).cgColor
            borderLayer.strokeColor = NSColor(calibratedWhite: 0.65, alpha: 0.6).cgColor
        }
    }
    
    // MARK: - Layout
    
    override func layout() {
        super.layout()
        updatePath(animated: false)
    }
    
    /// The rect matching the window's actual web content + bar.
    var contentRect: NSRect {
        let isHiddenMode = Settings.shared.topBarVisibility == .hidden
        let margin = contentInset
        
        var rect = bounds.insetBy(dx: margin, dy: margin)
        
        // In hidden mode, when revealed, the bar slot is excluded from the inner hole
        // so the thick ring expands to cover the bar area as well as the margin.
        if isHiddenMode && isRevealed {
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
        
        updatePath(animated: false)
        
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                borderLayer.opacity = revealed ? 1.0 : 0.0
            }
        } else {
            borderLayer.opacity = revealed ? 1.0 : 0.0
        }
    }
    
    private func updatePath(animated: Bool) {
        let path = CGMutablePath()
        
        let outerRect = bounds
        let innerRect = contentRect
        
        let margin = contentInset
        
        path.addPath(CGPath(roundedRect: outerRect, cornerWidth: cornerRadius + margin, cornerHeight: cornerRadius + margin, transform: nil))
        path.addPath(CGPath(roundedRect: innerRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil))
        
        borderLayer.path = path
        borderLayer.fillRule = .evenOdd
        hitTargetLayer.path = path
    }
}

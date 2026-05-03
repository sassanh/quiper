import AppKit
import QuartzCore

/// A view that renders the thin outline border around the window content.
/// Placed in the main window hierarchy, positioned above all other views to ensure the outline
/// never gets clipped or hidden by web content or top bar controls.
@MainActor
class WindowOutlineView: NSView {
    
    // MARK: - Properties
    
    var cornerRadius: CGFloat = Constants.WINDOW_CORNER_RADIUS
    var contentInset: CGFloat = 0 {
        didSet { updatePath(animated: false) }
    }
    
    private var barEdge: WindowMarginView.ThickEdge = .none
    
    /// Set this once at layout time so the outline is correct before the first reveal.
    func configureBarEdge(_ edge: WindowMarginView.ThickEdge) {
        guard barEdge != edge else { return }
        barEdge = edge
        updatePath(animated: false)
    }
    
    private var outlineWidth: CGFloat = 1.0
    private let outlineLayer = CAShapeLayer()
    
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
        
        outlineLayer.fillColor = nil
        outlineLayer.lineWidth = 1.0
        outlineLayer.opacity = 1.0
        layer?.addSublayer(outlineLayer)
        
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
        return nil
    }
    
    @objc private func appearanceSettingsChanged() {
        updateColors()
        updatePath(animated: false)
    }
    
    private func updateColors() {
        let isDark = effectiveAppearance.name.rawValue.contains("Dark")
        let settings = isDark ? Settings.shared.windowAppearance.dark : Settings.shared.windowAppearance.light
        
        outlineWidth = settings.outlineWidth
        outlineLayer.lineWidth = outlineWidth
        outlineLayer.strokeColor = settings.outlineColor.nsColor.cgColor
    }
    
    // MARK: - Layout
    
    override func layout() {
        super.layout()
        updatePath(animated: false)
    }
    
    // MARK: - Animation
    
    func setRevealed(_ revealed: Bool, edge: WindowMarginView.ThickEdge, animated: Bool = true) {
        if edge != .none { barEdge = edge }
        
        // Outline layer stays visible but we update the path just in case
        updatePath(animated: false)
        
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                outlineLayer.opacity = revealed ? 0.0 : 1.0
            }
        } else {
            outlineLayer.opacity = revealed ? 0.0 : 1.0
        }
    }
    
    private func updatePath(animated: Bool) {
        let isHiddenMode = Settings.shared.topBarVisibility == .hidden
        let margin = contentInset
        let barHeight = CGFloat(Constants.DRAGGABLE_AREA_HEIGHT)
        
        // The border should stick to the edges of the visible area (the content)
        // and expand OUTWARDS into the transparent margin so it doesn't eat into the content area.
        // A stroke is centered on its path. To make it expand entirely outwards,
        // we offset the path by half the stroke width outwards from the content edge.
        let pathOffset = margin - outlineWidth / 2.0
        var outlineRect = bounds.insetBy(dx: pathOffset, dy: pathOffset)
        
        // In hidden mode, the bar slot must be excluded from the outline shape so it doesn't cross
        // over the transparent slot where the bar slides in.
        if isHiddenMode {
            switch barEdge {
            case .top:
                outlineRect.size.height -= barHeight
            case .bottom:
                outlineRect.size.height -= barHeight
                outlineRect.origin.y += barHeight
            case .none:
                break
            }
        }
        
        // Hide the outline completely if outlineWidth is 0
        if outlineWidth <= 0 {
            outlineRect = .zero
        }
        
        // The corner radius must be mathematically concentric with the content edge.
        // The path is `outlineWidth / 2` further out than the content edge.
        let outlineCornerRadius = cornerRadius + outlineWidth / 2.0
        let outlinePath = CGPath(roundedRect: outlineRect, cornerWidth: outlineCornerRadius, cornerHeight: outlineCornerRadius, transform: nil)
        
        if animated {
            let outlineAnimation = CABasicAnimation(keyPath: "path")
            outlineAnimation.duration = 0.2
            outlineAnimation.fromValue = outlineLayer.path
            outlineAnimation.toValue = outlinePath
            outlineAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            outlineLayer.add(outlineAnimation, forKey: "pathAnimation")
        }
        
        outlineLayer.path = outlinePath
    }
}

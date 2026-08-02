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
    private let loadingBaseLayer = CAShapeLayer()
    private let loadingSegmentLayer = CAShapeLayer()
    private let loadingLineWidth: CGFloat = 4.0
    private var isLoading = false
    private var isRevealed = false
    
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

        loadingBaseLayer.fillColor = nil
        loadingBaseLayer.lineWidth = loadingLineWidth
        loadingBaseLayer.opacity = 0.0
        layer?.addSublayer(loadingBaseLayer)

        loadingSegmentLayer.fillColor = nil
        loadingSegmentLayer.lineWidth = loadingLineWidth
        loadingSegmentLayer.lineCap = .round
        loadingSegmentLayer.opacity = 0.0
        layer?.addSublayer(loadingSegmentLayer)
        
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
        loadingBaseLayer.strokeColor = NSColor.controlAccentColor.withAlphaComponent(0.2).cgColor
        loadingSegmentLayer.strokeColor = NSColor.controlAccentColor.cgColor
    }
    
    // MARK: - Layout
    
    override func layout() {
        super.layout()
        updatePath(animated: false)
    }
    
    // MARK: - Animation
    
    func setRevealed(_ revealed: Bool, edge: WindowMarginView.ThickEdge, animated: Bool = true) {
        if edge != .none { barEdge = edge }
        isRevealed = revealed
        
        // Outline layer stays visible but we update the path just in case
        updatePath(animated: false)
        
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                updateLayerOpacity()
            }
        } else {
            updateLayerOpacity()
        }
    }

    func setLoading(_ loading: Bool) {
        guard isLoading != loading else { return }
        isLoading = loading
        updatePath(animated: false)

        if loading {
            addLoadingAnimation()
        } else {
            loadingSegmentLayer.removeAnimation(forKey: "lineDashPhaseAnimation")
        }

        updateLayerOpacity()
    }

    private func updatePath(animated: Bool) {
        let outlinePath = path(for: outlineWidth)
        let loadingPath = path(for: loadingLineWidth)
        loadingBaseLayer.path = loadingPath
        loadingSegmentLayer.path = loadingPath

        if animated {
            let outlineAnimation = CABasicAnimation(keyPath: "path")
            outlineAnimation.duration = 0.2
            outlineAnimation.fromValue = outlineLayer.path
            outlineAnimation.toValue = outlinePath
            outlineAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            outlineLayer.add(outlineAnimation, forKey: "pathAnimation")
        }

        outlineLayer.path = outlinePath

        let width = loadingPath.boundingBox.width
        let height = loadingPath.boundingBox.height
        let radius = cornerRadius + loadingLineWidth / 2.0
        let pathLength = 2 * (width - 2 * radius) + 2 * (height - 2 * radius) + 2 * .pi * radius
        let segmentLength = max(pathLength * 0.15, 1.0)
        loadingSegmentLayer.lineDashPattern = [segmentLength, max(pathLength - segmentLength, 1.0)] as [NSNumber]

        if isLoading {
            addLoadingAnimation()
        }
    }

    private func path(for lineWidth: CGFloat) -> CGPath {
        let isHiddenMode = Settings.shared.topBarVisibility == .hidden
        let margin = contentInset
        let barHeight = CGFloat(Constants.DRAGGABLE_AREA_HEIGHT)

        // The border should stick to the edges of the visible area (the content)
        // and expand OUTWARDS into the transparent margin so it doesn't eat into the content area.
        let pathOffset = margin - lineWidth / 2.0
        var outlineRect = bounds.insetBy(dx: pathOffset, dy: pathOffset)

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

        if lineWidth <= 0 {
            outlineRect = .zero
        }

        let outlineCornerRadius = cornerRadius + lineWidth / 2.0
        return CGPath(
            roundedRect: outlineRect,
            cornerWidth: outlineCornerRadius,
            cornerHeight: outlineCornerRadius,
            transform: nil
        )
    }

    private func addLoadingAnimation() {
        loadingSegmentLayer.removeAnimation(forKey: "lineDashPhaseAnimation")

        guard let lineDashPattern = loadingSegmentLayer.lineDashPattern else { return }
        let pathLength = lineDashPattern.reduce(0) { result, value in
            result + value.doubleValue
        }
        guard pathLength > 0 else { return }

        let dashAnimation = CABasicAnimation(keyPath: "lineDashPhase")
        dashAnimation.fromValue = 0
        dashAnimation.toValue = pathLength
        dashAnimation.duration = 1.5
        dashAnimation.repeatCount = .infinity
        dashAnimation.timingFunction = CAMediaTimingFunction(name: .linear)
        loadingSegmentLayer.add(dashAnimation, forKey: "lineDashPhaseAnimation")
    }

    private func updateLayerOpacity() {
        outlineLayer.opacity = isLoading ? 0.0 : (isRevealed ? 0.0 : 1.0)
        loadingBaseLayer.opacity = isLoading ? 1.0 : 0.0
        loadingSegmentLayer.opacity = isLoading ? 1.0 : 0.0
    }
}

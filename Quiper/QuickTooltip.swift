import AppKit
import QuartzCore

/// A high-performance, fast-appearing tooltip panel that replaces the slow system tooltips.
final class QuickTooltip: NSPanel {
    
    static let shared = QuickTooltip()
    
    private let label: NSTextField
    private let loadingBorderView: LoadingBorderView
    
    private var currentTarget: Any?
    private var currentMargin: CGFloat = 4
    private var currentForcedWidth: CGFloat?
    private var currentForcedX: CGFloat?
    private var hideTimer: Timer?
    
    private init() {
        label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 12)
        label.textColor = .labelColor
        label.alignment = .left
        label.lineBreakMode = .byWordWrapping // Enable wrapping
        label.isEditable = false
        label.isSelectable = false
        label.isBezeled = false
        label.drawsBackground = false
        
        loadingBorderView = LoadingBorderView(frame: .zero)
        loadingBorderView.isHidden = true
        
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        isOpaque = false
        backgroundColor = .clear
        level = .statusBar
        hasShadow = true
        ignoresMouseEvents = true
        alphaValue = 0
        
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .popover
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 6
        
        visualEffect.addSubview(loadingBorderView)
        visualEffect.addSubview(label)
        
        loadingBorderView.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            loadingBorderView.topAnchor.constraint(equalTo: visualEffect.topAnchor),
            loadingBorderView.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor),
            loadingBorderView.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            loadingBorderView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
            
            label.topAnchor.constraint(equalTo: visualEffect.topAnchor, constant: 6),
            label.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor, constant: -6),
            label.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor, constant: -8)
        ])
        
        contentView = visualEffect
    }
    
    /// Show tooltip immediately
    /// - Parameters:
    ///   - string: The text to show
    ///   - view: The target view to align with
    ///   - margin: Vertical margin from the view
    ///   - forcedWidth: Optional fixed width for the tooltip
    ///   - forcedX: Optional fixed window X coordinate for the tooltip
    ///   - isLoading: Whether to show the loading spinner
    func show(_ string: String, for view: NSView, margin: CGFloat = 4, forcedWidth: CGFloat? = nil, forcedX: CGFloat? = nil, isLoading: Bool = false) {
        // Cancel pending hide
        hideTimer?.invalidate()
        hideTimer = nil
        
        currentTarget = view
        currentMargin = margin
        currentForcedWidth = forcedWidth
        currentForcedX = forcedX
        
        performShow(string, for: view, margin: margin, forcedWidth: forcedWidth, forcedX: forcedX, isLoading: isLoading)
    }
    
    /// Show tooltip specifically for a segment of an NSSegmentedControl
    func show(_ string: String, for control: NSSegmentedControl, segment: Int, margin: CGFloat = 4, forcedWidth: CGFloat? = nil, forcedX: CGFloat? = nil, isLoading: Bool = false) {
        // Cancel pending hide
        hideTimer?.invalidate()
        hideTimer = nil
        
        currentTarget = (control, segment)
        currentMargin = margin
        currentForcedWidth = forcedWidth
        currentForcedX = forcedX
        
        guard let rect = rectForSegment(segment, in: control),
              let window = control.window else { return }
        
        let rectInWindow = control.convert(rect, to: nil)
        performShow(string, in: window, targetRect: rectInWindow, margin: margin, forcedWidth: forcedWidth, forcedX: forcedX, isLoading: isLoading)
    }
    
    /// Dynamic update if content changes while showing
    func updateIfVisible(with string: String, for target: Any, isLoading: Bool = false) {
        // Cancel pending hide if we are updating (means we still want it)
        hideTimer?.invalidate()
        hideTimer = nil
        
        // Simple check to see if we're showing for this target
        if let currentView = currentTarget as? NSView, let targetView = target as? NSView, currentView === targetView {
            performUpdate(string, isLoading: isLoading)
        } else if let (currentControl, currentSeg) = currentTarget as? (NSSegmentedControl, Int),
                  let (targetControl, targetSeg) = target as? (NSSegmentedControl, Int),
                  currentControl === targetControl, currentSeg == targetSeg {
            performUpdate(string, isLoading: isLoading)
        }
    }
    
    private func performUpdate(_ string: String, isLoading: Bool) {
        guard alphaValue > 0 else { return }
        label.stringValue = string
        
        if isLoading {
            loadingBorderView.startAnimating()
        } else {
            loadingBorderView.stopAnimating()
        }
        
        recalculatePosition()
    }
    
    private func performShow(_ string: String, for view: NSView, margin: CGFloat, forcedWidth: CGFloat?, forcedX: CGFloat?, isLoading: Bool) {
        guard let window = view.window else { return }
        let rectInWindow = view.convert(view.bounds, to: nil)
        performShow(string, in: window, targetRect: rectInWindow, margin: margin, forcedWidth: forcedWidth, forcedX: forcedX, isLoading: isLoading)
    }
    
    private func performShow(_ string: String, in window: NSWindow, targetRect: NSRect, margin: CGFloat, forcedWidth: CGFloat?, forcedX: CGFloat?, isLoading: Bool) {
        label.stringValue = string
        currentMargin = margin
        currentForcedWidth = forcedWidth
        currentForcedX = forcedX
        
        if isLoading {
            loadingBorderView.startAnimating()
        } else {
            loadingBorderView.stopAnimating()
        }
        
        recalculatePosition(in: window, targetRect: targetRect)
        
        if alphaValue < 1 {
            orderFront(nil)
            animator().alphaValue = 1
        }
    }
    
    private func recalculatePosition(in window: NSWindow? = nil, targetRect: NSRect? = nil) {
        let activeWindow: NSWindow
        let activeRect: NSRect
        
        if let window = window, let targetRect = targetRect {
            activeWindow = window
            activeRect = targetRect
        } else {
            // Figure out from currentTarget
            if let view = currentTarget as? NSView, let win = view.window {
                activeWindow = win
                activeRect = view.convert(view.bounds, to: nil)
            } else if let (control, segment) = currentTarget as? (NSSegmentedControl, Int),
                      let win = control.window,
                      let rect = rectForSegment(segment, in: control) {
                activeWindow = win
                activeRect = control.convert(rect, to: nil)
            } else {
                return
            }
        }
        
        let margin = currentMargin
        let forcedWidth = currentForcedWidth
        let forcedX = currentForcedX
        
        // Calculate size needed
        let width = forcedWidth ?? 300
        let padding: CGFloat = 16 // 8 per side
        let labelWidth = width - padding
        
        // Ensure multiline wrapping respects strict width
        label.preferredMaxLayoutWidth = labelWidth
        
        let labelSize = label.cell!.cellSize(forBounds: NSRect(x: 0, y: 0, width: labelWidth, height: .greatestFiniteMagnitude))
        let totalHeight = labelSize.height + 12 // 6 per side vertical
        let totalSize = NSSize(width: width, height: totalHeight)
        
        let windowFrame = activeWindow.frame
        let screenOrigin = windowFrame.origin
        
        let targetInScreen = NSRect(
            x: screenOrigin.x + activeRect.minX,
            y: screenOrigin.y + activeRect.minY,
            width: activeRect.width,
            height: activeRect.height
        )
        
        let xPos = forcedX != nil ? (screenOrigin.x + forcedX!) : targetInScreen.minX
        
        let tooltipFrame = NSRect(
            x: xPos,
            y: targetInScreen.minY - totalSize.height - margin,
            width: totalSize.width,
            height: totalSize.height
        )
        
        setFrame(tooltipFrame, display: true)
    }
    
    func hide(for target: Any) {
        var matches = false
        if let currentView = currentTarget as? NSView, let targetView = target as? NSView {
            matches = (currentView == targetView)
        } else if let (currentControl, currentSegment) = currentTarget as? (NSSegmentedControl, Int),
                  let (targetControl, targetSegment) = target as? (NSSegmentedControl, Int) {
            matches = (currentControl == targetControl && currentSegment == targetSegment)
        } else if let currentObj = currentTarget as? NSObject, let targetObj = target as? NSObject {
            matches = (currentObj == targetObj)
        }
        
        if matches {
            hide()
        }
    }
    
    func hide() {
        // Debounce hide to prevent flickering when moving between tooltipped elements
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.currentTarget = nil
            
            if self.alphaValue > 0 {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.1
                    self.animator().alphaValue = 0
                }, completionHandler: { [weak self] in
                    self?.orderOut(nil)
                })
            }
        }
    }
    
    private func rectForSegment(_ segment: Int, in control: NSSegmentedControl) -> NSRect? {
        guard segment >= 0 && segment < control.segmentCount else { return nil }
        
        let bounds = control.bounds
        if let segmentedCell = control.cell as? NSSegmentedCell {
            let selector = Selector(("rectForSegment:inFrame:"))
            if segmentedCell.responds(to: selector),
               let imp = segmentedCell.method(for: selector) {
                typealias RectForSegment = @convention(c) (AnyObject, Selector, Int, NSRect) -> NSRect
                let fn = unsafeBitCast(imp, to: RectForSegment.self)
                return fn(segmentedCell, selector, segment, bounds)
            }
        }
        
        // Manual Fallback
        let count = control.segmentCount
        var totalWidth: CGFloat = 0
        for i in 0..<count {
            totalWidth += control.width(forSegment: i)
        }
        
        let availableWidth = bounds.width
        let padding = count > 0 ? (availableWidth - totalWidth) / CGFloat(count) : 0
        
        var currentX: CGFloat = 0
        for i in 0..<segment {
            currentX += control.width(forSegment: i) + padding
        }
        
        return NSRect(
            x: currentX,
            y: 0,
            width: control.width(forSegment: segment) + padding,
            height: bounds.height
        )
    }
}

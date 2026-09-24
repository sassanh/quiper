import AppKit

final class HoverTextField: NSTextField {
    // Prevent focus from being stolen from webview
    override var acceptsFirstResponder: Bool { false }

    private var trackingArea: NSTrackingArea?

    // Explicitly allow setting a larger hit-test view (e.g., the LoadingBorderView)
    weak var hitTestView: NSView?

    // Check if tooltip should be shown (e.g., to prevent showing when obscured)
    var shouldShowTooltip: ((NSEvent) -> Bool)?

    /// Invoked on mouse-up when the gesture was a click (no significant
    /// movement) anywhere on the title. Titles drag the window whether or
    /// not a click action is set, so click and drag never conflict.
    var onClick: (() -> Void)?

    /// Builds the right-click menu for the title. Return nil for no menu.
    /// AppKit positions and tracks the menu; a shown menu suppresses
    /// the click action that the closing mouse-up would otherwise trigger.
    var contextMenuProvider: ((NSEvent) -> NSMenu?)?

    private var dragTracker: WindowDragTracker?
    private var suppressNextClick = false
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        
        // Use hitTestView bounds if available, otherwise self.bounds
        let rect: NSRect
        if let hitView = hitTestView, let superview = superview {
             // Convert hitView frame to our coordinate system
             rect = convert(hitView.frame, from: superview)
        } else {
             rect = bounds
        }
        
        trackingArea = NSTrackingArea(rect: rect, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }
    
    override func mouseEntered(with event: NSEvent) {
        // Check external condition first
        if let shouldShow = shouldShowTooltip, !shouldShow(event) {
            return
        }
        
        if !stringValue.isEmpty {
            // Only show if truncated
            if isTruncated() {
                let width = hitTestView?.bounds.width ?? bounds.width
                QuickTooltip.shared.show(stringValue, for: self, forcedWidth: width)
            }
        }
    }
    
    func isTruncated() -> Bool {
        guard let cell = cell else { return false }
        let properSize = cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: CGFloat.greatestFiniteMagnitude, height: bounds.height))
        let availableWidth = hitTestView?.bounds.width ?? bounds.width
        return properSize.width > availableWidth
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let menu = contextMenuProvider?(event) else {
            return super.menu(for: event)
        }
        suppressNextClick = true
        return menu
    }
    
    override func mouseExited(with event: NSEvent) {
        QuickTooltip.shared.hide(for: self)
    }

    override func mouseDown(with event: NSEvent) {
        suppressNextClick = false
        dragTracker = WindowDragTracker(window: window)
        dragTracker?.begin()
    }

    override func mouseDragged(with event: NSEvent) {
        dragTracker?.update()
    }

    override func mouseUp(with event: NSEvent) {
        let didDrag = dragTracker?.end() ?? false
        dragTracker = nil
        defer { suppressNextClick = false }
        guard !suppressNextClick else { return }
        guard onClick != nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        if !didDrag && bounds.contains(point) {
            QuickTooltip.shared.hide(for: self)
            onClick?()
        }
    }
}

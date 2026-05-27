import AppKit

final class HoverTextField: NSTextField {
    // Prevent focus from being stolen from webview
    override var acceptsFirstResponder: Bool { false }
    
    private var trackingArea: NSTrackingArea?
    
    // Explicitly allow setting a larger hit-test view (e.g., the LoadingBorderView)
    weak var hitTestView: NSView?
    
    // Check if tooltip should be shown (e.g., to prevent showing when obscured)
    var shouldShowTooltip: ((NSEvent) -> Bool)?
    
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
    
    override func mouseExited(with event: NSEvent) {
        QuickTooltip.shared.hide(for: self)
    }
}

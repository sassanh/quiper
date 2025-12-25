import AppKit

public class OverlayWindow: NSWindow {
    public override var canBecomeKey: Bool {
        return true
    }
    
    public override var canBecomeMain: Bool {
        return true
    }
    
    // MARK: - Accessibility
    
    public override func isAccessibilityElement() -> Bool {
        return true
    }
    
    public override func accessibilityRole() -> NSAccessibility.Role? {
        return .window
    }
    
    public override func accessibilityTitle() -> String? {
        return "Quiper Overlay"
    }
}

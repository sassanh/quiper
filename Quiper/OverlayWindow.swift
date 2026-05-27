import AppKit

public class OverlayWindow: NSWindow {
    public override var canBecomeKey: Bool {
        return true
    }
    
    public override var canBecomeMain: Bool {
        return true
    }
    
    public override func performClose(_ sender: Any?) {
        if let controller = windowController as? MainWindowController {
            controller.performClose(sender)
        } else {
            super.performClose(sender)
        }
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

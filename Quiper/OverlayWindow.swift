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

    public override func keyDown(with event: NSEvent) {
        // WebKit has already routed the key to the page. The page may perform
        // its default action while still reporting the event as unhandled;
        // NSWindow's fallback would then beep. A web surface stays silent.
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

public class WindowContentView: NSView {
    public override func hitTest(_ point: NSPoint) -> NSView? {
        guard self.bounds.contains(point) else { return nil }
        return super.hitTest(point) ?? self
    }
}

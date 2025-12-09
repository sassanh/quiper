import AppKit

public class OverlayWindow: NSWindow {
    public override var canBecomeKey: Bool {
        return true
    }
}

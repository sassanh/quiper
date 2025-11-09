import AppKit

public class OverlayWindow: NSWindow {
    public override var canBecomeKey: Bool {
        return true
    }

    public var isFullScreen: Bool {
        styleMask.contains(.fullScreen)
    }
}

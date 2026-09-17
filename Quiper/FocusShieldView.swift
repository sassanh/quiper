import AppKit

/// Transparent shield over the content area while the overlay is unfocused.
/// The unfocused state reads through see-through web content (see
/// WebViewManager.setContentTransparent); this shield stays invisible and
/// only ensures the first click focuses the window instead of reaching the
/// page, so shortcuts can't silently land elsewhere.
@MainActor
final class FocusShieldView: NSView {

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        autoresizingMask = []
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Inactive — click to focus")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    override func rightMouseDown(with event: NSEvent) {
        mouseDown(with: event)
    }
}

import AppKit

public class DraggableView: NSView {
    // Prevent focus from being stolen from webview
    public override var acceptsFirstResponder: Bool { false }

    var onWindowDragBegan: (() -> Void)?
    var onWindowDragEnded: (() -> Void)?

    private var dragAnchorPoint: NSPoint?
    private var dragWindowOrigin: NSPoint?

    /// When true the view background is clear; the WindowFrameView border fill acts as background.
    var isTransparentBackground: Bool = false {
        didSet { updateBackgroundColor() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = true
        self.autoresizingMask = [.width, .minYMargin]
        updateBackgroundColor()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidChangeEffectiveAppearance() {
        updateBackgroundColor()
    }

    public override func hitTest(_ point: NSPoint) -> NSView? {
        if self.alphaValue < 0.05 { return nil }
        return super.hitTest(point)
    }

    func updateBackgroundColor() {
        guard !isTransparentBackground else {
            self.layer?.backgroundColor = NSColor.clear.cgColor
            return
        }
        if effectiveAppearance.name.rawValue.contains("Dark") {
            self.layer?.backgroundColor = NSColor(calibratedWhite: 0.2, alpha: 0.8).cgColor
        } else {
            self.layer?.backgroundColor = NSColor(calibratedWhite: 0.9, alpha: 0.8).cgColor
        }
    }

    public override func mouseDown(with event: NSEvent) {
        dragAnchorPoint = NSEvent.mouseLocation
        dragWindowOrigin = window?.frame.origin
        onWindowDragBegan?()
    }

    public override func mouseDragged(with event: NSEvent) {
        guard let anchor = dragAnchorPoint, let origin = dragWindowOrigin,
              let window = window else { return }
        let current = NSEvent.mouseLocation
        window.setFrameOrigin(NSPoint(
            x: origin.x + (current.x - anchor.x),
            y: origin.y + (current.y - anchor.y)
        ))
    }

    public override func mouseUp(with event: NSEvent) {
        dragAnchorPoint = nil
        dragWindowOrigin = nil
        onWindowDragEnded?()
    }
}

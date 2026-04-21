import AppKit

public class DraggableView: NSView {
    // Prevent focus from being stolen from webview
    public override var acceptsFirstResponder: Bool { false }
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
        if effectiveAppearance.name.rawValue.contains("Dark") {
            self.layer?.backgroundColor = NSColor(calibratedWhite: 0.2, alpha: 0.8).cgColor
        } else {
            self.layer?.backgroundColor = NSColor(calibratedWhite: 0.9, alpha: 0.8).cgColor
        }
    }

    public override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

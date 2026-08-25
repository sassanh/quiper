import AppKit

public class DraggableView: NSView {
    // Prevent focus from being stolen from webview
    public override var acceptsFirstResponder: Bool { false }

    var onWindowDragBegan: (() -> Void)?
    var onWindowDragEnded: (() -> Void)?

    private var dragTracker = WindowDragTracker(window: nil)

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
        onWindowDragBegan?()
        dragTracker = WindowDragTracker(window: window)
        dragTracker.begin()
    }

    public override func mouseDragged(with event: NSEvent) {
        dragTracker.update()
    }

    public override func mouseUp(with event: NSEvent) {
        dragTracker.end()
        onWindowDragEnded?()
    }
}

/// Tracks a window-drag gesture started by one of Quiper's draggable chrome
/// views, moving the window with the pointer. `end()` reports whether the
/// gesture moved far enough to count as a drag rather than a click, so views
/// that carry both a click action and drag responsibility can tell them apart.
struct WindowDragTracker {
    private weak var window: NSWindow?
    private var anchorPoint: NSPoint?
    private var originPoint: NSPoint?
    private var moved = false

    /// Movement below this many points (either axis) is treated as a click.
    private static let dragThreshold: CGFloat = 2

    init(window: NSWindow?) {
        self.window = window
    }

    mutating func begin() {
        anchorPoint = NSEvent.mouseLocation
        originPoint = window?.frame.origin
        moved = false
    }

    mutating func update() {
        guard let anchorPoint, let originPoint, let window else { return }
        let current = NSEvent.mouseLocation
        let dx = current.x - anchorPoint.x
        let dy = current.y - anchorPoint.y
        if !moved, abs(dx) >= Self.dragThreshold || abs(dy) >= Self.dragThreshold {
            moved = true
        }
        window.setFrameOrigin(NSPoint(x: originPoint.x + dx, y: originPoint.y + dy))
    }

    /// Finishes the gesture; returns whether it was a real drag.
    @discardableResult
    mutating func end() -> Bool {
        defer {
            anchorPoint = nil
            originPoint = nil
        }
        return moved
    }
}

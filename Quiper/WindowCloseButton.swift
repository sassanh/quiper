import AppKit

/// The close affordance every Quiper window shares: a plain ✕ drawn at
/// one size, so the main window and its popups present an identical
/// control. Stop-loading deliberately draws a filled square instead, so
/// close and stop can never look like the same button. Only the wiring
/// differs per window: the overlay hides, a popup closes.
final class WindowCloseButton: HoverIconButton {

    /// The one symbol every window's close control draws.
    static let symbolName = "xmark"

    init(accessibilityDescription: String, target: AnyObject?, action: Selector?) {
        let image = HoverIconButton.symbolImage(named: Self.symbolName, accessibilityDescription: accessibilityDescription)
        super.init(image: image, target: target, action: action)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

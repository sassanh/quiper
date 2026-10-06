import AppKit

/// The minimize/restore affordance a popup toolbar carries beside close:
/// a − that collapses the window to its toolbar, a + that expands it
/// again, so the glyph always names the action clicking it performs. One
/// size and weight — shared with `WindowCloseButton` — keeps the control
/// paired with ✕ at the trailing end.
final class WindowCollapseButton: HoverIconButton {

    /// The glyph while the window is expanded: click collapses it.
    static let expandedSymbolName = "minus"
    /// The glyph while the window is collapsed: click expands it.
    static let collapsedSymbolName = "plus"

    /// Name of the collapsed-state action, for VoiceOver and the tooltip.
    static let expandedDescription = "Minimize Window"
    /// Name of the expanded-state action, for VoiceOver and the tooltip.
    static let collapsedDescription = "Restore Window"

    /// Whether the window is collapsed to its toolbar — the single source
    /// for the glyph, the tooltip, and the accessibility label.
    var isCollapsed: Bool {
        didSet {
            guard oldValue != isCollapsed else { return }
            updatePresentation()
        }
    }

    init(target: AnyObject?, action: Selector?) {
        isCollapsed = false
        super.init(
            image: HoverIconButton.symbolImage(
                named: Self.expandedSymbolName,
                accessibilityDescription: Self.expandedDescription
            ),
            target: target,
            action: action
        )
        updatePresentation()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Redraws every state-dependent surface from `isCollapsed`, so the
    /// glyph and its labels can never describe different actions.
    private func updatePresentation() {
        let description = isCollapsed ? Self.collapsedDescription : Self.expandedDescription
        image = HoverIconButton.symbolImage(
            named: isCollapsed ? Self.collapsedSymbolName : Self.expandedSymbolName,
            accessibilityDescription: description
        )
        setAccessibilityLabel(description)
        tooltipText = description
        // ⌘M is the fixed minimize binding, like the fixed ⌘W on close.
        tooltipShortcut = "⌘M"
    }
}

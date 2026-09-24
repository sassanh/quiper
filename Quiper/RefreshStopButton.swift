import AppKit

final class RefreshStopButton: HoverIconButton {
    
    private static let refreshImage: NSImage = HoverIconButton.symbolImage(
        named: "arrow.clockwise",
        accessibilityDescription: "Reload"
    )
    
    /// The one symbol stop-loading draws — a filled square, never an ✕,
    /// so close and stop can never look like the same button.
    static let stopSymbolName = "stop.fill"

    private static let stopImage: NSImage = HoverIconButton.symbolImage(
        named: RefreshStopButton.stopSymbolName,
        accessibilityDescription: "Stop Loading"
    )
    
    var isLoadingState = false {
        didSet {
            image = isLoadingState ? Self.stopImage : Self.refreshImage
            tooltipText = isLoadingState ? "Stop" : "Reload"
            tooltipShortcut = isLoadingState ? "⎋" : "⌘R"
        }
    }
    
    init() {
        super.init(image: Self.refreshImage, target: nil, action: nil)
        tooltipText = "Reload"
        tooltipShortcut = "⌘R"
        setAccessibilityIdentifier("RefreshStopButton")
    }
    
    required init?(coder: NSCoder) { fatalError() }
}

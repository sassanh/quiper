import AppKit

final class RefreshStopButton: HoverIconButton {
    
    private static let refreshImage: NSImage = {
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        return NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Reload")!
            .withSymbolConfiguration(config)!
    }()
    
    private static let stopImage: NSImage = {
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        return NSImage(systemSymbolName: "xmark", accessibilityDescription: "Stop Loading")!
            .withSymbolConfiguration(config)!
    }()
    
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

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
            toolTip = isLoadingState ? "Stop" : "Reload"
        }
    }
    
    init() {
        super.init(image: Self.refreshImage, target: nil, action: nil)
        toolTip = "Reload"
        setAccessibilityIdentifier("RefreshStopButton")
    }
    
    required init?(coder: NSCoder) { fatalError() }
}

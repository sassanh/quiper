import Foundation

struct Constants {
    static let APP_NAME = "Quiper"
    static let DEFAULT_SERVICE = "Grok"

    static let LOGO_PATH = "logo/logo.png"
    static let WINDOW_FRAME_AUTOSAVE_NAME = "QuiperWindowFrame"
    static let WINDOW_CORNER_RADIUS: CGFloat = 10.0
    static let DRAGGABLE_AREA_HEIGHT: CGFloat = 32
    static let UI_PADDING: CGFloat = 5
    static let SERVICE_REORDER_DRAG_THRESHOLD: CGFloat = 2

    static let STATUS_ITEM_OBSERVER_CONTEXT = 1
    
    struct DefaultHotKey {
        static let flags: UInt = 0x80000 // Option key
        static let key: Int = 49      // Space bar
    }

    static let logDir: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let logDir = home.appendingPathComponent("Library/Logs/quiper")
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true, attributes: nil)
        return logDir
    }()
}

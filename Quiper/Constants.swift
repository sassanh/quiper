import Foundation

struct Constants {
    static let APP_NAME = "Quiper"
    static let DEFAULT_SERVICE = "Grok"
    
    nonisolated static let BUNDLE_ID: String = {
        return Bundle.main.bundleIdentifier ?? "app.sassanh.quiper.Quiper"
    }()

    nonisolated static let APP_FOLDER_NAME: String = {
        return BUNDLE_ID
    }()

    nonisolated static let IS_DEV: Bool = {
        return BUNDLE_ID.hasSuffix("QuiperDev")
    }()

    static let LOGO_PATH = "logo/logo.png"
    static let WINDOW_FRAME_AUTOSAVE_NAME = "QuiperWindowFrame"
    static let WINDOW_CORNER_RADIUS: CGFloat = 6.0
    static let DRAGGABLE_AREA_HEIGHT: CGFloat = 32
    static let WINDOW_MIN_WIDTH: CGFloat = 320
    static let WINDOW_MIN_HEIGHT: CGFloat = 200
    static let UI_PADDING: CGFloat = 5
    static let SERVICE_REORDER_DRAG_THRESHOLD: CGFloat = 2

    static let STATUS_ITEM_OBSERVER_CONTEXT = 1

    /// Launch flags and mode checks shared across app entry points.
    struct LaunchMode {
        nonisolated static let uiTestingFlag = "--uitesting"
        nonisolated static let templateValidationServerFlag = "--template-validation-server"

        nonisolated static var arguments: [String] {
            ProcessInfo.processInfo.arguments
        }

        nonisolated static var isUITesting: Bool {
            arguments.contains(uiTestingFlag)
        }

        nonisolated static var isTemplateValidationServer: Bool {
            arguments.contains(templateValidationServerFlag)
        }

        /// Suppress first-run wizard, ghost onboarding tips, automatic update prompts,
        /// and similar chrome that interferes with automation/lab sessions.
        /// Does **not** redirect storage paths (that remains `--uitesting`-only).
        nonisolated static var shouldSuppressInterferenceUI: Bool {
            isUITesting || isTemplateValidationServer
        }
    }

    struct Updates {
        static let latestReleaseAPI = URL(string: "https://api.github.com/repos/sassanh/quiper/releases/latest")!
        static let allReleasesAPI = URL(string: "https://api.github.com/repos/sassanh/quiper/releases")!
        static let latestReleasePage = URL(string: "https://github.com/sassanh/quiper/releases/latest")!
        static let automaticCheckInterval: TimeInterval = 60 * 60 * 12 // 12 hours
        static let preferredAssetExtensions = ["zip", "dmg"]
    }
    
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

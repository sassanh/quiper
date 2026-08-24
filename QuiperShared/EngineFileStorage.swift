import Foundation

/// File-backed storage for per-engine text artifacts—custom stylesheets and
/// action scripts—shared by both platforms. Layout matches the macOS original:
/// `<base>/CustomCSS/<serviceID>.css` and
/// `<base>/ActionScripts/<serviceID>/<actionID>.js`. Writes go through
/// `TextFileStorage` (empty content removes the file, unchanged content is
/// skipped) and carry complete file protection on iOS.
@MainActor
enum EngineFileStorage {
    // MARK: - Custom CSS

    static func customCSSURL(serviceID: UUID) -> URL {
        kindDirectory("CustomCSS")
            .appendingPathComponent("\(serviceID.uuidString).css", isDirectory: false)
    }

    static func loadCustomCSS(serviceID: UUID, fallback: String) -> String {
        loadText(at: customCSSURL(serviceID: serviceID), fallback: fallback)
    }

    static func saveCustomCSS(_ css: String, serviceID: UUID) {
        TextFileStorage.save(css, to: customCSSURL(serviceID: serviceID), writeOptions: writeOptions)
    }

    static func deleteCustomCSS(for serviceID: UUID) {
        try? FileManager.default.removeItem(at: customCSSURL(serviceID: serviceID))
    }

    static func deleteAllCustomCSS() {
        try? FileManager.default.removeItem(at: kindDirectory("CustomCSS"))
    }

    // MARK: - Action scripts

    static func actionScriptURL(serviceID: UUID, actionID: UUID) -> URL {
        serviceDirectory(serviceID)
            .appendingPathComponent("\(actionID.uuidString).js", isDirectory: false)
    }

    static func loadActionScript(serviceID: UUID, actionID: UUID, fallback: String) -> String {
        loadText(at: actionScriptURL(serviceID: serviceID, actionID: actionID), fallback: fallback)
    }

    static func saveActionScript(_ script: String, serviceID: UUID, actionID: UUID) {
        TextFileStorage.save(
            script,
            to: actionScriptURL(serviceID: serviceID, actionID: actionID),
            writeOptions: writeOptions
        )
    }

    static func deleteActionScript(serviceID: UUID, actionID: UUID) {
        try? FileManager.default.removeItem(
            at: actionScriptURL(serviceID: serviceID, actionID: actionID)
        )
    }

    static func deleteActionScripts(for serviceID: UUID) {
        try? FileManager.default.removeItem(at: serviceDirectory(serviceID))
    }

    static func deleteAllActionScripts() {
        try? FileManager.default.removeItem(at: kindDirectory("ActionScripts"))
    }

    // MARK: - Layout

    private static var baseDirectory: URL {
        #if os(macOS)
        let isRunningTests = NSClassFromString("XCTestCase") != nil
        let isUITesting = CommandLine.arguments.contains(Constants.LaunchMode.uiTestingFlag)
        let appDir: URL
        if isRunningTests || isUITesting {
            let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            appDir = tempDir.appendingPathComponent("QuiperTests-\(ProcessInfo.processInfo.processIdentifier)")
        } else {
            appDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent(Constants.APP_FOLDER_NAME, isDirectory: true)
        }
        #else
        let appDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent(Constants.APP_FOLDER_NAME, isDirectory: true)
        #endif

        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir
    }

    private static func kindDirectory(_ name: String) -> URL {
        let directory = baseDirectory.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func serviceDirectory(_ serviceID: UUID) -> URL {
        let directory = kindDirectory("ActionScripts")
            .appendingPathComponent(serviceID.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func loadText(at url: URL, fallback: String) -> String {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return fallback
        }
        return text
    }

    private static var writeOptions: Data.WritingOptions {
        #if os(iOS)
        return [.atomic, .completeFileProtection]
        #else
        return .atomic
        #endif
    }
}

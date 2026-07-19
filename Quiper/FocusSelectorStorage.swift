import Foundation
import AppKit

@MainActor
enum FocusSelectorStorage {
    private static var baseDirectory: URL {
        let isRunningTests = NSClassFromString("XCTestCase") != nil
        let isUITesting = CommandLine.arguments.contains("--uitesting")
        
        let appDir: URL
        if isRunningTests || isUITesting {
            let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            appDir = tempDir.appendingPathComponent("QuiperTests-\(ProcessInfo.processInfo.processIdentifier)")
        } else {
            let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            appDir = supportDir.appendingPathComponent(Constants.APP_FOLDER_NAME, isDirectory: true)
        }
        
        let selectorsDir = appDir.appendingPathComponent("FocusSelectors", isDirectory: true)
        try? FileManager.default.createDirectory(at: selectorsDir, withIntermediateDirectories: true)
        return selectorsDir
    }

    static func selectorURL(serviceID: UUID) -> URL {
        baseDirectory.appendingPathComponent("\(serviceID.uuidString).txt", isDirectory: false)
    }

    static func revealInFinder(serviceID: UUID, contents: String) {
        let url = selectorURL(serviceID: serviceID)
        if !FileManager.default.fileExists(atPath: url.path) {
            let data = Data(contents.utf8)
            try? data.write(to: url, options: .atomic)
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func copyPath(serviceID: UUID, contents: String) {
        let url = selectorURL(serviceID: serviceID)
        if !FileManager.default.fileExists(atPath: url.path) {
            let data = Data(contents.utf8)
            try? data.write(to: url, options: .atomic)
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url.path, forType: .string)
    }

    static func loadSelector(serviceID: UUID, fallback: String) -> String {
        let url = selectorURL(serviceID: serviceID)
        guard let data = try? Data(contentsOf: url),
              let selector = String(data: data, encoding: .utf8) else {
            return fallback
        }
        return selector
    }

    static func saveSelector(_ selector: String, serviceID: UUID) {
        let url = selectorURL(serviceID: serviceID)
        TextFileStorage.save(selector, to: url)
    }

    static func openInDefaultEditor(serviceID: UUID, contents: String) {
        let url = selectorURL(serviceID: serviceID)
        if !FileManager.default.fileExists(atPath: url.path) {
            let data = Data(contents.utf8)
            try? data.write(to: url, options: .atomic)
        }
        NSWorkspace.shared.open(url)
    }

    static func deleteSelector(for serviceID: UUID) {
        let url = selectorURL(serviceID: serviceID)
        try? FileManager.default.removeItem(at: url)
    }

    static func deleteAllSelectors() {
        let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = supportDir.appendingPathComponent(Constants.APP_FOLDER_NAME, isDirectory: true)
        let selectorsDir = appDir.appendingPathComponent("FocusSelectors", isDirectory: true)
        try? FileManager.default.removeItem(at: selectorsDir)
    }
}

import Foundation
import AppKit

@MainActor
enum CustomCSSStorage {
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
        
        let cssDir = appDir.appendingPathComponent("CustomCSS", isDirectory: true)
        try? FileManager.default.createDirectory(at: cssDir, withIntermediateDirectories: true)
        return cssDir
    }

    static func cssURL(serviceID: UUID) -> URL {
        baseDirectory.appendingPathComponent("\(serviceID.uuidString).css", isDirectory: false)
    }

    static func revealInFinder(serviceID: UUID, contents: String) {
        let url = cssURL(serviceID: serviceID)
        if !FileManager.default.fileExists(atPath: url.path) {
            let data = Data(contents.utf8)
            try? data.write(to: url, options: .atomic)
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func copyPath(serviceID: UUID, contents: String) {
        let url = cssURL(serviceID: serviceID)
        if !FileManager.default.fileExists(atPath: url.path) {
            let data = Data(contents.utf8)
            try? data.write(to: url, options: .atomic)
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url.path, forType: .string)
    }

    static func loadCSS(serviceID: UUID, fallback: String) -> String {
        let url = cssURL(serviceID: serviceID)
        guard let data = try? Data(contentsOf: url),
              let css = String(data: data, encoding: .utf8) else {
            return fallback
        }
        return css
    }

    static func saveCSS(_ css: String, serviceID: UUID) {
        let url = cssURL(serviceID: serviceID)
        TextFileStorage.save(css, to: url)
    }

    static func openInDefaultEditor(serviceID: UUID, contents: String) {
        let url = cssURL(serviceID: serviceID)
        if !FileManager.default.fileExists(atPath: url.path) {
            let data = Data(contents.utf8)
            try? data.write(to: url, options: .atomic)
        }
        NSWorkspace.shared.open(url)
    }

    static func deleteCSS(for serviceID: UUID) {
        let url = cssURL(serviceID: serviceID)
        try? FileManager.default.removeItem(at: url)
    }

    static func deleteAllCSS() {
        let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = supportDir.appendingPathComponent(Constants.APP_FOLDER_NAME, isDirectory: true)
        let cssDir = appDir.appendingPathComponent("CustomCSS", isDirectory: true)
        try? FileManager.default.removeItem(at: cssDir)
    }
}

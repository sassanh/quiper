import Foundation
import AppKit

enum ActionScriptStorage {
    private static var baseDirectory: URL {
        let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = supportDir.appendingPathComponent("Quiper", isDirectory: true)
        let scriptsDir = appDir.appendingPathComponent("ActionScripts", isDirectory: true)
        try? FileManager.default.createDirectory(at: scriptsDir, withIntermediateDirectories: true)
        return scriptsDir
    }

    private static func serviceDirectory(for serviceID: UUID) -> URL {
        let dir = baseDirectory.appendingPathComponent(serviceID.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func scriptURL(serviceID: UUID, actionID: UUID) -> URL {
        serviceDirectory(for: serviceID).appendingPathComponent("\(actionID.uuidString).js", isDirectory: false)
    }

    static func loadScript(serviceID: UUID, actionID: UUID, fallback: String) -> String {
        let url = scriptURL(serviceID: serviceID, actionID: actionID)
        guard let data = try? Data(contentsOf: url),
              let script = String(data: data, encoding: .utf8) else {
            return fallback
        }
        return script
    }

    static func saveScript(_ script: String, serviceID: UUID, actionID: UUID) {
        let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = scriptURL(serviceID: serviceID, actionID: actionID)
        if trimmed.isEmpty {
            try? FileManager.default.removeItem(at: url)
            return
        }
        let data = Data(script.utf8)
        try? data.write(to: url, options: .atomic)
    }

    static func openInDefaultEditor(serviceID: UUID, actionID: UUID, contents: String) {
        let url = scriptURL(serviceID: serviceID, actionID: actionID)
        if !FileManager.default.fileExists(atPath: url.path) {
            let data = Data(contents.utf8)
            try? data.write(to: url, options: .atomic)
        }
        NSWorkspace.shared.open(url)
    }

    static func deleteScript(serviceID: UUID, actionID: UUID) {
        let url = scriptURL(serviceID: serviceID, actionID: actionID)
        try? FileManager.default.removeItem(at: url)
    }

    static func deleteScripts(for serviceID: UUID) {
        let dir = baseDirectory.appendingPathComponent(serviceID.uuidString, isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
    }
}

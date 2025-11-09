import Foundation

enum Launcher {
    static func installAtLogin() {
        do {
            let plistURL = try agentPlistURL()
            let payload: [String: Any] = [
                "Label": agentLabel(),
                "ProgramArguments": [try executablePath()],
                "RunAtLoad": true
            ]
            let data = try PropertyListSerialization.data(fromPropertyList: payload, format: .xml, options: 0)
            try data.write(to: plistURL, options: .atomic)
            try launchctl(action: "load", plistURL: plistURL)
        } catch {
            NSLog("[Quiper] Failed to install login item: \(error)")
        }
    }

    static func uninstallFromLogin() {
        do {
            let plistURL = try agentPlistURL()
            try launchctl(action: "unload", plistURL: plistURL)
            try FileManager.default.removeItem(at: plistURL)
        } catch {
            NSLog("[Quiper] Failed to uninstall login item: \(error)")
        }
    }

    static func isInstalledAtLogin() -> Bool {
        guard let plistURL = try? agentPlistURL() else {
            return false
        }
        return FileManager.default.fileExists(atPath: plistURL.path)
    }

    // MARK: - Helpers
    private static func userLaunchAgentsDirectory() throws -> URL {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func agentLabel() -> String {
        "com.\(NSUserName()).quiper"
    }

    private static func agentPlistURL() throws -> URL {
        try userLaunchAgentsDirectory().appendingPathComponent("\(agentLabel()).plist", isDirectory: false)
    }

    private static func executablePath() throws -> String {
        if let bundlePath = Bundle.main.executableURL?.path {
            return bundlePath
        }
        return CommandLine.arguments[0]
    }

    private static func launchctl(action: String, plistURL: URL) throws {
        let process = Process()
        process.launchPath = "/bin/launchctl"
        process.arguments = [action, plistURL.path]
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw NSError(domain: "com.quiper.launchctl", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "launchctl \(action) failed"])
        }
    }
}

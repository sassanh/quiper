import Foundation

struct UpdateInstaller {
    let archiveURL: URL
    let updatesDirectory: URL
    let currentBundleURL: URL

    func perform() throws -> URL {
        let ext = archiveURL.pathExtension.lowercased()
        switch ext {
        case "zip":
            return try installFromZIP()
        case "dmg":
            return try installFromDMG()
        default:
            throw UpdateError.unsupportedAsset
        }
    }

    private func installFromZIP() throws -> URL {
        let extractionDir = updatesDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: extractionDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: extractionDir) }
        try runProcess("/usr/bin/unzip", arguments: ["-q", archiveURL.path, "-d", extractionDir.path])
        guard let appBundle = findAppBundle(in: extractionDir) else {
            throw UpdateError.missingAppBundle
        }
        return try replaceCurrentApp(with: appBundle)
    }

    private func installFromDMG() throws -> URL {
        let mount = try mountDMG()
        defer { try? detachDMG(device: mount.device) }
        guard let appBundle = findAppBundle(in: mount.mountPoint) else {
            throw UpdateError.missingAppBundle
        }
        return try replaceCurrentApp(with: appBundle)
    }

    private func findAppBundle(in root: URL) -> URL? {
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey])
        while let element = enumerator?.nextObject() as? URL {
            if element.pathExtension.lowercased() == "app" {
                return element
            }
        }
        return nil
    }

    private func replaceCurrentApp(with newApp: URL) throws -> URL {
        _ = try FileManager.default.replaceItemAt(currentBundleURL, withItemAt: newApp)
        return currentBundleURL
    }

    private func mountDMG() throws -> (mountPoint: URL, device: String) {
        let data = try runProcess("/usr/bin/hdiutil", arguments: ["attach", archiveURL.path, "-nobrowse", "-plist"], captureOutput: true)
        guard let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]] else {
            throw UpdateError.installationFailed("Unable to parse disk image metadata")
        }
        for entity in entities {
            if let mountPoint = entity["mount-point"] as? String,
               let device = entity["dev-entry"] as? String {
                return (URL(fileURLWithPath: mountPoint), device)
            }
        }
        throw UpdateError.installationFailed("Unable to mount disk image")
    }

    private func detachDMG(device: String) throws {
        _ = try? runProcess("/usr/bin/hdiutil", arguments: ["detach", device, "-quiet"])
    }

    @discardableResult
    private func runProcess(_ launchPath: String, arguments: [String], captureOutput: Bool = false) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let outputPipe = Pipe()
        if captureOutput {
            process.standardOutput = outputPipe
        }
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown error"
            throw UpdateError.installationFailed(message)
        }
        if captureOutput {
            return outputPipe.fileHandleForReading.readDataToEndOfFile()
        }
        return Data()
    }
}

enum UpdateError: LocalizedError {
    case invalidResponse
    case unsupportedAsset
    case missingAppBundle
    case installationFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Server returned an unexpected response"
        case .unsupportedAsset:
            return "The downloaded file type is not supported"
        case .missingAppBundle:
            return "The update package did not contain an app bundle"
        case .installationFailed(let message):
            return "Failed to install update: \(message)"
        }
    }
}

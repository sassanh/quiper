import Foundation
import AppKit
import UniformTypeIdentifiers

/// Handles exporting and importing the full Quiper configuration as a single `.quiper` JSON file.
/// The archive contains all settings (from `PersistedSettings`) plus every action script
/// inlined from `ActionScriptStorage`, making it completely self-contained.
enum ConfigPortManager {

    private static let fileExtension = "quiper"

    // MARK: – Export

    @MainActor
    static func exportConfig() throws -> Data {
        let settings = Settings.shared
        var ps = settings.makePersistedSettings()
        
        // Force sync ALL disk scripts into the PS services so the export is highly accurate and self-contained!
        let diskScripts = collectAllScripts(for: settings.services)
        for i in 0..<ps.services.count {
            let serviceID = ps.services[i].id
            for actionID in ps.services[i].actionScripts.keys {
                let key = "\(serviceID)/\(actionID)"
                if let content = diskScripts[key] {
                    ps.services[i].actionScripts[actionID] = content
                }
            }
        }
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(ps)
    }

    /// Gathers every JS action script stored on disk for the given services.

    private static func collectAllScripts(for services: [Service]) -> [String: String] {
        var result: [String: String] = [:]
        for service in services {
            for actionID in service.actionScripts.keys {
                let script = ActionScriptStorage.loadScript(
                    serviceID: service.id,
                    actionID: actionID,
                    fallback: service.actionScripts[actionID] ?? ""
                )
                let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                result["\(service.id)/\(actionID)"] = trimmed
            }
        }
        return result
    }

    // MARK: – Import

    @MainActor
    static func importConfig(from data: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let ps: PersistedSettings
        do {
            ps = try decoder.decode(PersistedSettings.self, from: data)
        } catch let error as DecodingError {
            throw ConfigPortError.decodingFailed(error)
        } catch {
            throw error
        }

        // Restore settings
        Settings.shared.applyPersistedSettings(ps)
        
        // Restore action scripts to disk. The memory structures were updated by `applyPersistedSettings`
        for service in ps.services {
            for (actionID, script) in service.actionScripts {
                ActionScriptStorage.saveScript(script, serviceID: service.id, actionID: actionID)
            }
        }
        Settings.shared.saveSettings()
    }

    // MARK: – Save panel helpers

    static func showExportPanel(in window: NSWindow?, completion: @escaping (Result<URL, Error>) -> Void) {
        let panel = NSSavePanel()
        panel.title = "Export Quiper Config"
        panel.nameFieldStringValue = "quiper-config.\(fileExtension)"
        panel.allowedContentTypes = [.init(filenameExtension: fileExtension)!]
        panel.canCreateDirectories = true

        let handler: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                do {
                    let data = try exportConfig()
                    try data.write(to: url, options: .atomic)
                    completion(.success(url))
                } catch {
                    completion(.failure(error))
                }
            }
        }

        if let window {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            panel.begin(completionHandler: handler)
        }
    }

    static func showImportPanel(in window: NSWindow?, completion: @escaping (Result<Void, Error>) -> Void) {
        let panel = NSOpenPanel()
        panel.title = "Import Quiper Config"
        panel.message = "⚠️ This will overwrite all current settings and action scripts."
        panel.prompt = "Import"
        panel.allowedContentTypes = [.init(filenameExtension: fileExtension)!]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        let handler: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                do {
                    let data = try Data(contentsOf: url)
                    try importConfig(from: data)
                    completion(.success(()))
                } catch {
                    completion(.failure(error))
                }
            }
        }

        if let window {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            panel.begin(completionHandler: handler)
        }
    }
}

enum ConfigPortError: LocalizedError {
    case decodingFailed(DecodingError)

    var errorDescription: String? {
        switch self {
        case .decodingFailed(let error):
            return "Failed to read the config file: \(error.detailedDescription)"
        }
    }
}

extension DecodingError {
    var detailedDescription: String {
        switch self {
        case .keyNotFound(let key, let context):
            let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
            let location = path.isEmpty ? "" : " at '\(path)'"
            return "Missing field '\(key.stringValue)'\(location)."
        case .typeMismatch(let type, let context):
            let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
            return "Incorrect type for field '\(path)': expected \(type). \(context.debugDescription)"
        case .valueNotFound(let type, let context):
            let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
            return "Value of type '\(type)' not found at '\(path)'."
        case .dataCorrupted(let context):
            let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
            let location = path.isEmpty ? "" : " at '\(path)'"
            return "Data corrupted\(location): \(context.debugDescription)"
        @unknown default:
            return self.localizedDescription
        }
    }
}

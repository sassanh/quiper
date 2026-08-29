import Foundation
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

/// Shared import/export helpers for Quiper configuration archives.
/// The archive is a self-contained JSON representation of `PersistedSettings`
/// with every per-engine text artifact inlined, suitable for backup/restore.
enum ConfigPortability {
    static let fileExtension = "quiper"
    static let defaultExportFilename = "quiper-config.quiper"

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func encode(_ persisted: PersistedSettings) throws -> Data {
        try makeEncoder().encode(persisted)
    }

    static func decode(from data: Data) throws -> PersistedSettings {
        do {
            return try makeDecoder().decode(PersistedSettings.self, from: data)
        } catch let error as DecodingError {
            throw ConfigPortError.decodingFailed(error)
        }
    }

    /// Inlines the latest file-backed script contents into the persisted copy.
    /// Mirrors the macOS export's disk-merge so an export captures edits made
    /// outside the in-memory model (e.g., direct file edits).
    @MainActor
    static func inlineFileScripts(into persisted: inout PersistedSettings) {
        // Nothing to inline – report packaging quickly.
        let total = persisted.services.reduce(0) { $0 + $1.actionScripts.count }
        if total == 0 {
            SyncPreparationState.shared.detail = "Packaging snapshot — inlining scripts (none)…"
        }
        var diskScripts: [String: String] = [:]
        var processed = 0
        for service in persisted.services {
            for actionID in service.actionScripts.keys {
                processed += 1
                // Particular job right now inside packaging – single line, no list.
                SyncPreparationState.shared.detail = "Packaging snapshot — loading script \(processed)/\(total) for \(service.name)…"
                // Keep Settings/AppEnvironment mirrors for existing observers (will be phased out)
                #if os(macOS)
                Settings.shared.syncPreparationDetail = SyncPreparationState.shared.detail
                #endif
                let script = EngineFileStorage.loadActionScript(
                    serviceID: service.id,
                    actionID: actionID,
                    fallback: service.actionScripts[actionID] ?? ""
                )
                let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                diskScripts["\(service.id.uuidString)/\(actionID.uuidString)"] = trimmed
            }
        }
        SyncPreparationState.shared.detail = "Packaging snapshot — merging \(diskScripts.count) scripts…"
        #if os(macOS)
        Settings.shared.syncPreparationDetail = SyncPreparationState.shared.detail
        #endif
        for index in persisted.services.indices {
            let serviceID = persisted.services[index].id
            for actionID in persisted.services[index].actionScripts.keys {
                let key = "\(serviceID.uuidString)/\(actionID.uuidString)"
                if let content = diskScripts[key] {
                    persisted.services[index].actionScripts[actionID] = content
                }
            }
        }
        SyncPreparationState.shared.detail = "Packaging snapshot — encoding \(persisted.services.count) engines…"
        #if os(macOS)
        Settings.shared.syncPreparationDetail = SyncPreparationState.shared.detail
        #endif
    }

    /// Persists the inlined scripts and custom CSS from a decoded archive back
    /// to file storage, matching the import path on both platforms.
    @MainActor
    static func persistFileArtifacts(from persisted: PersistedSettings) {
        for service in persisted.services where !service.isEncrypted {
            // Action scripts: each entry in the persisted service is authoritative.
            for (actionID, script) in service.actionScripts {
                EngineFileStorage.saveActionScript(script, serviceID: service.id, actionID: actionID)
            }
            // Custom CSS: persisted value (or absence) is authoritative.
            if let css = service.customCSS, !css.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                EngineFileStorage.saveCustomCSS(css, serviceID: service.id)
            } else if service.templateCustomCSSSync {
                EngineFileStorage.deleteCustomCSS(for: service.id)
            } else if service.customCSS == nil {
                // No stylesheet – ensure no stale file remains.
                EngineFileStorage.deleteCustomCSS(for: service.id)
            }
        }
    }

    #if canImport(UniformTypeIdentifiers)
    static var contentType: UTType {
        if let quiper = UTType(filenameExtension: fileExtension) {
            return quiper
        }
        return .data
    }
    #endif
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

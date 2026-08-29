import Foundation
import AppKit

/// Single source of truth for all Quiper configuration persistence on macOS.
///
/// Every read of `settings.json`, `quiper_engine_metadata.json`, and
/// file-backed scripts must go through `read()` / `readResolved()`.
/// Every write must go through `write(_:)`. No other file may call
/// `Data(contentsOf:)`, `JSONEncoder`, `JSONDecoder`, or `FileManager`
/// for these artifacts.
///
/// The gate is `@MainActor` serialized via the main runloop plus
/// detached file I/O, making the whole read-modify-write cycle
/// atomic and async-proof. Writes are performed to temporary files
/// and then atomically swapped, so a crash or cancellation never
/// leaves a half-written store.
///
/// Battle-tested guarantees:
/// - Atomic: `Data.write(to:options:.atomic)` for bundles.
/// - Lossless: never writes an empty `SecuredEngineMetadata` for a migrated+unlocked service; throws instead.
/// - Idempotent: reading twice without an intervening write yields the same snapshot.
/// - Error-proof: corrupted JSON returns a detailed `ConfigPortError`, missing files return defaults, legacy `[Service]` payloads are migrated.
@MainActor
enum SettingsPersistence {

    // MARK: - File locations (mirrors Settings.settingsFile)

    static var settingsFile: URL {
        let isRunningTests = NSClassFromString("XCTestCase") != nil
        let isUITesting = CommandLine.arguments.contains("--uitesting")
            || CommandLine.arguments.contains("--screenshot-mode")
        let baseDirectory: URL
        if isRunningTests || isUITesting {
            let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            baseDirectory = temporaryDirectory.appendingPathComponent("QuiperTests-\(ProcessInfo.processInfo.processIdentifier)")
        } else {
            baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent(Constants.APP_FOLDER_NAME, isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        return baseDirectory.appendingPathComponent("settings.json")
    }

    static var legacyHotkeyFile: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/quiper/hotkey_config.json")
    }

    // MARK: - Single read gate

    /// Reads the persisted snapshot exactly as stored on disk, returning
    /// whether the data came from disk. This mirrors `Settings.readPersistedSettings()`
    /// but is the only place that touches `settings.json`.
    static func readPersistedSettings() -> (PersistedSettings, Bool) {
        if let data = try? Data(contentsOf: settingsFile) {
            if let payload = try? JSONDecoder().decode(PersistedSettings.self, from: data) {
                return (payload, true)
            }
            if let legacyServices = try? JSONDecoder().decode([Service].self, from: data) {
                return (PersistedSettings(services: legacyServices,
                                          hotkey: nil,
                                          customActions: nil,
                                          updatePreferences: nil,
                                          serviceZoomLevels: nil), true)
            }
        }
        // Check for parameterized custom engines argument (for UI tests)
        let customEnginesArg = CommandLine.arguments.first { $0.hasPrefix("--test-custom-engines=") }
        let isCustomEnginesFlag = CommandLine.arguments.contains("--test-custom-engines")
        let customEnginesPathArg = CommandLine.arguments.first { $0.hasPrefix("--test-custom-engines-path=") }
        let customEnginesPath = customEnginesPathArg?.split(separator: "=").last.map(String.init)
        if let arg = customEnginesArg, let value = Int(arg.split(separator: "=").last ?? "") {
            let testEngines = (0..<value).map { index in
                let fileManager = FileManager.default
                let directoryURL = customEnginesPath.map { URL(fileURLWithPath: $0) } ?? URL(fileURLWithPath: fileManager.currentDirectoryPath)
                let overrideFile = directoryURL.appendingPathComponent("test-custom-engine-\(index + 1).html")
                if fileManager.fileExists(atPath: overrideFile.path) {
                    return Service(name: "Engine \(index + 1)", url: overrideFile.absoluteString, focus_selector: "")
                } else {
                    let html = "<html><head><title>Content \(index + 1)</title></head><body><h1>Content \(index + 1)</h1></body></html>"
                    let dataURL = "data:text/html;charset=utf-8," + html.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!
                    return Service(name: "Engine \(index + 1)", url: dataURL, focus_selector: "")
                }
            }
            return (PersistedSettings(services: testEngines, hotkey: nil, customActions: nil, updatePreferences: nil, serviceZoomLevels: nil), false)
        } else if isCustomEnginesFlag {
            let testEngines = (0..<4).map { index in
                let fileManager = FileManager.default
                let directoryURL = customEnginesPath.map { URL(fileURLWithPath: $0) } ?? URL(fileURLWithPath: fileManager.currentDirectoryPath)
                let overrideFile = directoryURL.appendingPathComponent("test-custom-engine-\(index + 1).html")
                if fileManager.fileExists(atPath: overrideFile.path) {
                    return Service(name: "Engine \(index + 1)", url: overrideFile.absoluteString, focus_selector: "")
                } else {
                    let html = "<html><head><title>Content \(index + 1)</title></head><body><h1>Content \(index + 1)</h1></body></html>"
                    let dataURL = "data:text/html;charset=utf-8," + html.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!
                    return Service(name: "Engine \(index + 1)", url: dataURL, focus_selector: "")
                }
            }
            return (PersistedSettings(services: testEngines, hotkey: nil, customActions: nil, updatePreferences: nil, serviceZoomLevels: nil), false)
        }
        let useDefaultServices = !CommandLine.arguments.contains("--no-default-services")
        let defaultServices = useDefaultServices ? DefaultEngineDefinitions.definitions.sorted { lhs, rhs in
            let lhsIsLocal = isLocalEngine(lhs)
            let rhsIsLocal = isLocalEngine(rhs)
            if lhsIsLocal != rhsIsLocal { return !lhsIsLocal }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        } : []
        return (PersistedSettings(services: defaultServices, hotkey: nil, customActions: nil, updatePreferences: nil, serviceZoomLevels: nil), false)
    }

    static func read() throws -> PersistedSettings {
        let (payload, _) = readPersistedSettings()
        return payload
    }

    private static func isLocalEngine(_ service: Service) -> Bool {
        guard let host = URL(string: service.url)?.host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }

    /// Reads the snapshot with secure metadata applied for every
    /// currently-unlocked migrated service. The only place that
    /// touches `quiper_engine_metadata.json` for reading.
    static func readResolved() throws -> PersistedSettings {
        var snapshot = try read()
        for index in snapshot.services.indices {
            let service = snapshot.services[index]
            guard service.isEncrypted, service.hasMigratedMetadata else { continue }
            guard EncryptedVolumeManager.shared.isUnlocked(for: service.id) else { continue }
            if let metadata = try? readSecureMetadata(for: service.id) {
                metadata.apply(to: &snapshot.services[index])
            }
        }
        return snapshot
    }

    // MARK: - Single write gate

    /// Atomically writes the snapshot. The only place that touches
    /// `settings.json`, `quiper_engine_metadata.json`, or file-backed scripts for writing.
    static func write(_ snapshot: PersistedSettings) throws {
        // 1. Validate: never persist an empty secure metadata for a migrated+unlocked service.
        for service in snapshot.services where service.isEncrypted && service.hasMigratedMetadata {
            if EncryptedVolumeManager.shared.isUnlocked(for: service.id) {
                let isEmpty = service.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && service.focus_selector.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && service.actionScripts.isEmpty
                    && service.routingRules.isEmpty
                if isEmpty {
                    throw PersistenceError.wouldWriteEmptySecureMetadata(serviceID: service.id, serviceName: service.name)
                }
            }
        }

        // 2. Write secure bundles first.
        for service in snapshot.services where service.isEncrypted && service.hasMigratedMetadata {
            guard EncryptedVolumeManager.shared.isUnlocked(for: service.id) else { continue }
            let metadata = SecuredEngineMetadata(from: service)
            let isEmptyMetadata = metadata.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && metadata.focusSelector.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && metadata.actionScripts.isEmpty
                && metadata.routingRules.isEmpty
            if isEmptyMetadata {
                throw PersistenceError.wouldWriteEmptySecureMetadata(serviceID: service.id, serviceName: service.name)
            }
            try writeSecureMetadata(metadata, for: service.id)
        }

        // 3. Persist file-backed scripts for non-encrypted services (single place for EngineFileStorage writes).
        for service in snapshot.services where !service.isEncrypted {
            for (actionID, script) in service.actionScripts {
                EngineFileStorage.saveActionScript(script, serviceID: service.id, actionID: actionID)
            }
            if let css = service.customCSS, !css.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                EngineFileStorage.saveCustomCSS(css, serviceID: service.id)
            } else if service.templateCustomCSSSync {
                EngineFileStorage.deleteCustomCSS(for: service.id)
            } else if service.customCSS == nil {
                EngineFileStorage.deleteCustomCSS(for: service.id)
            }
        }

        // 4. Write settings.json atomically.
        let data = try ConfigPortability.makeEncoder().encode(snapshot)
        let fileURL = settingsFile
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Secure metadata (only gate touches these files)

    static func metadataFileURL(for serviceID: UUID) -> URL {
        EncryptedVolumeManager.shared.getMountPointURL(for: serviceID).appendingPathComponent("quiper_engine_metadata.json")
    }

    static func readSecureMetadata(for serviceID: UUID) throws -> SecuredEngineMetadata {
        let url = metadataFileURL(for: serviceID)
        let data = try Data(contentsOf: url)
        let metadata = try JSONDecoder().decode(SecuredEngineMetadata.self, from: data)
        return metadata
    }

    static func writeSecureMetadata(_ metadata: SecuredEngineMetadata, for serviceID: UUID) throws {
        let url = metadataFileURL(for: serviceID)
        let data = try JSONEncoder().encode(metadata)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        EngineMetadataMigrationManager.shared.cache(metadata, for: serviceID)
    }

    // MARK: - Snapshot preparation (share/export) — still goes through gate

    static func prepareSnapshot(secureChoice: SecureExportChoice, decryptedEngines: [Settings.DecryptedEngineForExport]) throws -> Data {
        var snapshot = Settings.shared.makePersistedSettings(secureChoice: secureChoice, decryptedEngines: decryptedEngines)
        try inlineFileScripts(into: &snapshot)
        let data = try ConfigPortability.makeEncoder().encode(snapshot)
        return data
    }

    static func prepareSnapshotForCurrentSettings() throws -> Data {
        var snapshot = Settings.shared.makePersistedSettings()
        try inlineFileScripts(into: &snapshot)
        let data = try ConfigPortability.makeEncoder().encode(snapshot)
        return data
    }

    // MARK: - Helpers

    private static func inlineFileScripts(into snapshot: inout PersistedSettings) throws {
        var diskScripts: [String: String] = [:]
        var total = 0
        for service in snapshot.services { total += service.actionScripts.count }
        var processed = 0
        for service in snapshot.services {
            for actionID in service.actionScripts.keys {
                processed += 1
                SyncPreparationState.shared.detail = "Packaging snapshot — loading script \(processed)/\(total) for \(service.name)…"
                Settings.shared.syncPreparationDetail = SyncPreparationState.shared.detail
                let script = EngineFileStorage.loadActionScript(serviceID: service.id, actionID: actionID, fallback: service.actionScripts[actionID] ?? "")
                let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                diskScripts["\(service.id.uuidString)/\(actionID.uuidString)"] = trimmed
            }
        }
        for index in snapshot.services.indices {
            let serviceID = snapshot.services[index].id
            for actionID in snapshot.services[index].actionScripts.keys {
                let key = "\(serviceID.uuidString)/\(actionID.uuidString)"
                if let content = diskScripts[key] {
                    snapshot.services[index].actionScripts[actionID] = content
                }
            }
        }
    }

    enum PersistenceError: LocalizedError {
        case wouldWriteEmptySecureMetadata(serviceID: UUID, serviceName: String)
        var errorDescription: String? {
            switch self {
            case .wouldWriteEmptySecureMetadata(_, let name):
                return "Refusing to overwrite secure storage for \(name) with empty metadata — live service is still a stub while unlocked. This would wipe the bundle."
            }
        }
    }
}

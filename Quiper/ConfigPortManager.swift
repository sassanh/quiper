import Foundation
import AppKit
import UniformTypeIdentifiers

/// Handles exporting and importing the full Quiper configuration as a single `.quiper` JSON file.
/// The archive contains all settings (from `PersistedSettings`) plus every action script
/// inlined from `ActionScriptStorage`, making it completely self-contained.
@MainActor
enum ConfigPortManager {

    private static let fileExtension = ConfigPortability.fileExtension

    // MARK: – Export

    static func exportConfig() throws -> Data {
        var ps = Settings.shared.makePersistedSettings()
        ConfigPortability.inlineFileScripts(into: &ps)
        return try ConfigPortability.encode(ps)
    }

    static func exportConfig(secureChoice: SecureExportChoice, decryptedServices: [Service] = []) throws -> Data {
        var ps = Settings.shared.makePersistedSettings(secureChoice: secureChoice, decryptedServices: decryptedServices)
        ConfigPortability.inlineFileScripts(into: &ps)
        return try ConfigPortability.encode(ps)
    }

    static func exportConfig(secureChoice: SecureExportChoice, decryptedEngines: [Settings.DecryptedEngineForExport]) throws -> Data {
        var ps = Settings.shared.makePersistedSettings(secureChoice: secureChoice, decryptedEngines: decryptedEngines)
        ConfigPortability.inlineFileScripts(into: &ps)
        return try ConfigPortability.encode(ps)
    }

    static func exportConfigWithDecryption() async throws -> Data {
        var decrypted: [Settings.DecryptedEngineForExport] = []
        for service in Settings.shared.services where service.isEncrypted {
            let copy = try await Settings.shared.decryptedServiceForExport(serviceID: service.id)
            decrypted.append(copy)
        }
        return try exportConfig(secureChoice: .decryptForMigration, decryptedEngines: decrypted)
    }

    // MARK: – Import

    static func importConfig(from data: Data) throws {
        let ps = try ConfigPortability.decode(from: data)
        Settings.shared.applyPersistedSettings(ps)
        ConfigPortability.persistFileArtifacts(from: ps)
        Settings.shared.saveSettings()
    }

    static func importConfig(from data: Data, droppingOrphans: Bool) throws {
        var ps = try ConfigPortability.decode(from: data)
        if droppingOrphans {
            let orphans = Set(Settings.shared.orphanedServicesForImport(in: ps).map(\.id))
            ps.services.removeAll { orphans.contains($0.id) }
            for id in orphans {
                ps.persistedTabState?.activeIndicesByID.removeValue(forKey: id)
                ps.persistedTabState?.openTabs.removeValue(forKey: id)
                ps.persistedTabState?.tabTitles.removeValue(forKey: id)
                ps.persistedTabState?.tabInputs.removeValue(forKey: id)
                ps.persistedTabState?.tabPromptHistories.removeValue(forKey: id)
                ps.persistedTabState?.tabPromptHistoryEnabledOverrides.removeValue(forKey: id)
                ps.persistedTabState?.tabHistory?.removeAll { $0.serviceID == id }
                if ps.persistedTabState?.activeServiceID == id {
                    ps.persistedTabState?.activeServiceID = ps.services.first?.id
                }
            }
        }
        Settings.shared.applyPersistedSettings(ps)
        ConfigPortability.persistFileArtifacts(from: ps)
        Settings.shared.saveSettings()
    }

    // MARK: – Save panel helpers

    static func showExportPanel(in window: NSWindow?, completion: @escaping (Result<URL, Error>) -> Void) {
        let panel = NSSavePanel()
        panel.title = "Export Quiper Config"
        panel.nameFieldStringValue = "quiper-config"
        panel.allowedContentTypes = [ConfigPortability.contentType]
        panel.canCreateDirectories = true
        panel.level = .modalPanel

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

        NSApp.activate(ignoringOtherApps: true)
        if let window {
            window.makeKeyAndOrderFront(nil)
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            panel.begin(completionHandler: handler)
        }
    }

    static func showExportPanelWithChoice(in window: NSWindow?, choice: SecureExportChoice, completion: @escaping (Result<URL, Error>) -> Void) {
        let panel = NSSavePanel()
        panel.title = "Export Quiper Config"
        panel.nameFieldStringValue = "quiper-config"
        panel.allowedContentTypes = [ConfigPortability.contentType]
        panel.canCreateDirectories = true
        panel.level = .modalPanel

        let handler: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                do {
                    let data = try exportConfig(secureChoice: choice)
                    try data.write(to: url, options: .atomic)
                    completion(.success(url))
                } catch {
                    completion(.failure(error))
                }
            }
        }

        NSApp.activate(ignoringOtherApps: true)
        if let window {
            window.makeKeyAndOrderFront(nil)
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            panel.begin(completionHandler: handler)
        }
    }

    static func showExportPanelWithDecrypted(in window: NSWindow?, decryptedServices: [Service], completion: @escaping (Result<URL, Error>) -> Void) {
        let engines = decryptedServices.map { Settings.DecryptedEngineForExport(service: $0, tabState: nil) }
        showExportPanelWithDecryptedEngines(in: window, decryptedEngines: engines, completion: completion)
    }

    static func showExportPanelWithDecryptedEngines(in window: NSWindow?, decryptedEngines: [Settings.DecryptedEngineForExport], completion: @escaping (Result<URL, Error>) -> Void) {
        let panel = NSSavePanel()
        panel.title = "Export Quiper Config"
        panel.nameFieldStringValue = "quiper-config"
        panel.allowedContentTypes = [ConfigPortability.contentType]
        panel.canCreateDirectories = true
        panel.level = .modalPanel

        let handler: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                do {
                    let data = try exportConfig(secureChoice: .decryptForMigration, decryptedEngines: decryptedEngines)
                    try data.write(to: url, options: .atomic)
                    completion(.success(url))
                } catch {
                    completion(.failure(error))
                }
            }
        }

        NSApp.activate(ignoringOtherApps: true)
        if let window {
            window.makeKeyAndOrderFront(nil)
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            panel.level = .modalPanel
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



import Foundation
import AppKit
import LocalAuthentication

/// All engine metadata that should be stored exclusively in the secure bundle
/// once migration is complete. Separated from behavioral settings that remain
/// in plaintext settings.json.
struct SecuredEngineMetadata: Codable, Equatable {
    var url: String
    var focusSelector: String
    var iconBase64: String?
    var iconManuallyUnset: Bool?
    var legacyActivationShortcut: HotkeyManager.Configuration?
    var customCSS: String?
    var routingRules: [RoutingRule]
    var actionScripts: [UUID: String]
    var preservePrompt: Bool
    var templateActionScriptSync: [UUID: Bool]
    var templatePromptInputSelectorSync: Bool
    var templateCustomCSSSync: Bool

    enum CodingKeys: String, CodingKey {
        case url, focusSelector, iconBase64, iconManuallyUnset
        case legacyActivationShortcut = "activationShortcut"
        case customCSS, routingRules, actionScripts
        case preservePrompt, templateActionScriptSync
        case templatePromptInputSelectorSync, templateCustomCSSSync
    }

    init(from service: Service) {
        self.url = service.url
        self.focusSelector = service.focus_selector
        self.iconBase64 = service.iconBase64
        self.iconManuallyUnset = service.iconManuallyUnset
        self.legacyActivationShortcut = nil
        self.customCSS = service.customCSS
        self.routingRules = service.routingRules
        self.actionScripts = service.actionScripts
        self.preservePrompt = service.preservePrompt
        self.templateActionScriptSync = service.templateActionScriptSync
        self.templatePromptInputSelectorSync = service.templatePromptInputSelectorSync
        self.templateCustomCSSSync = service.templateCustomCSSSync
    }

    func apply(to service: inout Service) {
        service.url = url
        service.focus_selector = focusSelector
        service.iconBase64 = iconBase64
        service.iconManuallyUnset = iconManuallyUnset
        service.customCSS = customCSS
        service.routingRules = routingRules
        service.actionScripts = actionScripts
        service.preservePrompt = preservePrompt
        service.templateActionScriptSync = templateActionScriptSync
        service.templatePromptInputSelectorSync = templatePromptInputSelectorSync
        service.templateCustomCSSSync = templateCustomCSSSync
    }
}

/// File name used inside the mounted secure bundle for engine metadata.
private let metadataFileName = "quiper_engine_metadata.json"

@MainActor
final class EngineMetadataMigrationManager {
    static let shared = EngineMetadataMigrationManager()
    private init() {}

    private var inMemoryMetadata: [UUID: SecuredEngineMetadata] = [:]

    /// Path for the metadata file within a mounted secure bundle.
    func metadataFileURL(for serviceID: UUID) -> URL {
        EncryptedVolumeManager.shared.getMountPointURL(for: serviceID).appendingPathComponent(metadataFileName)
    }

    // MARK: - Bundle I/O

    /// Writes metadata to the mounted secure bundle atomically.
    func writeMetadata(_ metadata: SecuredEngineMetadata, for serviceID: UUID) throws {
        let url = metadataFileURL(for: serviceID)
        let data = try JSONEncoder().encode(metadata)
        try data.write(to: url, options: [.atomic])
        inMemoryMetadata[serviceID] = metadata
        NSLog("[MetadataMigration] Wrote metadata to secure bundle for service %@", serviceID.uuidString)
    }

    /// Reads metadata from the mounted secure bundle.
    func readMetadata(for serviceID: UUID) throws -> SecuredEngineMetadata {
        let url = metadataFileURL(for: serviceID)
        let data = try Data(contentsOf: url)
        let metadata = try JSONDecoder().decode(SecuredEngineMetadata.self, from: data)
        inMemoryMetadata[serviceID] = metadata
        return metadata
    }

    /// Reads metadata from the secure bundle without throwing.
    func readMetadataIfPresent(for serviceID: UUID) -> SecuredEngineMetadata? {
        try? readMetadata(for: serviceID)
    }

    /// Verifies that metadata was successfully written and can be read back.
    func verifyMetadata(for serviceID: UUID) -> Bool {
        do {
            _ = try readMetadata(for: serviceID)
            return true
        } catch {
            return false
        }
    }

    // MARK: - In-Memory Access

    /// Returns cached metadata for a service if available.
    func cachedMetadata(for serviceID: UUID) -> SecuredEngineMetadata? {
        inMemoryMetadata[serviceID]
    }

    /// Clears cached metadata (e.g., when engine locks).
    func clearCachedMetadata(for serviceID: UUID) {
        inMemoryMetadata.removeValue(forKey: serviceID)
    }

    // MARK: - Migration State

    /// Whether a service has legacy metadata still in settings.json.
    func hasLegacyMetadata(for service: Service) -> Bool {
        service.isEncrypted && !service.hasMigratedMetadata && !service.url.isEmpty
    }

    /// Returns all services with legacy metadata that need migration.
    func legacyServices(in services: [Service]) -> [Service] {
        services.filter { hasLegacyMetadata(for: $0) }
    }

    /// Whether any services have legacy metadata pending migration.
    func hasAnyLegacyMetadata(in services: [Service]) -> Bool {
        !legacyServices(in: services).isEmpty
    }

    // MARK: - Migration

    /// Migrates metadata from settings to the secure bundle.
    /// Must be called when the bundle is mounted and authenticated.
    /// The process is atomic: metadata is written, verified, then settings are updated.
    func migrateMetadata(for serviceID: UUID, context: LAContext) async throws {
        guard let index = Settings.shared.services.firstIndex(where: { $0.id == serviceID }) else {
            throw MetadataMigrationError.serviceNotFound
        }

        let service = Settings.shared.services[index]
        guard !service.hasMigratedMetadata else {
            NSLog("[MetadataMigration] Service %@ already migrated, skipping", serviceID.uuidString)
            return
        }

        NSLog("[MetadataMigration] Starting metadata migration for service %@", serviceID.uuidString)

        let metadata = SecuredEngineMetadata(from: service)

        do {
            try writeMetadata(metadata, for: serviceID)
        } catch {
            NSLog("[MetadataMigration] Failed to write metadata: %@", error.localizedDescription)
            throw MetadataMigrationError.writeFailed(error.localizedDescription)
        }

        if !verifyMetadata(for: serviceID) {
            throw MetadataMigrationError.verificationFailed
        }

        Settings.shared.services[index].hasMigratedMetadata = true

        Settings.shared.saveSettings()

        ActionScriptStorage.deleteScripts(for: serviceID)
        CustomCSSStorage.deleteCSS(for: serviceID)
        FocusSelectorStorage.deleteSelector(for: serviceID)

        NSLog("[MetadataMigration] Completed metadata migration for service %@", serviceID.uuidString)
    }

    /// Loads metadata for an unlocked service from the secure bundle into the Service model.
    func loadMetadataForUnlockedService(_ serviceID: UUID) {
        guard let index = Settings.shared.services.firstIndex(where: { $0.id == serviceID }) else {
            return
        }
        guard Settings.shared.services[index].hasMigratedMetadata else { return }

        if let metadata = readMetadataIfPresent(for: serviceID) {
            metadata.apply(to: &Settings.shared.services[index])
            if Settings.shared.services[index].activationShortcut == nil {
                Settings.shared.services[index].activationShortcut = metadata.legacyActivationShortcut
            }
            if metadata.legacyActivationShortcut != nil {
                Settings.shared.saveSettings()
            }
            NSLog("[MetadataMigration] Loaded metadata from bundle for service %@", serviceID.uuidString)
        }
    }

    /// Saves current in-memory metadata back to the secure bundle for a migrated service.
    /// Should be called when the service is modified (e.g., URL changed in settings).
    func saveMetadataToBundle(for serviceID: UUID) throws {
        guard let index = Settings.shared.services.firstIndex(where: { $0.id == serviceID }) else { return }
        let service = Settings.shared.services[index]
        guard service.hasMigratedMetadata else { return }

        let metadata = SecuredEngineMetadata(from: service)
        try writeMetadata(metadata, for: serviceID)
    }

    // MARK: - Wizard

    /// Presents the metadata migration wizard at app launch if legacy engines exist.
    func presentMigrationWizardIfNeeded(relativeTo window: NSWindow?) async {
        let legacyServices = legacyServices(in: Settings.shared.services)
        guard !legacyServices.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = "Upgrade Secure Engine Storage"
        alert.informativeText = "\(legacyServices.count) secured engine\(legacyServices.count == 1 ? "" : "s") still store metadata (URL, icons, scripts) in unencrypted settings. Migrating moves this data into each engine's encrypted storage bundle where only you can access it after authenticating.\n\nYou can migrate now by unlocking each engine, or skip and they'll be migrated automatically the next time you unlock them."
        alert.addButton(withTitle: "Migrate Now")
        alert.addButton(withTitle: "Skip")
        alert.alertStyle = .informational

        NSApp.activate(ignoringOtherApps: true)

        let response: NSApplication.ModalResponse
        if let window {
            response = await withCheckedContinuation { continuation in
                alert.beginSheetModal(for: window) { result in
                    continuation.resume(returning: result)
                }
            }
        } else {
            response = alert.runModal()
        }

        if response == .alertFirstButtonReturn {
            await runMigrationWizard(for: legacyServices, relativeTo: window)
        }
    }

    private func runMigrationWizard(for services: [Service], relativeTo window: NSWindow?) async {
        let panel = MetadataMigrationProgressPanel()
        panel.show()

        for (i, service) in services.enumerated() {
            panel.updateEngineName(service.name)
            panel.updateStatus("Unlocking \(service.name) (\(i + 1)/\(services.count))...")
            panel.bringToFront()

            do {
                let context = LAContext()
                try await context.evaluatePolicy(
                    .deviceOwnerAuthentication,
                    localizedReason: "Migrate \(service.name) metadata to secure storage"
                )

                panel.bringToFront()
                panel.updateStatus("Retrieving key for \(service.name)...")
                let key = try await SecureStorageManager.shared.retrieveKeyFromKeychain(for: service.id, context: context)

                if !EncryptedVolumeManager.shared.isUnlocked(for: service.id) {
                    panel.updateStatus("Mounting \(service.name)...")
                    try await EncryptedVolumeManager.shared.mountVolume(for: service.id, passphrase: key)
                }

                panel.updateStatus("Migrating \(service.name)...")
                try await migrateMetadata(for: service.id, context: context)

            } catch {
                if (error as? LAError)?.code == .userCancel {
                    panel.close()
                    return
                }
                NSLog("[MetadataMigration] Wizard: failed to migrate %@: %@", service.name, error.localizedDescription)
            }

            try? await EncryptedVolumeManager.shared.unmountVolume(for: service.id)
            EncryptedVolumeManager.shared.markLocked(service.id)

            if let index = Settings.shared.services.firstIndex(where: { $0.id == service.id }) {
                Settings.shared.services[index].url = ""
            }
        }

        panel.updateEngineName("")
        panel.updateStatus("Migration complete")
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        panel.close()
        Settings.shared.saveSettings()
    }
}

@MainActor
final class MetadataMigrationProgressPanel {
    private let panel: NSPanel
    private let engineNameLabel: NSTextField
    private let statusLabel: NSTextField
    private let spinner: NSProgressIndicator

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 168),
            styleMask: [.titled, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Migrate Engine Metadata"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .screenSaver

        let contentView = NSView(frame: panel.contentView?.bounds ?? .zero)
        contentView.translatesAutoresizingMaskIntoConstraints = false

        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.state = .active
        background.blendingMode = .behindWindow
        background.translatesAutoresizingMaskIntoConstraints = false

        let iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown
        let iconConfig = NSImage.SymbolConfiguration(pointSize: 22, weight: .medium)
        if let symbol = NSImage(systemSymbolName: "lock.rotation", accessibilityDescription: nil)?
            .withSymbolConfiguration(iconConfig) {
            let tinted = NSImage(size: symbol.size)
            tinted.lockFocus()
            NSColor.controlAccentColor.set()
            NSRect(origin: .zero, size: symbol.size).fill()
            symbol.draw(at: .zero, from: .zero, operation: .destinationIn, fraction: 1.0)
            tinted.unlockFocus()
            iconView.image = tinted
        }

        spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimation(nil)

        engineNameLabel = NSTextField(labelWithString: "")
        engineNameLabel.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        engineNameLabel.textColor = .labelColor
        engineNameLabel.alignment = .center
        engineNameLabel.translatesAutoresizingMaskIntoConstraints = false

        statusLabel = NSTextField(labelWithString: "Preparing...")
        statusLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .center
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(background)
        contentView.addSubview(iconView)
        contentView.addSubview(spinner)
        contentView.addSubview(engineNameLabel)
        contentView.addSubview(statusLabel)
        panel.contentView = contentView

        NSLayoutConstraint.activate([
            contentView.widthAnchor.constraint(equalToConstant: 420),
            contentView.heightAnchor.constraint(equalToConstant: 168),

            background.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            background.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            background.topAnchor.constraint(equalTo: contentView.topAnchor),
            background.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            iconView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            iconView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),

            engineNameLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            engineNameLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 10),

            spinner.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            spinner.topAnchor.constraint(equalTo: engineNameLabel.bottomAnchor, constant: 10),

            statusLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            statusLabel.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 10),
            statusLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -18),
        ])
    }

    func show() {
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func updateEngineName(_ name: String) {
        engineNameLabel.stringValue = name
    }

    func updateStatus(_ text: String) {
        statusLabel.stringValue = text
    }

    func bringToFront() {
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        spinner.stopAnimation(nil)
        panel.orderOut(nil)
    }
}

enum MetadataMigrationError: Error, LocalizedError {
    case serviceNotFound
    case writeFailed(String)
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .serviceNotFound:
            return "Engine not found in settings."
        case .writeFailed(let reason):
            return "Failed to write metadata to secure storage: \(reason)"
        case .verificationFailed:
            return "Metadata verification failed after writing."
        }
    }
}

import AppKit
import Foundation
import LocalAuthentication

struct SparseBundleMigrationResult {
    var migrated: [UUID] = []
    var failed: [(UUID, String)] = []
}

enum SparseBundleMigrationError: Error, LocalizedError {
    case notLegacyFormat
    case bundleMissing
    case verificationFailed
    case rollbackFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .notLegacyFormat:
            return "Secure storage is already using the current format."
        case .bundleMissing:
            return "Encrypted storage bundle was not found."
        case .verificationFailed:
            return "Migration verification failed. Your original secure storage was restored."
        case .rollbackFailed(let reason):
            return "Migration failed and rollback encountered an issue: \(reason)"
        }
    }
}

@MainActor
final class SparseBundleMigrationManager {
    static let shared = SparseBundleMigrationManager()
    
    private init() {}
    
    func presentPerEngineMigrationPrompt(engineName: String, relativeTo window: NSWindow?) async -> Bool {
        let alert = MigrationAlertPresenter.perEngineUpgradePrompt(engineName: engineName)
        
        NSApp.activate(ignoringOtherApps: true)
        if let window {
            return await MigrationAlertPresenter.runPrimaryActionSheet(alert, for: window)
        }
        
        return MigrationAlertPresenter.runPrimaryAction(alert)
    }
    
    func migrateEngine(serviceID: UUID, passphrase: String, context: LAContext? = nil) async throws {
        let volumeManager = EncryptedVolumeManager.shared
        let fileManager = FileManager.default
        
        guard volumeManager.bundleExists(for: serviceID) else {
            throw SparseBundleMigrationError.bundleMissing
        }
        let usesDiskutil = Settings.shared.services.first(where: { $0.id == serviceID })?.usesDiskutilSparseBundle ?? false
        guard !usesDiskutil else {
            throw SparseBundleMigrationError.notLegacyFormat
        }
        
        let bundleURL = volumeManager.getBundleURL(for: serviceID)
        let backupBundleURL = volumeManager.legacyBackupBundleURL(for: serviceID)
        var bundleMovedToBackup = false
        var newBundleCreated = false
        
        defer {
            if bundleMovedToBackup && !newBundleCreated {
                restoreLegacyBundle(from: backupBundleURL, to: bundleURL)
            }
        }
        
        NSLog("[SparseBundleMigration] Starting migration for service %@", serviceID.uuidString)
        
        try await prepareEngineForMigration(serviceID: serviceID, passphrase: passphrase)
        
        let backupFileCount: Int
        switch try SecureDataMigrationManager.shared.prepareMountedVolumeBackup(for: serviceID) {
        case .created:
            backupFileCount = countMigratableFiles(at: volumeManager.getMountPointURL(for: serviceID))
        case .reusedExisting:
            backupFileCount = countMigratableFilesInBackup(for: serviceID)
        }
        
        try await volumeManager.unmountVolume(for: serviceID)
        
        try removeLegacyBundleBackupIfPresent(at: backupBundleURL)
        try fileManager.moveItem(at: bundleURL, to: backupBundleURL)
        bundleMovedToBackup = true
        
        do {
            try await volumeManager.createVolume(for: serviceID, passphrase: passphrase, markAsDiskutilFormat: false)
            newBundleCreated = true
            try await volumeManager.mountVolume(for: serviceID, passphrase: passphrase, format: .modernDiskutil)
            
            SecureDataMigrationManager.shared.restoreData(for: serviceID)
            
            let restoredFileCount = countMigratableFiles(at: volumeManager.getMountPointURL(for: serviceID))
            if backupFileCount > 0 && restoredFileCount < backupFileCount {
                throw SparseBundleMigrationError.verificationFailed
            }
            
            try await volumeManager.unmountVolume(for: serviceID)
            try await volumeManager.mountVolume(for: serviceID, passphrase: passphrase, format: .modernDiskutil)
            
            try await volumeManager.unmountVolume(for: serviceID)
            
            try fileManager.removeItem(at: backupBundleURL)
            bundleMovedToBackup = false
            SecureDataMigrationManager.shared.discardBackup(for: serviceID)
            
            volumeManager.markUsesDiskutilSparseBundle(serviceID)
            NSLog("[SparseBundleMigration] Migration completed for service %@", serviceID.uuidString)
        } catch {
            NSLog("[SparseBundleMigration] Migration failed for service %@: %@", serviceID.uuidString, error.localizedDescription)
            volumeManager.clearUsesDiskutilSparseBundle(serviceID)
            try? await volumeManager.unmountVolume(for: serviceID)
            if fileManager.fileExists(atPath: bundleURL.path) {
                try? fileManager.removeItem(at: bundleURL)
            }
            newBundleCreated = false
            restoreLegacyBundle(from: backupBundleURL, to: bundleURL)
            bundleMovedToBackup = false
            throw error
        }
    }
    
    func migrateAllLegacyEngines(context: LAContext) async -> SparseBundleMigrationResult {
        var result = SparseBundleMigrationResult()
        let legacyServices = Settings.shared.services.filter {
            $0.isEncrypted
                && EncryptedVolumeManager.shared.bundleExists(for: $0.id)
                && !$0.usesDiskutilSparseBundle
        }
        
        for service in legacyServices {
            do {
                let passphrase = try await SecureStorageManager.shared.retrieveKeyFromKeychain(for: service.id, context: context)
                try await migrateEngine(serviceID: service.id, passphrase: passphrase, context: context)
                result.migrated.append(service.id)
            } catch {
                result.failed.append((service.id, error.localizedDescription))
            }
            
            await EncryptedVolumeManager.shared.resetMountStateForMigration(for: service.id)
        }
        
        return result
    }
    
    private func prepareEngineForMigration(serviceID: UUID, passphrase: String) async throws {
        let volumeManager = EncryptedVolumeManager.shared
        let fileManager = FileManager.default
        let bundleURL = volumeManager.getBundleURL(for: serviceID)
        let backupBundleURL = volumeManager.legacyBackupBundleURL(for: serviceID)
        
        if !volumeManager.bundleExists(for: serviceID),
           fileManager.fileExists(atPath: backupBundleURL.path) {
            restoreLegacyBundle(from: backupBundleURL, to: bundleURL)
        } else if volumeManager.bundleExists(for: serviceID),
                  fileManager.fileExists(atPath: backupBundleURL.path) {
            try removeLegacyBundleBackupIfPresent(at: backupBundleURL)
        }
        
        await volumeManager.resetMountStateForMigration(for: serviceID)
        try await volumeManager.mountVolume(for: serviceID, passphrase: passphrase)
    }
    
    private func removeLegacyBundleBackupIfPresent(at backupBundleURL: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: backupBundleURL.path) else { return }
        do {
            try fileManager.removeItem(at: backupBundleURL)
        } catch {
            throw NSError(
                domain: "SparseBundleMigration",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Failed to clear a stale secure storage backup before upgrading."]
            )
        }
    }
    
    private func restoreLegacyBundle(from backupURL: URL, to bundleURL: URL) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: backupURL.path) else { return }
        
        if fileManager.fileExists(atPath: bundleURL.path) {
            try? fileManager.removeItem(at: bundleURL)
        }
        
        do {
            try fileManager.moveItem(at: backupURL, to: bundleURL)
            NSLog("[SparseBundleMigration] Restored legacy bundle from backup")
        } catch {
            NSLog("[SparseBundleMigration] Failed to restore legacy bundle: %@", error.localizedDescription)
        }
    }
    
    private func countMigratableFilesInBackup(for serviceID: UUID) -> Int {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("QuiperMigration-\(serviceID.uuidString)")
        return countMigratableFiles(at: tempDir)
    }
    
    private func countMigratableFiles(at directoryURL: URL) -> Int {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        
        var count = 0
        for case let fileURL as URL in enumerator {
            let name = fileURL.lastPathComponent
            if name == ".DS_Store" || name == ".fseventsd" {
                continue
            }
            if (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                count += 1
            }
        }
        return count
    }
}

@MainActor
final class MigrationProgressPanel {
    private let panel: NSPanel
    private let statusLabel: NSTextField
    private let spinner: NSProgressIndicator
    
    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 148),
            styleMask: [.titled, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Upgrading Secure Storage"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.titlebarAppearsTransparent = true
        
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
        if let symbol = NSImage(systemSymbolName: "lock.rotation", accessibilityDescription: "Upgrading secure storage")?
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
        contentView.addSubview(statusLabel)
        panel.contentView = contentView
        
        NSLayoutConstraint.activate([
            contentView.widthAnchor.constraint(equalToConstant: 420),
            contentView.heightAnchor.constraint(equalToConstant: 148),
            
            background.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            background.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            background.topAnchor.constraint(equalTo: contentView.topAnchor),
            background.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            
            iconView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            iconView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),
            
            spinner.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            spinner.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 12),
            
            statusLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            statusLabel.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 14),
            statusLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -18),
        ])
    }
    
    func show() {
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }
    
    func updateStatus(_ text: String) {
        statusLabel.stringValue = text
    }
    
    func close() {
        spinner.stopAnimation(nil)
        panel.orderOut(nil)
    }
}
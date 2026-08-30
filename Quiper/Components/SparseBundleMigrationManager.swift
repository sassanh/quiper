import AppKit
import Foundation

struct SparseBundleMigrationResult {
    var migrated: [UUID] = []
    var failed: [(UUID, String)] = []
}

enum SparseBundleMigrationError: Error, LocalizedError {
    case legacyUnsupported

    var errorDescription: String? {
        switch self {
        case .legacyUnsupported:
            return "This secure storage was created with an older format that this version of Quiper no longer supports. Please download Quiper 5.0.0, open it once so it can migrate your protected engines, then update to this version again."
        }
    }
}

@MainActor
final class SparseBundleMigrationManager {
    static let shared = SparseBundleMigrationManager()
    private init() {}

    func presentPerEngineMigrationPrompt(engineName: String, relativeTo window: NSWindow?) async -> Bool {
        presentLegacyAlert(engineName: engineName, relativeTo: window)
        return false
    }

    func migrateEngine(serviceID: UUID, passphrase: String, context: Any? = nil) async throws {
        throw SparseBundleMigrationError.legacyUnsupported
    }

    func migrateAllLegacyEngines(context: Any) async -> SparseBundleMigrationResult {
        if let window = NSApp.keyWindow {
            presentLegacyAlert(engineName: nil, relativeTo: window)
        } else {
            presentLegacyAlert(engineName: nil, relativeTo: nil)
        }
        return SparseBundleMigrationResult()
    }

    private func presentLegacyAlert(engineName: String?, relativeTo window: NSWindow?) {
        let alert = NSAlert()
        alert.messageText = "Older Secure Storage Requires Quiper 5.0.0"
        if let name = engineName {
            alert.informativeText = "\(name) uses an older secure storage format that this version of Quiper no longer supports.\n\nPlease download Quiper 5.0.0 from the releases page, open it once so it can migrate your protected engines, then update to this version again. 5.0.0 was the last version that can open and convert those older bundles."
        } else {
            alert.informativeText = "Some of your protected engines use an older secure storage format that this version of Quiper no longer supports.\n\nPlease download Quiper 5.0.0 from the releases page, open it once so it can migrate your protected engines, then update to this version again. 5.0.0 was the last version that can open and convert those older bundles."
        }
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.buttons[0].keyEquivalent = "\u{1b}"
        if let window {
            alert.beginSheetModal(for: window, completionHandler: { _ in })
        } else {
            alert.runModal()
        }
    }
}

@MainActor
final class MigrationProgressPanel {
    func show() {}
    func updateStatus(_ text: String) {}
    func close() {}
}

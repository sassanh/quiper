import AppKit

@MainActor
enum MigrationAlertPresenter {
    enum Tone {
        case prompt
        case success
        case partialSuccess
        case failure
        case authentication
    }

    static func configure(
        tone: Tone,
        messageText: String,
        informativeText: String,
        primaryButton: String,
        secondaryButton: String? = nil
    ) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = messageText
        alert.informativeText = informativeText
        alert.addButton(withTitle: primaryButton)
        if let secondaryButton {
            alert.addButton(withTitle: secondaryButton)
        }
        applyTone(tone, to: alert)
        return alert
    }

    static func launchUpgradePrompt(legacyCount: Int) -> NSAlert {
        configure(
            tone: .prompt,
            messageText: "Upgrade Secure Storage?",
            informativeText: "Quiper is updating how encrypted engine data is stored. Your login sessions and cookies will be preserved. This one-time upgrade takes a moment for each secured engine (\(legacyCount) total).",
            primaryButton: "Upgrade Now",
            secondaryButton: "Later"
        )
    }

    static func perEngineUpgradePrompt(engineName: String) -> NSAlert {
        configure(
            tone: .prompt,
            messageText: "Upgrade Secure Storage for \(engineName)?",
            informativeText: "This engine uses an older secure storage format. Upgrading preserves your login sessions and cookies, and only takes a moment.",
            primaryButton: "Upgrade Now",
            secondaryButton: "Not Now"
        )
    }

    static func authenticationRequired(message: String) -> NSAlert {
        configure(
            tone: .authentication,
            messageText: "Authentication Required",
            informativeText: message,
            primaryButton: "OK"
        )
    }

    static func batchCompletion(result: SparseBundleMigrationResult) -> NSAlert {
        if result.failed.isEmpty {
            return configure(
                tone: .success,
                messageText: "Secure Storage Upgraded",
                informativeText: "All secured engines were upgraded successfully.",
                primaryButton: "OK"
            )
        }

        if result.migrated.isEmpty {
            let details = formattedFailureDetails(from: result.failed)
            return configure(
                tone: .failure,
                messageText: "Upgrade Failed",
                informativeText: details.isEmpty ? "No engines could be upgraded." : details,
                primaryButton: "OK"
            )
        }

        let failedNames = formattedFailureDetails(from: result.failed)
        return configure(
            tone: .partialSuccess,
            messageText: "Upgrade Partially Completed",
            informativeText: "Some engines were upgraded. These still need attention:\n\(failedNames)",
            primaryButton: "OK"
        )
    }

    static func runPrimaryAction(_ alert: NSAlert) -> Bool {
        alert.runModal() == .alertFirstButtonReturn
    }

    static func runPrimaryActionSheet(_ alert: NSAlert, for window: NSWindow) async -> Bool {
        await alert.beginSheetModal(for: window) == .alertFirstButtonReturn
    }

    private static func applyTone(_ tone: Tone, to alert: NSAlert) {
        switch tone {
        case .prompt:
            alert.alertStyle = .informational
            alert.icon = tintedSymbol(named: "lock.rotation", color: .controlAccentColor)
        case .success:
            alert.alertStyle = .informational
            alert.icon = tintedSymbol(named: "checkmark.circle.fill", color: .systemGreen)
        case .partialSuccess:
            alert.alertStyle = .warning
            alert.icon = tintedSymbol(named: "exclamationmark.triangle.fill", color: .systemOrange)
        case .failure:
            alert.alertStyle = .critical
            alert.icon = tintedSymbol(named: "xmark.circle.fill", color: .systemRed)
        case .authentication:
            alert.alertStyle = .warning
            alert.icon = tintedSymbol(named: "person.badge.key.fill", color: .systemOrange)
        }
    }

    private static func formattedFailureDetails(from failures: [(UUID, String)]) -> String {
        failures.compactMap { id, message -> String? in
            guard let name = Settings.shared.services.first(where: { $0.id == id })?.name else { return nil }
            return "\(name): \(message)"
        }.joined(separator: "\n")
    }

    private static func tintedSymbol(named name: String, color: NSColor, pointSize: CGFloat = 44) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) else {
            return nil
        }

        let tinted = NSImage(size: image.size)
        tinted.lockFocus()
        color.set()
        NSRect(origin: .zero, size: image.size).fill()
        image.draw(at: .zero, from: .zero, operation: .destinationIn, fraction: 1.0)
        tinted.unlockFocus()
        return tinted
    }
}
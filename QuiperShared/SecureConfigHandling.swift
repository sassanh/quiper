import Foundation

// MARK: - Export choices

enum SecureExportChoice: String, CaseIterable, Identifiable {
    case keepLocked
    case decryptForMigration
    case exclude

    var id: String { rawValue }
}

// MARK: - Helpers

extension PersistedSettings {
    var encryptedServices: [Service] {
        services.filter { $0.isEncrypted }
    }

    var hasEncryptedServices: Bool {
        !encryptedServices.isEmpty
    }

    /// Services that were exported as minimal stubs (isEncrypted && hasMigratedMetadata).
    var minimalEncryptedServices: [Service] {
        services.filter { $0.isEncrypted && $0.hasMigratedMetadata }
    }
}

extension Service {
    /// A decrypted copy suitable for migration export: the secure flags are cleared
    /// so `encode(to:)` includes the full metadata. The provenance flag is set
    /// so the importer can automatically re-enable Secure Storage.
    var decryptedForExport: Service {
        var copy = self
        copy.isEncrypted = false
        copy.hasMigratedMetadata = false
        copy.originatedFromSecureStorage = true
        return copy
    }
}

func orphanedEncryptedServices(
    in persisted: PersistedSettings,
    hasLocalBundle: (UUID) -> Bool
) -> [Service] {
    persisted.minimalEncryptedServices.filter { !hasLocalBundle($0.id) }
}

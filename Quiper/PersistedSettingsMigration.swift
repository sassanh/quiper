import Foundation

/// Persisted-settings migrations use these identifiers to share eligibility,
/// presentation, and persistence behavior without coupling their transformations.
enum PersistedSettingsMigration: Hashable, Sendable {
    case templateActionScriptSync
    case engineShortcutToggle
    case selectorDisplayModes
}

enum PersistedSettingsMigrationPresentation: Sendable {
    case automatic
    case prompted
}

enum PersistedSettingsMigrationDisposition: Equatable, Sendable {
    case notNeeded
    case deferred
    case runAutomatically
    case awaitingPrompt

    var isUnresolved: Bool {
        self == .deferred || self == .awaitingPrompt
    }
}

/// Classifies one persisted settings payload against the running app. All
/// version-aware settings migrations must use this context instead of comparing
/// version strings independently.
struct PersistedSettingsMigrationContext: Equatable, Sendable {
    enum SourceCompatibility: Equatable, Sendable {
        case newInstallation
        case unversionedLegacy
        case currentOrOlder
        case newer
        case unknown
    }

    let sourceCompatibility: SourceCompatibility
    let persistedVersion: String?
    let currentVersion: String

    init(loadedFromDisk: Bool, persistedVersion: String?, currentVersion: String) {
        self.persistedVersion = persistedVersion
        self.currentVersion = currentVersion

        guard loadedFromDisk else {
            sourceCompatibility = .newInstallation
            return
        }
        guard let persistedVersion else {
            sourceCompatibility = .unversionedLegacy
            return
        }

        switch QuiperVersion.compare(currentVersion, to: persistedVersion) {
        case .orderedSame, .orderedDescending:
            sourceCompatibility = .currentOrOlder
        case .orderedAscending:
            sourceCompatibility = .newer
        case nil:
            sourceCompatibility = .unknown
        }
    }

    var isExistingSettings: Bool {
        sourceCompatibility != .newInstallation
    }

    var isUnversionedExistingSettings: Bool {
        sourceCompatibility == .unversionedLegacy
    }

    func disposition(
        whenDetected detected: Bool,
        presentation: PersistedSettingsMigrationPresentation
    ) -> PersistedSettingsMigrationDisposition {
        guard detected else {
            return .notNeeded
        }
        guard canRewritePersistedSettings else {
            return .deferred
        }

        switch presentation {
        case .automatic:
            return .runAutomatically
        case .prompted:
            return .awaitingPrompt
        }
    }

    /// A future or unparseable source version is preserved until an app that
    /// can establish compatibility rewrites the payload.
    var versionForPersistence: String? {
        switch sourceCompatibility {
        case .newer, .unknown:
            return persistedVersion
        case .newInstallation, .unversionedLegacy, .currentOrOlder:
            return currentVersion
        }
    }

    private var canRewritePersistedSettings: Bool {
        switch sourceCompatibility {
        case .unversionedLegacy, .currentOrOlder:
            return true
        case .newInstallation, .newer, .unknown:
            return false
        }
    }
}

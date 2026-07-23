import Foundation
import Testing
@testable import Quiper

struct PersistedSettingsMigrationTests {
    @Test func sourceCompatibilityCoversEveryPersistenceBoundary() {
        #expect(
            context(loadedFromDisk: false, persistedVersion: nil).sourceCompatibility
                == .newInstallation
        )
        #expect(
            context(loadedFromDisk: true, persistedVersion: nil).sourceCompatibility
                == .unversionedLegacy
        )
        #expect(
            context(persistedVersion: "1.2.3").sourceCompatibility
                == .currentOrOlder
        )
        #expect(
            context(persistedVersion: "1.2.3-whatever (9)").sourceCompatibility
                == .currentOrOlder
        )
        #expect(
            context(persistedVersion: "1.2.3-whatever (11)").sourceCompatibility
                == .newer
        )
        #expect(
            context(persistedVersion: "not-a-version").sourceCompatibility
                == .unknown
        )
    }

    @Test func suffixAndBuildOrderingDriveMigrationEligibility() {
        let suffixAfterBase = PersistedSettingsMigrationContext(
            loadedFromDisk: true,
            persistedVersion: "1.2.3",
            currentVersion: "1.2.3-beta-nonproduction"
        )
        #expect(
            suffixAfterBase.disposition(whenDetected: true, presentation: .automatic)
                == .runAutomatically
        )

        let olderBuild = context(persistedVersion: "1.2.3-whatever (11)")
        #expect(
            olderBuild.disposition(whenDetected: true, presentation: .prompted)
                == .deferred
        )
    }

    @Test func automaticAndPromptedMigrationsShareOneEligibilityPolicy() {
        let eligible = context(persistedVersion: "1.2.3-whatever (9)")
        #expect(
            eligible.disposition(whenDetected: false, presentation: .automatic)
                == .notNeeded
        )
        #expect(
            eligible.disposition(whenDetected: true, presentation: .automatic)
                == .runAutomatically
        )
        #expect(
            eligible.disposition(whenDetected: true, presentation: .prompted)
                == .awaitingPrompt
        )

        let newer = context(persistedVersion: "1.2.3-whatever (11)")
        #expect(
            newer.disposition(whenDetected: true, presentation: .automatic)
                == .deferred
        )
        #expect(
            newer.disposition(whenDetected: true, presentation: .prompted)
                == .deferred
        )

        let unknown = context(persistedVersion: "not-a-version")
        #expect(
            unknown.disposition(whenDetected: true, presentation: .automatic)
                == .deferred
        )
        #expect(
            unknown.disposition(whenDetected: true, presentation: .prompted)
                == .deferred
        )
    }

    @Test func persistencePreservesNewerAndUnknownSourceVersions() {
        #expect(
            context(persistedVersion: "1.2.3-whatever (11)").versionForPersistence
                == "1.2.3-whatever (11)"
        )
        #expect(
            context(persistedVersion: "not-a-version").versionForPersistence
                == "not-a-version"
        )
        #expect(
            context(persistedVersion: "1.2.3-whatever (9)").versionForPersistence
                == "1.2.3-whatever (10)"
        )
        #expect(
            context(loadedFromDisk: true, persistedVersion: nil).versionForPersistence
                == "1.2.3-whatever (10)"
        )
    }

    private func context(
        loadedFromDisk: Bool = true,
        persistedVersion: String?
    ) -> PersistedSettingsMigrationContext {
        PersistedSettingsMigrationContext(
            loadedFromDisk: loadedFromDisk,
            persistedVersion: persistedVersion,
            currentVersion: "1.2.3-whatever (10)"
        )
    }
}

import Foundation
import Testing
import WebKit
@testable import QuiperiOS

/// Covers the iOS ports of the macOS persisted-settings migration prompt
/// (template action sync) and the first-run onboarding flag. Predicates must
/// stay byte-identical to macOS so a settings.json remains portable.
@MainActor
@Suite(.serialized)
struct IOSOnboardingAndMigrationTests {

    @Test func unversionedLegacyPayloadWithCandidatesPrompts() throws {
        let (environment, _) = try makeEnvironment(
            quiperVersion: nil,
            hasCompletedIOSOnboarding: nil,
            withTemplateCandidates: true
        )

        #expect(environment.needsTemplateActionSyncMigrationPrompt)
    }

    @Test func newInstallationNeverPrompts() throws {
        let (environment, settingsURL) = try makeEnvironment(
            quiperVersion: nil,
            hasCompletedIOSOnboarding: nil,
            withTemplateCandidates: false,
            writeSettingsFile: false
        )
        defer { removeSettings(at: settingsURL) }

        #expect(!environment.needsTemplateActionSyncMigrationPrompt)
        // A fresh install writes its (empty-engine) settings file by design.
        #expect(environment.services.isEmpty)
    }

    @Test func versionedCurrentPayloadNeverPrompts() throws {
        let (environment, _) = try makeEnvironment(
            quiperVersion: Bundle.main.versionDisplayString,
            hasCompletedIOSOnboarding: nil,
            withTemplateCandidates: true
        )

        #expect(!environment.needsTemplateActionSyncMigrationPrompt)
    }

    @Test func newerPayloadDefersPromptAndKeepsItsVersion() throws {
        let (environment, settingsURL) = try makeEnvironment(
            quiperVersion: "99.0.0",
            hasCompletedIOSOnboarding: nil,
            withTemplateCandidates: true
        )
        defer { removeSettings(at: settingsURL) }

        #expect(!environment.needsTemplateActionSyncMigrationPrompt)

        environment.resolveTemplateActionSyncMigration(updateScripts: true)

        let reloaded = try loadPersistedSettings(from: settingsURL)
        #expect(reloaded.quiperVersion == "99.0.0")
    }

    @Test func resolvingWithUpdateSyncsTemplateScriptsAndStampsVersion() throws {
        let (environment, settingsURL) = try makeEnvironment(
            quiperVersion: nil,
            hasCompletedIOSOnboarding: nil,
            withTemplateCandidates: true
        )
        defer { removeSettings(at: settingsURL) }
        let service = try #require(environment.services.first)
        let action = try #require(environment.customActions.first)

        environment.resolveTemplateActionSyncMigration(updateScripts: true)

        #expect(!environment.needsTemplateActionSyncMigrationPrompt)
        let updated = try #require(environment.services.first)
        #expect(updated.templateActionScriptSync[action.id] == true)
        #expect(updated.actionScripts[action.id] == nil)
        let scriptURL = EngineFileStorage.actionScriptURL(serviceID: service.id, actionID: action.id)
        #expect(!FileManager.default.fileExists(atPath: scriptURL.path))

        let reloaded = try loadPersistedSettings(from: settingsURL)
        #expect(reloaded.quiperVersion != nil)
    }

    @Test func resolvingWithKeepCustomMarksScriptsEditable() throws {
        let (environment, settingsURL) = try makeEnvironment(
            quiperVersion: nil,
            hasCompletedIOSOnboarding: nil,
            withTemplateCandidates: true
        )
        defer { removeSettings(at: settingsURL) }
        let action = try #require(environment.customActions.first)

        environment.resolveTemplateActionSyncMigration(updateScripts: false)

        #expect(!environment.needsTemplateActionSyncMigrationPrompt)
        let updated = try #require(environment.services.first)
        #expect(updated.templateActionScriptSync[action.id] == false)

        let reloaded = try loadPersistedSettings(from: settingsURL)
        #expect(reloaded.quiperVersion != nil)
    }

    @Test func onboardingAppearsOnceThenStaysDismissed() throws {
        let (environment, settingsURL) = try makeEnvironment(
            quiperVersion: nil,
            hasCompletedIOSOnboarding: nil,
            withTemplateCandidates: false
        )
        defer { removeSettings(at: settingsURL) }

        #expect(environment.needsIOSOnboarding)

        environment.completeIOSOnboarding()
        #expect(!environment.needsIOSOnboarding)

        let reloaded = try loadPersistedSettings(from: settingsURL)
        #expect(reloaded.hasCompletedIOSOnboarding == true)
    }

    // MARK: - Fixtures

    /// Writes a settings.json with the requested `quiperVersion` and, when
    /// candidates are requested, one template-matching engine whose action
    /// carries a stored custom script—then loads an environment from it.
    private func makeEnvironment(
        quiperVersion: String?,
        hasCompletedIOSOnboarding: Bool?,
        withTemplateCandidates: Bool,
        writeSettingsFile: Bool = true
    ) throws -> (AppEnvironment, URL) {
        let settingsURL = temporarySettingsURL()
        var payload = PersistedSettings(services: [])
        payload.quiperVersion = quiperVersion
        payload.hasCompletedIOSOnboarding = hasCompletedIOSOnboarding

        if withTemplateCandidates {
            var pair: (engine: Service, action: CustomAction)?
            for engine in DefaultEngineDefinitions.definitions {
                for action in DefaultActions.defaults
                where ActionScripts.defaultScript(for: engine, action: action) != nil {
                    pair = (engine, action)
                    break
                }
                if pair != nil { break }
            }
            let candidate = try #require(pair)
            var engine = candidate.engine
            engine.id = UUID()
            engine.actionScripts[candidate.action.id] = "console.log('legacy');"
            payload.services = [engine]
            payload.customActions = [candidate.action]
        }

        if writeSettingsFile {
            let data = try JSONEncoder().encode(payload)
            try data.write(to: settingsURL, options: .atomic)
        }

        let environment = AppEnvironment(
            settingsURL: settingsURL,
            enrichMissingIcons: false,
            websiteDataStoreManager: NoopDataStoreManager(),
            allowsNetworkWork: false
        )
        return (environment, settingsURL)
    }

    private func temporarySettingsURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("quiper-ios-tests-\(UUID().uuidString).json")
    }

    private func removeSettings(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func loadPersistedSettings(from url: URL) throws -> PersistedSettings {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(PersistedSettings.self, from: data)
    }
}

@MainActor
private final class NoopDataStoreManager: WebsiteDataStoreManaging {
    func dataStore(for serviceID: UUID) -> WKWebsiteDataStore {
        WKWebsiteDataStore.nonPersistent()
    }

    func resetLegacyDefaultStore() async {}

    func removeDataStore(for serviceID: UUID) async throws {}
}
